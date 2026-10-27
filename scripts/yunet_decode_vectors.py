"""Generate integer output-decoder ROMs and complete head-stream fixtures."""
from yunet_integer import *

THRESHOLD=math.ceil(.65**2*127**2)

def clip(v,lo,hi):return min(hi,max(lo,int(v)))
def lut_arrays(scales,heads):
    sig=np.zeros(1536,np.uint8);offset=np.zeros(768,np.int16);size=np.zeros(768,np.uint16)
    for level,stride in enumerate((8,16,32)):
        for byte in range(256):
            q=byte if byte<128 else byte-256
            for kind,base in [('cls',0),('obj',768)]:
                x=q*2.**scales[heads[f'{kind}_{stride}']]
                sig[base+level*256+byte]=round(127/(1+math.exp(-x)))
            x=q*2.**scales[heads[f'bbox_{stride}']]
            offset[level*256+byte]=clip(round(x*stride*16),-32768,32767)
            size[level*256+byte]=clip(round(math.exp(min(12.,max(-12.,x)))*stride*16),1,32767)
    return sig,offset,size

def candidate(level,gx,gy,q,sig,offset,size):
    cls,obj,bx,by,bw,bh=map(int,q);base=level*256
    score=int(sig[base+(cls&255)])*int(sig[768+base+(obj&255)])
    cx=gx*(8<<level)*16+int(offset[base+(bx&255)])
    cy=gy*(8<<level)*16+int(offset[base+(by&255)])
    w=int(size[base+(bw&255)]);h=int(size[base+(bh&255)])
    left=clip((cx-(w//2))//16,0,160);right=clip((cx+(w//2)+15)//16,0,160)
    top=clip((cy-(h//2))//16,0,90);bottom=clip((cy+(h//2)+15)//16,0,90)
    valid=score>=THRESHOLD and 0<=cx<160*16 and 0<=cy<90*16 and right>left and bottom>top
    side=min(90,max(right-left,bottom-top))*8
    centerx=(left+right)*4;centery=(top+bottom)*4
    x=clip(centerx-side//2,0,1280-side);y=clip(centery-side//2,0,720-side)
    return valid,score,(x,y,side,centerx,centery)

def main():
    m,weights=load_graph();net=json.loads((OUT/'network.json').read_text());ops,scales,heads,*_=lower(m,weights,net['scales'],
        {op['dst']:[1,op['shape'][2],op['shape'][0],op['shape'][1]] for op in net['operations']})
    sig,offset,size=lut_arrays(scales,heads);rom=ROOT/'rtl/analytics/face_cnn';rom.mkdir(exist_ok=True,parents=True)
    np.savetxt(rom/'sigmoid.hex',sig,fmt='%02x');np.savetxt(rom/'offset.hex',offset.astype(np.uint16),fmt='%04x');np.savetxt(rom/'size.hex',size,fmt='%04x')
    summary={}
    with (OUT/'decode_vectors.txt').open('w',encoding='ascii') as f:
        for name,a in fixture_images().items():
            t,_,_=infer(a,ops);rows=[];best=None;bestscore=-1
            for level,stride in enumerate((8,16,32)):
                c=t[heads[f'cls_{stride}']];o=t[heads[f'obj_{stride}']];b=t[heads[f'bbox_{stride}']]
                for y in range(c.shape[0]):
                    for x in range(c.shape[1]):
                        q=[int(c[y,x,0]),int(o[y,x,0]),*map(int,b[y,x])]
                        valid,score,box=candidate(level,x,y,q,sig,offset,size)
                        if valid and score>bestscore:best=box;bestscore=score
                        rows.append([level,x,y,*q])
            expected=[int(best is not None),max(0,bestscore),*(best or (0,0,0,0,0))]
            f.write(' '.join(map(str,[len(rows),*expected]))+'\n')
            for row in rows:f.write(' '.join(map(str,row))+'\n')
            summary[name]=dict(found=best is not None,score_product=max(0,bestscore),box=best)
    (OUT/'decoder_reference.json').write_text(json.dumps(dict(threshold_product=THRESHOLD,
        policy='single highest-score face, Q7 sigmoid product, Q4 clipped geometry; no tracking association yet',
        fixtures=summary),indent=2)+'\n')
    print(f'Generated {len(summary)} full head streams, {THRESHOLD=}')

if __name__=='__main__':main()
