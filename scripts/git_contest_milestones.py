"""Recover audited local milestones without checkout, backdating, or real-index edits."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess
from datetime import datetime,timezone,timedelta

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/git_milestones'
REF='refs/heads/codex/contest-milestones'

def sha(data):return hashlib.sha256(data).hexdigest()
def git(*args,input=None,env=None):
    p=subprocess.run(['git','-c','safe.directory='+ROOT.as_posix(),*args],cwd=ROOT,
        input=input,capture_output=True,env=env)
    if p.returncode:raise RuntimeError(p.stderr.decode('utf-8',errors='replace'))
    return p.stdout

def add_files(files,env):
    # Explicit paths only: never git add -A, and never stage multi-GB datasets.
    for target in files:
        if target.startswith('/') or '..' in Path(target).parts or '\t' in target or '\n' in target:raise ValueError(target)
    paths=list(files.values())
    objects=git('hash-object','-w','--no-filters','--stdin-paths',
        input=('\n'.join(p.as_posix() for p in paths)+'\n').encode(),env=env).decode().splitlines()
    if len(objects)!=len(paths):raise RuntimeError('hash-object result count')
    lines=''.join(f'100644 {obj}\t{target}\n' for target,obj in zip(files,objects))
    git('update-index','--index-info',input=lines.encode(),env=env)

def commit(parent,files,message,env):
    git('read-tree',parent,env=env)
    add_files(files,env)
    tree=git('write-tree',env=env).decode().strip()
    return git('commit-tree',tree,'-p',parent,input=(message+'\n').encode(),env=env).decode().strip()

def verify(mapping):
    checked=0
    for row in mapping['milestones']:
        for path,h in row['input_sha256'].items():
            if sha(git('show',row['commit']+':'+path))!=h.lower():raise RuntimeError('Git source mismatch '+row['key']+' '+path)
            checked+=1
        if row.get('bit_sha256'):
            path=f"contest_evidence/{row['key']}/camera_to_dsi_display.bit"
            if sha(git('show',row['commit']+':'+path))!=row['bit_sha256']:raise RuntimeError('Git bit mismatch '+row['key'])
        if row.get('tag') and git('rev-parse',row['tag']+'^{}').decode().strip()!=row['commit']:raise RuntimeError('Tag mismatch')
    print(f'Verified {checked} explicit Git source objects and milestone bit/tag objects')

def main():
    p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');p.add_argument('--verify',action='store_true');a=p.parse_args()
    if a.verify:
        verify(json.loads((OUT/'mapping.json').read_text(encoding='utf-8')));return
    audit=json.loads((OUT/'audit.json').read_text(encoding='utf-8'))
    if any(r['source_mismatches'] or not r['bit_matches'] for r in audit['milestones']):raise RuntimeError('Archive audit did not pass')
    if not a.write:print('Audit ready: 8 archived milestones plus explicitly unverified v43 WIP');return
    if (OUT/'mapping.json').exists():raise RuntimeError('Mapping exists; verify instead of duplicating history')
    if git('rev-parse','HEAD').decode().strip()!=audit['base_head']:raise RuntimeError('HEAD changed since audit')
    if subprocess.run(['git','-c','safe.directory='+ROOT.as_posix(),'show-ref','--verify','--quiet',REF],cwd=ROOT).returncode==0:raise RuntimeError('Target branch exists')
    index_before=sha((ROOT/'.git/index').read_bytes())
    env=os.environ.copy();env['GIT_INDEX_FILE']=str(OUT/'isolated.index')
    # Dates are the actual execution time. Do not inherit overrides from tools.
    env.pop('GIT_AUTHOR_DATE',None);env.pop('GIT_COMMITTER_DATE',None)
    mapping={'created_at':datetime.now(timezone(timedelta(hours=8))).isoformat(),
        'base_head':audit['base_head'],'branch':REF,'milestones':[]}
    parent=audit['base_head']
    keys=['v34-r8','v35-r1','v36-r5','v37-r3','v38-r1','v40-r4','v41-r2','v42-r3']
    for key,row in zip(keys,audit['milestones']):
        archive=ROOT/'releases'/row['archive'];files={}
        source_hashes={}
        for line in (archive/'source_sha256.txt').read_text(encoding='utf-8').splitlines():
            if line.strip():
                h,rel=line.split('  ',1);rel=rel.replace('\\','/');source_hashes[rel]=h.lower()
                path=archive/'source'/rel
                if sha(path.read_bytes())!=h.lower():raise RuntimeError('Archive changed '+str(path))
        for path in sorted((archive/'source').rglob('*')):
            if path.is_file() and path.suffix not in ('.pyc','.pyo'):files[path.relative_to(archive/'source').as_posix()]=path
        prefix='contest_evidence/'+key
        files[prefix+'/source_sha256.txt']=archive/'source_sha256.txt'
        files[prefix+'/original_metadata.json']=archive/row['metadata_file']
        files[prefix+'/camera_to_dsi_display.bit']=archive/'build/phy/camera_to_dsi_display.bit'
        metadata={**row,'key':key,'supplemental_commit':True,'commit_date_is_original_build_date':False,
            'archive_inputs_sha256':sha((archive/'source_sha256.txt').read_bytes()),'input_sha256':source_hashes}
        path=OUT/(key+'.json');path.write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        files['doc/contest_history/milestones/'+key+'.json']=path
        files['doc/contest_history/README.md']=ROOT/'doc/contest_history/README.md'
        label='candidate' if row['candidate'] else 'archived milestone'
        message=f'recover({key}): restore audited {label} from {row["archive"]}\n\nSupplemental record created now from existing immutable archive; not an original historical commit.\nOriginal build metadata and verification boundaries are retained under {prefix}.\nBit SHA256: {row["bit_sha256"]}\nNo new board validation is claimed.'
        parent=commit(parent,files,message,env)
        tag='contest/'+key
        git('tag','-a',tag,parent,'-m',f'Supplemental archived {label}; original archive {row["archive"]}; bit SHA256 {row["bit_sha256"]}. No backdating.',env=env)
        mapping['milestones'].append(dict(key=key,archive=row['archive'],commit=parent,tag=tag,input_sha256=source_hashes,bit_sha256=row['bit_sha256']))
        (OUT/'progress.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(key,parent,flush=True)
    # Current v43 inputs are frozen by the still-running verified build.
    snapshot=ROOT/'td_project/colorshading_runs_20261025_v43_osd_r2/source_sha256.txt'
    current={};files={}
    for line in snapshot.read_text(encoding='utf-8').splitlines():
        h,rel=line.split('  ',1);rel=rel.replace('\\','/');path=ROOT/rel
        if sha(path.read_bytes())!=h.lower():raise RuntimeError('v43 source changed since Check: '+rel)
        current[rel]=h.lower();files[rel]=path
    extras=['README.md','.gitignore','doc/osd_v43.md','doc/gimbal_wiring_hx1p35a.md',
        'scripts/osd_v43_reference.py','scripts/osd_v43_report.py','scripts/run_osd_v43_sim.ps1',
        'scripts/git_contest_milestones.py','scripts/run_face_pipeline_sim.ps1','scripts/run_vision_tasks_sim.ps1',
        'scripts/run_gimbal_sim.ps1','scripts/run_osd_checks.ps1','scripts/run_td_verified.ps1',
        'scripts/on_td_complete.ps1','td_project/build_colorshading.ps1',
        'sim/tb_osd_v43.sv','sim/tb_gimbal_pipeline.sv','sim/tb_region_buttons.sv',
        'sim/tb_gimbal_target.sv','sim/face_lbp/tb_face_pipeline.sv',
        'sim/vision_tasks/tb_vision_task_suite.sv','sim/vision_tasks/tb_vision_task_osd.sv']
    for rel in extras:files[rel]=ROOT/rel
    pending=OUT/'v43-wip.json'
    pending.write_text(json.dumps(dict(state='WIP, functional and routed timing gates still pending',
        input_sha256=current,build_run=snapshot.parent.name,board_verified=False),indent=2)+'\n',encoding='utf-8')
    files['doc/contest_history/milestones/v43-wip.json']=pending
    parent=commit(parent,files,'wip(v43): freeze compact OSD and SW3 display control before physical verification\n\nCurrent build/test results are pending. Do not claim this checkpoint is a verified bitstream.',env)
    mapping['milestones'].append(dict(key='v43-wip',commit=parent,input_sha256=current))
    git('update-ref',REF,parent,'0'*40,env=env)
    if sha((ROOT/'.git/index').read_bytes())!=index_before:raise RuntimeError('Real Git index changed unexpectedly')
    if git('rev-parse','HEAD').decode().strip()!=audit['base_head']:raise RuntimeError('HEAD moved unexpectedly')
    (OUT/'mapping.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    verify(mapping)
    print('Created local milestone branch; original HEAD, working files and real index preserved. No push.')

if __name__=='__main__':main()
