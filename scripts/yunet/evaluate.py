"""Single-target metrics using deployed LUTs, threshold, clipping and square conversion."""
import math,pickle
from pathlib import Path
import numpy as np
import torch
from common import ROOT,read,write,sha,stamp
from data import dataset,render

def iou(a,b):
    area=max(0,min(a[0]+a[2],b[0]+b[2])-max(a[0],b[0]))*max(0,min(a[1]+a[3],b[1]+b[3])-max(a[1],b[1]))
    return float(area/max(1e-9,a[2]*a[3]+b[2]*b[3]-area))

class Decoder:
    def __init__(self,rom=ROOT/'rtl/analytics/face_cnn'):
        self.sigmoid=np.array([int(v,16) for v in (rom/'sigmoid.hex').read_text().split()])
        a=np.array([int(v,16) for v in (rom/'offset.hex').read_text().split()]);self.offset=np.where(a>=32768,a-65536,a)
        self.size=np.array([int(v,16) for v in (rom/'size.hex').read_text().split()])
        if (len(self.sigmoid),len(self.offset),len(self.size))!=(1536,768,768):raise ValueError('Decoder LUT capacity mismatch')

    def __call__(self,heads,integer):
        best=None;best_score=-1
        for level,stride in enumerate((8,16,32)):
            cls,obj,box=heads['cls'][level],heads['obj'][level],heads['box'][level]
            for y in range(cls.shape[0]):
                for x in range(cls.shape[1]):
                    if integer:
                        c=int(cls[y,x,0])&255;o=int(obj[y,x,0])&255;b=[int(v)&255 for v in box[y,x]]
                        score=int(self.sigmoid[level*256+c])*int(self.sigmoid[768+level*256+o])
                        cx=x*stride*16+int(self.offset[level*256+b[0]]);cy=y*stride*16+int(self.offset[level*256+b[1]])
                        w=int(self.size[level*256+b[2]]);h=int(self.size[level*256+b[3]])
                        half_w=w//2;half_h=h//2
                    else:
                        c=float(np.clip(cls[y,x,0],-80,80));o=float(np.clip(obj[y,x,0],-80,80))
                        score=127**2/((1+math.exp(-c))*(1+math.exp(-o)))
                        b=box[y,x];cx=(x+float(b[0]))*stride*16;cy=(y+float(b[1]))*stride*16
                        w=min(65535,max(0,round(math.exp(float(np.clip(b[2],-12,12)))*stride*16)))
                        h=min(65535,max(0,round(math.exp(float(np.clip(b[3],-12,12)))*stride*16)))
                        half_w=w//2;half_h=h//2
                    if score<6815 or score<=best_score or not(0<=cx<2560 and 0<=cy<1440):continue
                    left=max(0,min(160,math.floor((cx-half_w)/16)))
                    right=max(0,min(160,math.floor((cx+half_w+15)/16)))
                    top=max(0,min(90,math.floor((cy-half_h)/16)))
                    bottom=max(0,min(90,math.floor((cy+half_h+15)/16)))
                    if right<=left or bottom<=top:continue
                    side=min(90,max(right-left,bottom-top))*8
                    center=[(left+right)*4,(top+bottom)*4]
                    square=[max(0,min(1280-side,center[0]-side//2)),max(0,min(720-side,center[1]-side//2)),side,side]
                    best=dict(rect=[left,top,right-left,bottom-top],center=center,square=square,score=float(score),anchor=[level,x,y])
                    best_score=score
        return best

class FloatRunner:
    def __init__(self,model,device='cpu'):
        self.model=model;self.device=device
    @torch.no_grad()
    def __call__(self,a):
        self.model.eval()
        raw=self.model(torch.from_numpy(a.transpose(2,0,1)[None].astype(np.float32)).to(self.device))
        return {k:[v.detach().cpu().numpy()[0].transpose(1,2,0) for v in raw[k]] for k in ('cls','obj','box')}

class IntegerRunner:
    def __init__(self,qdir):
        from quantize import infer
        # Local pipeline output only; downloaded input is always SHA-checked ONNX.
        with (Path(qdir)/'ops_for_infer.pkl').open('rb') as f:self.blob=pickle.load(f)
        self.infer=infer
    def __call__(self,a):
        values,_,_=self.infer(a,self.blob['ops'])
        return {kind:[values[self.blob['heads'][f'{name}_{s}']] for s in (8,16,32)] for kind,name in [('cls','cls'),('obj','obj'),('box','bbox')]}

def metrics(work,split,runner,integer,decoder=None):
    decoder=decoder or Decoder();data,rows=dataset(work,split)
    result=dict(images=len(rows),positive_images=0,negative_images=0,accepted=0,hits=0,negative_accepted=0,
                center_error_camera_pixels=[],square_iou=[],groups={});predictions=[]
    for row in rows:
        a,boxes,_=render(data,row);prediction=decoder(runner(a),integer)
        negative=row['negative'];result['negative_images' if negative else 'positive_images']+=1
        result['accepted']+=prediction is not None
        hit=False
        if negative:result['negative_accepted']+=prediction is not None
        elif prediction and len(boxes):
            value,index=max((iou(prediction['rect'],b),i) for i,b in enumerate(boxes));hit=value>=.5
            if hit:
                x,y,w,h=boxes[index];cx,cy=(x+w/2)*8,(y+h/2)*8
                result['center_error_camera_pixels'].append(float(math.hypot(prediction['center'][0]-cx,prediction['center'][1]-cy)))
                result['square_iou'].append(float(iou(prediction['square'],[x*8,y*8,w*8,h*8])))
        result['hits']+=hit
        size=max((max(b[2:]) for b in boxes),default=0)
        group='background' if negative else 'small' if size<20 else 'near' if size>=48 else 'medium'
        g=result['groups'].setdefault(group,dict(images=0,hits=0,accepted=0));g['images']+=1;g['hits']+=hit;g['accepted']+=prediction is not None
        predictions.append(dict(id=row['id'],group=group,hit=hit,negative=negative,prediction=prediction))
    result['single_target_hit_rate']=result['hits']/max(1,result['positive_images'])
    result['precision']=result['hits']/max(1,result['accepted'])
    result['negative_acceptance_rate']=result['negative_accepted']/max(1,result['negative_images'])
    errors=result.pop('center_error_camera_pixels');result['mean_center_error_camera_pixels']=float(np.mean(errors)) if errors else None
    result['mean_square_iou']=float(np.mean(result.pop('square_iou'))) if errors else None
    result.update(integer=integer,iou_threshold=.5,selection='single highest score, no NMS',score_product_threshold=6815,
                  scope='WIDER crops processed by camera contract; no physical-board accuracy claim')
    return result,predictions

def acceptable(base,new):
    return (new['precision']>=base['precision']-.015 and
            new['single_target_hit_rate']>=base['single_target_hit_rate']-.02 and
            new['negative_acceptance_rate']<=base['negative_acceptance_rate']+.025)

def compare(args):
    work=args.work;out=work/'evaluation';out.mkdir(exist_ok=True)
    report={}
    for split in ('val','test'):
        report[split]={}
        for tag in ('baseline','candidate'):
            m,p=metrics(work,split,IntegerRunner(work/'quantized'/tag),True)
            report[split][tag]=m;write(out/f'{split}_{tag}_predictions.json',p)
    report['non_regression_passed']=all(acceptable(report[s]['baseline'],report[s]['candidate']) for s in ('val','test'))
    report['test_used_for_checkpoint_selection']=False
    report['training_weights_changed']=read(work/'training/result.json')['changed_tensors']>0
    report['accuracy_accepted']=report['non_regression_passed'] and report['training_weights_changed']
    write(out/'report.json',report);stamp(work,'evaluate',status='completed',accuracy_accepted=report['accuracy_accepted'])
    print('INTEGER EVALUATION',report['accuracy_accepted'],flush=True)
    return report
