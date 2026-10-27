"""Append verified v43 evidence, preserving the original branch and real index."""
import os,json
from pathlib import Path
from git_contest_milestones import ROOT,OUT,REF,git,sha,commit,verify

def main():
    mapping_path=OUT/'mapping.json'
    mapping=json.loads(mapping_path.read_text(encoding='utf-8'))
    if any(r['key']=='v43-r2' for r in mapping['milestones']):
        verify(mapping);return
    validation=json.loads((ROOT/'reports/osd_v43/validation.json').read_text(encoding='utf-8'))
    if validation['status']!='passed' or validation['errors'] or len(validation['tests'])!=12:
        raise RuntimeError('Verification gates incomplete')
    release=ROOT/'releases/vision_osd_v43_r2'
    manifest=json.loads((release/'manifest.json').read_text(encoding='utf-8'))
    for item in manifest:
        if sha((release/item['path']).read_bytes())!=item['sha256']:raise RuntimeError('Archive changed')
    parent=git('rev-parse',REF).decode().strip()
    if parent!=mapping['milestones'][-1]['commit']:raise RuntimeError('Milestone tip changed')
    head=git('rev-parse','HEAD');index=sha((ROOT/'.git/index').read_bytes())
    env=os.environ.copy();env['GIT_INDEX_FILE']=str(OUT/'verified_v43.index')
    env.pop('GIT_AUTHOR_DATE',None);env.pop('GIT_COMMITTER_DATE',None)
    files={};inputs={};prefix='contest_evidence/v43-r2/'
    for line in (release/'source_sha256.txt').read_text(encoding='utf-8').splitlines():
        h,rel=line.split('  ',1);rel=rel.replace('\\','/')
        path=release/'source'/rel
        if sha(path.read_bytes())!=h.lower():raise RuntimeError('Input changed')
        inputs[rel]=h.lower();files[rel]=path
    for path in release.rglob('*'):
        if path.is_file() and 'source' not in path.relative_to(release).parts[:1]:
            rel=path.relative_to(release).as_posix()
            # Retain complete evidence beside the runnable canonical source tree.
            files[prefix+rel]=path
    files[prefix+'camera_to_dsi_display.bit']=release/'build/phy/camera_to_dsi_display.bit'
    for rel in ['doc/osd_v43.md','doc/contest_history/README.md','scripts/git_verify_v43_milestone.py']:
        files[rel]=ROOT/rel
    new=commit(parent,files,'verify(v43-r2): archive compact OSD with passing RGB regression and routed timing\n\n12 functional checks passed; 5,529,600 exact RGB pixels. Setup +0.234ns, hold +0.020ns; 106 frozen build inputs.\nLocal verification only; not flashed or board-validated. Historical checkpoints remain supplemental records.',env)
    tag='contest/v43-r2'
    git('tag','-a',tag,new,'-m','Verified local build and 12 functional checks; no board-validation claim.',env=env)
    git('update-ref',REF,new,parent,env=env)
    row=dict(key='v43-r2',archive=release.name,commit=new,tag=tag,input_sha256=inputs,
             bit_sha256=validation['build']['bit_sha256'].lower())
    mapping['milestones'].append(row)
    mapping_path.write_text(json.dumps(mapping,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    verify(mapping)
    if git('rev-parse','HEAD')!=head or sha((ROOT/'.git/index').read_bytes())!=index:
        raise RuntimeError('Original checkout/index changed')
    print(json.dumps(row|{'input_sha256':f'{len(inputs)} verified inputs'},indent=2))

if __name__=='__main__':main()
