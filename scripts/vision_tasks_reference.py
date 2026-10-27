"""Independent integer references and deterministic adversarial video fixtures.

No training. These tests establish arithmetic/state-machine behavior, not real
camera accuracy. Measured RTL results are evaluated separately by the reporter.
"""
from pathlib import Path
from collections import deque
import json
import numpy as np
from PIL import Image, ImageOps

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'sim/vision_tasks'
OUT=ROOT/'reports/vision_tasks'


def hexfile(path,a,width=2):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(''.join(f'{int(x):0{width}x}\n' for x in np.asarray(a).ravel()))


def rgbhex(path,rgb):
    a=np.asarray(rgb,dtype=np.uint32)
    hexfile(path,(a[...,0]<<16)|(a[...,1]<<8)|a[...,2],6)


def luma(rgb):
    a=np.asarray(rgb,dtype=np.int32)
    return ((a[...,0]+2*a[...,1]+a[...,2])>>2).astype(np.uint8)


def rgb_means(rgb):
    a=np.asarray(rgb,dtype=np.uint32);h,w=a.shape[:2]
    return ((a.reshape(h//8,8,w//8,8,3).sum((1,3))+32)>>6).astype(np.uint8)


def clahe_maps(gray):
    h,w=gray.shape;ny=(h+31)//32;nx=(w+31)//32
    maps=np.empty((ny,nx,32),dtype=np.uint8)
    histograms=[]
    for y in range(ny):
        for x in range(nx):
            tile=gray[y*32:(y+1)*32,x*32:(x+1)*32]
            hist=np.bincount((tile.ravel()>>3),minlength=32).astype(np.int64)
            clipped=np.minimum(hist,max(1,tile.size//16))
            excess=int((hist-clipped).sum())
            redistributed=clipped+excess//32+(np.arange(32)<excess%32)
            assert redistributed.sum()==tile.size
            maps[y,x]=(redistributed.cumsum()*255//tile.size).astype(np.uint8)
            histograms.append(hist.tolist())
    return maps,histograms


def clahe_apply(rgb,maps):
    h,w=rgb.shape[:2];ny,nx,_=maps.shape
    def axis(n,tiles):
        d=np.maximum(np.arange(n)-128,0)
        lo=np.minimum(d>>8,tiles-1);hi=np.minimum(lo+1,tiles-1)
        weight=np.where((np.arange(n)>=128)&((d>>8)<tiles-1),d&255,0)
        return lo,hi,weight
    x0,x1,wx=axis(w,nx);y0,y1,wy=axis(h,ny)
    gray=luma(rgb).astype(np.int64);b=gray>>3
    def lookup(yy,xx):
        high=maps[yy[:,None],xx[None,:],b].astype(np.int64)
        low=maps[yy[:,None],xx[None,:],np.maximum(b-1,0)].astype(np.int64)
        low=np.where(b==0,0,low)
        return (low*8+(high-low)*((gray&7)+1)+4)>>3
    a=lookup(y0,x0);c=lookup(y0,x1);d=lookup(y1,x0);e=lookup(y1,x1)
    top=a*256+(c-a)*wx[None,:]
    bottom=d*256+(e-d)*wx[None,:]
    mapped=(top*256+(bottom-top)*wy[:,None]+32768)>>16
    delta=(mapped-gray)>>1
    return np.clip(rgb.astype(np.int64)+delta[...,None],0,255).astype(np.uint8)


class Tracker:
    def __init__(self,w=64,h=48):
        self.w=w;self.h=h;self.found=False;self.pending=True;self.cx=w//2;self.cy=h//2;self.template=None

    def step(self,image,reseed=False):
        if reseed:self.pending=True;self.found=False
        if not self.pending and not self.found:
            return dict(result=0,found=0,x=self.cx,y=self.cy,best=0,second=0,quality=0)
        a=image.astype(np.int32)
        def patch(x,y):return a[y:y+16,x+1:x+17]-a[y:y+16,x:x+16]
        if self.pending:
            self.template=patch(self.w//2-8,self.h//2-8)
            self.found=int(np.abs(self.template).sum())>=1024;self.pending=False
            self.cx=self.w//2;self.cy=self.h//2
            return dict(result=1,found=int(self.found),x=self.cx,y=self.cy,best=0,second=0,quality=255 if self.found else 0)
        candidates=[]
        for y in range(max(0,self.cy-16),min(self.h-16,self.cy)+1):
            for x in range(max(0,self.cx-16),min(self.w-17,self.cx)+1):
                candidates.append((int(np.abs(patch(x,y)-self.template).sum()),x,y))
        best,x,y=min(candidates,key=lambda t:t[0])
        second=min([s for s,xx,yy in candidates if abs(xx-x)>2 or abs(yy-y)>2] or [0x3ffff])
        self.found=best<=6144 and second>=best+256
        if self.found:self.cx=x+8;self.cy=y+8
        return dict(result=1,found=int(self.found),x=self.cx,y=self.cy,best=best,second=second,
                    quality=min(255,(second-best)>>4) if self.found else 0)


def majority(mask):
    p=np.pad(mask.astype(np.uint8),1)
    counts=sum(p[y:y+mask.shape[0],x:x+mask.shape[1]].astype(np.int16) for y in range(3) for x in range(3))
    return counts>=5


def components(mask):
    m=mask.copy();h,w=m.shape;best=None
    for y in range(h):
        for x in range(w):
            if not m[y,x]:continue
            q=deque([(x,y)]);m[y,x]=False;points=[]
            while q:
                xx,yy=q.popleft();points.append((xx,yy))
                for nx,ny in [(xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)]:
                    if 0<=nx<w and 0<=ny<h and m[ny,nx]:m[ny,nx]=False;q.append((nx,ny))
            if 12<=len(points)<=w*h//2 and (best is None or len(points)>len(best)):best=points
    if best is None:return dict(found=0,x=0,y=0,w=0,h=0,cx=0,cy=0,area=0)
    p=np.array(best);lo=p.min(0);hi=p.max(0);center=p.sum(0)//len(p)
    return dict(found=1,x=int(lo[0]),y=int(lo[1]),w=int(hi[0]-lo[0]+1),h=int(hi[1]-lo[1]+1),
                cx=int(center[0]),cy=int(center[1]),area=len(p))


class Region:
    def __init__(self):self.pending=True;self.calibrated=False

    def step(self,rgb,reseed=False):
        if reseed:self.pending=True;self.calibrated=False
        h,w=rgb.shape[:2];a=rgb.astype(np.int32);rg=a[...,0]-a[...,1];bg=a[...,2]-a[...,1]
        empty=dict(found=0,x=0,y=0,w=0,h=0,cx=0,cy=0,area=0)
        if self.pending:
            p=a[h//2-1:h//2+2,w//2-1:w//2+2];s=p.sum((0,1));sr=int(s[0]-s[1]);sb=int(s[2]-s[1])
            self.seed_y=int((int(s[0])+2*int(s[1])+int(s[2]))/9)
            self.neutral=abs(sr)+abs(sb)<360
            self.calibrated=64<=self.seed_y<=980;self.pending=False
            self.rg=int(sr/9);self.bg=int(sb/9)
            pr=p[...,0]-p[...,1];pb=p[...,2]-p[...,1]
            self.tolerance=min(96,24+int(np.ptp(pr))+int(np.ptp(pb)))
            return dict(calibrated=int(self.calibrated),overflow=0,**empty)
        if not self.calibrated:return dict(calibrated=0,overflow=0,**empty)
        mask=(np.abs(rg-self.rg)+np.abs(bg-self.bg)<=self.tolerance)&(luma(rgb)>=16)&(luma(rgb)<=245)
        if self.neutral:mask &= np.abs(a[...,0]+2*a[...,1]+a[...,2]-self.seed_y)<=128
        return dict(calibrated=1,overflow=0,**components(majority(mask)))


def prepare():
    BASE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(20261020);w,h=64,48
    texture=rng.integers(35,185,(28,40),dtype=np.uint8)
    background=rng.integers(88,93,(h,w),dtype=np.uint8)
    def moving(dx=0,dy=0,brightness=0):
        image=background.copy();left=12+dx;top=10+dy
        x0=max(0,left);x1=min(w,left+40);y0=max(0,top);y1=min(h,top+28)
        image[y0:y1,x0:x1]=texture[y0-top:y1-top,x0-left:x1-left]
        return np.clip(image.astype(int)+brightness,0,255).astype(np.uint8)
    tracker=Tracker();track_records=[]
    def add_track(name,image,action=0):
        nonlocal tracker
        if action==1:tracker=Tracker()
        expected=tracker.step(image,action==2)
        hexfile(BASE/f'{name}.hex',image);Image.fromarray(image).save(BASE/f'{name}.png')
        track_records.append(dict(name=name,action=action,**expected))
    add_track('track_seed',moving(),1)
    add_track('track_move',moving(5,-3))
    add_track('track_light',moving(9,1,24))
    occlusion=np.full((h,w),96,dtype=np.uint8)
    add_track('track_occluded',occlusion)
    add_track('track_no_auto_relock',moving())
    add_track('track_reseed',moving(),2)
    for n,dx in enumerate([8,16,23]):add_track(f'track_edge{n}',moving(dx))
    add_track('track_flat',np.full((h,w),128,dtype=np.uint8),1)
    stripes=np.tile(np.where(np.arange(w)%4<2,40,180).astype(np.uint8),(h,1))
    add_track('track_stripes_seed',stripes,1);add_track('track_ambiguous',stripes)
    (BASE/'tracker_cases.txt').write_text(''.join(f"{r['name']} {r['action']} "+' '.join(str(r[k]) for k in ['result','found','x','y','best','second','quality'])+'\n' for r in track_records))
    assert all(r['found'] for r in track_records if r['name'] in ['track_move','track_light','track_edge0','track_edge1','track_edge2'])
    assert not next(r for r in track_records if r['name']=='track_ambiguous')['found']

    def scene(x=20,y=12,b=0,small=True):
        image=np.full((h,w,3),80,dtype=np.uint8);image[y:y+20,x:x+24]=(180,45,40)
        if small:image[2:8,2:10]=(180,45,40)
        for xx,yy in [(0,20),(5,35),(42,2),(58,38)]:image[yy,xx]=(180,45,40)
        return np.clip(image.astype(int)+b,0,255).astype(np.uint8)
    reg=Region();region_records=[]
    def add_region(name,image,action=0):
        nonlocal reg
        if action==1:reg=Region()
        result=reg.step(image,action==2)
        rgbhex(BASE/f'{name}.hex',image);Image.fromarray(image).save(BASE/f'{name}.png')
        region_records.append(dict(name=name,action=action,**result))
    add_region('region_pick',scene(),1);add_region('region_components',scene())
    add_region('region_light',scene(b=20));add_region('region_move',scene(x=32,y=14))
    add_region('region_empty',np.full((h,w,3),80,dtype=np.uint8))
    edge=np.full((h,w,3),80,dtype=np.uint8);edge[:16,:20]=(180,45,40)
    add_region('region_edge',edge);add_region('region_overexposed',np.full((h,w,3),255,dtype=np.uint8))
    add_region('region_neutral_pick',np.full((h,w,3),80,dtype=np.uint8),1)
    add_region('region_repick',scene(),2);add_region('region_after_repick',scene())
    def soft_scene(color,x=20,y=12):
        image=np.full((h,w,3),230,dtype=np.uint8);image[y:y+20,x:x+24]=color;return image
    add_region('region_skin_pick',soft_scene((150,125,115)),1)
    add_region('region_skin_found',soft_scene((150,125,115)))
    add_region('region_gray_pick',soft_scene((100,100,100)),1)
    add_region('region_gray_found',soft_scene((100,100,100),x=32,y=14))
    add_region('region_dark_pick',np.zeros((h,w,3),dtype=np.uint8),1)
    add_region('region_white_pick',np.full((h,w,3),255,dtype=np.uint8),1)
    (BASE/'region_cases.txt').write_text(''.join(f"{r['name']} {r['action']} "+' '.join(str(r[k]) for k in ['calibrated','found','overflow','x','y','w','h','cx','cy','area'])+'\n' for r in region_records))
    (BASE/'region_overflow_cases.txt').write_text('region_pick 1 1 0 0 0 0 0 0 0 0 0\nregion_components 0 1 0 1 0 0 0 0 0 0 0\n')

    # A controlled uneven-light version of an existing classic photo fixture.
    photo=np.asarray(ImageOps.fit(Image.open(ROOT/'sim/face_lbp/data/lena.jpg').convert('RGB'),(1280,720)),dtype=np.float64)
    gain=np.linspace(.18,.95,1280)[None,:,None]
    image=np.clip(photo*gain,0,255).astype(np.uint8)
    sample=rgb_means(image);gray=luma(sample);maps,hist=clahe_maps(gray);expected=clahe_apply(image,maps)
    rgbhex(BASE/'clahe_input.hex',image);rgbhex(BASE/'clahe_expected.hex',expected)
    hexfile(BASE/'clahe_small.hex',gray);hexfile(BASE/'clahe_maps.hex',maps)
    next_maps,_=clahe_maps(255-gray)
    hexfile(BASE/'clahe_next_maps.hex',next_maps)
    rgbhex(BASE/'clahe_next_probe.hex',clahe_apply(image,next_maps)[0,:32])
    Image.fromarray(image).save(OUT/'clahe_input.png')
    # Native sampler probe covers corners, column transitions, rounding and gaps.
    yy,xx=np.indices((48,64));probe=np.stack([(xx*11+yy*3)%256,(xx*2+yy*17)%256,(xx*7+yy*5)%256],-1).astype(np.uint8)
    rgbhex(BASE/'sampler_rgb.hex',probe);rgbhex(BASE/'sampler_expected.hex',rgb_means(probe))
    # Smaller native-video end-to-end fixture (64x48 blocks -> 512x384 pixels).
    native=np.asarray(ImageOps.fit(Image.open(ROOT/'sim/face_lbp/data/lena.jpg').convert('RGB'),(512,384)),dtype=np.float64)
    native=np.clip(native*np.linspace(.22,.9,512)[None,:,None],0,255).astype(np.uint8)
    nm,_=clahe_maps(luma(rgb_means(native)))
    rgbhex(BASE/'suite_clahe_input.hex',native);rgbhex(BASE/'suite_clahe_expected.hex',clahe_apply(native,nm))
    summary=dict(tracker=track_records,region=region_records,clahe=dict(tiles=15,bins=32,histograms=hist,
        pixels=int(image.shape[0]*image.shape[1]),maps=list(map(int,maps.ravel())),
        source='Existing classic lena.jpg, controlled uneven-light transform; no field accuracy claim.'),
        sampler_pixels=3072,sampler_blocks=48)
    (OUT/'reference.json').write_text(json.dumps(summary,indent=2))
    print('Prepared:',len(track_records),'tracker cases,',len(region_records),'region cases, 720p CLAHE + sampler probes')


if __name__=='__main__':prepare()
