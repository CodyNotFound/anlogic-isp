"""Fresh constraint Check + reroute of an identical placed design.

Only one changed SDC file is permitted. Every other selected build input and the
canonical full project XML must match. No HDL/header/ROM/pin change can use this
path. Final route, setup/hold, bit generation and completion checks run normally.
"""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,re,shutil,subprocess

ROOT=Path(__file__).resolve().parents[1]
NAME='camera_to_dsi_display'
SHELL=shutil.which('pwsh.exe')


def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def inputs(run):
    return {rel.replace('\\','/'):sha.lower() for sha,rel in
            (line.split('  ',1) for line in (run/'source_sha256.txt').read_text().splitlines())}


def project(path):
    # TD's XML-like format contains bare '&' and '::' tag names. Compare the
    # exact project text, normalizing only the File Path rewrites made by the
    # existing isolated-run builder. Device/top/options remain in the comparison.
    return re.sub(r'<File Path="([^"]+)"',lambda m:'<File Path="'+
        str((path.parent/m[1]).resolve()).lower()+'"',path.read_text())


def ps(script,*args):
    if not SHELL:raise RuntimeError('PowerShell 7 (pwsh.exe) is required for the verified build environment')
    subprocess.run([SHELL,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/script),*map(str,args)],cwd=ROOT,check=True)


def main():
    p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--run',required=True);args=p.parse_args()
    for value in [args.base,args.run]:
        if not re.fullmatch(r'colorshading_runs_[A-Za-z0-9_]+',value):raise ValueError('Invalid isolated run')
    base=ROOT/'td_project'/args.base;run=ROOT/'td_project'/args.run
    if run.exists():raise ValueError('Preserve existing run; choose a fresh name')
    if not (base/'syn/.opt_gate.end.f').exists() or not (base/'phy/.opt_place.end.f').exists():raise ValueError('Base synthesis/placement incomplete')
    if project(ROOT/f'td_project/{NAME}.al')!=project(base/f'syn/{NAME}.prj'):raise ValueError('Project differs; full synthesis required')
    old=inputs(base);sdc=f'td_project/{NAME}.sdc'
    changed=[rel for rel,sha in old.items() if digest(ROOT/rel)!=sha]
    if changed!=[sdc]:raise ValueError(f'Only the main SDC may change, got {changed}')
    text=(base/f'phy/{NAME}_phy.area').read_text()
    for pat,limit in [('slice',21216),('eram',108),('dsp',40)]:
        if int(re.search(r'(?m)^#'+pat+r'\s+(\d+)',text)[1])>limit:raise ValueError('Base physical capacity exceeds device')
    version=args.run.split('_20261020_',1)[-1];jobpath=ROOT/f'doc/compile/{version}_job.json'
    now=lambda:datetime.now(timezone.utc).isoformat()
    job=dict(status='running',run=args.run,stage='Check',started_utc=now(),completed_utc=None,error=None,
             constraint_only_revision=True,source_run=args.base)
    def save():jobpath.write_text(json.dumps(job,indent=2))
    save()
    try:
        ps('td_project/build_colorshading.ps1','-Stage','Check','-RunName',args.run)
        current=inputs(run)
        if set(current)!=set(old) or [k for k in old if old[k]!=current[k]]!=[sdc]:raise ValueError('Selected sources changed during fresh Check')
        for rel,sha in current.items():
            if digest(ROOT/rel)!=sha:raise ValueError('Inputs changed after Check')
        for sub,files in [('syn',[f'{NAME}_gate.db',f'{NAME}_gate.area',f'{NAME}_gate.ts',f'{NAME}_gate.timing','.opt_gate.end.f']),
                          ('phy',[f'{NAME}_place.db',f'{NAME}_place.timing',f'{NAME}_phy.area','.opt_place.end.f'])]:
            for name in files:shutil.copy2(base/sub/name,run/sub/name)
        provenance=dict(base_run=args.base,unchanged_non_SDC_inputs=len(old)-1,changed_file=sdc,
            old_SDC_sha256=old[sdc],new_SDC_sha256=current[sdc],project_identity_verified=True,
            gate_checkpoint_sha256=digest(base/f'syn/{NAME}_gate.db'),
            placed_checkpoint_sha256=digest(base/f'phy/{NAME}_place.db'),
            reload_user_SDC_after_DB_import=True,
            note='No HDL/header/ROM/pin change. Placement retained; DefaultFlow sp reloads user SDC before full routing/hold-fix/bitgen.')
        (run/'checkpoint_provenance.json').write_text(json.dumps(provenance,indent=2))
        job['stage']='Implementation';save()
        ps('td_project/build_colorshading.ps1','-Stage','Implementation','-RunName',args.run,'-AllowGateTimingExploration','-RouteOnly')
        ps('scripts/on_td_complete.ps1','-TdProcessId','0','-ProjectRoot',ROOT,'-RunName',args.run)
        result=json.loads((ROOT/f'doc/compile/{version}_completion.json').read_text(encoding='utf-8-sig'))
        job['status']=result['status']
        if job['status']!='passed':job['error']='; '.join(result['errors'])
    except Exception as e:
        job['status']='failed';job['error']=str(e);raise
    finally:job['completed_utc']=now();save()
    if job['status']!='passed':raise ValueError(job['error'])


if __name__=='__main__':main()
