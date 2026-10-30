"""Pinned, checked downloads with HTTP Range resume and safe ZIP extraction."""
import json,os,shutil,stat,time,urllib.request,zipfile
from pathlib import Path,PurePosixPath
from common import sha,write,MODEL_SHA,ROOT,stamp

REV='833d07e7bf3860f294242312fe95eed0561eeb17'
DATA={
 'WIDER_train.zip':('e23b76129c825cafae8be944f65310b2e1ba1c76885afe732f179c41e5ed6d59',1465602149),
 'WIDER_val.zip':('f9efbd09f28c5d2d884be8c0eaef3967158c866a593fc36ab0413e4b2a58a17a',362752168),
 'wider_face_split.zip':('c7561e4f5e7a118c249e0a5c5c902b0de90bbf120d7da9fa28d99041f68a8a5c',3591642)}
MODEL_URL='https://huggingface.co/opencv/opencv_zoo/resolve/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx'

def fetch(url,path,expected,size=None):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists():
        if sha(path)!=expected:raise ValueError(f'Checksum mismatch in existing {path.name}; preserve it and choose a clean download cache')
        print('VERIFIED CACHE',path.name,flush=True);return
    partial=path.with_name(path.name+'.part')
    for attempt in range(4):
        offset=partial.stat().st_size if partial.exists() else 0
        if size and offset==size:break
        req=urllib.request.Request(url,headers={'User-Agent':'anlogic-isp-training','Range':f'bytes={offset}-'} if offset else {'User-Agent':'anlogic-isp-training'})
        try:
            with urllib.request.urlopen(req,timeout=90) as response:
                append=offset>0 and response.status==206
                if append and not response.headers.get('Content-Range','').startswith(f'bytes {offset}-'):raise ValueError('Invalid HTTP resume range')
                with partial.open('ab' if append else 'wb') as output:
                    copied=offset if append else 0;last=time.monotonic()
                    while True:
                        block=response.read(1048576)
                        if not block:break
                        output.write(block);copied+=len(block)
                        if time.monotonic()-last>10:print('DOWNLOAD',path.name,copied,'bytes',flush=True);last=time.monotonic()
            break
        except (OSError,TimeoutError):
            if attempt==3:raise
            time.sleep(min(2**attempt,4))
    if size and partial.stat().st_size!=size:raise ValueError('Incomplete download: '+path.name)
    if sha(partial)!=expected:raise ValueError('Downloaded checksum mismatch: '+path.name)
    os.replace(partial,path)

def extract(archive,dest):
    dest=Path(dest);dest.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            name=PurePosixPath(info.filename.replace('\\','/'))
            if name.is_absolute() or '..' in name.parts or ':' in str(name) or stat.S_ISLNK(info.external_attr>>16):raise ValueError('Unsafe archive entry')
            output=dest.joinpath(*name.parts)
            if not output.resolve().is_relative_to(dest.resolve()):raise ValueError('Archive escaped extraction root')
            if info.is_dir():output.mkdir(parents=True,exist_ok=True);continue
            output.parent.mkdir(parents=True,exist_ok=True)
            with z.open(info) as src,output.open('wb') as dst:shutil.copyfileobj(src,dst,1048576)

def ensure_extracted(archive,dest,check,marker,expected,trust_existing=False):
    marker=Path(marker);started=marker.with_suffix('.started')
    completed=False
    if marker.exists():
        try:completed=json.loads(marker.read_text()).get('sha256')==expected
        except (ValueError,OSError):pass
    if check.exists() and not started.exists() and (completed or trust_existing):return
    marker.parent.mkdir(parents=True,exist_ok=True)
    started.write_text(expected,encoding='ascii')
    extract(archive,dest)
    if not check.exists():raise ValueError('Archive did not contain the expected dataset structure')
    write(marker,dict(status='completed',sha256=expected))
    started.unlink()

def run(args):
    work=args.work;cache=args.downloads or work/'downloads';data=args.data_root or work/'data'
    upstream=work/'upstream';upstream.mkdir(parents=True,exist_ok=True)
    model=upstream/'yunet.onnx'
    if args.model:
        if sha(args.model)!=MODEL_SHA:raise ValueError('Expected the pinned official warm-start model')
        shutil.copyfile(args.model,model)
    else:fetch(MODEL_URL,model,MODEL_SHA)
    sources={}
    for name,(expected,size) in DATA.items():
        url=f'https://huggingface.co/datasets/CUHK-CSE/wider_face/resolve/{REV}/data/{name}'
        archive=cache/name;fetch(url,archive,expected,size);sources[name]=dict(url=url,sha256=expected,bytes=size)
        check=data/('splits/wider_face_split/wider_face_train_bbx_gt.txt' if name=='wider_face_split.zip' else name[:-4]+'/images')
        ensure_extracted(archive,data/'splits' if name=='wider_face_split.zip' else data,check,
                         work/'extraction'/(name+'.json'),expected,trust_existing=args.data_root is not None)
    annotations=data/'splits/wider_face_split'
    if not (annotations/'wider_face_val_bbx_gt.txt').is_file():raise FileNotFoundError('Missing validation annotations')
    write(work/'sources.json',dict(dataset=sources,model=dict(url=MODEL_URL,sha256=MODEL_SHA),dataset_card='https://huggingface.co/datasets/CUHK-CSE/wider_face',data_root=str(data.resolve()),cache_root=str(cache.resolve())))
    shutil.copyfile(ROOT/'assets/models/yunet/LICENSE',upstream/'LICENSE')
    stamp(work,'download',status='passed',model_sha256=sha(model))
    return data
