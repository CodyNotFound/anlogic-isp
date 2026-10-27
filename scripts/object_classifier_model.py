"""Hardware contract v1: validate/export a trained NPZ, or make arithmetic-only fixtures.

NumPy/Pillow only. Selftest weights are deliberately NOT trained classifiers.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

ROOT=Path(__file__).resolve().parents[1]
FIELDS={'conv_weight':(np.int8,(8,3,3,3)), 'conv_bias':(np.int32,(8,)),
        'conv_shift':(np.uint8,(8,)), 'fc_weight':(np.int8,(4,1800)),
        'fc_bias':(np.int32,(4,)), 'reject_margin':(np.uint32,())}


def load(path):
    with np.load(path,allow_pickle=False) as z:
        if set(z.files)!=set(FIELDS): raise ValueError('NPZ keys must exactly match contract v1')
        model={k:z[k].copy() for k in FIELDS}
    for k,(dtype,shape) in FIELDS.items():
        if model[k].dtype!=dtype or model[k].shape!=shape: raise ValueError(f'{k}: expected {dtype} {shape}')
    if np.any(model['conv_shift']>15): raise ValueError('conv_shift must be 0..15')
    if not 1<=int(model['reject_margin'])<=2147483647: raise ValueError('reject_margin out of range')
    for wk,bk,limit in [('conv_weight','conv_bias',128),('fc_weight','fc_bias',127)]:
        bound=np.abs(model[bk].astype(np.int64))+limit*np.abs(model[wk].astype(np.int64)).reshape(len(model[bk]),-1).sum(1)
        if np.any(bound>2147483647): raise ValueError(f'{wk}/{bk}: possible int32 accumulator overflow')
    return model


def reference(model,image):
    if image.dtype!=np.uint8 or image.shape!=(32,32,3): raise ValueError('Need RGB uint8[32,32,3]')
    inp=image.astype(np.int64)-128
    windows=sliding_window_view(inp,(3,3),axis=(0,1)).transpose(0,1,3,4,2)
    accum=np.einsum('yxijk,oijk->yxo',windows,model['conv_weight'].astype(np.int64))+model['conv_bias']
    shift=model['conv_shift'].astype(np.int64)
    half=np.where(shift>0,1<<np.maximum(0,shift-1),0)
    activation=np.clip((accum+half)>>shift,0,127).astype(np.uint8)
    pool=activation.reshape(15,2,15,2,8).max(axis=(1,3))
    logits=model['fc_weight'].astype(np.int64)@pool.ravel().astype(np.int64)+model['fc_bias']
    order=np.argsort(-logits,kind='stable')
    margin=int(logits[order[0]]-logits[order[1]])
    margin=min(margin,0xffffffff)
    rejected=order[0]==0 or margin<int(model['reject_margin'])
    return dict(accum=accum,activation=activation,pool=pool,logits=logits,
                class_id=0 if rejected else int(order[0]),rejected=bool(rejected),margin=margin)


def writehex(path,values,bits):
    mask=(1<<bits)-1
    path.write_text(''.join(f'{int(v)&mask:0{(bits+3)//4}x}\n' for v in np.asarray(values).ravel()),encoding='ascii')


def export(path,dest,kind):
    model=load(path)
    dest.mkdir(parents=True,exist_ok=True)
    writehex(dest/'weights.hex',np.concatenate([model['conv_weight'].ravel(),model['fc_weight'].ravel()]),8)
    writehex(dest/'bias.hex',np.concatenate([model['conv_bias'],model['fc_bias']]),32)
    writehex(dest/'shift.hex',model['conv_shift'],4)
    writehex(dest/'reject.hex',[model['reject_margin']],32)
    meta=dict(contract_version=1,model_kind=kind,source_npz_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
              classes=['unknown','cup','phone','figurine'],input_shape=[32,32,3],input_order='RGB/HWC',
              weights=7416,conv_MACs=194400,fc_MACs=7200,reject_margin=int(model['reject_margin']))
    (dest/'export_manifest.json').write_text(json.dumps(meta,indent=2))
    return model


def fixtures(model,dest,images,labels=None):
    dest.mkdir(parents=True,exist_ok=True)
    records=[]
    with (dest/'expected.txt').open('w') as f:
        f.write(str(len(images))+'\n')
        for i,im in enumerate(images):
            result=reference(model,im)
            writehex(dest/f'image_{i:03}.hex',im,8)
            writehex(dest/f'pool_{i:03}.hex',result['pool'],8)
            logits=list(map(int,result['logits']))
            f.write(f"{i} {result['class_id']} {int(result['rejected'])} {result['margin']} {' '.join(map(str,logits))}\n")
            records.append(dict(index=i,label=None if labels is None else int(labels[i]),
                                class_id=result['class_id'],rejected=result['rejected'],margin=result['margin'],logits=logits))
    (dest/'reference.json').write_text(json.dumps(records,indent=2))
    return records


def selftest():
    dest=ROOT/'sim/object_classifier/selftest'
    dest.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(20261019)
    model=dict(conv_weight=rng.integers(-8,9,(8,3,3,3),dtype=np.int8),
               conv_bias=np.array([0,2000,-2000,255,-255,65536,-65536,1],dtype=np.int32),
               conv_shift=np.array([7,8,6,4,0,10,15,3],dtype=np.uint8),
               fc_weight=rng.integers(-8,9,(4,1800),dtype=np.int8),
               fc_bias=np.array([0,500,-500,3000],dtype=np.int32),reject_margin=np.array(1,dtype=np.uint32))
    yy,xx=np.mgrid[:32,:32]
    images=np.stack([np.zeros((32,32,3),np.uint8),np.full((32,32,3),255,np.uint8),
                     np.stack([(xx*17+yy*3)%256,(xx*5+yy*11)%256,(xx*13+yy*19)%256],axis=-1).astype(np.uint8),
                     rng.integers(0,256,(32,32,3),dtype=np.uint8),np.full((32,32,3),128,np.uint8)])
    margins=sorted(reference(model,im)['margin'] for im in images)
    model['reject_margin']=np.array(margins[len(margins)//2]+1,dtype=np.uint32)
    for name,override,subset in [('arithmetic',{},images),
                                 ('ties',dict(fc_weight=np.zeros((4,1800),np.int8),fc_bias=np.zeros(4,np.int32)),images[3:4]),
                                 ('negative',dict(fc_weight=np.zeros((4,1800),np.int8),fc_bias=np.array([-100,-30,-40,-50],np.int32),reject_margin=np.array(1,np.uint32)),images[2:3]),
                                 ('wide_margin',dict(fc_weight=np.zeros((4,1800),np.int8),fc_bias=np.array([-2000000000,2000000000,-1999999999,-1999999998],np.int32),reject_margin=np.array(2147483647,np.uint32)),images[2:3])]:
        path=dest/name
        path.mkdir(exist_ok=True)
        np.savez(path/'model.npz',**(model|override))
        m=export(path/'model.npz',path,'arithmetic_selftest_NOT_TRAINED')
        records=fixtures(m,path,subset)
        print(name,json.dumps(records))
    # Full-range dense int8 ROMs keep the hardware probe from only exercising
    # a narrower signed multiplier that happens to suffice for small weights.
    probe_rng=np.random.default_rng(20261020)
    probe=model|dict(conv_weight=probe_rng.integers(-128,128,(8,3,3,3),dtype=np.int8),
                     conv_shift=np.array([11,12,10,8,0,14,15,7],np.uint8),
                     fc_weight=probe_rng.integers(-128,128,(4,1800),dtype=np.int8),
                     reject_margin=np.array(1,np.uint32))
    path=dest/'full_range'
    path.mkdir(exist_ok=True)
    np.savez(path/'model.npz',**probe)
    m=export(path/'model.npz',path,'arithmetic_selftest_NOT_TRAINED')
    print('full_range',json.dumps(fixtures(m,path,images[3:4])))
    (dest/'README.md').write_text('These are arithmetic-only fixtures. No trained object recognition model is included.\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--selftest',action='store_true')
    parser.add_argument('--model',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--test-vectors',type=Path)
    args=parser.parse_args()
    if args.selftest: selftest();return
    if args.model is None or args.output is None: parser.error('Need --model and --output, or --selftest')
    model=export(args.model,args.output,'externally_trained_REQUIRES_EVALUATION')
    if args.test_vectors:
        with np.load(args.test_vectors,allow_pickle=False) as z:
            images=z['images'];labels=z['labels']
        if images.dtype!=np.uint8 or images.shape[1:]!=(32,32,3) or labels.shape!=(len(images),):
            raise ValueError('test_vectors: images uint8[N,32,32,3], labels[N]')
        records=fixtures(model,args.output,images,labels)
        print(json.dumps(dict(samples=len(images),accuracy=float(np.mean([r['class_id']==r['label'] for r in records])))))


if __name__=='__main__':main()
