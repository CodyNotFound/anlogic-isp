"""Controlled scale/roll trials; independent frame gradients and search oracle.

These are transformed photos, not an independent tracking accuracy benchmark.
Both v38 banks and extended banks see exactly the same images and search grid.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageOps
import vision_rotation_reference as ref

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'sim/vision_tasks/scale_v40'
OUT=ROOT/'reports/vision_tasks/scale_v40'

def main():
    BASE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    old_coeff=list(ref.COEFF);new_coeff=old_coeff+[(224,0),(288,0)]
    def save(name,a):
        (BASE/f'{name}.hex').write_text(''.join(f'{int(v):02x}\n' for v in a.ravel()),encoding='ascii')
    lines=[];records=[]
    for source in ['figurine','lena','texture']:
        if source=='texture':
            rng=np.random.default_rng(411)
            from PIL.ImageFilter import GaussianBlur
            photo=Image.fromarray(rng.integers(20,236,(32,32),dtype=np.uint8)).filter(GaussianBlur(.7))
        else:
            photo=ImageOps.fit(Image.open(ROOT/f'sim/face_lbp/data/{source}.jpg').convert('L'),(32,32))
        seed=np.full((48,64),44,np.uint8);seed[8:40,16:48]=photo
        ref.COEFF=new_coeff;bank=ref.templates(seed);ref.COEFF=old_coeff
        for trial,(scale,angle) in enumerate([(s,0) for s in [.8,.875,1.,1.125,1.25]]+[(1.,a) for a in [-18,-12,-6,6,12,18]]):
            name=f'{source}_{trial:02d}';seed_name=name+'_seed'
            save(seed_name,seed)
            (BASE/f'{seed_name}_templates.hex').write_text(''.join(f'{int(v)&511:03x}\n' for v in bank.ravel()),encoding='ascii')
            lines.append(f'{seed_name} 1 1 32 24 0 0 255\n')
            # Resize the actual object, then translate; no oracle-template paste.
            n=round(32*scale);obj=photo.resize((n,n),Image.Resampling.BILINEAR).rotate(angle,resample=Image.Resampling.BILINEAR,fillcolor=44)
            image=np.full((48,64),44,np.uint8);x=34-n//2;y=23-n//2
            image[y:y+n,x:x+n]=obj;save(name,image)
            old=ref.match(image,bank[:7],center=(32,24));new=ref.match(image,bank,center=(32,24))
            lines.append(f'{name} 0 '+' '.join(str(new[k]) for k in ['found','x','y','best','second','quality'])+'\n')
            def correct(r):return bool(r['found'] and abs(r['x']-34)<=2 and abs(r['y']-23)<=2)
            records.append(dict(source=source,scale=scale,angle=angle,old=old,new=new,old_correct=correct(old),new_correct=correct(new)))
    negative_lines=[];negatives=[]
    stripe=np.where(np.indices((48,64))[1]%4<2,220,20).astype(np.uint8)
    ref.COEFF=new_coeff
    for name,s,image in [('stripe_ambiguity',stripe,stripe),('constant_occlusion',seed,np.full((48,64),100,np.uint8))]:
        bank=ref.templates(s);save(name+'_seed',s);save(name,image)
        (BASE/f'{name}_seed_templates.hex').write_text(''.join(f'{int(v)&511:03x}\n' for v in bank.ravel()),encoding='ascii')
        result=ref.match(image,bank);assert not result['found'],result
        negative_lines.append(f'{name}_seed 1 1 32 24 0 0 255\n')
        negative_lines.append(f'{name} 0 '+' '.join(str(result[k]) for k in ['found','x','y','best','second','quality'])+'\n')
        negatives.append(dict(name=name,**result))
    (BASE/'negative_cases.txt').write_text(''.join(negative_lines),encoding='ascii')
    (OUT/'negative_reference.json').write_text(json.dumps(negatives,indent=2),encoding='utf-8')
    ref.COEFF=old_coeff
    (BASE/'cases.txt').write_text(''.join(lines),encoding='ascii')
    (OUT/'reference.json').write_text(json.dumps(dict(trials=records,old_correct=sum(r['old_correct'] for r in records),new_correct=sum(r['new_correct'] for r in records),total=len(records)),indent=2),encoding='utf-8')
    print(json.dumps(dict(old_correct=sum(r['old_correct'] for r in records),new_correct=sum(r['new_correct'] for r in records),total=len(records))))

if __name__=='__main__':main()
