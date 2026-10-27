"""Independent image-space rotation experiment and integer bank reference."""
from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageOps,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'sim/vision_tasks/rotation'
OUT=ROOT/'reports/vision_tasks/rotation'
COEFF=[(256,0),(255,27),(255,-27),(250,53),(250,-53),(243,79),(243,-79)]

def templates(frame):
    y,x=np.mgrid[-8:8,-8:9]
    banks=[]
    for c,s in COEFF:
        # Floor coordinates and 4-bit fractions, including negative offsets.
        qx=c*x+s*y;qy=c*y-s*x
        ix=qx//256+frame.shape[1]//2;iy=qy//256+frame.shape[0]//2
        fx=(qx%256)//16;fy=(qy%256)//16
        a=frame.astype(np.int64)
        sampled=((a[iy,ix]*(16-fx)+a[iy,ix+1]*fx)*(16-fy)
                 +(a[iy+1,ix]*(16-fx)+a[iy+1,ix+1]*fx)*fy+128)//256
        banks.append(np.diff(sampled,axis=1))
    return np.array(banks)

def match(frame,bank,radius=4,center=(32,24)):
    a=frame.astype(np.int64);candidates=[]
    for y in range(max(0,center[1]-8-radius),min(a.shape[0]-16,center[1]-8+radius)+1):
        for x in range(max(0,center[0]-8-radius),min(a.shape[1]-17,center[0]-8+radius)+1):
            grad=np.diff(a[y:y+16,x:x+17],axis=1)
            scores=np.abs(bank-grad).sum((1,2));k=int(scores.argmin())
            candidates.append((int(scores[k]),x,y,k))
    best,x,y,k=min(candidates,key=lambda v:v[0])
    second=min(v[0] for v in candidates if abs(v[1]-x)>2 or abs(v[2]-y)>2)
    found=best<=6144 and second>=best+256
    return dict(found=int(found),x=x+8 if found else center[0],y=y+8 if found else center[1],
                best=best,second=second,quality=min(255,(second-best)>>4) if found else 0,bank=k)

def main():
    BASE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    def save(name,a):
        (BASE/f'{name}.hex').write_text(''.join(f'{int(v):02x}\n' for v in a.ravel()))
        Image.fromarray(a).resize((384,288),Image.Resampling.NEAREST).save(OUT/f'{name}.png')
    records=[];lines=[];examples=[]
    for source in ['figurine','lena','fruits','texture']:
        if source=='texture':
            rng=np.random.default_rng(411)
            photo=Image.fromarray(rng.integers(20,236,(32,32),dtype=np.uint8)).filter(__import__('PIL.ImageFilter',fromlist=['GaussianBlur']).GaussianBlur(.7))
        else:photo=ImageOps.fit(Image.open(ROOT/f'sim/face_lbp/data/{source}.jpg').convert('L'),(32,32))
        seed=np.full((48,64),44,np.uint8);seed[8:40,16:48]=photo
        bank=templates(seed);energy=int(np.abs(bank[0]).sum())
        (BASE/f'{source}_seed_templates.hex').write_text(''.join(f'{int(v)&511:03x}\n' for v in bank.ravel()))
        save(f'{source}_seed',seed)
        for angle in [-18,-12,-6,-3,0,3,6,12,18]:
            name=f'{source}_{angle:+d}'.replace('+','p').replace('-','m')
            image=np.full((48,64),44,np.uint8)
            # Independent continuous-angle Pillow resampling, not bank lookup.
            turned=photo.rotate(angle,resample=Image.Resampling.BILINEAR,center=(16,16),fillcolor=44)
            image[6:38,19:51]=turned
            save(name,image)
            new=match(image,bank);old=match(image,bank[:1])
            assert new['found'] and abs(new['x']-35)<=1 and abs(new['y']-22)<=1,(name,new)
            seed_q=255 if energy>=1024 else 0
            lines.append(f'{source}_seed 1 {int(energy>=1024)} 32 24 0 0 {seed_q}\n')
            lines.append(f'{name} 0 '+ ' '.join(str(new[k]) for k in ['found','x','y','best','second','quality'])+'\n')
            records.append(dict(name=name,source=source,angle=angle,expected_center=[35,22],new=new,baseline=old,seed_energy=energy))
            if angle in [-12,0,12]:examples.append((name,image,new,old))
    # Negative controls retain the original rejection thresholds.
    seed=np.array(Image.open(OUT/'texture_seed.png').resize((64,48),Image.Resampling.NEAREST))
    bank=templates(seed)
    for name,image in [('occluded',np.full((48,64),44,np.uint8)),('unrelated',np.random.default_rng(901).integers(0,256,(48,64),dtype=np.uint8))]:
        save(name,image);new=match(image,bank)
        lines.append('texture_seed 1 1 32 24 0 0 255\n')
        lines.append(f'{name} 0 '+' '.join(str(new[k]) for k in ['found','x','y','best','second','quality'])+'\n')
        assert not new['found'],(name,new)
        records.append(dict(name=name,source='negative',new=new))
    (BASE/'cases.txt').write_text(''.join(lines))
    (OUT/'reference.json').write_text(json.dumps(records,indent=2))
    photo=ImageOps.fit(Image.open(ROOT/'sim/face_lbp/data/figurine.jpg').convert('L'),(32,32))
    seed=np.full((48,64),44,np.uint8);seed[8:40,16:48]=photo;save('sequence_seed',seed)
    bank=templates(seed)
    (BASE/'sequence_seed_templates.hex').write_text(''.join(f'{int(v)&511:03x}\n' for v in bank.ravel()))
    sequence=[];seq_lines=['sequence_seed 1 1 32 24 0 0 255\n'];center=(32,24)
    for i,angle in enumerate(range(-18,19,3)):
        name=f'sequence_{i:02d}';dy=i%3-1
        image=np.full((48,64),44,np.uint8)
        image[8+dy:40+dy,16+i:48+i]=photo.rotate(angle,resample=Image.Resampling.BILINEAR,center=(16,16),fillcolor=44)
        result=match(image,bank,center=center)
        assert result['found'] and abs(result['x']-32-i)<=1 and abs(result['y']-24-dy)<=1,(name,result)
        center=result['x'],result['y'];save(name,image)
        seq_lines.append(f'{name} 0 '+' '.join(str(result[k]) for k in ['found','x','y','best','second','quality'])+'\n')
        sequence.append(dict(name=name,angle=angle,expected_center=[32+i,24+dy],new=result))
    (BASE/'sequence_cases.txt').write_text(''.join(seq_lines))
    (OUT/'sequence_reference.json').write_text(json.dumps(sequence,indent=2))
    seed=np.full((90,160),44,np.uint8);seed[29:61,64:96]=photo;save('production_seed',seed)
    bank=templates(seed);energy=int(np.abs(bank[0]).sum())
    (BASE/'production_seed_templates.hex').write_text(''.join(f'{int(v)&511:03x}\n' for v in bank.ravel()))
    image=np.full((90,160),44,np.uint8)
    image[26:58,69:101]=photo.rotate(12,resample=Image.Resampling.BILINEAR,center=(16,16),fillcolor=44)
    save('production_move',image);result=match(image,bank,radius=8,center=(80,45))
    assert result['found'] and (result['x'],result['y'])==(85,42),result
    (BASE/'production_cases.txt').write_text(f'production_seed 1 1 80 45 0 0 255\nproduction_move 0 '+' '.join(str(result[k]) for k in ['found','x','y','best','second','quality'])+'\n')
    (OUT/'production_reference.json').write_text(json.dumps(result,indent=2))
    y,x=np.mgrid[:48,:64];striped=np.where(x%4<2,220,20).astype(np.uint8)
    bank=templates(striped);save('ambiguity_seed',striped);save('ambiguity_image',striped)
    (BASE/'ambiguity_seed_templates.hex').write_text(''.join(f'{int(v)&511:03x}\n' for v in bank.ravel()))
    result=match(striped,bank);assert not result['found'] and result['best']==result['second']==0,result
    (BASE/'ambiguity_cases.txt').write_text('ambiguity_seed 1 1 32 24 0 0 255\nambiguity_image 0 '+' '.join(str(result[k]) for k in ['found','x','y','best','second','quality'])+'\n')
    (OUT/'ambiguity_reference.json').write_text(json.dumps(result,indent=2))
    for source in ['figurine','lena','fruits','texture']:
        rows=[r for r in records if r['source']==source]
        print(source,'old',sum(r['baseline']['found'] for r in rows),'new',sum(r['new']['found'] for r in rows),'/',len(rows),'energy',rows[0]['seed_energy'])
    sheet=Image.new('RGB',(1152,4*320),'#15202b');d=ImageDraw.Draw(sheet)
    for i,(name,a,new,old) in enumerate(examples):
        x=i%3*384;y=i//3*320;im=Image.fromarray(a).convert('RGB').resize((384,288),Image.Resampling.NEAREST)
        if new['found']:ImageDraw.Draw(im).rectangle(((new['x']-8)*6,(new['y']-8)*6,(new['x']+8)*6,(new['y']+8)*6),outline='lime',width=2)
        sheet.paste(im,(x,y));d.text((x+4,y+291),f'{name}: old={old["found"]}, new={new["found"]}',fill='white')
    sheet.save(OUT/'reference_comparison.png')

if __name__=='__main__':main()
