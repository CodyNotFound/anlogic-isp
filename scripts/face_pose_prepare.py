"""Export compact human ROMs and scale/roll fixtures; ground truth is evaluation-only."""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image
import face_lbp_prepare as lbp
from face_pose_experiment import make_cases,rotate,evaluate,OLD,NEW,ANGLES

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'sim/face_pose'
OUT=ROOT/'reports/face_pose'
COEFF=[(256,0),(222,128),(222,-128),(247,66),(247,-66)]


def mapped(target,view):
    if not target['found']:return dict(found=False,box=[0,0,0],center=[0,0],votes=0,view=0)
    x,y,size=target['box'];cx=x+size//2;cy=y+size//2;c,s=COEFF[view]
    sx=max(0,min(159,(80*256+c*(cx-80)+s*(cy-45)+128)>>8))
    sy=max(0,min(89,(45*256-s*(cx-80)+c*(cy-45)+128)>>8))
    width=min(90,(size*(c+abs(s))+255)>>8)
    return dict(found=True,box=[max(0,min(160-width,sx-width//2)),max(0,min(90-width,sy-width//2)),width],
                center=[sx,sy],votes=target['votes'],view=view)


def truth(name):
    if name=='fruits':return None
    if name.startswith('close_'):
        f=float(name.split('_')[1]);return [80-14*f,45-14*f,28*f,28*f]
    if name.startswith('roll_'):
        a=math.radians(30 if name=='roll_plus30' else -30)
        corners=[(80+math.cos(a)*(x-80)+math.sin(a)*(y-45),45-math.sin(a)*(x-80)+math.cos(a)*(y-45))
                 for x in [73,101] for y in [35,63]]
        x,y=np.min(corners,axis=0);right,bottom=np.max(corners,axis=0)
        return [float(x),float(y),float(right-x),float(bottom-y)]
    return [73,35,28,28]


def main():
    BASE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    stages,weak=lbp.models();human=weak[:139];dest=ROOT/'rtl/analytics/face_lbp'
    lbp.hexfile(dest/'human_weak.hex',[(t['mask']<<48)|((t['left']&0xffffff)<<24)|(t['right']&0xffffff) for t in human],76)
    lbp.hexfile(dest/'human_stage.hex',[(s['first']<<34)|(s['last']<<24)|(s['threshold']&0xffffff) for s in stages[:20]],11)
    lbp.hexfile(dest/'human_geometry.hex',[sum(v<<(7*(3-i)) for i,v in enumerate(lbp.geometry(t['rect'],size))) for size in NEW for t in human],7)
    cases=make_cases();records=[]
    for name in ['upright','close_2.9','roll_plus30','roll_minus30','fruits']:
        image=cases[name];lbp.hexfile(BASE/f'{name}.hex',image.ravel(),2)
        old=evaluate(image,OLD,stages,weak)
        views=[]
        for index,angle in enumerate(ANGLES):
            rotated=rotate(image,angle)
            result=evaluate(rotated,NEW,stages,weak)
            views.append(dict(index=index,angle=angle,**result))
            lbp.hexfile(BASE/f'{name}_view{index}.hex',rotated.ravel(),2)
            if index==0 and result['found']:break
        candidates=[v for v in views if v['found']]
        winner=max(candidates,key=lambda v:v['votes'],default=None)
        expected=mapped(winner,winner['index']) if winner else mapped(dict(found=False),0)
        total_features=sum(v['features'] for v in views)
        fields=[int(expected['found']),*expected['box'],*expected['center'],expected['votes'],expected['view'],total_features,len(views)]
        (BASE/f'{name}.expected').write_text(' '.join(map(str,fields))+'\n')
        Image.fromarray(image).save(BASE/f'{name}.png')
        records.append(dict(name=name,ground_truth=truth(name),old=old,views=views,expected=expected,total_features=total_features))
        print(name,json.dumps(expected),flush=True)
    (OUT/'reference.json').write_text(json.dumps(dict(scales=NEW,angles=ANGLES,cases=records,
        note='Geometric transforms of an existing classic photo. Not independent real-world accuracy evidence.'),indent=2))


if __name__=='__main__':main()
