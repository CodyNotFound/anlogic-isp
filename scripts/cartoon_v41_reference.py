"""Integer image fixtures and an independent array reference for cel rendering."""
from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageOps
ROOT=Path(__file__).resolve().parents[1]
SIM=ROOT/'sim/cartoon';OUT=ROOT/'reports/cartoon_v41'

def render(rgb,smooth_th=24,ink_th=40,ink_dark=56,ink_solid=80,shade_shift=5):
    a=np.asarray(rgb,dtype=np.int32);h,w,_=a.shape
    ys=[np.maximum(np.arange(h)+d,0) for d in [-2,-1,0]]
    xs=[np.maximum(np.arange(w)+d,0) for d in [-2,-1,0]]
    taps=[[a[yy[:,None],xx[None,:]] for xx in xs] for yy in ys]
    center=taps[1][1]
    blur=sum(taps[y][x]*([1,2,1][y]*[1,2,1][x]) for y in range(3) for x in range(3))
    blur=(blur+8)//16
    luma=[[(p[:,:,0]//4+p[:,:,1]//2+p[:,:,2]//4) for p in row] for row in taps]
    gx=sum([3,10,3][j]*(luma[j][2]-luma[j][0]) for j in range(3))
    gy=sum([3,10,3][j]*(luma[2][j]-luma[0][j]) for j in range(3))
    strength=(np.abs(gx)+np.abs(gy))//16
    chroma=(np.abs(taps[1][2]-taps[1][0]).sum(axis=2)+np.abs(taps[2][1]-taps[0][1]).sum(axis=2))//4
    strength=np.maximum(strength,chroma)
    smooth=np.where((strength<=smooth_th)[:,:,None],blur,center)
    y=smooth[:,:,0]//4+smooth[:,:,1]//2+smooth[:,:,2]//4
    bands=np.minimum(((y+(1<<(shade_shift-1)))>>shade_shift)<<shade_shift,255)
    poster=np.clip(smooth+(bands-y)[:,:,None],0,255)
    out=np.where((strength>=ink_solid)[:,:,None],np.array([16,16,24]),
                 np.where((strength>=ink_dark)[:,:,None],poster//4,
                          np.where((strength>=ink_th)[:,:,None],poster//2,poster)))
    return out.astype(np.uint8),strength

def hexfile(path,a):
    a=np.asarray(a,dtype=np.uint32);v=(a[:,:,0]<<16)|(a[:,:,1]<<8)|a[:,:,2]
    path.write_text(''.join(f'{int(p):06x}\n' for p in v.ravel()),encoding='ascii')

def main():
    SIM.mkdir(exist_ok=True,parents=True);OUT.mkdir(exist_ok=True,parents=True)
    cases=[]
    for name in ['lena','fruits','grace_hopper','figurine']:
        image=Image.open(ROOT/f'sim/face_lbp/data/{name}.jpg').convert('RGB')
        image=ImageOps.pad(image,(640,360),color=(96,96,96),method=Image.Resampling.LANCZOS)
        a=np.asarray(image);expected,strength=render(a)
        hexfile(SIM/f'{name}.hex',a);hexfile(SIM/f'{name}.expected',expected)
        image.save(OUT/f'{name}_input.png');Image.fromarray(expected).save(OUT/f'{name}_reference.png')
        cases.append(dict(name=name,width=640,height=360,pixels=640*360,ink_fraction=float(np.mean(strength>=40))))
    image=ImageOps.pad(Image.open(ROOT/'sim/face_lbp/data/lena.jpg').convert('RGB'),(1280,720),color=(96,96,96),method=Image.Resampling.LANCZOS)
    a=np.asarray(image);expected,_=render(a)
    hexfile(SIM/'native720.hex',a);hexfile(SIM/'native720.expected',expected)
    image.save(OUT/'native720_input.png');Image.fromarray(expected).save(OUT/'native720_reference.png')
    cases.append(dict(name='native720',width=1280,height=720,pixels=921600,scope='native application fixture'))
    # Color-only contours, noisy flats, ramps, opposite frame contents, row seams.
    rng=np.random.default_rng(4101)
    y,x=np.mgrid[:12,:24]
    probe=np.zeros((12,24,3),np.uint8)
    probe[:,:12]=[252,0,0];probe[:,12:]=[0,126,0] # identical approximation Y=63
    for name,a in [('isoluma',probe),('noise',np.clip(120+rng.integers(-6,7,(12,24,3)),0,255).astype(np.uint8)),
                   ('ramp',np.stack([(x*11+y*7)%256,(x*7+y*21)%256,(x*31+y*3)%256],axis=2).astype(np.uint8)),
                   ('white',np.full((12,24,3),255,np.uint8)),('black',np.zeros((12,24,3),np.uint8))]:
        expected,strength=render(a);hexfile(SIM/f'{name}.hex',a);hexfile(SIM/f'{name}.expected',expected)
        cases.append(dict(name=name,width=24,height=12,pixels=24*12))
    (OUT/'reference.json').write_text(json.dumps({'algorithm':'edge-gated RGB Gaussian + rounded luma bands + luma/color ink','cases':cases},indent=2),encoding='utf-8')
    print(json.dumps(cases,indent=2))

if __name__=='__main__':main()
