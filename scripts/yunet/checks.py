"""Check actual source provenance and PyTorch/ONNX interface before optimizing weights."""
import hashlib,zipfile
from pathlib import Path
import numpy as np
import torch
from common import read,write,sha,MODEL_SHA
from data import dataset,render

def validate_origins(work):
    work=Path(work);sources=read(work/'sources.json');data=Path(sources['data_root']);cache=Path(sources['cache_root'])
    fingerprints=read(work/'prepared/sources.json')
    with zipfile.ZipFile(cache/'WIDER_train.zip') as train,zipfile.ZipFile(cache/'WIDER_val.zip') as val,zipfile.ZipFile(cache/'wider_face_split.zip') as labels:
        for rel,expected in fingerprints.items():
            archive=train if rel.startswith('WIDER_train/') else val
            h=hashlib.sha256()
            with archive.open(rel) as f:
                for block in iter(lambda:f.read(1048576),b''):h.update(block)
            if h.hexdigest()!=expected or sha(data/rel)!=expected:raise ValueError('Extracted image is not the verified dataset entry: '+rel)
        for name in ('wider_face_train_bbx_gt.txt','wider_face_val_bbx_gt.txt'):
            expected=hashlib.sha256(labels.read('wider_face_split/'+name)).hexdigest()
            if sha(data/'splits/wider_face_split'/name)!=expected:raise ValueError('Annotations differ from verified archive')
    write(work/'prepared/origin_check.json',dict(status='passed',source_images=len(fingerprints),annotations=2))

def before_training(work):
    from yunet_torch import YuNetN
    from quantize import load_graph,session
    work=Path(work);model=work/'upstream/yunet.onnx'
    if sha(model)!=MODEL_SHA:raise ValueError('Warm-start model identity changed')
    validate_origins(work)
    data,rows=dataset(work,'train');canvas,_,_=render(data,rows[0]);x=canvas.transpose(2,0,1)[None].astype(np.float32)
    graph,_=load_graph(model);run=session(graph);net=YuNetN().load_onnx(model).eval()
    with torch.no_grad():actual=net(torch.from_numpy(x))
    errors={}
    for output,expected in zip(run.get_outputs(),run.run(None,{'input':x})):
        kind,stride=output.name.rsplit('_',1);level=(8,16,32).index(int(stride))
        value=actual['box' if kind=='bbox' else kind][level]
        if kind in ('cls','obj'):value=value.sigmoid()
        value=value.permute(0,2,3,1).numpy().reshape(expected.shape)
        errors[output.name]=float(np.max(np.abs(value-expected)))
        if not np.allclose(value,expected,rtol=1e-4,atol=1e-4):raise ValueError('PyTorch does not match ONNX: '+output.name)
    write(work/'prepared/model_check.json',dict(status='passed',input=[1,3,96,160],head_max_abs_error=errors))
