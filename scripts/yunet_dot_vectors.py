"""Extract actual YuNet convolution dot products from the full integer trace."""
from yunet_integer import *

def main():
    OUT.mkdir(exist_ok=True,parents=True)
    network=json.loads((OUT/'network.json').read_text())
    weights=np.load(OUT/'integer_model.npz');trace=np.load(OUT/'lena_integer_trace.npz')
    vectors=[];coverage={};rng=np.random.default_rng(4501)
    for op in network['operations']:
        if op['op']!='conv':continue
        h,w,co=op['shape'];ci=trace[op['src']].shape[-1]
        n=next(n for n in load_graph()[0].graph.node if n.name==op['name'])
        shape=load_graph()[1][n.input[1]].transpose(0,2,3,1).shape
        k=shape[1];group=op['group'];wc=shape[-1]
        wf=weights['weights'][op['weight_offset']:op['weight_offset']+math.prod(shape)].reshape(shape)
        src=trace[op['src']]
        # Every output channel, including zero padding at all four image corners.
        for channel in range(co):
            for y,x in ((0,0),(h-1,w-1),(int(rng.integers(h)),int(rng.integers(w)))):
                av=[];wv=[]
                for ky in range(k):
                    for kx in range(k):
                        iy=y*op['stride']+ky-op['pad'];ix=x*op['stride']+kx-op['pad']
                        for ic in range(wc):
                            av.append(int(src[iy,ix,channel if group>1 else ic]) if 0<=iy<src.shape[0] and 0<=ix<src.shape[1] else 0)
                            wv.append(int(wf[channel,ky,kx,ic]))
                bias=int(weights['bias'][op['bias_offset']+channel]);shift=int(op['shift'][channel])
                acc=int(np.dot(np.array(av,np.int64),np.array(wv,np.int64)))+bias
                v=int(np.clip(rounded_shift(acc,shift),0 if op['relu'] else -128,127))
                assert v==trace[op['dst']][y,x,channel],(op['name'],channel,y,x)
                vectors.append((av,wv,bias,shift,int(op['relu']),acc,v));coverage[op['name']]=coverage.get(op['name'],0)+1
    # Exercise negative shifts, signedness, clipping and rounding half ties.
    for shift in (-3,0,1,7,20):
        for r in (0,1):
            for av,wv,bias in [([255,-128,127,-1],[127,-128,-127,127],-300),([1,0,0,0],[1,0,0,0],-2),([-128]*4,[127]*4,0)]:
                acc=int(np.dot(av,wv))+bias;v=int(np.clip(rounded_shift(acc,shift),0 if r else -128,127))
                vectors.append((av,wv,bias,shift,r,acc,v))
    with (OUT/'dot_vectors.txt').open('w',encoding='ascii') as f:
        for av,wv,bias,shift,r,acc,v in vectors:
            beats=(len(av)+3)//4;f.write(f'{beats} {bias} {shift} {r} {acc} {v}\n')
            for i in range(beats):
                a=av[i*4:i*4+4];w=wv[i*4:i*4+4];a+=[0]*(4-len(a));w+=[0]*(4-len(w))
                f.write(' '.join(map(str,a+w))+'\n')
    (OUT/'dot_coverage.json').write_text(json.dumps(dict(vectors=len(vectors),conv_layers=coverage,
        source='Real per-layer integer activations and pretrained YuNet weights; no injected face positions'),indent=2)+'\n')
    print(f'Generated {len(vectors)} dot products across {len(coverage)} real convolution layers')

if __name__=='__main__':main()
