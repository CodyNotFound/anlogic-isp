from pathlib import Path
import numpy as np,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/effects_v60';OUT.mkdir(exist_ok=True)
W,H=96,48

def render(a,new):
 a=a.astype(np.int32)
 if new:
  prev1=np.concatenate([a[:,:1],a[:,:-1]],axis=1)
  prev2=np.concatenate([a[:,:1],a[:,:1],a[:,:-2]],axis=1)
  a=np.median(np.stack([prev2,prev1,a]),axis=0).astype(np.int32)
 ys=[np.maximum(np.arange(H)+d,0) for d in [-2,-1,0]];xs=[np.maximum(np.arange(W)+d,0) for d in [-2,-1,0]]
 t=[[a[yy[:,None],xx[None,:]] for xx in xs] for yy in ys];center=t[1][1]
 blur=(sum(t[y][x]*([1,2,1][y]*[1,2,1][x]) for y in range(3) for x in range(3))+8)//16
 l=[[v[:,:,0]//4+v[:,:,1]//2+v[:,:,2]//4 for v in row] for row in t]
 gx=sum([3,10,3][i]*(l[i][2]-l[i][0]) for i in range(3));gy=sum([3,10,3][i]*(l[2][i]-l[0][i]) for i in range(3))
 strength=np.maximum((abs(gx)+abs(gy))//16,(abs(t[1][2]-t[1][0]).sum(2)+abs(t[2][1]-t[0][1]).sum(2))//4)
 color=np.where((strength<=24)[:,:,None],blur,center)
 sy=color[:,:,0]//4+color[:,:,1]//2+color[:,:,2]//4
 delta=np.minimum(((sy+16)//32)*32,255)-sy
 shaded=np.clip(color+delta[:,:,None],0,255)
 allowance=np.where(sy<64,12,0) if new else 0
 cartoon=np.where((strength>=80+allowance)[:,:,None],[16,16,24],np.where((strength>=56+allowance)[:,:,None],shaded//4,np.where((strength>=40+allowance)[:,:,None],shaded//2,shaded)))
 th=np.where(sy<(96 if new else 16),20,10+sy//32)
 edge=np.where(strength>=80,255,np.where(strength>=40,192,np.where(strength>=20,112,np.where(strength>=th,64,0 if new else np.where(strength>=th//2,24,0)))))
 return cartoon.astype(np.uint8),edge.astype(np.uint8)

def rgbhex(a):return (a[:,:,0].astype(np.uint32)<<16)|(a[:,:,1].astype(np.uint32)<<8)|a[:,:,2]
rng=np.random.default_rng(20261025)
flat=np.full((H,W,3),40,np.uint8)
noise=np.clip(flat.astype(int)+rng.integers(-12,13,(H,W,3)),0,255).astype(np.uint8)
imp=flat.copy();imp[rng.random((H,W))<.02]=255
weak=flat.copy();weak[:,W//2:]=64
chroma=np.zeros_like(flat);chroma[:,:W//2]=[80,40,40];chroma[:,W//2:]=[40,40,80]
ramp=rng.integers(0,256,(H,W,3),dtype=np.uint8)
cases=[('flat',flat),('noise',noise),('impulse',imp),('weak_step',weak),('color_step',chroma),('random',ramp),('black',np.zeros_like(flat)),('white',np.full_like(flat,255))]
metrics=[]
for i,(name,a) in enumerate(cases):
 new,e=render(a,True);old,oe=render(a,False)
 np.savetxt(OUT/f'input_{i}.hex',rgbhex(a).reshape(-1),fmt='%06x')
 np.savetxt(OUT/f'cartoon_{i}.hex',rgbhex(new).reshape(-1),fmt='%06x')
 np.savetxt(OUT/f'edge_{i}.hex',e.reshape(-1).astype(np.uint32)*0x010101,fmt='%06x')
 metrics.append(dict(case=name,old_edge_nonzero=float(np.mean(oe[3:,3:]>0)),new_edge_nonzero=float(np.mean(e[3:,3:]>0)),old_ink_fraction=float(np.mean(oe[3:,3:]>=112)),new_ink_fraction=float(np.mean(e[3:,3:]>=112))))
print(json.dumps(metrics,indent=2));(OUT/'quality.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
