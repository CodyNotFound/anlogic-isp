"""Archive only a timing-clean gimbal bit with checked sources and test logs."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--name',required=True);p.add_argument('--profile',choices=['v36','v37','v38'],default='v36');a=p.parse_args()
 if not re.fullmatch(r'colorshading_runs_[A-Za-z0-9_]+',a.run) or not re.fullmatch(r'[A-Za-z0-9_]+',a.name):raise ValueError('Invalid name')
 version=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',a.run).group(1)
 run=ROOT/'td_project'/a.run;doc=ROOT/'doc/compile'
 job=json.loads((doc/(version+'_job.json')).read_text(encoding='utf-8'))
 completion=json.loads((doc/(version+'_completion.json')).read_text(encoding='utf-8'))
 if job['status']!='passed' or completion['status']!='passed':raise ValueError('Build not passed')
 if completion['setup_wns_ns']<0 or completion['hold_wns_ns']<0 or completion['setup_tns_ns']!=0 or completion['hold_tns_ns']!=0:raise ValueError('Timing failed')
 if completion['slices']>21216 or completion['ram']>108 or completion['dsp']>40:raise ValueError('Resource failed')
 bit=run/'phy/camera_to_dsi_display.bit'
 if sha(bit)!=completion['bit_sha256'].lower():raise ValueError('Bit checksum differs')
 sources=[]
 for line in (run/'source_sha256.txt').read_text(encoding='utf-8').splitlines():
  digest,rel=line.split('  ',1);src=ROOT/rel
  if sha(src)!=digest.lower():raise ValueError('Stale build source: '+rel)
  sources.append(src)
 tests={
  'controller':('reports/gimbal/tb_servo_gimbal.log','PASS tb_servo_gimbal'),
  'production_pwm':('reports/gimbal/tb_servo_production.log','PASS tb_servo_production'),
  'panel':('reports/gimbal/tb_gimbal_panel.log','PASS tb_gimbal_panel'),
  'osd_modes':('reports/gimbal/tb_gimbal_osd.log','PASS tb_gimbal_osd'),
  'target_handshake':('reports/face_pose/v36_target/tb_gimbal_target.log','PASS tb_gimbal_target'),
  'controls':('reports/face_pose/v36_controls_final/tb_gimbal_pipeline.log','PASS tb_gimbal_pipeline'),
  'face_video':('reports/face_pose/v36_final/tb_face_pipeline.log','PASS tb_face_pipeline'),
  'native_tracking':('reports/vision_tasks/task_suite_v36_gimbal.log','PASS tb_vision_task_suite'),
  'compositor':('reports/vision_tasks/task_osd_v36_final.log','PASS tb_vision_task_osd'),
  'buzzer':('reports/gimbal/buzz_sim/tb_buzz_ctrl.log','TB_BUZZ_PASS'),
  'buzzer_production':('reports/gimbal/buzz_sim/tb_buzz_production.log','TB_BUZZ_PRODUCTION_PASS'),
  'legacy_osd':('sim/tb_ref_osd_mixer.log','PASS tb_ref_osd_mixer'),
  'legacy_modes':('sim/tb_mode_ctrl_ref_modes.log','PASS tb_mode_ctrl_ref_modes'),
  'legacy_pixels':('sim/tb_pixel_algorithm_ref_modes.log','PASS tb_pixel_algorithm_ref_modes'),
  'ab_osd':('reports/gimbal/ab_osd.log','PASS tb_ab_before_osd')}
 if a.profile in ('v37','v38'):
  tests.update({
   'target_handshake':('reports/face_pose/v37_target/tb_gimbal_target.log','PASS tb_gimbal_target'),
   'controls':('reports/face_pose/v37_controls/tb_gimbal_pipeline.log','PASS tb_gimbal_pipeline'),
   'region_buttons_pwm':('reports/face_pose/v37_buttons_final/tb_region_buttons.log','PASS tb_region_buttons'),
   'face_video':('reports/face_pose/v37_final/tb_face_pipeline.log','PASS tb_face_pipeline'),
   'native_tracking':('reports/vision_tasks/task_suite_v37_final.log','PASS tb_vision_task_suite'),
   'region_cases':('reports/vision_tasks/region_v37.log','PASS tb_vision_region'),
   'region_overflow':('reports/vision_tasks/region_overflow_v37.log','PASS tb_vision_region'),
   'compositor':('reports/vision_tasks/task_osd_v37_glyph.log','PASS tb_vision_task_osd'),
   'task_hud':('reports/vision_tasks/hud_v37_glyph.log','PASS tb_vision_hud'),
   'region_compositor':('reports/gimbal/v37/full_region_osd.log','PASS tb_vision_task_osd'),
   'ab_osd':('reports/gimbal/ab_osd.log','PASS tb_ab_before_osd')})
 if a.profile=='v38':
  for name,top in [('controller','servo_gimbal'),('production_pwm','servo_production'),('panel','gimbal_panel'),('osd_modes','gimbal_osd')]:
   tests[name]=('reports/gimbal/v38_final/tb_'+top+'.log','PASS tb_'+top)
  tests['controls']=('reports/face_pose/v38_final_controls/tb_gimbal_pipeline.log','PASS tb_gimbal_pipeline')
  tests['region_buttons_pwm']=('reports/face_pose/v38_final_buttons/tb_region_buttons.log','PASS tb_region_buttons')
  tests['speed_benchmark']=('reports/gimbal/v38_final/tb_gimbal_speed.log','PASS tb_gimbal_speed')
  tests['analysis_latency']=('reports/gimbal/v38_final/tb_gimbal_analysis_latency.log','PASS tb_gimbal_analysis_latency')
 checked={}
 for name,(rel,marker) in tests.items():
  log=ROOT/rel;text=log.read_text(encoding='utf-8',errors='replace')
  if marker not in text or re.search(r'\*\* (Error|Fatal)',text):raise ValueError('Test failed: '+name)
  checked[name]={'path':rel,'sha256':sha(log),'passed':True}
 dest=ROOT/'releases'/a.name
 if dest.exists():raise ValueError('Preserve existing archive; use fresh name')
 extras=['td_project/camera_to_dsi_display.al','td_project/build_colorshading.ps1','scripts/run_td_verified.ps1',
 'scripts/on_td_complete.ps1','scripts/run_gimbal_sim.ps1','scripts/run_buzz_sim.ps1','scripts/run_face_pipeline_sim.ps1',
 'scripts/run_vision_tasks_sim.ps1','scripts/run_osd_checks.ps1','scripts/archive_gimbal_release.py',
 'doc/gimbal_wiring_hx1p35a.md','doc/gimbal_panel_plan_20261021.md','doc/gimbal_v36_validation.md','README.md',
 'reports/gimbal/functional_source_sha256.json','reports/gimbal/manual_panel.png','reports/gimbal/docs/manual_page7.png',
 'sim/tb_servo_gimbal.v','sim/tb_gimbal_panel.sv','sim/tb_gimbal_osd.sv','sim/tb_gimbal_pipeline.sv',
 'sim/tb_gimbal_target.sv','sim/tb_buzz_ctrl.v','sim/tb_ab_before_osd.v','scripts/run_ab_osd_sim.ps1','scripts/run_camera_path_checks.ps1','scripts/vision_tasks_reference.py','sim/face_lbp/tb_face_pipeline.sv',
 'sim/osd_font_rom.hex','sim/logo_idx.hex','sim/logo_pal.hex','sim/osd_rom_sim_models.v','sim/osd_rom_real_models.v',
 'sim/tb_ref_osd_mixer.v','sim/tb_mode_ctrl_ref_modes.v','sim/tb_pixel_algorithm_ref_modes.v']
 if a.profile in ('v37','v38'):
  extras += ['sim/tb_region_buttons.sv','doc/gimbal_v37_validation.md']
  extras += ['reports/gimbal/v37/tracking_osd.png','reports/gimbal/v37/region_osd.png']
 if a.profile=='v38':
  extras += ['sim/tb_gimbal_speed.sv','sim/tb_gimbal_analysis_latency.sv','scripts/run_gimbal_speed_sim.ps1','reports/gimbal/v38_final/servo_v37_baseline.v','reports/gimbal/v38_final/speed_measurements.csv','reports/gimbal/v38_final/analysis_latency.csv','reports/gimbal/v38_final/functional_checks.json','doc/gimbal_v38_validation.md']
 extras += [str(x.relative_to(ROOT)) for pattern in ['*.sv','*.hex','*.txt'] for x in (ROOT/'sim/vision_tasks').glob(pattern)]
 copies={str(src.relative_to(ROOT)):dest/'source'/src.relative_to(ROOT) for src in sources}
 for rel in extras:copies[rel]=dest/'source'/rel
 for rel,output in copies.items():
  output.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,output)
 for folder in ['syn','phy']:
  for pattern in ['*.area','*.ts','*.timing','*.log','*.bit']:
   for src in (run/folder).glob(pattern):
    out=dest/'build'/folder/src.name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,out)
 for src in [run/'source_sha256.txt',doc/(version+'_job.json'),doc/(version+'_completion.json')]:shutil.copy2(src,dest/src.name)
 for test in checked.values():
  src=ROOT/test['path'];out=dest/'evidence'/test['path'];out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,out)
 for src in (ROOT/'reports/gimbal').glob('*.png'):shutil.copy2(src,dest/'evidence'/src.name)
 if a.profile in ('v37','v38'):
  for pattern in ['*.png','*.log','*.json','*.txt']:
   for src in (ROOT/'reports/gimbal/v37').glob(pattern):
    # Passing test logs are copied above. Retain the controlled old-RTL
    # rejection separately, without mixing abandoned build/test attempts in.
    prior_build='build_r3_console.log' if a.profile=='v38' else 'build_'+version.rsplit('_',1)[-1]+'_console.log'
    if src.suffix=='.log' and src.name not in {'old_skin_rejection.log','old_region_compile.log',prior_build}:continue
    shutil.copy2(src,dest/'evidence'/src.name)
 if a.profile=='v38':
  src=ROOT/'reports/gimbal'/('v38_build_'+version.rsplit('_',1)[-1]+'_console.log')
  shutil.copy2(src,dest/'evidence'/src.name)
 summary={'build':completion,'functional_tests':checked,'board_model_user_confirmed':'HX1P35A',
 'J1':{'1':'C18 horizontal PWM','2':'D15 vertical PWM','12':'GND'},
 'limits_us':{'h':[500,2500],'v':[1050,2150]},'flashed':False,'board_verified':False,
 'native_suite_note':'Native pixel regression predates the export-only TTL fix; final first-result handshake separately tested.',
 'ab_fixture_note':'AB isolation disables face detection; its log includes unused face-ROM relative-path warnings. Production Check and the full FACE regression load explicit model ROMs.'}
 if a.profile in ('v37','v38'):
  summary['controls']={'AWB':'always on','SW1':'AB','SW2':'AE','SW3':'AUTO','SW4':'MANUAL priority','auto_off':'hold position; no home','K3':'down in manual; no ISP demo'}
  summary['auto_sources']=['FACE','TRACK','REGION']
  summary['native_suite_note']='Current native suite and first-result handshake tested.'
  summary['ab_fixture_note']='AB isolation uses explicit face-ROM paths; FACE/passthrough is separately checked with native pixels.'
 if a.profile=='v38':
  summary['motion']={'manual_fine_us':4,'manual_fast_us':32,'acceleration_ms':200,'auto_max_us_per_result':32,'auto_near_center_us':1}
  summary['pixel_regression_note']='v37 pixel/analytics regressions reused: only the servo controller changed; v38 reruns PWM, panel, OSD, buttons, and native REGION-to-PWM integration.'
 (dest/'completion.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
 manifest=[{'path':str(f.relative_to(dest)).replace('\\','/'),'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(dest.rglob('*')) if f.is_file()]
 (dest/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 for item in manifest:
  if sha(dest/item['path'])!=item['sha256']:raise ValueError('Copy verification failed')
 print(json.dumps({'archive':str(dest),'files':len(manifest),'bit_sha256':sha(bit)},indent=2))
if __name__=='__main__':main()
