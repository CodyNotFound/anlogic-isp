"""Independent anchor/vote reference for the serialized face selector."""
from pathlib import Path
import random
r=random.Random(401624)
cases=[[],[(10,10,24)],[(10,10,24)]*300,
       [(10,10,24)]*3+[(90,50,24)]*3,
       [(i*14,20,8) for i in range(17)]]
for _ in range(251):
    anchors=[(r.randrange(150),r.randrange(80),r.choice([24,28,32,40,48,64,72,80,88])) for _ in range(r.randrange(1,22))]
    candidates=[]
    for _ in range(r.randrange(1,120)):
        x,y,w=r.choice(anchors)
        candidates.append((max(0,min(159,x+r.randrange(-9,10))),max(0,min(89,y+r.randrange(-9,10))),w))
    cases.append(candidates)
lines=[str(len(cases))]
for candidates in cases:
    slots=[];overflow=False
    for x,y,w in candidates:
        for slot in slots:
            sx,sy,sw,v=slot
            small=min(w,sw)
            if abs(x-sx)<=small//4 and abs(y-sy)<=small//4 and abs(w-sw)<=small//2:
                slot[3]=min(255,v+1);break
        else:
            if len(slots)<16:slots.append([x,y,w,1])
            else:overflow=True
    best=max(slots,key=lambda a:a[3]) if slots else [0,0,0,0]
    found=not overflow and best[3]>=3
    x,y,w=best[:3] if found else (0,0,0)
    lines.append(f'{len(candidates)} {int(found)} {int(overflow)} {x} {y} {w} {best[3]}')
    lines.extend(f'{x} {y} {w}' for x,y,w in candidates)
root=Path(__file__).resolve().parents[1]
(root/'sim/face_lbp/selector_v40.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
print(f'Prepared {len(cases)} independent selector sequences')
