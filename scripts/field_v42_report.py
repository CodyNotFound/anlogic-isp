"""Audit functional evidence, current inputs, routed STA and release contents."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/field_v42'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def entries(p):return {rel.replace('\\','/'):h.lower() for h,rel in (line.split('  ',1) for line in p.read_text(encoding='utf-8').splitlines())}
def main():
 p=argparse.ArgumentParser();p.add_argument('--run',default='colorshading_runs_20261024_v42_field_r3');p.add_argument('--archive');a=p.parse_args()
 if not re.fullmatch('colorshading_runs_[A-Za-z0-9_]+',a.run):raise ValueError('run')
 run=ROOT/'td_project'/a.run;version=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',a.run)[1]
 pipelined=not a.run.endswith(('_r1','_r2'))
 tests={}
 for name in ['region','region_overflow','region_identity','region_lighting','legacy_fixes','gaussian','task_suite','task_osd','hud','sampler']:
  top='tb_vision_region' if name=='region_overflow' else 'tb_vision_'+name
  tests[name]=(f'reports/vision_tasks/{name}_v42_field.log','PASS '+top)
  if pipelined and name in ['region','region_overflow','region_identity','region_lighting','task_suite','task_osd']:
   tests[name]=(f'reports/vision_tasks/{name}_v42_pipe.log','PASS '+top)
 tests['edge']=('reports/field_v42/edge.log','PASS tb_vision_edge_lighting')
 for name in ['shadow_chroma','color_tone4']:tests[name]=(f'reports/field_v42/tb_{name}.log','PASS tb_'+name)
 for name in ['servo_gimbal','servo_production','gimbal_panel','gimbal_osd']:tests[name]=(f'reports/gimbal/v42_field/tb_{name}.log','PASS tb_'+name)
 for key,directory,top in [('ab_inverse','v42_ab_inverse','tb_field_pipeline'),('native_cartoon','v42_native_cartoon','tb_cartoon_pipeline'),('native_face','v42_native_face','tb_face_pipeline'),('gimbal_target','v42_gimbal_target','tb_gimbal_target'),('region_buttons','v42_region_buttons','tb_region_buttons'),('gimbal_buttons','v42_gimbal_buttons','tb_gimbal_pipeline')]:tests[key]=(f'reports/face_pose/{directory}/{top}.log','PASS '+top)
 if pipelined:
  tests['gimbal_target']=('reports/face_pose/v42_gimbal_target_r3/tb_gimbal_target.log','PASS tb_gimbal_target')
  tests['region_buttons']=('reports/face_pose/v42_region_buttons_r3/tb_region_buttons.log','PASS tb_region_buttons')
 tests['analysis_interface']=('reports/field_v42/analysis_latency.log','PASS tb_gimbal_analysis_latency')
 tests['ab_osd']=('reports/gimbal/ab_osd.log','PASS tb_ab_before_osd')
 for top in ['tb_ref_osd_mixer','tb_mode_ctrl_ref_modes','tb_pixel_algorithm_ref_modes']:tests[top]=('sim/'+top+'.log','PASS '+top)
 for name in ['lena','fruits','grace_hopper','figurine','probes']:tests['cartoon_'+name]=(f'reports/cartoon_v41/{name}_modelsim.log','PASS tb_pixel_cartoon '+name)
 for width in [24,1280]:tests['compat_'+str(width)]=(f'reports/field_v42/compat_{width}.log','PASS tb_field_effect_compat')
 errors=[];checked={}
 from datetime import datetime
 first_job=json.loads((ROOT/'doc/compile/v42_field_r1_job.json').read_text(encoding='utf-8'))
 fresh_since=datetime.fromisoformat(first_job['started_utc'].replace('Z','+00:00')).timestamp()
 for name,(rel,marker) in tests.items():
  f=ROOT/rel
  if not f.exists():errors.append('Missing '+rel);continue
  text=f.read_text(encoding='utf-8',errors='replace')
  if marker not in text or re.search(r'\*\* (Error|Fatal)|\bFAIL\b',text):errors.append('Not passed '+rel);continue
  if rel.startswith('sim/') and f.stat().st_mtime<fresh_since:errors.append('Stale shared log '+rel);continue
  checked[name]=dict(path=rel,sha256=sha(f),marker=marker)
 base=entries(ROOT/'releases/vision_cartoon_v41_r2/source_sha256.txt');current=entries(run/'source_sha256.txt')
 if len(current)!=106 or set(current)!=set(base):errors.append('Unexpected source set')
 for rel,h in current.items():
  if sha(ROOT/rel)!=h:errors.append('Changed after Check '+rel)
 def project_tree(path):
  # TD project syntax is XML-like, with unescaped attribute contents.
  # Preserve all settings and normalize only the source paths, as TD does.
  text=path.read_text(encoding='utf-8')
  return re.sub(r'<File Path="([^"]+)"',lambda m:'<File Path="'+str((path.parent/m[1]).resolve()).lower()+'"',text)
 if project_tree(ROOT/'td_project/camera_to_dsi_display.al')!=project_tree(run/'syn/camera_to_dsi_display.prj'):errors.append('Project changed since compilation')
 changed=[rel for rel in current if base.get(rel)!=current[rel]]
 reused={}
 if pipelined:
  r2=entries(ROOT/'td_project/colorshading_runs_20261024_v42_field_r2/source_sha256.txt')
  if {p for p in current if current[p]!=r2.get(p)}!={'rtl/analytics/vision_tasks/vision_color_region.v'}:errors.append('Unexpected R3 delta from R2')
  fresh={'region','region_overflow','region_identity','region_lighting','task_suite','task_osd','gimbal_target','region_buttons','analysis_interface'}
  reused={name:'Unchanged component or display mode with color segmenter disabled; only R3 delta is internal color-mask pipeline' for name in tests if name not in fresh}
 expected={'rtl/analytics/vision_tasks/vision_color_region.v','rtl/analytics/vision_tasks/vision_task_suite.v','rtl/app/vision_pipeline.v','rtl/control/servo_gimbal_ctrl.v','rtl/isp/color_tone4.v','rtl/isp/pixel_algorithm.v','rtl/isp/pixel_cartoon.v','rtl/overlay/gimbal_osd.v'}
 if set(changed)!=expected:errors.append('Unexpected RTL changes')
 baseline=OUT/'baseline/color_old.log'
 if not baseline.exists() or not re.search('dim_tilt cal1 f0.*expected cal1 f1',baseline.read_text(encoding='utf-8',errors='replace')):errors.append('Old color failure not reproduced')
 images={}
 for name in ['lena','figurine','fruits','grace_hopper','native720']:
  directory=ROOT/'reports/cartoon_v41';f=directory/(name+'_pipeline.ppm' if name=='native720' else name+'_rtl.ppm');e=directory/(name+'_reference.png')
  if name=='native720' and 'native_cartoon' not in checked:continue
  if not f.exists() or not np.array_equal(np.array(Image.open(f)),np.array(Image.open(e))):errors.append('TOON RGB '+name)
  else:images['toon_'+name]=dict(path=f.relative_to(ROOT).as_posix(),sha256=sha(f))
 for name in (ROOT/'sim/vision_tasks/v42_edge/cases.txt').read_text(encoding='ascii').splitlines():
  f=OUT/f'edge_{name}_rtl.ppm';e=ROOT/f'sim/vision_tasks/v42_edge/{name}.expected'
  v=np.loadtxt(e,dtype=str);v=np.array([int(x,16) for x in v]);expected_rgb=np.stack([v>>16,(v>>8)&255,v&255],1).reshape(90,160,3).astype(np.uint8)
  if not f.exists() or not np.array_equal(np.array(Image.open(f)),expected_rgb):errors.append('Edge RGB '+name)
  else:images['edge_'+name]=dict(path=f.relative_to(ROOT).as_posix(),sha256=sha(f))
 if 'edge_figurine' in images:
  canvas=Image.new('RGB',(960,210),(24,30,40));draw=ImageDraw.Draw(canvas)
  for i,(kind,label) in enumerate([('input.png','INPUT'),('old.png','OLD THRESHOLD 80'),('rtl.ppm','FPGA RTL: GRADED CONTOUR')]):
   canvas.paste(Image.open(OUT/('edge_figurine_'+kind)).resize((320,180)),(i*320,30));draw.text((i*320+8,8),label,fill='white')
  canvas.save(OUT/'edge_comparison_rtl.png')
 completion=ROOT/f'doc/compile/{version}_completion.json';job_path=ROOT/f'doc/compile/{version}_job.json';job=json.loads(job_path.read_text(encoding='utf-8'));build=None
 if not completion.exists():errors.append('Build not complete' if job['status']!='failed' else 'Build failed: '+str(job['error']))
 else:
  build=json.loads(completion.read_text(encoding='utf-8'))
  if job['status']!='passed' or build['status']!='passed':errors.append('Build did not pass')
  if build['setup_wns_ns']<0 or build['hold_wns_ns']<0 or build['setup_tns_ns'] or build['hold_tns_ns']:errors.append('Routed timing failed')
  if build['slices']>21216 or build['ram']>108 or build['dsp']>40:errors.append('Capacity failed')
  bit=run/'phy/camera_to_dsi_display.bit'
  if not bit.exists() or sha(bit)!=build['bit_sha256'].lower():errors.append('Bit checksum')
 report=dict(status='passed' if not errors else 'incomplete',errors=errors,tests=checked,reused_r2_checks=reused,source_inputs=len(current),changed_from_v41=changed,unchanged_from_v41=len(current)-len(changed),image_checks=images,old_color_expected_failure=dict(path='reports/field_v42/baseline/color_old.log',sha256=sha(baseline)) if baseline.exists() else None,build=build,flashed=False,board_verified=False,
  scope='color illumination and reacquisition; indefinite servo hold; AB before effects; graded RGB/Y edges; shadow chroma suppression',
  test_scope_note='Final helper tweak only changes edge_out levels; existing native tests cover modes00/09/11/12/14, whose pixel expressions and interface are unchanged. Current 07 output and current TOON standalone RTL separately rechecked. No face accuracy claim.')
 (OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps(dict(status=report['status'],passed=len(checked),expected=len(tests),errors=errors),indent=2))
 if not a.archive:return
 if errors:raise ValueError('Release gates incomplete')
 if not re.fullmatch('[A-Za-z0-9_]+',a.archive):raise ValueError('archive')
 dest=ROOT/'releases'/a.archive
 if dest.exists():raise ValueError('Archive exists')
 def copy(f,target):target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
 for rel in current:copy(ROOT/rel,dest/'source'/rel)
 for f in [completion,job_path,run/'source_sha256.txt']:copy(f,dest/f.name)
 for directory in ['syn','phy']:
  for f in (run/directory).iterdir():
   if f.is_file() and f.suffix.lower() in ['.log','.logw','.bit','.area','.ts','.timing','.prj','.cfg','.tcl','.f','.qor']:copy(f,dest/'build'/directory/f.name)
 for v in checked.values():copy(ROOT/v['path'],dest/'evidence'/v['path'])
 extras=[ROOT/'README.md',ROOT/'doc/field_tracking_v42.md',ROOT/'td_project/camera_to_dsi_display.al',ROOT/'td_project/build_colorshading.ps1',ROOT/'sim/face_lbp/SOURCES.md',ROOT/'doc/compile/v42_field_r1_job.json',ROOT/'doc/compile/v42_field_r2_job.json',ROOT/'td_project/colorshading_runs_20261024_v42_field_r1/syn/check.log']
 dirs=['scripts','sim','sim/cartoon','sim/vision_tasks','sim/vision_tasks/v42_color','sim/vision_tasks/v42_edge','sim/face_lbp','sim/face_lbp/data','sim/face_lbp/models','reports/field_v42','reports/field_v42/baseline','reports/cartoon_v41']
 for directory in dirs:
  suffixes=['.py','.ps1','.v','.sv','.txt','.md','.hex','.expected','.png','.jpg','.ppm','.json','.xml']
  if directory.startswith('reports/field_v42'):suffixes+=['.log','.area','.ts','.timing','.csv']
  extras += [f for f in (ROOT/directory).iterdir() if f.is_file() and f.name!='progress.json' and f.suffix.lower() in suffixes]
 if pipelined:
  snapshot=OUT/'r2_source'
  for rel,h in entries(snapshot/'source_sha256.txt').items():
   if sha(snapshot/rel)!=h:raise ValueError('R2 snapshot changed '+rel)
  extras += [f for f in snapshot.rglob('*') if f.is_file()]
 for f in extras:copy(f,dest/'source'/f.relative_to(ROOT))
 (dest/'completion.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 manifest=[dict(path=f.relative_to(dest).as_posix(),bytes=f.stat().st_size,sha256=sha(f)) for f in sorted(dest.rglob('*')) if f.is_file()]
 (dest/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 for e in manifest:
  if sha(dest/e['path'])!=e['sha256']:raise ValueError('Archive checksum')
 print(json.dumps(dict(archive=str(dest),files=len(manifest),bit_sha256=build['bit_sha256']),indent=2))
if __name__=='__main__':main()
