"""Apply the lifetime-checked alias plan to the hardware instruction ABI."""
from pathlib import Path
import json,math
from yunet_inplace_plan import main as plan_main
ROOT=Path(__file__).resolve().parents[1]
def main():
    plan_main()
    net=json.loads((ROOT/'reports/yunet_v45/network.json').read_text())
    original=json.loads((ROOT/'reports/yunet_v45/schedule.json').read_text())
    plan=json.loads((ROOT/'reports/yunet_v46/inplace_plan.json').read_text())
    bases={'input':0};words=[];checks=[]
    for old,step,op in zip(original['schedule'],plan['steps'],net['operations']):
        if op['op']=='conv':assert all(1<=s<=31 for s in op['shift']), 'Update RTL positive-convolution-shift contract'
        if op['op']=='add':assert all(s in (0,1) for s in op['shifts']), 'Update RTL misc-scale contract'
        elif op['op']!='conv':assert op['shifts']==[0], 'Update RTL pool/resize-scale contract'
        srcs=[op['src']] if isinstance(op['src'],str) else op['src'];word=int(old['descriptor'],16)
        def field(v,pos,bits):
            nonlocal word
            mask=((1<<bits)-1)<<pos;word=(word&~mask)|((v<<pos)&mask)
        field(bases[srcs[0]],4,17);field(bases[srcs[-1]] if len(srcs)>1 else 0,21,17);field(step['base'],38,17)
        field(int(step['alias'] is not None),148,1);field(int(step['alias'] is not None and 'reverse' in step['strategy']),149,1)
        words.append(f'{word:040x}');bases[op['dst']]=step['base'];checks.append(f"{step['base']} {math.prod(op['shape'])}")
    rom=ROOT/'rtl/analytics/face_cnn';(rom/'program.hex').write_text('\n'.join(words)+'\n',encoding='ascii')
    lines=['// Generated alias-aware head offsets.']
    for name,src in net['heads'].items():lines.append(f"localparam [16:0] HEAD_{name.upper()}=17'd{bases[src]};")
    (rom/'yunet_heads.vh').write_text('\n'.join(lines)+'\n',encoding='ascii')
    (ROOT/'reports/yunet_v45/op_checks.txt').write_text('\n'.join(checks)+'\n',encoding='ascii')
    out=ROOT/'reports/yunet_v47';out.mkdir(exist_ok=True,parents=True)
    (out/'schedule.json').write_text(json.dumps(dict(steps=plan['steps'],arena_bytes=65536,row_cache_bytes=7680,
        aliases=plan['aliases'],heads={k:bases[v] for k,v in net['heads'].items()}),indent=2)+'\n')
if __name__=='__main__':main()
