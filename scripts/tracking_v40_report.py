"""Validate the selected native regressions; optionally archive a routed bit."""
from pathlib import Path
import argparse, hashlib, json, re, shutil

ROOT=Path(__file__).resolve().parents[1]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser();p.add_argument('--run');p.add_argument('--archive');a=p.parse_args()
    tests={}
    for case in ['upright','close_2.9','roll_plus30','roll_minus30','fruits']:
        tests['face_full_'+case]=(f'reports/face_pose/v40_r4_full/{case}_modelsim.log',f'PASS tb_face_pose {case}')
    for case in ['upright','roll_plus30','hopper','dim','periodic']:
        tests['face_local_'+case]=(f'reports/face_pose/v40_r4_local/{case}_modelsim.log',f'PASS tb_face_local_search {case}')
    for top in ['face_position_overlay','face_video_timeout','face_video_result_ttl','face_temporal','face_video_mode']:
        tests[top]=(f'reports/face_pose/v40_r4/video/tb_{top}.log',f'PASS tb_{top}')
    tests['selector_reference']=('reports/tracking_v40/selector_r4.log','PASS tb_face_selector')
    tests['selector_protocol']=('reports/tracking_v40/protocol_r4.log','PASS protocol')
    tests['bounded_patch_policy']=('reports/tracking_v40/patch_policy.log','PASS tb_face_patch_policy')
    for name,variant in [('scale','v40_scale'),('scale_negative','v40_final'),('local_recovery','v40_r3'),
                         ('region_identity','v40_r3'),('region','v40_r3'),('region_overflow','v40_r3'),
                         ('tracker','v40_tracking'),('task_suite','v40_final'),('task_osd','v40_final'),('hud','v40_final'),
                         ('sampler','v40_final'),('demo_cdc','v40_final'),('gaussian','v40_final'),('legacy_fixes','v40_final')]:
        top='scale' if name=='scale_negative' else 'region' if name=='region_overflow' else name
        tests[name]=(f'reports/vision_tasks/{name}_{variant}.log',f'PASS tb_vision_{top}')
    for variant,top in [('controls','gimbal_pipeline'),('target','gimbal_target'),('region','region_buttons'),('pipeline','face_pipeline')]:
        folder='v40_r3_region' if variant=='region' else 'v40_r4_pipeline' if variant=='pipeline' else 'v40_'+variant
        tests['integration_'+variant]=(f'reports/face_pose/{folder}/tb_{top}.log',f'PASS tb_{top}')
    # These sources are byte-identical to v38; the source delta gate below
    # prevents accidentally reusing their checks after changing those modules.
    for key,top in [('controller','servo_gimbal'),('production_pwm','servo_production'),('panel','gimbal_panel'),('osd_modes','gimbal_osd')]:
        tests['reused_v38_'+key]=(f'releases/vision_gimbal_v38_r1/evidence/reports/gimbal/v38_final/tb_{top}.log',f'PASS tb_{top}')
    checked={};errors=[]
    for name,(path,marker) in tests.items():
        f=ROOT/path
        if not f.exists():errors.append('Missing '+path);continue
        s=f.read_text(encoding='utf-8',errors='replace')
        if marker not in s or re.search(r'\*\* (Error|Fatal)|\bFAIL\b',s):errors.append('Not passed '+path);continue
        checked[name]=dict(path=path,sha256=sha(f),marker=marker)
    changes=[]
    base=ROOT/'releases/vision_gimbal_v38_r1/source_sha256.txt'
    for line in base.read_text(encoding='utf-8').splitlines():
        old,path=line.split('  ',1)
        if sha(ROOT/path)!=old.lower():changes.append(path.replace('\\','/'))
    expected={'rtl/analytics/face_lbp/'+x+'.v' for x in ['face_lbp_core','face_candidate_select','face_detector_snapshot','face_pose_snapshot','face_video_position']}
    expected|={'rtl/analytics/vision_tasks/'+x+'.v' for x in ['vision_color_region','vision_sad_tracker','vision_task_suite']}
    if set(changes)!=expected:errors.append('Unexpected source delta from verified v38: '+str(changes))
    reused_hashes={}
    for name in ['vision_color_region','vision_sad_tracker','vision_task_suite']:
        path='rtl/analytics/vision_tasks/'+name+'.v'
        prior=ROOT/'reports/tracking_v40/r3_source'/path
        if not prior.exists() or sha(prior)!=sha(ROOT/path):
            errors.append('Reused analytics regressions no longer match r3 snapshot: '+path)
        else:reused_hashes[path]=sha(prior)
    local={}
    import csv
    for case in ['upright','roll_plus30','hopper','dim','periodic']:
        f=ROOT/f'reports/face_pose/v40_r4_local/{case}_sequence.csv'
        if f.exists():
            rows=list(csv.DictReader(f.open(encoding='utf-8')))
            local[case]=[{**r,'compute_ms_at_75MHz':round(int(r['cycles'])/75000,4)} for r in rows]
    report=dict(status='passed' if not errors else 'incomplete',errors=errors,tests=checked,
                changed_active_sources=changes,reused_analytics_source_sha256=reused_hashes,face_local_sequences=local,
                local_test_scope={'upright':'motion, negative fallback, reacquisition','roll_plus30':'motion, negative fallback, reacquisition',
                                  'hopper':'three positive moving frames only','dim':'three positive moving frames only','periodic':'nine frames, continuously verified local search without forced global-scan stalls'},
                board_verified=False,flashed=False,scope='face, selected-template and color tracking; category recognition cancelled')
    out=ROOT/'reports/tracking_v40';out.mkdir(parents=True,exist_ok=True)
    (out/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['status'],passed=len(checked),errors=errors),ensure_ascii=False,indent=2))
    if errors:raise SystemExit(1)
    if not a.archive:return
    if not a.run or not re.fullmatch(r'colorshading_runs_[A-Za-z0-9_]+',a.run) or not re.fullmatch(r'[A-Za-z0-9_]+',a.archive):raise ValueError('Invalid run/archive')
    version=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',a.run).group(1)
    completion=ROOT/f'doc/compile/{version}_completion.json';job=ROOT/f'doc/compile/{version}_job.json'
    build=json.loads(completion.read_text(encoding='utf-8'));j=json.loads(job.read_text(encoding='utf-8'))
    if build['status']!='passed' or j['status']!='passed':raise ValueError('Build not passed')
    if build['setup_wns_ns']<0 or build['hold_wns_ns']<0 or build['setup_tns_ns'] or build['hold_tns_ns']:raise ValueError('Timing failed')
    if build['slices']>21216 or build['ram']>108 or build['dsp']>40:raise ValueError('Capacity failed')
    run=ROOT/'td_project'/a.run;bit=run/'phy/camera_to_dsi_display.bit'
    if sha(bit)!=build['bit_sha256'].lower():raise ValueError('Bit checksum mismatch')
    dest=ROOT/'releases'/a.archive
    if dest.exists():raise ValueError('Archive already exists')
    sources=[]
    for line in (run/'source_sha256.txt').read_text(encoding='utf-8').splitlines():
        digest,path=line.split('  ',1);f=ROOT/path
        if sha(f)!=digest.lower():raise ValueError('Sources changed after build: '+path)
        sources.append(f)
    def copy(f,target):target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
    for f in sources:copy(f,dest/'source'/f.relative_to(ROOT))
    for f in [completion,job,run/'source_sha256.txt']:copy(f,dest/f.name)
    for folder in ['syn','phy']:
        for f in (run/folder).iterdir():
            if f.is_file() and f.suffix.lower() in ['.bit','.log','.logw','.area','.sta','.rpt','.json','.ts','.timing','.prj','.cfg','.tcl']:copy(f,dest/'build'/folder/f.name)
    for t in checked.values():copy(ROOT/t['path'],dest/'evidence'/t['path'])
    extras=[ROOT/'td_project/camera_to_dsi_display.al',ROOT/'td_project/build_colorshading.ps1',ROOT/'doc/tracking_v40_validation.md',ROOT/'doc/tracking_v40_board_check.md',ROOT/'doc/gimbal_wiring_hx1p35a.md',out/'validation.json',ROOT/f'reports/vision_tasks/v40_build_{version.rsplit("_",1)[-1]}_console.log']
    for f in out.glob('r1*json'):extras.append(f)
    extras.append(out/'selector_resources.json')
    extras.append(ROOT/'rtl/analytics/face_lbp/README.md')
    extras.append(ROOT/'README.md')
    for d in ['scripts','sim','sim/face_lbp','sim/face_lbp/data','sim/face_lbp/models','sim/face_pose','sim/vision_tasks','sim/vision_tasks/scale_v40','sim/vision_tasks/rotation']:
        for f in (ROOT/d).iterdir():
            if f.is_file() and f.suffix.lower() in ['.py','.ps1','.v','.sv','.hex','.expected','.target','.txt','.md','.xml','.jpg','.png']:extras.append(f)
    for d in ['reports/face_pose/v40_r4_local','reports/face_pose/v40_r4_full','reports/face_pose/v40_r4/video','reports/vision_tasks/scale_v40']:
        for f in (ROOT/d).iterdir():
            if f.is_file() and f.suffix.lower() in ['.csv','.json','.png']:extras.append(f)
    for f in extras:
        if f.exists():copy(f,dest/'source'/f.relative_to(ROOT))
    report['build']=build
    (dest/'completion.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    manifest=[dict(path=f.relative_to(dest).as_posix(),sha256=sha(f),bytes=f.stat().st_size) for f in sorted(dest.rglob('*')) if f.is_file()]
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    for item in manifest:
        if sha(dest/item['path'])!=item['sha256']:raise ValueError('Archive verification failed')
    print(json.dumps(dict(archive=str(dest),files=len(manifest),bit_sha256=sha(bit)),indent=2))

if __name__=='__main__':main()
