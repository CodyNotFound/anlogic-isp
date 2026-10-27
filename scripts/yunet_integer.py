"""YuNet graph lowering and deterministic power-of-two integer inference.

PC execution is a development oracle, never the deployed camera recognition path.
Convolution uses OHWI weights, HWC activations, signed int8 hidden activations,
int32 bias/accumulator, arithmetic right shift with half-up rounding and saturation.
Raw input is unsigned BGR 0..255; no hidden normalization or RGB swap.
"""
from pathlib import Path
import copy,json,hashlib,math
import numpy as np
import onnx
from onnx import helper,numpy_helper
import onnxruntime as ort
import cv2

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/'models/yunet/face_detection_yunet_2023mar.onnx'
OUT=ROOT/'reports/yunet_v45'
W,H=160,96

def attributes(n):return {a.name:helper.get_attribute_value(a) for a in n.attribute}
def exponent(maximum,limit=127):return max(-24,int(math.ceil(math.log2(max(float(maximum)/limit,2.**-24)))))
def rounded_shift(a,s):
    a=np.asarray(a,dtype=np.int64)
    return (a+(1<<(s-1)))>>s if s>0 else a<<(-s)

def convolution(x,w,pad=0,stride=1,group=1):
    """HWC/OHWI convolution with independent numpy window construction."""
    kh,kw=w.shape[1:3];h,wi,ci=x.shape;co=w.shape[0]
    p=np.pad(x,((pad,pad),(pad,pad),(0,0)))
    windows=np.lib.stride_tricks.sliding_window_view(p,(kh,kw),axis=(0,1))[::stride,::stride]
    # sliding_window_view produces H,W,C,KH,KW.
    if group==1:return np.einsum('xycij,oijc->xyo',windows,w,optimize=True)
    assert group==ci==co and w.shape[-1]==1
    return np.einsum('xycij,cij->xyc',windows,w[:,:,:,0],optimize=True)

def load_graph():
    m=onnx.load(MODEL);weights={a.name:numpy_helper.to_array(a) for a in m.graph.initializer}
    # KPS is unused by position tracking. Prune only its exclusive branch.
    outputs=[o.name for o in m.graph.output if not o.name.startswith('kps')]
    needed=set(outputs);nodes=[]
    for n in reversed(m.graph.node):
        if any(o in needed for o in n.output):nodes.append(n);needed.update(n.input)
    nodes.reverse()
    del m.graph.node[:];m.graph.node.extend(nodes)
    kept=[a for a in m.graph.initializer if a.name in needed]
    del m.graph.initializer[:];m.graph.initializer.extend(kept)
    kept=[a for a in m.graph.output if a.name in outputs]
    del m.graph.output[:];m.graph.output.extend(kept)
    # The original export caches 640x640 internal shapes. Re-infer all internals
    # from our explicit input, rather than relying on ORT's lenient shape merge.
    del m.graph.value_info[:]
    dims=m.graph.input[0].type.tensor_type.shape.dim;dims[2].dim_value=H;dims[3].dim_value=W
    for o in m.graph.output:
        for d in o.type.tensor_type.shape.dim:d.ClearField('dim_value');d.ClearField('dim_param')
    return m,weights

def verify_lowering(m,weights,ops,a):
    run=session(m,True);raw=run.run(None,{'input':a.transpose(2,0,1)[None].astype(np.float32)})
    expected={o.name:v[0].transpose(1,2,0) for o,v in zip(run.get_outputs(),raw) if v.ndim==4}
    nodes={n.name:n for n in m.graph.node};t={'input':a.astype(np.float32)};errors={}
    for op in ops:
        if op['op']=='conv':
            n=nodes[op['name']];w=weights[n.input[1]].transpose(0,2,3,1)
            v=convolution(t[op['src']],w,op['pad'],op['stride'],op['group'])+weights[n.input[2]]
            if op['relu']:v=np.maximum(v,0)
        elif op['op']=='maxpool':
            x=t[op['src'][0]];v=np.maximum.reduce([x[::2,::2],x[1::2,::2],x[::2,1::2],x[1::2,1::2]])
        elif op['op']=='resize':v=np.repeat(np.repeat(t[op['src'][0]],2,0),2,1)
        else:v=t[op['src'][0]]+t[op['src'][1]]
        want=expected[op['dst']];error=float(np.max(np.abs(v-want)))
        if error>1e-3+float(np.max(np.abs(want)))*2e-4:raise AssertionError((op['name'],error))
        errors[op['name']]=error;t[op['dst']]=v
    return errors

def session(m,intermediate=False):
    m=copy.deepcopy(m)
    if intermediate:
        names={o.name for o in m.graph.output}
        for n in m.graph.node:
            if n.op_type in ('Conv','Relu','MaxPool','Resize','Add') and n.output[0] not in names:
                m.graph.output.append(helper.make_tensor_value_info(n.output[0],onnx.TensorProto.FLOAT,None))
    opt=ort.SessionOptions();opt.intra_op_num_threads=2
    return ort.InferenceSession(m.SerializeToString(),sess_options=opt,providers=['CPUExecutionProvider'])

def fixture_images():
    """Small deterministic development probes, NOT an independent accuracy set."""
    data=ROOT/'sim/face_lbp/data';out={}
    for name in ('lena','grace_hopper','messi5','fruits','figurine'):
        a=cv2.imread(str(data/(name+'.jpg')))
        scale=min(W/a.shape[1],90/a.shape[0]);nw,nh=round(a.shape[1]*scale),round(a.shape[0]*scale)
        canvas=np.zeros((H,W,3),np.uint8);ox=(W-nw)//2;oy=(90-nh)//2
        canvas[oy:oy+nh,ox:ox+nw]=cv2.resize(a,(nw,nh),interpolation=cv2.INTER_AREA)
        out[name]=canvas
    base=out['lena']
    for angle in (-30,-15,15,30):
        out[f'lena_roll_{angle}']=cv2.warpAffine(base,cv2.getRotationMatrix2D((80,45),angle,1),(W,H))
    out['lena_dim']=np.rint(base*.4).astype(np.uint8)
    original=cv2.imread(str(data/'lena.jpg'))
    out['lena_close']=cv2.resize(original[155:395,165:385],(W,H),interpolation=cv2.INTER_AREA)
    for angle in (-30,-15,15,30):
        out[f'close_roll_{angle}']=cv2.warpAffine(out['lena_close'],cv2.getRotationMatrix2D((80,48),angle,1),(W,H))
    out['black']=np.zeros((H,W,3),np.uint8)
    out['gray']=np.full((H,W,3),100,np.uint8)
    return out

def calibrate(m,images):
    run=session(m,True);ranges={};shapes={}
    for a in images.values():
        values=run.run(None,{'input':a.transpose(2,0,1)[None].astype(np.float32)})
        for meta,value in zip(run.get_outputs(),values):
            ranges[meta.name]=max(ranges.get(meta.name,0),float(np.max(np.abs(value))))
            shapes[meta.name]=list(value.shape)
    return {name:exponent(v*1.15) for name,v in ranges.items()},shapes

def lower(m,weights,scales,shapes):
    operations=[];aliases={'input':'input'};all_weights=[];all_bias=[];all_shifts=[]
    # Fuse only Conv->Relu with one consumer, retaining the Relu's calibrated scale.
    consumers={}
    for n in m.graph.node:
        for v in n.input:consumers[v]=consumers.get(v,0)+1
    nodes=list(m.graph.node);scales=dict(scales);scales['input']=0
    for i,n in enumerate(nodes):
        op=n.op_type;a=attributes(n);src=[aliases.get(x,x) for x in n.input];dest=n.output[0]
        if op=='Relu':continue
        if op=='Conv':
            relu=i+1<len(nodes) and nodes[i+1].op_type=='Relu' and nodes[i+1].input[0]==dest and consumers[dest]==1
            if relu:dest=nodes[i+1].output[0];aliases[n.output[0]]=dest;aliases[dest]=dest
            wf=weights[n.input[1]].transpose(0,2,3,1);bf=weights[n.input[2]]
            we=np.array([exponent(np.max(np.abs(v))) for v in wf],np.int32)
            wq=np.stack([np.clip(np.rint(v/2.**e),-127,127).astype(np.int8) for v,e in zip(wf,we)])
            ie=scales[src[0]];oe=scales[dest]
            bq=np.rint(bf/np.power(2.,we+ie)).astype(np.int64)
            if np.any(np.abs(bq)>2147483647):raise OverflowError(n.name+' bias')
            shift=oe-ie-we
            shape=shapes[dest];oh,ow=shape[2:];ci=wf.shape[-1];co=len(wf);kh,kw=wf.shape[1:3]
            operations.append(dict(op='conv',name=n.name,src=src[0],dst=dest,shape=[oh,ow,co],
                weights=wq,bias=bq.astype(np.int32),shift=shift,relu=bool(relu),
                pad=a['pads'][0],stride=a['strides'][0],group=a['group'],
                weight_offset=len(all_weights),bias_offset=len(all_bias),macs=oh*ow*co*ci*kh*kw))
            all_weights.extend(wq.reshape(-1).tolist());all_bias.extend(bq.tolist());all_shifts.extend(shift.tolist())
        elif op in ('MaxPool','Resize','Add'):
            operations.append(dict(op=op.lower(),name=n.name,src=src[:2] if op=='Add' else src[:1],dst=dest,
                shape=[shapes[dest][2],shapes[dest][3],shapes[dest][1]],
                shifts=[scales[dest]-scales[x] for x in (src[:2] if op=='Add' else src[:1])]))
        elif op in ('Transpose','Reshape','Sigmoid'):
            # Output layout/nonlinearity is handled by the integer result decoder.
            aliases[dest]=src[0]
        else:raise ValueError('Unsupported '+op)
    heads={o.name:aliases[o.name] for o in m.graph.output}
    return operations,scales,heads,np.array(all_weights,np.int8),np.array(all_bias,np.int32),np.array(all_shifts,np.int32)

def infer(a,ops):
    tensors={'input':a.astype(np.int64)};maxacc=0;saturation={}
    for op in ops:
        if op['op']=='conv':
            acc=convolution(tensors[op['src']],op['weights'].astype(np.int64),op['pad'],op['stride'],op['group'])+op['bias']
            maxacc=max(maxacc,int(np.max(np.abs(acc))))
            if np.any(np.abs(acc)>2147483647):raise OverflowError(op['name']+' accumulator')
            v=np.stack([rounded_shift(acc[:,:,i],int(s)) for i,s in enumerate(op['shift'])],axis=2)
            low=0 if op['relu'] else -128
        elif op['op']=='maxpool':
            x=tensors[op['src'][0]];v=np.maximum.reduce([x[0::2,0::2],x[1::2,0::2],x[0::2,1::2],x[1::2,1::2]])
            v=rounded_shift(v,op['shifts'][0]);low=-128
        elif op['op']=='resize':
            v=np.repeat(np.repeat(tensors[op['src'][0]],2,0),2,1);v=rounded_shift(v,op['shifts'][0]);low=-128
        elif op['op']=='add':
            # Accumulate at the finer binary scale, round ONCE after addition.
            # shift=out_exp-in_exp. Align at the smallest input exponent.
            e=max(op['shifts']);v=sum(tensors[x] << (e-s) for x,s in zip(op['src'],op['shifts']))
            v=rounded_shift(v,e);low=-128
        else:raise ValueError(op['op'])
        saturation[op['dst']]=float(np.mean((v<-128)|(v>127)))
        tensors[op['dst']]=np.clip(v,low,127).astype(np.int64)
    return tensors,maxacc,saturation

def decode(heads,threshold=.65):
    boxes=[]
    for stride in (8,16,32):
        cls=np.clip(heads[f'cls_{stride}'].reshape(-1),0,1)
        obj=np.clip(heads[f'obj_{stride}'].reshape(-1),0,1)
        reg=heads[f'bbox_{stride}'].reshape(-1,4)
        for i,score in enumerate(np.sqrt(cls*obj)):
            if score<threshold:continue
            cx=(i%(W//stride)+reg[i,0])*stride;cy=(i//(W//stride)+reg[i,1])*stride
            bw,bh=np.exp(np.clip(reg[i,2:],-12,12))*stride
            boxes.append([float(cx-bw/2),float(cy-bh/2),float(bw),float(bh),float(score)])
    keep=[]
    for b in sorted(boxes,key=lambda b:-b[4]):
        if all(iou(b,k)<.3 for k in keep):keep.append(b)
    return keep

def iou(a,b):
    x=max(0,min(a[0]+a[2],b[0]+b[2])-max(a[0],b[0]));y=max(0,min(a[1]+a[3],b[1]+b[3])-max(a[1],b[1]))
    inter=x*y;return inter/max(1e-12,a[2]*a[3]+b[2]*b[3]-inter)

def live_memory(ops):
    """Exact tensor lifetimes for this schedule; byte counts, no BRAM packing claim."""
    last={};sizes={'input':H*W*3};peak=0;live={'input'};trace=[]
    for i,op in enumerate(ops):
        for s in ([op['src']] if isinstance(op['src'],str) else op['src']):last[s]=i
        sizes[op['dst']]=math.prod(op['shape'])
    # Keep output heads (their small arrays are decoded after graph completion).
    for op in ops:
        if op['dst'] not in last:last[op['dst']]=len(ops)
    for i,op in enumerate(ops):
        live.add(op['dst']);n=sum(sizes[x] for x in live);peak=max(peak,n)
        trace.append(dict(node=op['name'],live_bytes=n))
        live={x for x in live if last.get(x,-1)>i}
    return peak,trace

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    m,weights=load_graph();images=fixture_images();scales,shapes=calibrate(m,images)
    ops,scales,heads,wq,bq,shifts=lower(m,weights,scales,shapes)
    float_errors=verify_lowering(m,weights,ops,images['lena'])
    run=session(m);results={};peakacc=0
    for fixture,a in images.items():
        raw=run.run(None,{'input':a.transpose(2,0,1)[None].astype(np.float32)})
        float_heads={o.name:v for o,v in zip(run.get_outputs(),raw)}
        t,acc,sat=infer(a,ops);peakacc=max(peakacc,acc)
        qheads={name:t[src].astype(float)*2.**scales[src] for name,src in heads.items()}
        for name in qheads:
            if name.startswith(('cls','obj')):qheads[name]=1/(1+np.exp(-qheads[name]))
        fb=decode(float_heads);qb=decode(qheads)
        agreement=[max((iou(b,f) for f in fb),default=0) for b in qb]
        results[fixture]=dict(float_boxes=fb,integer_boxes=qb,float_integer_iou=agreement,
            worst_saturation=max(sat.values()),max_abs_accumulator=acc)
        canvas=a.copy()
        for b in qb:cv2.rectangle(canvas,(round(b[0]),round(b[1])),(round(b[0]+b[2]),round(b[1]+b[3])),(0,255,0),1)
        cv2.imwrite(str(OUT/(fixture+'.png')),canvas)
        if fixture=='lena':np.savez_compressed(OUT/'lena_integer_trace.npz',**{k:v.astype(np.int16) for k,v in t.items()})
    serial=[]
    for op in ops:
        serial.append({k:(v.tolist() if isinstance(v,np.ndarray) else v) for k,v in op.items() if k not in ('weights','bias')})
    peak,trace=live_memory(ops)
    report=dict(scope='development probes calibrated on these same images; NOT independent accuracy evaluation',
        model_sha256=hashlib.sha256(MODEL.read_bytes()).hexdigest(),input_bgr=[W,H],
        operations=len(ops),weight_bytes=wq.size,bias_bytes=bq.nbytes,macs=sum(o.get('macs',0) for o in ops),
        hidden_tensor_peak_bytes=peak,peak_abs_accumulator=peakacc,
        lowered_float_nodes_verified=len(float_errors),lowered_float_max_absolute_error=max(float_errors.values()),results=results)
    (OUT/'evaluation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    (OUT/'network.json').write_text(json.dumps(dict(operations=serial,scales=scales,heads=heads,memory_trace=trace),indent=2)+'\n',encoding='utf-8')
    np.savez_compressed(OUT/'integer_model.npz',weights=wq,bias=bq,shift=shifts)
    np.savetxt(OUT/'weights.hex',wq.astype(np.uint8),fmt='%02x')
    np.savetxt(OUT/'bias.hex',bq.astype(np.uint32),fmt='%08x')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
