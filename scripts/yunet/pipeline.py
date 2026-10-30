"""Download -> camera-contract samples -> full YuNet fine-tuning -> integer FPGA resources."""
import argparse,json,os,shutil,sys,time,traceback
from pathlib import Path
from common import ROOT,CONTRACT,read,write,sha,stamp,source_hash

DEFAULTS=dict(train_samples=4000,val_samples=400,test_samples=800,steps=1000,batch=12,lr=1e-5,
              eval_every=250,checkpoint_every=25,threads=4,seed=7351,device='auto',verify_rtl='auto',timeout=3600)
STAGES=('download','prepare','train','quantize','evaluate','export','verify')

def parser():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('stage',choices=(*STAGES,'all'),nargs='?',default='all')
    ap.add_argument('--work',type=Path,required=True,help='Isolated outputs; never the production RTL directory')
    for n in ('downloads','data-root','model','modelsim-bin'):ap.add_argument('--'+n,type=Path)
    for n in ('train-samples','val-samples','test-samples','steps','batch','eval-every','checkpoint-every','threads','seed','timeout'):
        ap.add_argument('--'+n,type=int)
    ap.add_argument('--lr',type=float);ap.add_argument('--device',choices=('auto','cpu','cuda','mps'))
    ap.add_argument('--verify-rtl',choices=('auto','require','skip'))
    ap.add_argument('--resume',action='store_true');ap.add_argument('--offline',action='store_true')
    ap.add_argument('--smoke',action='store_true',default=None,help='Tiny execution test, never accuracy-qualified')
    return ap

def verify(args):
    from verify_rtl import run
    package=args.work/'fpga'
    available=args.modelsim_bin or os.environ.get('MODELSIM_BIN') or shutil.which('vlog.exe') or shutil.which('vlog')
    if args.verify_rtl=='skip' or not available and args.verify_rtl=='auto':return dict(status='pending',reason='Run fpga/verify.py on a host with ModelSim')
    binpath=args.modelsim_bin or (Path(os.environ['MODELSIM_BIN']) if os.environ.get('MODELSIM_BIN') else Path(available).parent if available else None)
    previous=package/'verification/completion.json'
    if args.resume and previous.exists():
        last=read(previous);manifest=read(package/'manifest.json')
        if last.get('status')=='passed' and {k:v for k,v in last.get('source_sha256',{}).items() if k.startswith(('rtl/','sim/'))}=={k:v for k,v in manifest.items() if k.startswith(('rtl/','sim/'))} and all(sha(package/p)==v for p,v in manifest.items()):
            last['source_sha256']={k:v for k,v in manifest.items() if k.startswith(('rtl/','sim/'))}
            last['metadata_manifest_sha256']=sha(package/'manifest.json')
            last['reused_on_unchanged_rtl_inputs']=True
            write(previous,last)
            return last
    return run(package,binpath,args.timeout)

def status(args,rtl=None):
    package=args.work/'fpga'
    if not package.exists():return
    evaluation=read(args.work/'evaluation/report.json')
    if rtl is None:
        p=package/'verification/completion.json';rtl=read(p) if p.exists() else dict(status='pending')
        manifest=read(package/'manifest.json')
        actual={k:v for k,v in manifest.items() if k.startswith(('rtl/','sim/'))}
        previous={k:v for k,v in rtl.get('source_sha256',{}).items() if k.startswith(('rtl/','sim/'))}
        if rtl.get('status')=='passed' and (actual!=previous or not all(sha(package/k)==v for k,v in manifest.items())):rtl=dict(status='pending',reason='Current package differs from verified inputs')
    test=evaluation['test']['candidate']
    sufficient=test['positive_images']>=200 and test['negative_images']>=100
    integer_changed=read(package/'integer_delta.json')['changed']
    selected=read(args.work/'training/result.json')['validation_eligible']
    accepted=evaluation['accuracy_accepted'] and sufficient and not args.smoke and integer_changed and selected
    result=dict(integer_parameters_changed=integer_changed,float_selection_accepted=selected,smoke_only=bool(args.smoke),accuracy_accepted=accepted,metrics_non_regression=evaluation['non_regression_passed'],
                sufficient_test_samples=sufficient,rtl_status=rtl['status'],eligible_for_whole_board_build=accepted and rtl['status']=='passed',
                production_modified=False,routed_timing='not_run',board_validation='pending',contract_sha256=sha(CONTRACT),
                candidate_sha256=sha(args.work/'training/candidate.onnx'),manifest_sha256=sha(package/'manifest.json'))
    write(package/'status.json',result);write(args.work/'result.json',result)
    print('RESOURCE STATUS: accuracy_accepted=',accepted,'rtl=',rtl['status'],'smoke=',bool(args.smoke),flush=True)

def main():
    args=parser().parse_args();args.work=args.work.resolve()
    if ROOT.is_relative_to(args.work) or any(args.work.is_relative_to(ROOT/n) for n in ('rtl','assets','scripts','sim','td_project','.git')):raise ValueError('Work directory cannot overlap production sources or their parents')
    args.work.mkdir(parents=True,exist_ok=True)
    old=read(args.work/'config.json') if args.resume and (args.work/'config.json').exists() else {}
    if args.smoke is None:args.smoke=old.get('smoke',False)
    defaults=dict(DEFAULTS)
    if args.smoke:defaults.update(train_samples=40,val_samples=10,test_samples=10,steps=8,batch=4,eval_every=4,checkpoint_every=4)
    for key,value in defaults.items():
        if getattr(args,key) is None:setattr(args,key,old.get(key,value))
    for key in ('downloads','data_root','model','modelsim_bin'):
        value=getattr(args,key)
        if value is None and old.get(key):value=Path(old[key])
        if value is not None:setattr(args,key,value.resolve())
    if min(args.steps,args.batch,args.eval_every,args.checkpoint_every,args.threads,args.train_samples,args.val_samples,args.test_samples)<=0:raise ValueError('Counts must be positive')
    config={k:str(v) if isinstance(v,Path) else v for k,v in vars(args).items() if k!='stage'}
    if args.stage in ('all','train') and (args.work/'training/last.pt').exists() and not args.resume:raise ValueError('Existing training run: use --resume or a fresh work directory')
    if args.stage in ('all','prepare') and (args.work/'prepared/manifest.json').exists() and not args.resume:raise ValueError('Existing prepared samples: use --resume or a fresh work directory')
    write(args.work/'config.json',config)
    stages=STAGES if args.stage=='all' else (args.stage,)
    try:
        for stage in stages:
            print('\n===',stage.upper(),'===',flush=True)
            stamp(args.work,'active',stage=stage,status='running')
            if stage=='download':
                from download import run
                if args.offline:
                    from download import DATA
                    cache=args.downloads or args.work/'downloads'
                    if any(not (cache/n).is_file() for n in DATA) or not args.model and not (args.work/'upstream/yunet.onnx').exists():raise FileNotFoundError('Offline cache incomplete')
                run(args)
            elif stage=='prepare':
                from data import prepare,verify_sources
                marker=args.work/'prepared/manifest.json'
                if args.resume and marker.exists():
                    m=read(marker)
                    if (m['train'],m['val'],m['test'],m['seed'])!=(args.train_samples,args.val_samples,args.test_samples,args.seed):raise ValueError('Prepared data configuration changed')
                    verify_sources(args.work)
                else:prepare(args)
                from checks import validate_origins
                validate_origins(args.work)
            elif stage=='train':
                from checks import before_training
                before_training(args.work)
                from train import run
                run(args)
            elif stage=='quantize':
                from export_fpga import quantize
                quantize(args)
            elif stage=='evaluate':
                from evaluate import compare
                report=compare(args)
                test=report['test']['candidate']
                report['smoke_only']=bool(args.smoke)
                report['sufficient_test_samples']=test['positive_images']>=200 and test['negative_images']>=100
                report['accuracy_accepted']=report['accuracy_accepted'] and report['sufficient_test_samples'] and not args.smoke
                write(args.work/'evaluation/report.json',report)
                stamp(args.work,'evaluate',status='completed',accuracy_accepted=report['accuracy_accepted'])
            elif stage=='export':
                from export_fpga import export
                export(args);status(args)
            elif stage=='verify':
                result=verify(args);status(args,result);stamp(args.work,'verify',**{k:v for k,v in result.items() if k in ('status','cycles','reason')})
        stamp(args.work,'active',stage=args.stage,status='completed')
        print('COMPLETED',args.stage,'outputs:',args.work,flush=True)
    except Exception as error:
        stamp(args.work,'active',stage=stage,status='failed',error=str(error));raise

if __name__=='__main__':main()
