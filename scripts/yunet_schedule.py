"""Lower the complete position-only YuNet graph to FPGA ROMs and arena offsets.

This first full-network baseline retains complete maps. Its memory cost is
reported explicitly; integration must reclaim the old detector and reduce maps.
"""
from yunet_integer import *

def main():
    net=json.loads((OUT/'network.json').read_text());ops=net['operations'];heads=net['heads']
    weights=np.load(OUT/'integer_model.npz');tensors={'input':dict(shape=[H,W,4],base=0,size=H*W*4)}
    last={};free=[(0,131072)];peak=0;live={};allocations={}
    for i,op in enumerate(ops):
        for x in [op['src']] if isinstance(op['src'],str) else op['src']:last[x]=i
    for x in heads.values():last[x]=len(ops)+1
    def allocate(name,shape):
        nonlocal peak
        size=(math.prod(shape)+3)//4*4
        for j,(base,n) in enumerate(free):
            if n>=size:
                free.pop(j)
                if n>size:free.append((base+size,n-size));free.sort()
                live[name]=(base,size);allocations[name]=dict(base=base,size=size,shape=shape);peak=max(peak,base+size)
                return base
        raise MemoryError((name,size,free))
    def release(name):
        free.append(live.pop(name));free.sort();merged=[]
        for b,n in free:
            if merged and sum(merged[-1])==b:merged[-1]=(merged[-1][0],merged[-1][1]+n)
            else:merged.append((b,n))
        free[:]=merged
    allocate('input',[H,W,4]);romweights=[];descriptors=[];schedule=[]
    for i,op in enumerate(ops):
        srcs=[op['src']] if isinstance(op['src'],str) else op['src'];src=tensors[srcs[0]]
        base=allocate(op['dst'],op['shape']);tensors[op['dst']]=allocations[op['dst']]
        ih,iw,ci=src['shape'];oh,ow,co=op['shape'];opcode={'conv':1,'maxpool':2,'resize':3,'add':4}[op['op']]
        k=1;stride=1;pad=0;dw=0;relu=0;wb=0;bb=0;s1=0;s2=0
        if opcode==1:
            original_ci=3 if op['src']=='input' else (1 if op['group']>1 else ci)
            count=next(o['weight_offset'] for o in ops[i+1:] if o['op']=='conv')-op['weight_offset'] if any(o['op']=='conv' for o in ops[i+1:]) else len(weights['weights'])-op['weight_offset']
            k=round(math.sqrt(count/(co*original_ci)))
            w=weights['weights'][op['weight_offset']:op['weight_offset']+count].reshape(co,k,k,original_ci)
            if op['src']=='input':w=np.pad(w,((0,0),(0,0),(0,0),(0,1)))
            while len(romweights)%4:romweights.append(0)
            wb=len(romweights);romweights.extend(w.reshape(-1).tolist());bb=op['bias_offset']
            stride=op['stride'];pad=op['pad'];dw=int(op['group']>1);relu=int(op['relu'])
        else:s1=op['shifts'][0];s2=op['shifts'][-1]
        # Fixed bitfield ABI, decoded in yunet_network.v.
        fields=[(opcode,0,4),(src['base'],4,17),(tensors[srcs[-1]]['base'] if len(srcs)>1 else 0,21,17),
            (base,38,17),(iw,55,8),(ih,63,8),(ow,71,8),(oh,79,8),(ci,87,7),(co,94,7),
            (k==3,101,1),(stride==2,102,1),(pad,103,1),(dw,104,1),(relu,105,1),
            (wb,106,16),(bb,122,11),(s1,133,7),(s2,140,7),(op['src']=='input',147,1)]
        word=0
        for value,shift,bits in fields:word|=(int(value)&((1<<bits)-1))<<shift
        descriptors.append(word);schedule.append(dict(index=i,name=op['name'],input=srcs,output=op['dst'],descriptor=f'{word:040x}'))
        for name in list(live):
            if last.get(name,-1)==i:release(name)
    rom=ROOT/'rtl/analytics/face_cnn'
    while len(romweights)%4:romweights.append(0)
    for bank in range(4):np.savetxt(rom/f'weights{bank}.hex',np.array(romweights[bank::4],np.int8).astype(np.uint8),fmt='%02x')
    np.savetxt(rom/'bias.hex',weights['bias'].astype(np.uint32),fmt='%08x')
    np.savetxt(rom/'shift.hex',weights['shift'].astype(np.uint8)&127,fmt='%02x')
    (rom/'program.hex').write_text('\n'.join(f'{x:040x}' for x in descriptors)+'\n',encoding='ascii')
    trace=np.load(OUT/'lena_integer_trace.npz');raw=np.pad(trace['input'],((0,0),(0,0),(0,1)))
    np.savetxt(OUT/'input.hex',raw.astype(np.uint8).reshape(-1),fmt='%02x')
    for i,op in enumerate(ops):np.savetxt(OUT/f'op_{i:02}.hex',trace[op['dst']].astype(np.uint8).reshape(-1),fmt='%02x')
    report=dict(status='scheduled',scope='complete-map baseline; not a camera-integrated resource fit',
        feature_arena_bytes=131072,arena_high_water_bytes=peak,weight_bank_depth=len(romweights)//4,
        program_depth=len(ops),bias_depth=len(weights['bias']),allocations=allocations,heads=heads,schedule=schedule)
    (OUT/'schedule.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    (OUT/'op_checks.txt').write_text('\n'.join(f"{allocations[o['dst']]['base']} {math.prod(o['shape'])}" for o in ops)+'\n',encoding='ascii')
    head_lines=['// Generated arena offsets for the integer output decoder.']
    for name,src in heads.items():head_lines.append(f"localparam [16:0] HEAD_{name.upper()}=17'd{allocations[src]['base']};")
    (rom/'yunet_heads.vh').write_text('\n'.join(head_lines)+'\n',encoding='ascii')
    print(json.dumps({k:v for k,v in report.items() if k not in ('allocations','heads','schedule')},indent=2))

if __name__=='__main__':main()
