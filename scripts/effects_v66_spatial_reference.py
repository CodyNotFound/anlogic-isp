from pathlib import Path
import numpy as np,json
ROOT=Path(__file__).resolve().parents[1];O=ROOT/'reports/effects_v66';O.mkdir(exist_ok=True);W,H=96,48
for case in range(8):
 for prefix in ['input','edge','cartoon']:(O/f'{prefix}_{case}.hex').write_bytes((ROOT/'reports/effects_v60'/f'{prefix}_{case}.hex').read_bytes())
metrics=[]
for case in range(8):
 rgb=np.loadtxt(O/f'input_{case}.hex',dtype=np.uint32,converters={0:lambda x:int(x,16)}).reshape(H,W)
 np.savetxt(O/f'mode0_{case}.hex',rgb.reshape(-1),fmt='%06x')
 a=np.stack([(rgb>>16)&255,(rgb>>8)&255,rgb&255],2).astype(int)
 prev1=np.concatenate([a[:,:1],a[:,:-1]],axis=1)
 prev2=np.concatenate([a[:,:1],a[:,:1],a[:,:-2]],axis=1)
 a=np.median(np.stack([prev2,prev1,a]),axis=0).astype(int)
 filtered=a[:,:,0]//4+a[:,:,1]//2+a[:,:,2]//4
 gray=filtered
 yy=[np.maximum(np.arange(H)+d,0) for d in [-2,-1,0]];xx=[np.maximum(np.arange(W)+d,0) for d in [-2,-1,0]]
 t=[[filtered[y[:,None],x[None,:]] for x in xx] for y in yy]
 center=t[1][1];summ=sum(v for row in t for v in row);avg=(summ-center)//8
 detail=center-avg
 sharp=np.clip(center+np.where(abs(detail)>6,detail*4,0),0,255)
 delta=center-t[0][0];emboss=np.clip(128+np.where(abs(delta)>6,delta,0),0,255)
 blur=np.zeros_like(gray);horizontal=0
 for y in range(H):
  for x in range(W):
   horizontal=int(filtered[y,x]) if x==0 else (int(filtered[y,x])+3*horizontal+2)//4
   blur[y,x]=horizontal if y==0 else (horizontal+3*int(blur[y-1,x])+2)//4
 valid=(np.arange(H)[:,None]>=2)&(np.arange(W)[None,:]>=2)
 for mode,out in [(5,sharp),(6,blur),(8,emboss)]:
  out=out.astype(np.uint32)*0x010101
  np.savetxt(O/f'mode{mode}_{case}.hex',out.reshape(-1),fmt='%06x')
 metrics.append(dict(case=case,emboss_std=float(emboss[3:,3:].std()),blur_std=float(blur[3:,3:].std()),sharpen_std=float(sharp[3:,3:].std())))
(O/'spatial_quality.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
