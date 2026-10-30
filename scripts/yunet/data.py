"""Deterministic 16:9 manifests; HD augmentation precedes exact RTL downsampling."""
import hashlib,json,math,random
from pathlib import Path
import cv2
import numpy as np
from common import sha,write,read,stamp
from deployment import camera_canvas

def annotations(path):
    lines=Path(path).read_text(encoding='utf-8').splitlines();result={};i=0
    while i<len(lines):
        name=lines[i].strip();count=int(lines[i+1]);i+=2;boxes=[]
        if count==0 and i<len(lines) and '/' not in lines[i] and lines[i].split()[0].lstrip('-').isdigit():i+=1
        for _ in range(count):
            f=list(map(int,lines[i].split()));i+=1
            boxes.append(dict(box=f[:4],valid=len(f)<8 or f[7]==0,blur=f[4] if len(f)>4 else 0))
        result[name]=boxes
    return result

def image(path):
    value=cv2.imread(str(path))
    if value is None:raise FileNotFoundError(path)
    return value

def labels(faces,crop):
    x,y,w,h=crop;valid=[];ignored=[]
    for face in faces:
        fx,fy,fw,fh=face['box'];left=max(x,fx);top=max(y,fy);right=min(x+w,fx+fw);bottom=min(y+h,fy+fh)
        if right<=left or bottom<=top:continue
        box=[(left-x)*160/w,(top-y)*90/h,(right-left)*160/w,(bottom-top)*90/h]
        visibility=(right-left)*(bottom-top)/max(1,fw*fh)
        (valid if face['valid'] and face['blur']<2 and min(box[2:])>=7 and visibility>=.85 else ignored).append(box)
    return valid,ignored

def prepare(args):
    work=args.work;source=read(work/'sources.json');data=Path(source['data_root']);out=work/'prepared';out.mkdir(exist_ok=True)
    fingerprints={};manifests={};used_content={}
    for split,count in [('train',args.train_samples),('val',args.val_samples),('test',args.test_samples)]:
        folder='WIDER_train' if split=='train' else 'WIDER_val'
        ann_path=data/'splits/wider_face_split'/('wider_face_train_bbx_gt.txt' if split=='train' else 'wider_face_val_bbx_gt.txt')
        ann=annotations(ann_path)
        names=sorted(ann)
        if split!='train':names=[n for n in names if (int(hashlib.sha256(n.encode()).hexdigest()[:8],16)%3==0)==(split=='test')]
        rng=random.Random(args.seed+{'train':0,'val':1,'test':2}[split]);rows=[];attempt=0;shapes={}
        while len(rows)<count:
            attempt+=1
            if attempt>count*200:raise RuntimeError('Insufficient valid crops')
            name=rng.choice(names);rel=folder+'/images/'+name;path=data/rel
            if rel not in shapes:
                a=image(path);shapes[rel]=a.shape[:2];fingerprints[rel]=sha(path)
            if fingerprints[rel] in used_content and used_content[fingerprints[rel]]!=split:continue
            ih,iw=shapes[rel];negative=len(rows)%5==0
            if negative:
                w=int(min(iw,ih*16/9)*rng.uniform(.2,.7));h=round(w*9/16)
                if w<16 or h<9:continue
                x=rng.randrange(iw-w+1);y=rng.randrange(ih-h+1)
                if any(x<fx+fw and x+w>fx and y<fy+fh and y+h>fy for f in ann[name] for fx,fy,fw,fh in [f['box']]):continue
                boxes=[];ignored=[]
            else:
                faces=[f for f in ann[name] if f['valid'] and f['blur']<2 and min(f['box'][2:])>=8]
                if not faces:continue
                anchor=rng.choice(faces);fx,fy,fw,fh=anchor['box'];target=rng.choice([10,14,20,28,40,56,80])
                w=max(16,min(iw,int(ih*16/9),round(160*max(fw,fh)/target)));h=round(w*9/16)
                x=round(np.clip(fx+fw/2-w/2+rng.uniform(-.1,.1)*w,0,iw-w));y=round(np.clip(fy+fh/2-h/2+rng.uniform(-.1,.1)*h,0,ih-h))
                boxes,ignored=labels(ann[name],[x,y,w,h])
                if not boxes:continue
            used_content[fingerprints[rel]]=split
            rows.append(dict(id=f'{split}_{len(rows):06d}',image=rel,source_sha256=fingerprints[rel],group=rel,
                             crop=[x,y,w,h],boxes=boxes,ignore_boxes=ignored,negative=negative))
        manifests[split]=rows;write(out/f'{split}.json',rows)
        print('PREPARED',split,len(rows),'samples',len({r['image'] for r in rows}),'source images',flush=True)
    assert not ({r['group'] for r in manifests['val']}&{r['group'] for r in manifests['test']})
    write(out/'sources.json',fingerprints)
    calibration=out/'calibration';calibration.mkdir(exist_ok=True)
    for row in manifests['train'][:min(32,len(manifests['train']))]:
        a,_,_=render(data,row);cv2.imwrite(str(calibration/(row['id']+'.png')),a)
    for split in manifests:
        preview=out/'preview'/split;preview.mkdir(parents=True,exist_ok=True)
        for row in manifests[split][:min(4,len(manifests[split]))]:
            a,_,_=render(data,row);cv2.imwrite(str(preview/(row['id']+'.png')),a)
    report=dict(seed=args.seed,contract='HD16:9 -> rounded8x8 -> bottom6zeros BGR',train=len(manifests['train']),val=len(manifests['val']),test=len(manifests['test']),
                source_sha256=fingerprints,annotation_sha256={n:sha(data/'splits/wider_face_split'/n) for n in ['wider_face_train_bbx_gt.txt','wider_face_val_bbx_gt.txt']})
    write(out/'manifest.json',report);stamp(work,'prepare',status='passed',manifest_sha256=sha(out/'manifest.json'))

def render(data,row,rng=None):
    a=image(Path(data)/row['image']);x,y,w,h=row['crop'];a=a[y:y+h,x:x+w]
    a=cv2.resize(a,(1280,720),interpolation=cv2.INTER_AREA if min(w/1280,h/720)>1 else cv2.INTER_LINEAR)
    boxes=np.array(row['boxes'],np.float32).reshape(-1,4);ignored=np.array(row['ignore_boxes'],np.float32).reshape(-1,4)
    if rng:
        if rng.random()<.5:
            a=a[:,::-1].copy()
            for b in (boxes,ignored):b[:,0]=160-b[:,0]-b[:,2]
        if rng.random()<.35 and all(b[0]>8 and b[1]>8 and b[0]+b[2]<152 and b[1]+b[3]<82 for b in np.concatenate((boxes,ignored))):
            m=cv2.getRotationMatrix2D((640,360),rng.uniform(-20,20),1)
            def rotated(b):
                result=[]
                for x,y,w,h in b:
                    p=np.array([[x,y,1],[x+w,y,1],[x,y+h,1],[x+w,y+h,1]],np.float32);p[:,:2]*=8
                    p=p@m.T/8;lo=p.min(0);hi=p.max(0);result.append([*lo,*(hi-lo)])
                return np.asarray(result,np.float32).reshape(-1,4)
            rb,ri=rotated(boxes),rotated(ignored)
            if all(b[0]>=0 and b[1]>=0 and b[0]+b[2]<=160 and b[1]+b[3]<=90 for b in np.concatenate((rb,ri))):
                a=cv2.warpAffine(a,m,(1280,720),borderMode=cv2.BORDER_REPLICATE);boxes,ignored=rb,ri
        if rng.random()<.8:
            # Sensor-domain approximations; all happen before block averaging.
            gains=np.array([rng.uniform(.85,1.15) for _ in range(3)],np.float32)
            a=np.clip(a.astype(np.float32)*rng.uniform(.55,1.35)*gains+rng.uniform(-15,15),0,255).astype(np.uint8)
        if rng.random()<.25:a=cv2.GaussianBlur(a,(5,5),rng.uniform(.4,1.3))
    return camera_canvas(a),boxes,ignored

def dataset(work,split):
    return Path(read(Path(work)/'sources.json')['data_root']),read(Path(work)/'prepared'/f'{split}.json')

def verify_sources(work):
    data=Path(read(Path(work)/'sources.json')['data_root'])
    for rel,expected in read(Path(work)/'prepared/sources.json').items():
        if sha(data/rel)!=expected:raise ValueError('Prepared source changed: '+rel)
