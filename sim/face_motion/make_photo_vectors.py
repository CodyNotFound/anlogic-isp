"""Offline photo-transform probes and exact gradient-matcher goldens.
OpenCV is used ONLY to place the initial test ROI, never online on FPGA.
Three source photos/derived transforms are regression evidence, not an accuracy
benchmark. Supply existing 160x96 calibration PNGs; generated files stay in build/.
"""
import argparse,json,hashlib
from pathlib import Path
import cv2,numpy as np
ROOT=Path(__file__).resolve().parents[2]

def gray(a):
 return ((a[:,:,2].astype(np.int16)+2*a[:,:,1].astype(np.int16)+a[:,:,0].astype(np.int16))>>2)
def origin(x,y):return max(12,min(148,x))-12,max(12,min(78,y))-12

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--fixtures',type=Path,required=True)
 ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();a.out.mkdir(parents=True,exist_ok=True)
 detector=cv2.FaceDetectorYN.create(str(ROOT/'models/yunet/face_detection_yunet_2023mar.onnx'),'',(160,96),.55,.3,5000)
 frames=[];meta=[];report=[]
 variants=[(0,1,1),(0,1,.7),(0,1,1.25),(5,1,1),(-5,1,1),(0,1.05,1),(0,.95,1)]
 for name in ('lena','lena_close','grace_hopper'):
  path=a.fixtures/(name+'.png');bgr=cv2.imread(str(path))
  if bgr is None or bgr.shape!=(96,160,3):raise ValueError('Expected 160x96 calibration PNG: '+str(path))
  _,faces=detector.detect(bgr)
  if faces is None:raise ValueError('No seed face in '+name)
  face=max(faces,key=lambda f:f[-1]);x,y=np.rint(face[:2]+face[2:4]/2).astype(int)
  x,y=max(12,min(148,int(x))),max(12,min(78,int(y)))
  adaptive=int(max(face[2:4])*8>=256);ox,oy=origin(x,y);src=gray(bgr)[:90];roi=src[oy:oy+24,ox:ox+24]
  bx=by=8;energy=0
  if adaptive:
   for cy in (0,8,16):
    for cx in (0,8,16):
     e=int(np.abs(np.diff(roi[cy:cy+8,cx:cx+8],axis=1)).sum())
     if e>energy:energy=e;bx=cx;by=cy
  tpl=roi[by:by+8,bx:bx+8];tg=np.diff(tpl,axis=1);texture=int(np.abs(tg).sum())
  px,py=ox+bx+4,oy+by+4;seed_px,seed_py=px,py
  probes=[]
  for angle,scale,gain in variants:
   px,py=seed_px,seed_py
   rows=[(px,py,int(not adaptive or texture>=400),0)];frames.append(src)
   m=cv2.getRotationMatrix2D((x,y),angle,scale);m[:,2]+=[3,2]
   rgb=cv2.warpAffine(bgr,m,(160,96));rgb=np.clip(np.rint(rgb*gain),0,255).astype(np.uint8)
   g=gray(rgb)[:90];ox,oy=origin(px,py);roi=g[oy:oy+24,ox:ox+24]
   scores=[]
   for cy in range(17):
    for cx in range(17):scores.append(int(np.abs(np.diff(roi[cy:cy+8,cx:cx+8],axis=1)-tg).sum()))
   k=int(np.argmin(scores));best=scores[k];second=sorted(scores)[1]
   found=texture>=400 and best<=1800 and second>=best+max(64,best>>3)
   target=np.array([seed_px,seed_py,1.0])@m.T
   actual=np.array([ox+k%17+4,oy+k//17+4])
   error=float(np.linalg.norm(actual-target))
   probes.append(dict(roll=angle,scale=scale,gain=gain,found=bool(found),error_samples=error,best=best,second=second))
   if found and error>2:raise AssertionError('Accepted inaccurate match: '+name+' '+str(probes[-1]))
   if found:px,py=map(int,actual)
   rows.append((px,py,int(found),best));frames.append(g);meta.append((x,y,adaptive,rows))
  report.append(dict(photo=name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),adaptive=bool(adaptive),texture=texture,probes=probes))
 np.savetxt(a.out/'frames.hex',np.stack(frames).astype(np.uint8).reshape(-1),fmt='%02x')
 with (a.out/'expected.txt').open('w',encoding='ascii') as f:
  f.write(str(len(meta))+'\n')
  for x,y,adaptive,rows in meta:
   f.write(f'{x} {y} {adaptive} {len(rows)}\n')
   for row in rows:f.write(' '.join(map(str,row))+'\n')
 (a.out/'photo_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print('PHOTO PROBES',len(report),'photos,',sum(len(r['probes']) for r in report),'transforms,',sum(p['found'] for r in report for p in r['probes']),'accepted; rejected probes are recorded, not hidden')

if __name__=='__main__':main()
