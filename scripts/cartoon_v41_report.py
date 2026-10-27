"""Audit the cel renderer, native application regression, and routed release."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/cartoon_v41'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--run',default='colorshading_runs_20261024_v41_cartoon_r2');p.add_argument('--archive');a=p.parse_args()
 if not re.fullmatch(r'colorshading_runs_[A-Za-z0-9_]+',a.run):raise ValueError('Run name')
 version=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',a.run)[1]
 run=ROOT/'td_project'/a.run
 r2=a.run.endswith('_r2')
 tests={}
 for name in ['lena','fruits','grace_hopper','figurine','probes']:
  tests['cartoon_'+name]=(f'reports/cartoon_v41/{name}_modelsim.log',f'PASS tb_pixel_cartoon {name}')
 tests.update(compat=('reports/cartoon_v41/compat.log','PASS tb_effect_compat'),
  native_cartoon=('reports/face_pose/v41_native_cartoon/tb_cartoon_pipeline.log','PASS tb_cartoon_pipeline'),
  native_face=('reports/face_pose/v41_face_pipeline/tb_face_pipeline.log','PASS tb_face_pipeline'),
  target=('reports/face_pose/v41_gimbal_target/tb_gimbal_target.log','PASS tb_gimbal_target'),
  region_buttons=('reports/face_pose/v41_region_buttons/tb_region_buttons.log','PASS tb_region_buttons'),
  gimbal_buttons=('reports/face_pose/v41_gimbal_buttons/tb_gimbal_pipeline.log','PASS tb_gimbal_pipeline'),
  ab_composition=('reports/gimbal/ab_osd.log','PASS tb_ab_before_osd'))
 if r2:
  tests['compat_1280']=('reports/cartoon_v41/compat_1280.log','PASS tb_effect_compat')
  for key in ['native_cartoon','native_face','target','region_buttons','gimbal_buttons']:
   path,marker=tests[key];directory,name=path.rsplit('/',1)
   tests[key]=(directory+'_r2/'+name,marker)
 for top in ['tb_ref_osd_mixer','tb_mode_ctrl_ref_modes','tb_pixel_algorithm_ref_modes']:
  tests['osd_'+top]=(f'sim/{top}.log',f'PASS {top}')
 for name in ['task_suite','task_osd','hud','sampler','legacy_fixes','gaussian']:
  tests['tasks_'+name]=(f'reports/vision_tasks/{name}_v41_effects'+('_r2' if r2 else '')+'.log',f'PASS tb_vision_{name}')
 errors=[];checked={}
 job_path=ROOT/f'doc/compile/{version}_job.json'
 job=json.loads(job_path.read_text(encoding='utf-8')) if job_path.exists() else {}
 from datetime import datetime
 started=datetime.fromisoformat(job['started_utc'].replace('Z','+00:00')).timestamp() if job else 0
 for name,(rel,marker) in tests.items():
  f=ROOT/rel
  if not f.exists():errors.append('Missing '+rel);continue
  s=f.read_text(encoding='utf-8',errors='replace')
  if marker not in s or re.search(r'\*\* (Error|Fatal)|\bFAIL\b',s):errors.append('Not passed '+rel);continue
  if (rel.startswith('sim/') or r2 and not name.startswith('cartoon_') and name!='compat') and f.stat().st_mtime<started:errors.append('Stale test log '+rel);continue
  checked[name]=dict(path=rel,sha256=sha(f),marker=marker)
 # The frozen module is the genuine v40 source with only its module name changed.
 old=ROOT/'releases/vision_tracking_v40_r4/source/rtl/isp/pixel_algorithm.v'
 expected_old=old.read_text(encoding='utf-8').replace('module pixel_algorithm #(','module pixel_algorithm_v40 #(')
 if (ROOT/'sim/cartoon/pixel_algorithm_v40.v').read_text(encoding='utf-8')!=expected_old:errors.append('Compatibility oracle differs from frozen v40')
 base={}
 for line in (ROOT/'releases/vision_tracking_v40_r4/source_sha256.txt').read_text(encoding='utf-8').splitlines():
  digest,rel=line.split('  ',1);base[rel.replace('\\','/')]=digest.lower()
 current={};sources=[]
 for line in (run/'source_sha256.txt').read_text(encoding='utf-8').splitlines():
  digest,rel=line.split('  ',1);rel=rel.replace('\\','/');current[rel]=digest.lower();f=ROOT/rel
  if sha(f)!=digest.lower():errors.append('Sources changed after Check '+rel)
  sources.append(f)
 changed=[r for r in base if r in current and current[r]!=base[r]]
 added=sorted(set(current)-set(base));removed=sorted(set(base)-set(current))
 if set(changed)!={'rtl/isp/pixel_algorithm.v','rtl/app/vision_pipeline.v','user_source/hdl_source/hdmi_mixer.v'} or added!=['rtl/isp/pixel_cartoon.v'] or removed:
  errors.append('Unexpected source delta '+repr((changed,added,removed)))
 reused={}
 if r2:
  helper='rtl/isp/pixel_cartoon.v'
  if sha(ROOT/helper)!=sha(OUT/'r1_source'/helper):errors.append('Reused core RTL changed')
  for key in tests:
   if key.startswith('cartoon_'):
    reused[key]=dict(reason='Unchanged standalone renderer; R2 changes only legacy gray line memories outside this DUT',rtl=helper,rtl_sha256=sha(ROOT/helper))
 image_results={}
 for name in ['lena','fruits','grace_hopper','figurine']:
  f=OUT/f'{name}_rtl.ppm';e=OUT/f'{name}_reference.png'
  if not f.exists():errors.append('Missing RTL output '+name);continue
  actual=np.array(Image.open(f));expected=np.array(Image.open(e))
  if actual.shape!=(360,640,3) or not np.array_equal(actual,expected):errors.append('RGB mismatch '+name);continue
  Image.fromarray(actual).save(OUT/f'{name}_rtl.png')
  image_results[name]=dict(pixels=640*360,rtl_ppm_sha256=sha(f),expected_png_sha256=sha(e))
 f=OUT/'native720_pipeline.ppm'
 if 'native_cartoon' in checked:
  if not f.exists() or not np.array_equal(np.array(Image.open(f)),np.array(Image.open(OUT/'native720_reference.png'))):errors.append('Native RGB output mismatch')
  else:
   Image.open(f).save(OUT/'native720_pipeline.png')
   image_results['native720']=dict(pixels=921600,rtl_ppm_sha256=sha(f),expected_png_sha256=sha(OUT/'native720_reference.png'))
 completion=ROOT/f'doc/compile/{version}_completion.json';build=None
 if not completion.exists():errors.append('Build failed: '+str(job.get('error')) if job.get('status')=='failed' else 'Build not complete')
 else:
  build=json.loads(completion.read_text(encoding='utf-8'))
  if build['status']!='passed' or job.get('status')!='passed':errors.append('Build did not pass')
  elif build['setup_wns_ns']<0 or build['hold_wns_ns']<0 or build['setup_tns_ns'] or build['hold_tns_ns']:errors.append('Final timing failed')
  if build['slices']>21216 or build['ram']>108 or build['dsp']>40:errors.append('Capacity failed')
  bit=run/'phy/camera_to_dsi_display.bit'
  if not bit.exists() or sha(bit)!=build['bit_sha256'].lower():errors.append('Bit checksum')
 report=dict(status='passed' if not errors else 'incomplete',errors=errors,tests=checked,
  changed_active_sources=changed,added_active_sources=added,source_files_checked=len(current),
  unchanged_v40_inputs=sum(1 for r in base if current.get(r)==base[r]),
  image_results=image_results,build=build,reused_component_checks=reused,flashed=False,board_verified=False,
  scope='mode09 cel cartoon, four-clock display alignment; unchanged face/template/color analysis reused from v40')
 (OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps(dict(status=report['status'],passed=len(checked),errors=errors),ensure_ascii=False,indent=2))
 if not a.archive:return
 if errors:raise ValueError('Release gates incomplete')
 if not re.fullmatch(r'[A-Za-z0-9_]+',a.archive):raise ValueError('Archive name')
 dest=ROOT/'releases'/a.archive
 if dest.exists():raise ValueError('Archive already exists')
 def copy(f,target):target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
 for f in sources:copy(f,dest/'source'/f.relative_to(ROOT))
 for f in [completion,job_path,run/'source_sha256.txt']:copy(f,dest/f.name)
 for d in ['syn','phy']:
  for f in (run/d).iterdir():
   if f.is_file() and f.suffix.lower() in ['.bit','.log','.logw','.area','.timing','.ts','.prj','.cfg','.tcl']:copy(f,dest/'build'/d/f.name)
 for entry in checked.values():copy(ROOT/entry['path'],dest/'evidence'/entry['path'])
 extras=[ROOT/'doc/cartoon_v41.md',ROOT/'README.md',ROOT/'td_project/camera_to_dsi_display.al',ROOT/'td_project/build_colorshading.ps1',ROOT/'sim/face_lbp/SOURCES.md']
 for d in ['scripts','sim/cartoon','sim/face_lbp/data','sim/face_lbp/models']:
  extras += [f for f in (ROOT/d).iterdir() if f.is_file() and f.suffix.lower() in ['.py','.ps1','.sv','.v','.hex','.expected','.txt','.md','.png','.jpg','.xml']]
 extras += [f for f in OUT.iterdir() if f.is_file() and f.name!='progress.json' and f.suffix.lower() in ['.png','.ppm','.json','.log']]
 if r2:
  snapshot=OUT/'r1_source'
  for entry in json.loads((snapshot/'snapshot.json').read_text(encoding='utf-8')):
   if sha(snapshot/entry['path'])!=entry['sha256']:raise ValueError('R1 snapshot changed '+entry['path'])
  extras += [f for f in snapshot.rglob('*') if f.is_file()]
 for f in extras:copy(f,dest/'source'/f.relative_to(ROOT))
 # Reproduction of the application regression also needs the existing HDL TBs.
 for d in ['sim','sim/face_lbp','sim/vision_tasks']:
  for f in (ROOT/d).iterdir():
   if f.is_file() and f.suffix.lower() in ['.sv','.v','.hex','.txt','.target','.expected']:copy(f,dest/'source'/f.relative_to(ROOT))
 (dest/'completion.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 manifest=[dict(path=f.relative_to(dest).as_posix(),bytes=f.stat().st_size,sha256=sha(f)) for f in sorted(dest.rglob('*')) if f.is_file()]
 (dest/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 for entry in manifest:
  if sha(dest/entry['path'])!=entry['sha256']:raise ValueError('Archive checksum '+entry['path'])
 print(json.dumps(dict(archive=str(dest),files=len(manifest),bit_sha256=build['bit_sha256']),indent=2))
if __name__=='__main__':main()
