from pathlib import Path
import numpy as np,ast,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];O=ROOT/'reports/effects_v67';O.mkdir(exist_ok=True);W,H=96,48
# Reuse the independent cartoon/edge mathematical reference (no RTL parsing).
s=(ROOT/'scripts/effects_v60_reference.py').read_text(encoding='utf-8');nodes=[n for n in ast.parse(s).body if isinstance(n,ast.FunctionDef)];exec(compile(ast.Module(body=nodes,type_ignores=[]),'cartoon_reference','exec'))
scenes=[]
for i in range(8):
 rgb=np.loadtxt(ROOT/'reports/effects_v60'/f'input_{i}.hex',dtype=np.uint32,converters={0:lambda x:int(x,16)}).reshape(H,W)
 scenes.append(np.stack([(rgb>>16)&255,(rgb>>8)&255,rgb&255],2).astype(np.uint8))
for c in [[180,30,20],[25,170,45],[30,40,190]]:scenes.append(np.tile(np.array(c,np.uint8),(H,W,1)))
checker=np.zeros((H,W,3),np.uint8);checker[:]=[25,170,45];checker[(np.indices((H,W)).sum(0)//6)%2==0]=[180,30,20];scenes.append(checker)
metrics=[]
for case,raw in enumerate(scenes):
 np.savetxt(O/f'input_{case}.hex',rgbhex(raw).reshape(-1),fmt='%06x');np.savetxt(O/f'mode0_{case}.hex',rgbhex(raw).reshape(-1),fmt='%06x')
 cartoon,edge=render(raw,True);np.savetxt(O/f'mode9_{case}.hex',rgbhex(cartoon).reshape(-1),fmt='%06x');np.savetxt(O/f'mode7_{case}.hex',edge.reshape(-1).astype(np.uint32)*0x010101,fmt='%06x')
 a=raw.astype(int);prev1=np.concatenate([a[:,:1],a[:,:-1]],1);prev2=np.concatenate([a[:,:1],a[:,:1],a[:,:-2]],1);a=np.median(np.stack([prev2,prev1,a]),axis=0).astype(int)
 gray=a[:,:,0]//4+a[:,:,1]//2+a[:,:,2]//4
 yy=[np.maximum(np.arange(H)+d,0)for d in [-2,-1,0]];xx=[np.maximum(np.arange(W)+d,0)for d in [-2,-1,0]]
 t=[[gray[y[:,None],x[None,:]]for x in xx]for y in yy];center=t[1][1];avg=(sum(v for row in t for v in row)-center)//8;detail=center-avg
 centered_rgb=a[yy[1][:,None],xx[1][None,:]];sharp=np.clip(centered_rgb+np.where(abs(detail)>6,detail*4,0)[:,:,None],0,255).astype(np.uint8)
 delta=center-t[0][0];emboss=np.clip(128+np.where(abs(delta)>6,delta,0),0,255).astype(np.uint8)
 blur=np.zeros_like(a)
 for y in range(H):
  for x in range(W):
   horizontal=a[y,x]if x==0 else (a[y,x]+3*horizontal+2)//4
   blur[y,x]=horizontal if y==0 else (horizontal+3*blur[y-1,x]+2)//4
 blur=blur.astype(np.uint8)
 for mode,image in [(5,sharp),(6,blur)]:np.savetxt(O/f'mode{mode}_{case}.hex',rgbhex(image).reshape(-1),fmt='%06x')
 np.savetxt(O/f'mode8_{case}.hex',emboss.reshape(-1).astype(np.uint32)*0x010101,fmt='%06x')
 if case>=8 and case<=10:assert np.array_equal(sharp,raw)and np.array_equal(blur,raw),'flat color/brightness preservation failed'
 if case in [5,11]:Image.fromarray(np.concatenate([raw,sharp,blur],axis=1)).resize((864,144),Image.Resampling.NEAREST).save(O/f'color_preview_{case}.png')
 metrics.append(dict(case=case,mean_rgb_before=raw.mean((0,1)).tolist(),mean_rgb_sharp=sharp.mean((0,1)).tolist(),mean_rgb_blur=blur.mean((0,1)).tolist(),flat_field_exact=bool(case in [8,9,10])))
(O/'quality.json').write_text(json.dumps(metrics,indent=2));print('Generated twelve RGB scenes / six modes, original cartoon/edge math, exact solid RGB preservation')
s=(ROOT/'sim/tb_effects_spatial_v66.sv').read_text(encoding='utf-8').replace('v66','v67').replace('f<8','f<12').replace('221184','331776').replace('eight scenes','twelve scenes').replace('#3000000','#5000000')
s=s.replace(' if(mode==7)$sformat(name,"reports/effects_v67/edge_%0d.hex",f);\n if(mode==9)$sformat(name,"reports/effects_v67/cartoon_%0d.hex",f);','').replace(' $sformat(name,"reports/effects_v67/edge_%0d.hex",f);$readmemh(name,edges);','')
# Eliminate any unused old-edge fixture loads; unknown-fixture assertions remain mandatory.
s='\n'.join(line for line in s.splitlines()if not('edge_%0d.hex'in line))+'\n'
(ROOT/'sim/tb_effects_spatial_v67.sv').write_text(s,encoding='utf-8')
