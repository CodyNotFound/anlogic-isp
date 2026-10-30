"""Full YuNet warm-start fine-tuning with deterministic resume and held-out selection."""
import math,os,random,time
from pathlib import Path
import numpy as np
import torch
import torch.nn.functional as F
from common import read,write,sha,source_hash,environment,stamp
from data import dataset,render,verify_sources
from yunet_torch import YuNetN,export_onnx_weights
from evaluate import FloatRunner,metrics,acceptable

def loss_fn(student,teacher,gt):
    # Unannotated/tiny/invalid faces are not made hard background targets:
    # keep teacher probabilities there. Only annotation-disjoint crops are explicit negatives.
    total=student['cls'][0].sum()*0
    for level,stride in enumerate((8,16,32)):
        sc,so,sb=(student[k][level] for k in ('cls','obj','box'))
        tc,to,tb=(teacher[k][level] for k in ('cls','obj','box'))
        confidence=(tc.sigmoid()*to.sigmoid()).sqrt()
        total+=2*F.binary_cross_entropy_with_logits(sc,tc.sigmoid())+2*F.binary_cross_entropy_with_logits(so,to.sigmoid())
        trusted=confidence[:,0]>.2
        if trusted.any():total+=.25*F.smooth_l1_loss(sb.permute(0,2,3,1)[trusted],tb.permute(0,2,3,1)[trusted])
        positive=[];targets=[]
        # Preserve the installed model's stride assignment at this input size;
        # the other two heads remain protected by distillation.
        if stride==8:
            for n,boxes in enumerate(gt):
                for x,y,w,h in boxes:
                    x0=max(0,int((x+.25*w)/stride));x1=min(sc.shape[3]-1,int((x+.75*w)/stride))
                    y0=max(0,int((y+.25*h)/stride));y1=min(sc.shape[2]-1,int((y+.75*h)/stride))
                    if x1<x0 or y1<y0:continue
                    scores=confidence[n,0,y0:y1+1,x0:x1+1];index=int(scores.argmax())
                    yy=y0+index//scores.shape[1];xx=x0+index%scores.shape[1]
                    positive.append((n,yy,xx));targets.append([(x+w/2)/stride-xx,(y+h/2)/stride-yy,math.log(w/stride),math.log(h/stride)])
        if positive:
            n,y,x=zip(*positive)
            total+=.15*F.binary_cross_entropy_with_logits(sc[n,0,y,x],torch.ones_like(sc[n,0,y,x]))
            total+=.15*F.binary_cross_entropy_with_logits(so[n,0,y,x],torch.ones_like(so[n,0,y,x]))
            total+=.25*F.smooth_l1_loss(sb.permute(0,2,3,1)[n,y,x],torch.tensor(targets,device=sb.device,dtype=sb.dtype))
        negatives=[n for n,b in enumerate(gt) if not len(b)]
        if negatives:
            for output in (sc,so):
                flat=output[negatives].flatten(1);hard=flat.topk(min(12,flat.shape[1]),dim=1).values
                total+=.10*F.binary_cross_entropy_with_logits(hard,torch.zeros_like(hard))
    return total

def save(path,blob):
    path=Path(path);temp=path.with_name(path.name+'.tmp');torch.save(blob,temp);os.replace(temp,path)

def run(args):
    work=args.work;out=work/'training';out.mkdir(exist_ok=True)
    cv2=__import__('cv2');cv2.setNumThreads(1);torch.set_num_threads(args.threads)
    torch.manual_seed(args.seed);rng=random.Random(args.seed)
    if args.device=='auto':device=torch.device('cuda' if torch.cuda.is_available() else 'mps' if hasattr(torch.backends,'mps') and torch.backends.mps.is_available() else 'cpu')
    else:device=torch.device(args.device)
    verify_sources(work)
    model=YuNetN().load_onnx(work/'upstream/yunet.onnx').to(device)
    teacher=YuNetN().load_onnx(work/'upstream/yunet.onnx').to(device).eval()
    for p in teacher.parameters():p.requires_grad_(False)
    groups=[dict(params=[],lr=args.lr/5),dict(params=[],lr=args.lr)]
    for name,p in model.p.items():
        p.requires_grad_('kps' not in name)
        if p.requires_grad:groups[int('bbox_head' in name)]['params'].append(p)
    optimizer=torch.optim.AdamW(groups,weight_decay=1e-5)
    data,rows=dataset(work,'train')
    signature=dict(steps=args.steps,batch=args.batch,lr=args.lr,seed=args.seed,eval_every=args.eval_every,
                   manifest_sha256=sha(work/'prepared/manifest.json'),source_model_sha256=sha(work/'upstream/yunet.onnx'),scripts={k:v for k,v in source_hash().items() if Path(k).name in ('train.py','data.py','deployment.py','yunet_torch.py','evaluate.py','common.py')})
    current=out/'last.pt';start=0;best=-1e9;history=[];selected=None
    if current.exists():
        if not args.resume:raise ValueError('Training checkpoint exists; use --resume or choose a new work directory')
        checkpoint=torch.load(current,map_location='cpu',weights_only=False)
        if checkpoint['signature']!=signature:raise ValueError('Resume configuration, data or script fingerprint changed')
        model.load_state_dict(checkpoint['model']);optimizer.load_state_dict(checkpoint['optimizer'])
        for state in optimizer.state.values():
            for key,value in state.items():
                if torch.is_tensor(value):state[key]=value.to(device)
        rng.setstate(checkpoint['rng']);torch.set_rng_state(checkpoint['torch_rng'])
        start=checkpoint['step'];best=checkpoint['best'];history=checkpoint['history'];selected=checkpoint['selected']
    baseline,_=metrics(work,'val',FloatRunner(teacher,device),False)
    write(out/'run.json',dict(signature=signature,environment=environment(),device=str(device),architecture='full YuNet, unchanged channels and layers',baseline=baseline))
    print('TRAIN BASELINE',baseline,flush=True)
    log_path=out/'loss.csv'
    with log_path.open('a' if start else 'w',encoding='utf-8') as log:
        if not start:log.write('step,loss,seconds\n')
        t0=time.monotonic()
        for step in range(start+1,args.steps+1):
            batch=[render(data,rng.choice(rows),rng) for _ in range(args.batch)]
            x=torch.from_numpy(np.stack([b[0] for b in batch]).transpose(0,3,1,2).astype(np.float32)).to(device)
            with torch.no_grad():old=teacher(x)
            model.train();new=model(x);loss=loss_fn(new,old,[b[1] for b in batch])
            if not torch.isfinite(loss):raise ValueError('Non-finite training loss')
            optimizer.zero_grad(set_to_none=True);loss.backward();torch.nn.utils.clip_grad_norm_(model.parameters(),2);optimizer.step()
            for j,g in enumerate(optimizer.param_groups):g['lr']=args.lr/(5 if j==0 else 1)*(.1+.9*(1+math.cos(math.pi*step/args.steps))/2)
            log.write(f'{step},{loss.item():.8f},{time.monotonic()-t0:.2f}\n');log.flush()
            if step==1 or step%25==0:print('TRAIN STEP',step,'/',args.steps,'loss',round(loss.item(),6),flush=True)
            if step%args.eval_every==0 or step==args.steps:
                result,_=metrics(work,'val',FloatRunner(model,device),False)
                eligible=acceptable(baseline,result)
                score=result['single_target_hit_rate']+.5*result['precision']-2*result['negative_acceptance_rate']
                history.append(dict(step=step,eligible=eligible,score=score,metrics=result));write(out/'selection.json',history)
                # Store genuinely trained candidates even when rejected; never rename official weights as trained.
                if selected is None or (eligible and score>best):
                    selected=step;best=score if eligible else -1e9
                    save(out/'best.pt',model.state_dict());export_onnx_weights(model,src=work/'upstream/yunet.onnx',dst=out/'candidate.onnx')
                print('TRAIN EVAL',step,'eligible',eligible,'hit',result['single_target_hit_rate'],flush=True)
            if step%args.checkpoint_every==0 or step%args.eval_every==0 or step==args.steps:
                save(current,dict(model=model.state_dict(),optimizer=optimizer.state_dict(),step=step,best=best,history=history,selected=selected,
                                  signature=signature,rng=rng.getstate(),torch_rng=torch.get_rng_state()))
    chosen=torch.load(out/'best.pt',map_location='cpu',weights_only=True)
    original={k:v.detach().cpu() for k,v in teacher.state_dict().items()}
    if chosen.keys()!=original.keys() or any(chosen[k].shape!=original[k].shape for k in original):raise ValueError('Topology changed')
    changed=sum(not torch.equal(chosen[k],original[k]) for k in original)
    if not changed:raise ValueError('No trained tensors changed')
    write(out/'result.json',dict(status='completed',steps=args.steps,selected_step=selected,changed_tensors=changed,
                                candidate_sha256=sha(out/'candidate.onnx'),weights_only=True,architecture_changed=False,
                                validation_eligible=next(h['eligible'] for h in history if h['step']==selected)))
    stamp(work,'train',status='completed',changed_tensors=changed,selected_step=selected)
