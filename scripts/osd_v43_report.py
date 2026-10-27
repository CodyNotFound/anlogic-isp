"""Gate and archive v43 with current-source, simulation, routed STA and bit evidence."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
from datetime import datetime,timezone

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/osd_v43'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def hashes(path):return {r.replace('\\','/'):h.lower() for h,r in
    (s.split('  ',1) for s in path.read_text(encoding='utf-8').splitlines() if s.strip())}

def main():
    p=argparse.ArgumentParser();p.add_argument('--run',default='colorshading_runs_20261025_v43_osd_r2')
    p.add_argument('--archive',action='store_true');a=p.parse_args()
    if not re.fullmatch(r'colorshading_runs_[A-Za-z0-9_]+',a.run):raise ValueError('run')
    version=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',a.run)[1]
    run=ROOT/'td_project'/a.run
    errors=[];tests={}
    first_job=json.loads((ROOT/'doc/compile/v43_osd_r1_job.json').read_text(encoding='utf-8'))
    fresh_since=datetime.fromisoformat(first_job['started_utc'].replace('Z','+00:00')).timestamp()
    checks={
      'compact_rgb':('reports/osd_v43/tb_osd_v43_r2.log','PASS tb_osd_v43'),
      'buttons':('reports/face_pose/v43_buttons/tb_gimbal_pipeline.log','PASS tb_gimbal_pipeline'),
      'region_controls':('reports/face_pose/v43_region/tb_region_buttons.log','PASS tb_region_buttons'),
      'face_overlay':('reports/face_pose/v43_face/tb_face_pipeline.log','PASS tb_face_pipeline'),
      'task_suite':('reports/vision_tasks/task_suite_v43_suite.log','PASS tb_vision_task_suite'),
      'hud':('reports/vision_tasks/hud_v43_suite.log','PASS tb_vision_hud'),
      'servo':('reports/gimbal/v43_servo/tb_servo_gimbal.log','PASS tb_servo_gimbal'),
      'production_pwm':('reports/gimbal/v43_servo/tb_servo_production.log','PASS tb_servo_production'),
      'panel':('reports/gimbal/v43_servo/tb_gimbal_panel.log','PASS tb_gimbal_panel'),
      'legacy_mixer':('sim/tb_ref_osd_mixer.log','PASS tb_ref_osd_mixer'),
      'legacy_pixels':('sim/tb_pixel_algorithm_ref_modes.log','PASS tb_pixel_algorithm_ref_modes'),
      'mode_buttons':('sim/tb_mode_ctrl_ref_modes.log','PASS tb_mode_ctrl_ref_modes'),
    }
    for name,(rel,marker) in checks.items():
        path=ROOT/rel
        if not path.exists():errors.append('Missing '+rel);continue
        s=path.read_text(encoding='utf-8',errors='replace')
        if marker not in s or re.search(r'\*\* (Error|Fatal)|\bFAIL\b',s):errors.append('Not passed '+rel);continue
        # Do not admit older logs under shared filenames.
        if path.stat().st_mtime < fresh_since:errors.append('Stale log '+rel);continue
        tests[name]={'path':rel,'sha256':sha(path),'marker':marker}
    completion_path=ROOT/f'doc/compile/{version}_completion.json'
    job_path=ROOT/f'doc/compile/{version}_job.json'
    build=None
    if not completion_path.exists():errors.append('Build not complete')
    else:
        build=json.loads(completion_path.read_text(encoding='utf-8'))
        job=json.loads(job_path.read_text(encoding='utf-8'))
        if build['status']!='passed' or job['status']!='passed':errors.append('Build failed')
        if build['setup_wns_ns']<0 or build['hold_wns_ns']<0 or build['setup_tns_ns'] or build['hold_tns_ns']:errors.append('Routed timing')
        if build['slices']>21216 or build['ram']>108 or build['dsp']>40:errors.append('Physical capacity')
        if sha(run/'phy/camera_to_dsi_display.bit')!=build['bit_sha256'].lower():errors.append('Bit checksum')
    current=hashes(run/'source_sha256.txt') if (run/'source_sha256.txt').exists() else {}
    if len(current)!=106:errors.append(f'Expected 106 explicit build inputs, got {len(current)}')
    for rel,h in current.items():
        if not (ROOT/rel).exists() or sha(ROOT/rel)!=h:errors.append('Current source differs: '+rel)
    base=hashes(ROOT/'releases/vision_color_tracking_v42_r3/source_sha256.txt')
    changed=[r for r,h in current.items() if base.get(r)!=h]
    # Mandatory branding assets and all camera/pixel algorithms are unchanged.
    for rel in ['user_source/hdl_source/osd_logo_idx.mif','user_source/hdl_source/osd_logo_pal.mif',
                'user_source/hdl_source/osd_font_rom.mif','rtl/isp/pixel_algorithm.v',
                'rtl/isp/pixel_cartoon.v','rtl/isp/color_tone4.v','rtl/control/servo_gimbal_ctrl.v',
                'rtl/analytics/face_lbp/face_pose_snapshot.v','rtl/analytics/vision_tasks/vision_color_region.v']:
        if sha(ROOT/rel)!=base[rel]:errors.append('Unexpected algorithm/asset change: '+rel)
    report=dict(status='passed' if not errors else 'incomplete',errors=errors,run=a.run,tests=tests,
        explicit_inputs=len(current),changed_from_v42=changed,build=build,
        scope='Compact shared-font OSD; SW3 info visibility with mandatory logo; automatic tracking modes independent of SW3',
        simulation_boundary='Injected positions validate composition/control only; no classifier accuracy claim',
        flashed=False,board_verified=False)
    OUT.mkdir(exist_ok=True,parents=True)
    (OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=report['status'],tests=len(tests),errors=errors,build=build),ensure_ascii=False))
    if errors:raise SystemExit(1)
    if not a.archive:return
    destination=ROOT/'releases'/('vision_osd_'+version.replace('_osd_','_'))
    if destination.exists():raise FileExistsError('Preserve existing release: '+str(destination))
    for rel in current:
        target=destination/'source'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,target)
    shutil.copy2(run/'source_sha256.txt',destination/'source_sha256.txt')
    for name in ['phy','syn']:
        for pattern in (['*.bit','*.sta','*.rpt','*.area','*.qor','*.log','*.adc','*.sdc','*.cfg'] if name=='phy' else ['*.area','*.log','*.cfg']):
            for source in (run/name).glob(pattern):
                target=destination/'build'/name/source.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    evidence=set(r['path'] for r in tests.values())|{
        'reports/osd_v43/validation.json','scripts/osd_v43_reference.py','scripts/run_osd_v43_sim.ps1',
        'scripts/osd_v43_report.py','sim/tb_osd_v43.sv','doc/osd_v43.md','doc/gimbal_wiring_hx1p35a.md',
        'sim/tb_gimbal_pipeline.sv','sim/tb_region_buttons.sv','sim/face_lbp/tb_face_pipeline.sv',
        'sim/vision_tasks/tb_vision_task_suite.sv','sim/vision_tasks/tb_vision_task_osd.sv',
        'sim/osd_font_rom.hex','sim/logo_idx.hex','sim/logo_pal.hex'}
    evidence.update(p.relative_to(ROOT).as_posix() for p in OUT.glob('expected_*.png'))
    evidence.update(p.relative_to(ROOT).as_posix() for p in OUT.glob('compile_*.log'))
    for rel in sorted(evidence):
        target=destination/'evidence'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,target)
    for source in [completion_path,job_path]:shutil.copy2(source,destination/source.name)
    shutil.copy2(OUT/'validation.json',destination/'completion.json')
    manifest=[dict(path=f.relative_to(destination).as_posix(),bytes=f.stat().st_size,sha256=sha(f))
        for f in sorted(destination.rglob('*')) if f.is_file()]
    (destination/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for item in manifest:
        if sha(destination/item['path'])!=item['sha256']:raise RuntimeError('Archive checksum: '+item['path'])
    print(f'Archived {len(manifest)} files: {destination}')

if __name__=='__main__':main()
