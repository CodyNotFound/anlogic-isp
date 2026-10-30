"""Shared reproducibility and atomic artifact helpers."""
import hashlib,json,os,sys,platform
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CONTRACT=ROOT/'assets/models/yunet/quantization.json'
MODEL_SHA='8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4'

def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()

def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def write(path,data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.tmp')
    temp.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    os.replace(temp,path)

def source_hash():
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(Path(__file__).parent.glob('*.py'))}

def environment():
    import torch,numpy,cv2,onnx,onnxruntime
    return dict(python=sys.version,platform=platform.platform(),torch=torch.__version__,numpy=numpy.__version__,
                opencv=cv2.__version__,onnx=onnx.__version__,onnxruntime=onnxruntime.__version__)

def stamp(work,section,**extra):
    state=Path(work)/'state.json';data=read(state) if state.exists() else {}
    data[section]=extra;write(state,data)
