"""Array reference for shared RGB/luma contours, including weak/noisy scenes."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'sim/vision_tasks/v42_edge'
def reference(rgb):
 a=rgb.astype(np.int32);p=np.pad(a,((2,0),(2,0),(0,0)),mode='edge');h,w=a.shape[:2]
 t=[[p[j:j+h,i:i+w] for i in range(3)] for j in range(3)]
 y=[[v[:,:,0]//4+v[:,:,1]//2+v[:,:,2]//4 for v in row] for row in t]
 gx=sum(k*(y[j][2]-y[j][0]) for j,k in enumerate([3,10,3]));gy=sum(k*(y[2][i]-y[0][i]) for i,k in enumerate([3,10,3]))
 strength=np.maximum((abs(gx)+abs(gy))//16,(abs(t[1][2]-t[1][0]).sum(2)+abs(t[2][1]-t[0][1]).sum(2))//4)
 blur=(sum(t[j][i]*[1,2,1][j]*[1,2,1][i] for j in range(3) for i in range(3))+8)//16
 c=np.where((strength<=24)[:,:,None],blur,t[1][1]);l=c[:,:,0]//4+c[:,:,1]//2+c[:,:,2]//4
 threshold=np.where(l<16,20,10+l//32)
 level=np.select([strength>=80,strength>=40,strength>=20,strength>=threshold,strength>=threshold//2],[255,192,112,64,24],default=0)
 old=np.where((abs(gx)+abs(gy))//16>=80,255,0);old[:2]=0;old[:,:2]=0
 return np.repeat(level[:,:,None],3,2).astype(np.uint8),np.repeat(old[:,:,None],3,2).astype(np.uint8)
def main():
 OUT.mkdir(parents=True,exist_ok=True);rows=[];rng=np.random.default_rng(42)
 cases={}
 for name in ['lena','figurine','fruits']:
  cases[name]=np.array(ImageOps.fit(Image.open(ROOT/f'sim/face_lbp/data/{name}.jpg').convert('RGB'),(160,90)))
 a=np.full((90,160,3),96,np.uint8);a[:,80:]=116;cases['weak_step']=a
 a=np.zeros((90,160,3),np.uint8);a[:,:80]=[252,0,0];a[:,80:]=[0,126,0];cases['isoluma']=a
 cases['dark_noise']=np.clip(5+rng.integers(-3,4,(90,160,3)),0,255).astype(np.uint8)
 cases['uniform']=np.full((90,160,3),120,np.uint8)
 cases['black']=np.zeros((90,160,3),np.uint8)
 for name,a in cases.items():
  e,old=reference(a)
  for suffix,data in [('hex',a),('expected',e)]:
   v=data[:,:,0].astype(int)*65536+data[:,:,1].astype(int)*256+data[:,:,2];(OUT/f'{name}.{suffix}').write_text(''.join(f'{p:06x}\n' for p in v.ravel()),encoding='ascii')
  rows.append(name+'\n')
  if name in ['figurine','weak_step','isoluma']:
   Image.fromarray(a).save(ROOT/f'reports/field_v42/edge_{name}_input.png')
   Image.fromarray(old).save(ROOT/f'reports/field_v42/edge_{name}_old.png')
   Image.fromarray(e).save(ROOT/f'reports/field_v42/edge_{name}_expected.png')
   Image.fromarray(np.concatenate([a,old,e],axis=1)).resize((960,180)).save(ROOT/f'reports/field_v42/edge_{name}.png')
 (OUT/'cases.txt').write_text(''.join(rows),encoding='ascii');print('Prepared',len(rows),'edge cases')
if __name__=='__main__':main()
