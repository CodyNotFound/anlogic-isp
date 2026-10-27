"""Check scale expansion and fixed-point image-rotation retries on local photo fixtures."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
import face_lbp_prepare as lbp

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/face_pose'
BASE=ROOT/'sim/face_lbp'
OLD=[24,28,32,40,48,64]
NEW=OLD+[72,80,88]
ANGLES=[0,30,-30,15,-15]


def rotate(gray,angle):
    # Inverse mapping, nearest neighbor; exactly reproducible with shift/add RTL.
    cos,sin={0:(256,0),30:(222,128),-30:(222,-128),15:(247,66),-15:(247,-66)}[angle]
    y,x=np.mgrid[:90,:160]
    sx=(80*256+cos*(x-80)+sin*(y-45)+128)>>8
    sy=(45*256-sin*(x-80)+cos*(y-45)+128)>>8
    valid=(sx>=0)&(sx<160)&(sy>=0)&(sy<90)
    result=np.full((90,160),96,np.uint8)
    result[valid]=gray[sy[valid],sx[valid]]
    return result


def evaluate(gray,sizes,stages,weak):
    lbp.SIZES=sizes
    boxes,count=lbp.detect(gray,0,stages,weak)
    return dict(**lbp.select_target(boxes),features=count,candidates=len(boxes))


def make_cases():
    image=np.array([int(s,16) for s in (BASE/'lena_full.hex').read_text().split()],np.uint8).reshape(90,160)
    yy,xx=np.mgrid[:90,:160]
    cases={'upright':image,
           'roll_plus30':np.asarray(Image.fromarray(image).rotate(30,resample=Image.Resampling.BILINEAR,fillcolor=96)),
           'roll_minus30':np.asarray(Image.fromarray(image).rotate(-30,resample=Image.Resampling.BILINEAR,fillcolor=96)),
           'roll_plus15':np.asarray(Image.fromarray(image).rotate(15,resample=Image.Resampling.BILINEAR,fillcolor=96)),
           'roll_minus15':np.asarray(Image.fromarray(image).rotate(-15,resample=Image.Resampling.BILINEAR,fillcolor=96)),
           'fruits':np.array([int(s,16) for s in (BASE/'fruits_negative.hex').read_text().split()],np.uint8).reshape(90,160)}
    for factor in [2.9,3.,3.1]:
        sx=np.clip(np.rint((xx-80)/factor+87).astype(int),0,159)
        sy=np.clip(np.rint((yy-45)/factor+49).astype(int),0,89)
        cases[f'close_{factor}']=image[sy,sx]
    return cases


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    stages,weak=lbp.models()
    cases=make_cases()
    results=[]
    for name,gray in cases.items():
        old=evaluate(gray,OLD,stages,weak)
        retries=[]
        for angle in ANGLES:
            result=evaluate(rotate(gray,angle),NEW,stages,weak)
            retries.append(dict(angle=angle,**result))
        record=dict(name=name,old=old,retries=retries)
        results.append(record)
        Image.fromarray(gray).resize((640,360)).save(OUT/f'{name}.png')
        print(json.dumps(record),flush=True)
    (OUT/'experiment.json').write_text(json.dumps(results,indent=2))


if __name__=='__main__':main()
