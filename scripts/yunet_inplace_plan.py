"""Lifetime-checked cache reuse plan; hardware implementation is a separate gate.

An alias is legal only after the source's last consumer. Pointwise expansion
requires reverse traversal and a full-pixel cache; spatial convolution requires
three original source rows. This planner never claims baseline RTL implements it.
"""
from pathlib import Path
import json,math

ROOT=Path(__file__).resolve().parents[1]
def main():
    net=json.loads((ROOT/'reports/yunet_v45/network.json').read_text());ops=net['operations']
    last={};shapes={'input':[96,160,4]}
    for i,o in enumerate(ops):
        for x in [o['src']] if isinstance(o['src'],str) else o['src']:last[x]=i
        shapes[o['dst']]=o['shape']
    for h in net['heads'].values():last[h]=len(ops)
    free=[(0,65536)];live={};steps=[];peak=0;row_cache=0;pixel_cache=0
    def coalesce():
        free.sort();out=[]
        for b,n in free:
            if out and sum(out[-1])==b:out[-1]=(out[-1][0],out[-1][1]+n)
            else:out.append((b,n))
        free[:]=out
    def alloc(name,size):
        for j,(b,n) in enumerate(free):
            if n>=size:
                free.pop(j)
                if n>size:free.append((b+size,n-size))
                coalesce();live[name]=(b,size);return b
        raise MemoryError((name,size,free))
    alloc('input',96*160*4)
    for i,o in enumerate(ops):
        srcs=[o['src']] if isinstance(o['src'],str) else o['src'];n=(math.prod(o['shape'])+3)//4*4
        alias=None;strategy='separate allocation'
        for src in srcs:
            if last[src]!=i:continue
            ih,iw,ci=shapes[src];oh,ow,co=o['shape'];b,old=live[src]
            if o['op']=='conv':
                spatial=o['pad']!=0
                if spatial and ow*co>o['stride']*iw*ci:continue
                mode='three source rows' if spatial else 'pixel cache, reverse traversal' if co>ci else 'pixel cache, forward traversal'
            elif o['op']=='maxpool':mode='four reads before compacted write'
            elif o['op']=='resize':mode='reverse traversal'
            else:mode='read both operands before write'
            if n>old:
                match=next((j for j,(fb,fn) in enumerate(free) if fb==b+old and fn>=n-old),None)
                if match is None:continue
                fb,fn=free.pop(match)
                if fn>n-old:free.append((b+n,fn-(n-old)))
            elif n<old:free.append((b+n,old-n))
            del live[src];live[o['dst']]=(b,n);alias=src;strategy=mode;coalesce()
            if mode=='three source rows':row_cache=max(row_cache,3*iw*ci)
            elif mode.startswith('pixel cache'):pixel_cache=max(pixel_cache,ci)
            break
        if alias is None:b=alloc(o['dst'],n)
        peak=max(peak,max(base+size for base,size in live.values()))
        ranges=sorted(live.values())
        assert all(a+na<=b for (a,na),(b,nb) in zip(ranges,ranges[1:])),(i,live)
        steps.append(dict(index=i,name=o['name'],dst=o['dst'],base=b,bytes=n,alias=alias,strategy=strategy))
        for src in srcs:
            if last[src]==i and src in live:free.append(live.pop(src));coalesce()
    out=ROOT/'reports/yunet_v46';out.mkdir(parents=True,exist_ok=True)
    report=dict(status='plan only; NOT implemented or physically verified',arena_bytes=65536,
        arena_high_water_bytes=peak,three_row_cache_bytes=row_cache,pixel_cache_bytes=pixel_cache,
        aliases=sum(x['alias'] is not None for x in steps),steps=steps,
        ram_estimate='Feature arena 64 to 32 blocks, plus estimated 4 row-cache blocks; estimated 28 RAM saved. Actual inference and placement must verify.')
    (out/'inplace_plan.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='steps'},indent=2))
if __name__=='__main__':main()
