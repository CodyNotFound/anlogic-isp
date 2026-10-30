"""Quantize with frozen deployment scales, prove bounds, and package candidate FPGA inputs."""
import importlib.util,json,shutil,subprocess,sys
from pathlib import Path
import numpy as np
from common import ROOT,CONTRACT,read,write,sha,stamp

def helper(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def quantize(args):
    script=Path(__file__).parent/'quantize.py'
    for tag,model in [('baseline',args.work/'upstream/yunet.onnx'),('candidate',args.work/'training/candidate.onnx')]:
        out=args.work/'quantized'/tag
        subprocess.run([sys.executable,str(script),'--model',str(model),'--calib-dir',str(args.work/'prepared/calibration'),
                        '--out',str(out),'--scale-reference',str(CONTRACT)],check=True)
        net=read(out/'network.json');fixed=read(CONTRACT)
        if {k:net['scales'][v] for k,v in net['heads'].items()}!=fixed['head_scales']:raise ValueError('Decoder head scales changed')
    reference=args.work/'scheduled_baseline'
    subprocess.run([sys.executable,str(Path(__file__).parent/'schedule.py'),'--qdir',str(args.work/'quantized/baseline'),'--out',str(reference)],check=True)
    names=['program.hex','bias.hex','shift.hex']+[f'weights{i}.hex' for i in range(4)]
    for name in names:
        original=[int(v,16) for v in (ROOT/'rtl/analytics/face_cnn'/name).read_text().split()]
        actual=[int(v,16) for v in (reference/name).read_text().split()]
        if actual!=original:raise ValueError('Baseline does not reproduce production: '+name)
    stamp(args.work,'quantize',status='passed',contract_sha256=sha(CONTRACT),baseline_matches_production=True)

def export(args):
    from data import verify_sources
    verify_sources(args.work)
    work=args.work;package=work/'fpga';rom=package/'rtl/analytics/face_cnn';rom.mkdir(parents=True,exist_ok=True)
    stage=work/'scheduled';stage.mkdir(exist_ok=True)
    subprocess.run([sys.executable,str(Path(__file__).parent/'schedule.py'),'--qdir',str(work/'quantized/candidate'),'--out',str(stage)],check=True)
    report=read(stage/'schedule_report.json')
    if report['ops']!=55 or report['weight_bank_depth']!=12373 or report['arena_peak_bytes']>65536:raise ValueError('Production shape/memory contract changed')
    production=ROOT/'rtl/analytics/face_cnn'
    def words(p):return [int(v,16) for v in p.read_text().split()]
    if words(stage/'program.hex')!=words(production/'program.hex'):raise ValueError('Topology, scales or memory schedule changed')
    for name in ['program.hex','bias.hex','shift.hex','yunet_heads.vh']+[f'weights{i}.hex' for i in range(4)]:shutil.copyfile(stage/name,rom/name)
    delta={}
    for name in ['bias.hex','shift.hex']+[f'weights{i}.hex' for i in range(4)]:
        a,b=words(production/name),words(rom/name)
        delta[name]=sum(x!=y for x,y in zip(a,b))
    write(package/'integer_delta.json',dict(changed=any(delta.values()),entries=delta))
    for name in ['sigmoid.hex','offset.hex','size.hex']:shutil.copyfile(production/name,rom/name)
    for source in production.glob('*.v'):shutil.copyfile(source,rom/source.name)
    pack=helper('candidate_pack',ROOT/'scripts/cnn/pack_yunet_rom.py')
    folder,files,packing=pack.generate(package)
    for name,text in files.items():(folder/name).write_bytes(text.encode('ascii'))
    if packing['shift_bits']!=3:raise ValueError('Candidate needs a wider shift memory; review hardware resources before export')
    bounds=helper('candidate_bounds',ROOT/'scripts/cnn/check_yunet_dw_bounds.py').prove(package,18,20)
    golden=package/'sim/cnn/data/network_reference';golden.mkdir(parents=True,exist_ok=True)
    for name in ['input.hex','op_checks.txt']+[f'op_{i:02d}.hex' for i in range(55)]:shutil.copyfile(stage/name,golden/name)
    shutil.copyfile(ROOT/'sim/cnn/tb_yunet_network_fast.sv',package/'sim/cnn/tb_yunet_network_fast.sv')
    shutil.copyfile(Path(__file__).parent/'verify_rtl.py',package/'verify.py')
    shutil.copyfile(work/'training/candidate.onnx',package/'candidate.onnx')
    shutil.copyfile(work/'upstream/LICENSE',package/'LICENSE')
    shutil.copyfile(CONTRACT,package/'quantization.json')
    write(package/'bounds.json',bounds);write(package/'packing.json',packing)
    write(package/'evaluation.json',read(work/'evaluation/report.json'))
    write(package/'training.json',read(work/'training/result.json'))
    sources=read(work/'sources.json');sources.pop('data_root',None);sources.pop('cache_root',None)
    write(package/'sources.json',sources)
    configuration=read(work/'config.json')
    for key in ('work','downloads','data_root','model','modelsim_bin'):configuration.pop(key,None)
    write(package/'configuration.json',configuration)
    write(package/'prepared_manifest.json',read(work/'prepared/manifest.json'))
    write(package/'training_environment.json',read(work/'training/run.json'))
    from common import source_hash
    write(package/'tool_sources.json',source_hash())
    (package/'README.md').write_text("""# Candidate FPGA model resources

This package does not modify the production project. Copying only weights is insufficient:
the ROMs, packed bias/shift, unpack header, head offsets and LUTs are a single matched set.

- `rtl/analytics/face_cnn/`: candidate CNN RTL and all initialization resources.
- `sim/cnn/data/network_reference/`: input and full 55-operation integer golden.
- `verify.py`: standalone ModelSim regression. Run `python verify.py --modelsim-bin <bin>`.
- `evaluation.json`: baseline/candidate held-out single-target metrics.
- `status.json`: smoke/accuracy/RTL gates. Rejected candidates are still retained for diagnosis.

Only an eligible candidate should enter a NEW whole-board build. Full routed timing,
resource acceptance and actual-board accuracy remain separate gates. No bitstream is
claimed by this model-resource export. Existing production files remain untouched.
""",encoding='utf-8')
    # Runtime logs and status are intentionally outside the immutable payload manifest.
    manifest={p.relative_to(package).as_posix():sha(p) for p in package.rglob('*') if p.is_file() and
              'verification' not in p.relative_to(package).parts and p.name not in ('manifest.json','status.json')}
    write(package/'manifest.json',manifest)
    stamp(work,'export',status='passed',manifest_sha256=sha(package/'manifest.json'))
    return package
