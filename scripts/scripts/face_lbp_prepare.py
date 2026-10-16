"""Export trained LBP stump cascades and real-image RTL fixtures. No fake faces.

Requires numpy and Pillow. Run from any directory; all outputs stay in the repo.
Geometry is scaled on the 24px feature grid, unlike OpenCV's image pyramid.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageOps, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'sim/face_lbp'
OUT = ROOT / 'reports/face_lbp'
W, H = 160, 90
SIZES = [24, 28, 32, 40, 48, 64]
STRIDE = 1
Q = 1 << 22


def models():
    stages, weak = [], []
    for name in ['frontal', 'anime']:
        c = ET.parse(BASE / f'models/{name}.xml').getroot().find('cascade')
        assert c.findtext('featureType') == 'LBP'
        assert c.findtext('width') == c.findtext('height') == '24'
        assert len(c.find('stages'))==20
        features = [list(map(int, f.findtext('rect').split())) for f in c.find('features')]
        for s in c.find('stages'):
            start = len(weak)
            for t in s.find('weakClassifiers'):
                nodes = list(map(int, t.findtext('internalNodes').split()))
                assert nodes[:2] == [0, -1] and len(nodes) == 11, 'Only depth-1 categorical trees supported'
                leaves = list(map(float, t.findtext('leafValues').split()))
                weak.append(dict(rect=features[nodes[2]], mask=sum((n & 0xffffffff) << (32*i) for i, n in enumerate(nodes[3:])),
                                 left=round(leaves[0]*Q), right=round(leaves[1]*Q),
                                 float_left=leaves[0],float_right=leaves[1]))
            # Match OpenCV's model loader: avoid rejecting boundary sums due to
            # floating-point noise (THRESHOLD_EPS = 1e-5 in cascadedetect.cpp).
            threshold=float(np.float32(float(s.findtext('stageThreshold')))-np.float32(1e-5))
            stages.append(dict(first=start, last=len(weak)-1, threshold=round(threshold*Q),float_threshold=threshold))
    assert len(weak)==910 and len(stages)==40
    assert all(-(1<<23)<=v<(1<<23) for t in weak for v in [t['left'],t['right']])
    assert all(-(1<<23)<=s['threshold']<(1<<23) for s in stages)
    assert all(sum(max(abs(t['left']),abs(t['right'])) for t in weak[s['first']:s['last']+1])<(1<<31) for s in stages)
    return stages, weak


def geometry(rect, size):
    x, y, w, h = [(v*size+12)//24 for v in rect]
    return x, y, max(1, min(w, (size-x)//3)), max(1, min(h, (size-y)//3))


def hexfile(path, values, digits):
    path.write_text(''.join(f'{int(v):0{digits}x}\n' for v in values), encoding='ascii')


def export(stages, weak):
    dest = ROOT / 'rtl/analytics/face_lbp'
    hexfile(dest/'weak.hex', [(t['mask'] << 48) | ((t['left'] & 0xffffff) << 24) | (t['right'] & 0xffffff) for t in weak], 76)
    hexfile(dest/'stage.hex', [(s['first'] << 34) | (s['last'] << 24) | (s['threshold'] & 0xffffff) for s in stages], 11)
    hexfile(dest/'geometry.hex', [sum(v << (7*(3-i)) for i, v in enumerate(geometry(t['rect'], size))) for size in SIZES for t in weak], 7)


def detect(gray, model, stages, weak, floating=False):
    # Vectorize windows, but preserve exact integer integral/feature operations.
    ii = np.pad(gray.astype(np.int64).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    boxes, feature_count = [], 0
    for size in SIZES:
        ys, xs = np.mgrid[0:H-size+1:STRIDE, 0:W-size+1:STRIDE]
        xs, ys = xs.ravel(), ys.ravel()
        for s in stages[model*20:model*20+20]:
            score = np.zeros(len(xs), dtype=np.float64 if floating else np.int64)
            for t in weak[s['first']:s['last']+1]:
                feature_count += len(xs)
                fx, fy, cw, ch = geometry(t['rect'], size)
                cells = []
                for ry in range(3):
                    for rx in range(3):
                        x, y = xs+fx+rx*cw, ys+fy+ry*ch
                        cells.append(ii[y+ch,x+cw]-ii[y,x+cw]-ii[y+ch,x]+ii[y,x])
                code = np.zeros(len(xs), dtype=np.uint16)
                for bit, cell in zip([128,64,32,16,8,4,2,1], [0,1,2,5,8,7,6,3]):
                    code |= (cells[cell] >= cells[4]).astype(np.uint16)*bit
                subset = np.array([(t['mask'] >> int(v)) & 1 for v in code], dtype=bool)
                score += np.where(subset, t['float_left'] if floating else t['left'], t['float_right'] if floating else t['right'])
            keep = score >= (s['float_threshold'] if floating else s['threshold'])
            xs, ys = xs[keep], ys[keep]
            if not len(xs):
                break
        else:
            boxes.extend([[int(x), int(y), size] for x,y in zip(xs,ys)])
    # Hardware scans scale/y/x, same order as these vectors.
    return boxes, feature_count


def groups(boxes, minimum=3):
    # Offline evaluation only. Transitive graph grouping is NOT yet RTL.
    remaining = set(range(len(boxes)))
    result = []
    while remaining:
        pending = [remaining.pop()]
        group = []
        while pending:
            i = pending.pop()
            group.append(boxes[i])
            x,y,w = boxes[i]
            neighbors = [j for j in remaining if abs(boxes[j][0]-x) <= min(w,boxes[j][2])*0.25
                         and abs(boxes[j][1]-y) <= min(w,boxes[j][2])*0.25
                         and abs(boxes[j][2]-w) <= min(w,boxes[j][2])*0.4]
            remaining.difference_update(neighbors)
            pending.extend(neighbors)
        if len(group) >= minimum:
            result.append([*[round(float(v)) for v in np.mean(group,axis=0)], len(group)])
    return sorted(result, key=lambda b: -b[3])


def letterbox(im):
    return ImageOps.pad(im.convert('L'), (W,H), method=Image.Resampling.BILINEAR, color=96)


def select_target(boxes):
    slots=[]
    overflow=False
    for x,y,w in boxes:
        for slot in slots:
            ax,ay,aw,votes=slot
            small=min(w,aw)
            if abs(x-ax)<=small//4 and abs(y-ay)<=small//4 and abs(w-aw)<=small//2:
                slot[3]=min(255,votes+1)
                break
        else:
            if len(slots)<16: slots.append([x,y,w,1])
            else: overflow=True
    best=max(slots,key=lambda s:s[3],default=[0,0,0,0])
    found=not overflow and best[3]>=3
    return dict(found=found,overflow=overflow,box=best[:3] if found else [0,0,0],votes=best[3])


def main():
    BASE.mkdir(exist_ok=True)
    OUT.mkdir(exist_ok=True)
    stages, weak = models()
    export(stages, weak)
    lena = Image.open(BASE/'data/lena.jpg')
    hopper = Image.open(BASE/'data/grace_hopper.jpg')
    # Full photo tests retain FOV; close-up and translations are explicit controls.
    cases = [('lena_full',letterbox(lena),0), ('hopper_full',letterbox(hopper),0),
             ('messi_full',letterbox(Image.open(BASE/'data/messi5.jpg')),0),
             ('fruits_negative',letterbox(Image.open(BASE/'data/fruits.jpg')),0),
             ('blank_negative',Image.new('L',(W,H),128),0),
             ('lena_dim',letterbox(lena).point(lambda v: v//2),0)]
    cases.append(('lena_rotated_30',letterbox(lena).rotate(30,fillcolor=96),0))
    occluded=letterbox(lena)
    ImageDraw.Draw(occluded).rectangle((72,34,103,47),fill=96)
    cases.append(('lena_eyes_occluded',occluded,0))
    face = lena.crop((190,170,400,390)).convert('L').resize((40,42),Image.Resampling.BILINEAR)
    for name,x,y in [('left',12,20),('right',100,32)]:
        canvas = Image.new('L',(W,H),96)
        canvas.paste(face,(x,y))
        cases.append((f'photo_{name}',canvas,0))
    for filename in ['figurine.jpg','anime.jpg']:
        if (BASE/'data'/filename).exists():
            im = Image.open(BASE/'data'/filename)
            cases.extend([(filename.split('.')[0]+'_human_model',letterbox(im),0),
                          (filename.split('.')[0]+'_anime_model',letterbox(im),1)])
    manifest=[]
    for idx,(name,im,model) in enumerate(cases):
        gray=np.asarray(im)
        boxes, count = detect(gray,model,stages,weak)
        float_boxes,_ = detect(gray,model,stages,weak,floating=True)
        assert boxes==float_boxes, f'Q22 quantization changes candidates: {name}'
        grouped=groups(boxes)
        target=select_target(boxes)
        hexfile(BASE/f'{name}.hex',gray.ravel(),2)
        # Count followed by candidate (x,y,size) triples, consumed by Verilog.
        (BASE/f'{name}.expected').write_text(str(len(boxes))+'\n'+''.join(f'{x} {y} {w}\n' for x,y,w in boxes))
        (BASE/f'{name}.target').write_text(f"{int(target['found'])} {int(target['overflow'])} {' '.join(map(str,target['box']))} {target['votes']} {count}\n")
        im=im.convert('RGB')
        draw=ImageDraw.Draw(im)
        for x,y,w in boxes:
            draw.rectangle((x,y,x+w-1,y+w-1),outline=(100,100,100),width=1)
        if target['found']:
            x,y,w=target['box']
            draw.rectangle((x,y,x+w-1,y+w-1),outline='lime',width=1)
            draw.text((x,y-10),str(target['votes']),fill='lime')
        im.resize((640,360)).save(OUT/f'{name}.png')
        item=dict(name=name,model=model,candidates=len(boxes),groups=grouped,target=target,features=count,float_quantized_equal=True)
        manifest.append(item)
        print(json.dumps(item),flush=True)
    (BASE/'cases.txt').write_text(str(len(cases))+'\n'+''.join(f'{c[0]} {c[2]}\n' for c in cases))
    (OUT/'reference.json').write_text(json.dumps(dict(width=W,height=H,sizes=SIZES,stages=len(stages),weak=len(weak),cases=manifest),indent=2))
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (BASE/'models').glob('*.xml')}
    (OUT/'model_sha256.json').write_text(json.dumps(hashes,indent=2))


if __name__=='__main__':
    main()
