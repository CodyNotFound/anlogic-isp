"""Generate a decoder/scanner fixture from the committed 55-op golden writes.
This checks model-specific head offsets and integer decoder LUT integration;
the independent full network test verifies the convolution results themselves.
"""
import hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[2]
rom=root/'rtl/analytics/face_cnn';ref=root/'sim/cnn/data/network_reference'
out=root/'build/head_offsets';out.mkdir(parents=True,exist_ok=True)
mem=[0]*65536
for i,line in enumerate((ref/'op_checks.txt').read_text().splitlines()):
 base,count=map(int,line.split());values=[int(v,16) for v in (ref/f'op_{i:02d}.hex').read_text().split()]
 assert len(values)==count
 mem[base:base+count]=values
heads={n:int(v) for n,v in re.findall(r"HEAD_(\w+)=17'd(\d+)",(rom/'yunet_heads.vh').read_text())}
def values(n):return [int(v,16) for v in (rom/n).read_text().split()]
sig=values('sigmoid.hex');off=[v if v<32768 else v-65536 for v in values('offset.hex')];size=values('size.hex')
def clamp(x,lo,hi):return max(lo,min(x,hi))
best=None;scorebest=-1
for lev,stride in enumerate((8,16,32)):
 for y in range(96//stride):
  for x in range(160//stride):
   a=y*(160//stride)+x;b=lev*256
   c=mem[heads[f'CLS_{stride}']+a];o=mem[heads[f'OBJ_{stride}']+a]
   bx,by,bw,bh=mem[heads[f'BBOX_{stride}']+4*a:heads[f'BBOX_{stride}']+4*a+4]
   score=sig[b+c]*sig[768+b+o];cx=x*stride*16+off[b+bx];cy=y*stride*16+off[b+by];w=size[b+bw];h=size[b+bh]
   left=clamp((cx-w//2)//16,0,160);right=clamp((cx+w//2+15)//16,0,160)
   top=clamp((cy-h//2)//16,0,90);bottom=clamp((cy+h//2+15)//16,0,90)
   if score>=6815 and 0<=cx<2560 and 0<=cy<1440 and right>left and bottom>top and score>scorebest:
    side=min(90,max(right-left,bottom-top))*8;xc=(left+right)*4;yc=(top+bottom)*4
    best=[clamp(xc-side//2,0,1280-side),clamp(yc-side//2,0,720-side),side,xc,yc];scorebest=score
expected=[int(best is not None),max(0,scorebest),*(best or [0]*5)]
(out/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in mem))
(out/'expected.txt').write_text(' '.join(map(str,expected))+'\n')
report=dict(expected=expected,heads=heads,hashes={n:hashlib.sha256((rom/n).read_bytes()).hexdigest() for n in ['program.hex','yunet_heads.vh','sigmoid.hex','offset.hex','size.hex']})
(out/'fixture.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
