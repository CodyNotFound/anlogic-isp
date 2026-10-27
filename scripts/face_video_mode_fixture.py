"""Prepare a native RGB photo for the 720p face-mode RTL input; no annotated box input."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageOps
from face_lbp_prepare import models, detect, select_target, hexfile

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'sim/face_lbp'
OUT=ROOT/'reports/face_lbp'


def main():
    image=ImageOps.pad(Image.open(BASE/'data/lena.jpg').convert('RGB'),(1280,720),
                       method=Image.Resampling.BILINEAR,color=(96,96,96))
    rgb=np.asarray(image).astype(np.uint16)
    gray=((rgb[:,:,0]+2*rgb[:,:,1]+rgb[:,:,2])>>2).astype(np.uint16)
    small=((gray.reshape(90,8,160,8).sum((1,3))+32)>>6).astype(np.uint8)
    stages,weak=models()
    boxes,features=detect(small,0,stages,weak)
    target=select_target(boxes)
    if not target['found']:raise ValueError('Native photo not detected; report failure instead of changing model to match it')
    packed=(rgb[:,:,0].astype(np.uint32)<<16)|(rgb[:,:,1].astype(np.uint32)<<8)|rgb[:,:,2]
    hexfile(BASE/'lena_video_rgb.hex',packed.ravel(),6)
    hexfile(BASE/'lena_video_gray.hex',small.ravel(),2)
    (BASE/'lena_video.target').write_text(f"{int(target['found'])} {int(target['overflow'])} {' '.join(map(str,target['box']))} {target['votes']} {features}\n")
    image.save(OUT/'lena_video_input.png')
    (OUT/'lena_video_reference.json').write_text(json.dumps(dict(target=target,features=features,
        preprocessing='RGB720p -> (R+2G+B)>>2 -> 8x8 block sum, +32, >>6',
        source='Existing OpenCV lena.jpg; classic functional fixture, not independent accuracy evidence.'),indent=2))
    print(json.dumps(target))


if __name__=='__main__':main()
