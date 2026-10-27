"""Semantic color/pose sequence: geometric masks define expected components."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'sim/vision_tasks/v42_color'
def clean(m):
 p=np.pad(m.astype(int),1);return sum(p[y:y+48,x:x+64] for y in range(3) for x in range(3))>=5
def image(cx=32,cy=24,w=18,h=14,angle=0,gain=1,add=0,gloss=False,color=(224,112,32),extra=False,empty=False):
 mask=Image.new('1',(64,48));draw=ImageDraw.Draw(mask)
 if not empty:
  a=np.deg2rad(angle);xy=[]
  for x,y in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]:xy.append((round(cx+x*np.cos(a)-y*np.sin(a)),round(cy+x*np.sin(a)+y*np.cos(a))))
  draw.polygon(xy,fill=1)
 m=np.array(mask,dtype=bool);rgb=np.full((48,64,3),48,dtype=np.uint8)
 rgb[m]=np.clip(np.array(color)*gain+add,0,255).astype(np.uint8)
 if gloss:
  rgb[cy-2:cy+2,cx-2:cx+2]=235;m[cy-2:cy+2,cx-2:cx+2]=False
 if extra:rgb[34:43,3:12]=color
 # White lamp is always present, including pick and reacquisition frames.
 rgb[1:7,2:10]=250
 return rgb,m
def geometry(m):
 y,x=np.where(clean(m));return int(x.sum()//len(x)),int(y.sum()//len(y)),len(x)
def main():
 OUT.mkdir(parents=True,exist_ok=True);lines=[]
 cases=[('pick',{},0,False),('lock',{},0,True),('dim_tilt',dict(angle=25,gain=.55,cx=35),0,True),
 ('neutral_glint',dict(angle=-20,gain=.8,add=24,cx=37,gloss=True),0,True),('thin_tilt',dict(w=6,cx=38,gain=.35),0,True),
 ('whiteout',dict(color=(235,235,235),cx=38),0,False),('restore',dict(w=8,cx=39,gain=.7),0,True)]
 cases += [(f'gone{i}',dict(empty=True),0,False) for i in range(4)]
 cases += [('reenter_first',dict(cx=54,cy=12,w=10,h=10),0,False),('reenter_confirm',dict(cx=54,cy=12,w=10,h=10),0,True),
 ('wrong_hue',dict(cx=54,cy=12,w=10,h=10,color=(225,30,25)),0,False),('gone_again0',dict(empty=True),0,False),('gone_again1',dict(empty=True),0,False),
 ('ambiguous',dict(cx=52,cy=12,w=10,h=10,extra=True),0,False),('unique_first',dict(cx=14,cy=25,w=10,h=10),0,False),('unique_confirm',dict(cx=14,cy=25,w=10,h=10),0,True),
 ('abort',dict(),2,False),('after_abort_first',dict(cx=17,cy=26,w=10,h=10),0,False),('after_abort_confirm',dict(cx=17,cy=26,w=10,h=10),0,True),
 ('new_blue_pick',dict(color=(30,100,220)),1,False),('new_blue_lock',dict(color=(30,100,220)),0,True),('old_orange_rejected',dict(),0,False)]
 for name,kw,action,found in cases:
  rgb,m=image(**kw);x,y,area=geometry(m) if found else (0,0,0)
  if name=='dim_tilt':rgb[-1,-1]=[224,112,32] # isolated last-bit sentinel; majority removes it
  v=(rgb[:,:,0].astype(int)<<16)|(rgb[:,:,1].astype(int)<<8)|rgb[:,:,2]
  (OUT/f'{name}.hex').write_text(''.join(f'{p:06x}\n' for p in v.ravel()),encoding='ascii')
  lines.append(f'{name} {action} 1 {int(found)} {x} {y} {area}\n')
 (OUT/'cases.txt').write_text(''.join(lines),encoding='ascii');print('Prepared',len(cases),'semantic cases')
if __name__=='__main__':main()
