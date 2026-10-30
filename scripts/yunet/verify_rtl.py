"""Standalone full-network RTL verification for an exported candidate package."""
import argparse,hashlib,json,re,shutil,subprocess,time
from pathlib import Path

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def update_package_status(package,rtl_status):
    path=Path(package)/'status.json'
    if not path.is_file():return
    record=json.loads(path.read_text(encoding='utf-8-sig'))
    record['rtl_status']=rtl_status
    record['eligible_for_whole_board_build']=bool(record.get('accuracy_accepted') and not record.get('smoke_only') and rtl_status=='passed')
    temp=path.with_name(path.name+'.tmp');temp.write_text(json.dumps(record,indent=2),encoding='utf-8');temp.replace(path)

def run(package,modelsim_bin=None,timeout=3600):
    package=Path(package).resolve()
    update_package_status(package,'running')
    manifest=json.loads((package/'manifest.json').read_text())
    for rel,value in manifest.items():
        p=(package/rel).resolve()
        if not p.is_relative_to(package) or sha(p)!=value:raise ValueError('Candidate package checksum mismatch: '+rel)
    suffix='.exe' if __import__('os').name=='nt' else ''
    tool=Path(modelsim_bin) if modelsim_bin else Path(shutil.which('vlog'+suffix) or '').parent
    def exe(name):
        p=tool/(name+suffix)
        if not p.is_file():raise FileNotFoundError('ModelSim unavailable: set --modelsim-bin or PATH')
        return str(p.resolve())
    out=package/'verification';out.mkdir(exist_ok=True);library=out/'work'
    if not library.exists():subprocess.run([exe('vlib'),str(library)],check=True,cwd=package,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    src=package/'rtl/analytics/face_cnn'
    command=[exe('vlog'),'-sv','+incdir+'+str(src),'-work',str(library),str(src/'yunet_dot4.v'),str(src/'yunet_network.v'),str(package/'sim/cnn/tb_yunet_network_fast.sv')]
    compiled=subprocess.run(command,cwd=package,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=timeout)
    (out/'compile.log').write_text(compiled.stdout,encoding='utf-8')
    if compiled.returncode or 'Errors: 0, Warnings: 0' not in compiled.stdout:raise RuntimeError('Candidate RTL compilation failed or warned')
    command=[exe('vsim'),'-c','-lib',str(library),'-wlf',str(out/'waves.wlf'),'tb_yunet_network_fast','-l',str(out/'test.log'),'-do','onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0']
    t0=time.monotonic()
    with (out/'console.log').open('w',encoding='utf-8') as log:
        try:result=subprocess.run(command,cwd=package,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        except subprocess.TimeoutExpired:
            (out/'completion.json').write_text(json.dumps(dict(status='failed',reason='timeout')),encoding='utf-8');raise
    text=(out/'test.log').read_text(encoding='utf-8',errors='replace')
    match=re.search(r'all 55 operations, 659460 exact activation bytes, (\d+) cycles',text)
    passed=result.returncode==0 and bool(match) and 'Errors: 0, Warnings: 0' in text
    unchanged=all(sha(package/rel)==value for rel,value in manifest.items())
    record=dict(status='passed' if passed and unchanged else 'failed',source_sha256={k:v for k,v in manifest.items() if k.startswith(('rtl/','sim/'))},payload_manifest_sha256=sha(package/'manifest.json'),
                cycles=int(match[1]) if match else None,seconds=time.monotonic()-t0,
                scope='One candidate input, all 55 operations and 659460 activation bytes; not routed timing or board acceptance')
    (out/'completion.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    if record['status']!='passed':raise RuntimeError('Candidate RTL output did not match integer golden')
    update_package_status(package,'passed')
    print('RTL PASSED',record['cycles'],'cycles',flush=True);return record

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,default=Path(__file__).resolve().parent)
    ap.add_argument('--modelsim-bin',type=Path);ap.add_argument('--timeout',type=int,default=3600)
    a=ap.parse_args();run(a.package,a.modelsim_bin,a.timeout)
