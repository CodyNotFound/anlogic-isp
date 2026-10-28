"""Retain a timing-clean bit, its explicit inputs and evidence outside Git."""
from pathlib import Path
import argparse,hashlib,json,re,shutil

parser=argparse.ArgumentParser()
parser.add_argument('run',help='isolated anlogic-isp_runs_* directory name')
args=parser.parse_args()
assert re.fullmatch(r'anlogic-isp_runs_[A-Za-z0-9_]+',args.run)
root=Path(__file__).resolve().parents[1]
run=root/'td_project'/args.run
match=re.search(r'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$',args.run)
version=args.run
completion=root/'build/verification'/f'{version}_completion.json'
record=json.loads(completion.read_text(encoding='utf-8-sig'))
assert record['status']=='passed',record
for key in ('setup_wns_ns','hold_wns_ns'):assert record[key]>=0
for key in ('setup_tns_ns','hold_tns_ns'):assert record[key]==0
target=root/'releases'/version
assert not target.exists(),'Preserve existing archive; use a fresh run name'
entries=[]
for line in (run/'source_sha256.txt').read_text(encoding='utf-8-sig').splitlines():
    sha,path=line.split('  ',1)
    source=(root/path.replace('\\','/')).resolve()
    assert source.is_relative_to(root.resolve())
    assert hashlib.sha256(source.read_bytes()).hexdigest().upper()==sha.upper(),path
    entries.append((sha,source,source.relative_to(root)))
bit=run/'phy/anlogic-isp.bit'
assert hashlib.sha256(bit.read_bytes()).hexdigest().upper()==record['bit_sha256']
target.mkdir(parents=True)
for _,source,rel in entries:
    out=target/'source'/rel
    out.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(source,out)
for source in (bit,run/'source_sha256.txt',completion,run/'phy/anlogic-isp_phy.ts',run/'phy/anlogic-isp_phy.area',run/'phy/final_timing.rpt',run/'phy/anlogic-isp_exception.timing',run/'phy/settings.cfg'):
    shutil.copyfile(source,target/source.name)
if (root/'reports/optimized_validation.json').exists():
    shutil.copyfile(root/'reports/optimized_validation.json',target/'functional_validation.json')
    data=json.loads((root/'reports/optimized_validation.json').read_text(encoding='utf-8'))
    for value in data.values():
        if isinstance(value,dict) and 'path' in value:
            source=root/value['path']
            assert hashlib.sha256(source.read_bytes()).hexdigest()==value['sha256']
            out=target/'functional_logs'/source.name
            out.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,out)
manifest={str(p.relative_to(target)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*') if p.is_file()}
(target/'archive_sha256.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(f'Retained {len(entries)} source inputs and {len(manifest)} archive files: {target}')
