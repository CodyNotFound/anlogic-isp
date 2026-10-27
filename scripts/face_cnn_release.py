"""Verify and archive a complete FPGA-only face candidate with honest evidence.

Functional evidence is pinned to Git objects, not arbitrary old log filenames.
All active inputs must match a committed, functionally tested RTL baseline.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,shutil

ROOT=Path(__file__).resolve().parents[1]
BASE=None
def digest(data):return hashlib.sha256(data).hexdigest()
def git_blob(path):
    p=subprocess.run(['git','-c','safe.directory='+ROOT.as_posix(),'show',BASE+':'+path],cwd=ROOT,capture_output=True)
    if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace'))
    return p.stdout
def main():
    global BASE
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--baseline',required=True);p.add_argument('--archive',action='store_true');a=p.parse_args()
    if not re.fullmatch('[0-9a-f]{40}',a.baseline):raise ValueError('Specify exact tested commit')
    BASE=a.baseline
    if not re.fullmatch(r'colorshading_runs_[A-Za-z0-9_]+',a.run):raise ValueError('run')
    version=re.search(r'_(v\d+.*)$',a.run)[1];run=ROOT/'td_project'/a.run
    errors=[];inputs={};changes=[]
    for line in (run/'source_sha256.txt').read_text(encoding='utf-8').splitlines():
        h,rel=line.split('  ',1);rel=rel.replace('\\','/')
        if Path(rel).is_absolute() or '..' in Path(rel).parts:raise ValueError(rel)
        data=(ROOT/rel).read_bytes();inputs[rel]=h.lower()
        if digest(data)!=h.lower():errors.append('Source changed after Check: '+rel)
        baseline=git_blob(rel)
        if data!=baseline:
            changes.append(rel)
            errors.append('Active input differs from tested baseline: '+rel)
    if 'td_project/camera_to_dsi_display.al' not in inputs:errors.append('Missing active-project definition hash')
    checks={
        'full_integer_network':('reports/yunet_v52/network_sim.log','PASS tb_yunet_network'),
        'native_rgb_to_pwm':('reports/yunet_v53/native_sim.log','PASS tb_yunet_native_gimbal'),
        'shared_frame':('reports/yunet_v53/shared_tracker_r2.log','PASS tb_yunet_shared_tracker'),
        'shared_color_queue':('reports/yunet_v53/shared_region.log','PASS tb_yunet_shared_region'),
        'full_color_queue':('reports/yunet_v53/region_capacity.log','PASS tb_yunet_region_capacity'),
        'exhaustive_add':('reports/yunet_v49/misc_sim.log','PASS tb_yunet_misc_exact'),
        'legacy_tracker':('reports/vision_tasks/tracker_v53_shared.log','PASS tb_vision_tracker'),
        'legacy_tasks':('reports/vision_tasks/task_suite_v53_shared.log','PASS tb_vision_task_suite'),
        'legacy_region':('reports/vision_tasks/region_v53_shared.log','PASS tb_vision_region'),
        'legacy_overflow':('reports/vision_tasks/region_overflow_v53_shared.log','PASS tb_vision_region'),
        'sampler':('reports/yunet_v45/sampler_sim.log','PASS tb_yunet_rgb_snapshot'),
        'dot':('reports/yunet_v45/dot_sim.log','PASS tb_yunet_dot4'),
        'decoder':('reports/yunet_v45/decode_sim_r2.log','PASS tb_yunet_decode'),
    }
    evidence={};logs={}
    for name,(rel,marker) in checks.items():
        data=git_blob(rel);text=data.decode('utf-8',errors='replace')
        if marker not in text or re.search(r'\*\* (Fatal|Error)|\bFAIL\b',text):errors.append('Functional proof did not pass: '+name)
        evidence[name]=dict(commit=BASE,path=rel,sha256=digest(data),marker=marker);logs[rel]=data
    cp=ROOT/f'doc/compile/{version}_completion.json';jp=ROOT/f'doc/compile/{version}_job.json'
    build=json.loads(cp.read_text(encoding='utf-8')) if cp.exists() else None
    job=json.loads(jp.read_text(encoding='utf-8')) if jp.exists() else None
    if not build or not job:errors.append('Integrated build not complete')
    else:
        if build['status']!='passed' or job['status']!='passed':errors.append('Integrated build failed')
        if any(build.get(k) is None or build[k]>n for k,n in [('slices',21216),('ram',108),('dsp',40),('memory_slices',8112)]):errors.append('Physical capacity missing or exceeded')
        if any(build.get(k) is None or build[k]<0 for k in ('setup_wns_ns','hold_wns_ns')) or any(build.get(k)!=0 for k in ('setup_tns_ns','hold_tns_ns')):errors.append('Final routed setup/hold failed')
        bit=run/'phy/camera_to_dsi_display.bit'
        if not bit.exists() or digest(bit.read_bytes())!=str(build.get('bit_sha256')).lower():errors.append('Bitstream checksum mismatch')
    for marker in ('.opt_place.end.f','.opt_route.end.f','.bitgen.end.f'):
        if not (run/'phy'/marker).exists():errors.append('Missing physical success marker: '+marker)
    model=ROOT/'models/yunet/face_detection_yunet_2023mar.onnx'
    if digest(model.read_bytes())!='8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4':errors.append('Original model mismatch')
    report=dict(status='passed' if not errors else 'incomplete',errors=errors,run=a.run,build=build,explicit_inputs=len(inputs),
        functional_baseline=BASE,input_differences=changes,tests=evidence,
        scope='Complete YuNet integer inference on FPGA; FACE11, compact OSD, preserved template/color tracking and gimbal controls',
        limits=['Small photo probes and arithmetic verification are not independent accuracy evaluation.',
                'Core computes a new position in about 0.27 seconds; video FPS is not detector FPS.',
                'No camera-board or mechanical closed-loop acceptance has been performed.'],flashed=False,board_verified=False)
    out=ROOT/'reports'/('face_release_'+version);out.mkdir(exist_ok=True,parents=True)
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=report['status'],errors=errors,build=build),indent=2))
    if errors:raise SystemExit(1)
    if not a.archive:return
    main_root=ROOT
    if ROOT.parent.name=='worktrees':main_root=ROOT.parent.parent
    destination=main_root/'releases'/('vision_face_cnn_'+version)
    if destination.exists():raise FileExistsError('Preserve existing release '+str(destination))
    for rel in inputs:
        target=destination/'source'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,target)
    shutil.copy2(run/'source_sha256.txt',destination/'source_sha256.txt')
    for folder in ('models/yunet','scripts','sim/face_cnn'):
        for source in (ROOT/folder).glob('*'):
            if source.is_file() and (folder!='scripts' or source.name.startswith(('yunet_','run_yunet','build_yunet','face_cnn_release'))):
                target=destination/'evidence'/folder/source.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for source in (ROOT/'sim/face_lbp/data').glob('*.jpg'):
        target=destination/'evidence/sim/face_lbp/data'/source.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for rel,data in logs.items():
        target=destination/'evidence/pinned_functional'/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    for folder in ('reports/yunet_v45','reports/yunet_v48'):
        for pattern in ('input.hex','op_*.hex','op_checks.txt','native_shift.hex','native_expected.txt'):
            for source in (ROOT/folder).glob(pattern):
                target=destination/'evidence'/folder/source.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for pattern in ('*.bit','*.ts','*.timing','*.area','*.log','*.sdc','*.adc','*.cfg'):
        for source in (run/'phy').glob(pattern):
            target=destination/'build/phy'/source.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for source in (cp,jp,out/'validation.json'):
        shutil.copy2(source,destination/source.name)
    (destination/'completion.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    manifest=[dict(path=f.relative_to(destination).as_posix(),bytes=f.stat().st_size,sha256=digest(f.read_bytes()))
        for f in sorted(destination.rglob('*')) if f.is_file()]
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    for item in manifest:
        if digest((destination/item['path']).read_bytes())!=item['sha256']:raise RuntimeError('Archive checksum')
    print(f'Archived {len(manifest)} files: {destination}')
if __name__=='__main__':main()
