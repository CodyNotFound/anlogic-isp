"""Retain a timing-clean bit, its explicit inputs and evidence outside Git."""
from pathlib import Path
import argparse,hashlib,json,re,shutil

parser=argparse.ArgumentParser()
parser.add_argument('run',help='isolated anlogic-isp_runs_* directory name')
parser.add_argument('--check-only',action='store_true',help='Validate the retained build without creating an archive')
args=parser.parse_args()
assert re.fullmatch(r'anlogic-isp_runs_[A-Za-z0-9_]+',args.run)
root=Path(__file__).resolve().parents[1]
run=root/'build/td'/args.run
match=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',args.run)
version=args.run
completion=root/'build/verification'/f'{version}_completion.json'
record=json.loads(completion.read_text(encoding='utf-8-sig'))
assert record['status']=='passed',record
for key in ('setup_wns_ns','hold_wns_ns'):assert record[key]>=0
for key in ('setup_tns_ns','hold_tns_ns'):assert record[key]==0
target=root.parent/'anlogic-isp-artifacts'/'builds'/version
entries=[]
for line in (run/'source_sha256.txt').read_text(encoding='utf-8-sig').splitlines():
    sha,path=line.split('  ',1)
    source=(root/path.replace('\\','/')).resolve()
    assert source.is_relative_to(root.resolve())
    assert hashlib.sha256(source.read_bytes()).hexdigest().upper()==sha.upper(),path
    entries.append((sha,source,source.relative_to(root)))
bit=run/'phy/anlogic-isp.bit'
assert hashlib.sha256(bit.read_bytes()).hexdigest().upper()==record['bit_sha256']
if args.check_only:
    print(f'PASS archive inputs: {len(entries)} unchanged sources; bit SHA256 {record["bit_sha256"]}; setup {record["setup_wns_ns"]}ns hold {record["hold_wns_ns"]}ns')
    raise SystemExit(0)
assert not target.exists(),'Preserve existing archive; use a fresh run name'
target.mkdir(parents=True)
for _,source,rel in entries:
    out=target/'source'/rel
    out.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(source,out)
for source in (bit,run/'source_sha256.txt',completion,run/'phy/anlogic-isp_phy.ts',run/'phy/anlogic-isp_phy.area',run/'phy/final_timing.rpt',run/'phy/anlogic-isp_exception.timing',run/'phy/settings.cfg'):
    shutil.copyfile(source,target/source.name)
# Current regression proofs are optional and must match their actual inputs.
# Stale/failed results never become functional acceptance for a newer build.
functional=[]
for proof_path in sorted((root/'build/sim').glob('*/completion.json')):
    proof=json.loads(proof_path.read_text(encoding='utf-8-sig'))
    inputs=proof.get('source_sha256',[])
    if proof.get('status')!='passed' or not inputs:
        continue
    if any(not Path(v['path']).is_file() or hashlib.sha256(Path(v['path']).read_bytes()).hexdigest().lower()!=v['sha256'].lower() for v in inputs):
        continue
    out=target/'functional_logs'/proof_path.parent.name
    out.mkdir(parents=True)
    for name in ('completion.json','compile.log','test.log','equivalence.json'):
        source=proof_path.parent/name
        if source.is_file():shutil.copyfile(source,out/name)
    functional.append(proof_path.parent.name)
(target/'functional_tests.json').write_text(json.dumps({'scope':'Available passing regressions with matching inputs; not a claim that all tests were run','tests':functional},indent=2),encoding='utf-8')
audit=run/'phy/sta_audit'
assert (audit/'check_timing.rpt').exists(),'Clock audit evidence missing'
for source in audit.rglob('*'):
    if source.is_file():
        out=target/'sta_audit'/source.relative_to(audit)
        out.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,out)
manifest={str(p.relative_to(target)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*') if p.is_file()}
(target/'archive_sha256.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(f'Retained {len(entries)} source inputs and {len(manifest)} archive files: {target}')
