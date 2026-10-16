from pathlib import Path
import re
root=Path(r'[LOCAL_PATH]')
src=root.parent/'user_source/hdl_source'
def parse_mif(path, width):
    vals={}
    for line in path.read_text().splitlines():
        m=re.match(r'\s*(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',line)
        if m: vals[int(m.group(1))]=int(m.group(2),16)
    return vals
idx=parse_mif(src/'osd_logo_idx.mif',8)
pal=parse_mif(src/'osd_logo_pal.mif',24)
(root/'logo_idx.hex').write_text(''.join(f'{idx.get(i,0):02x}\n' for i in range(16384)))
(root/'logo_pal.hex').write_text(''.join(f'{pal.get(i,0):06x}\n' for i in range(256)))
expected=[]
for y in range(16,201):
    for x in range(16,179):
        hit=(24<=x<170 and 24<=y<118)
        if hit and idx.get((y-24)*146+(x-24),0)!=0:
            rgb=pal.get(idx[(y-24)*146+(x-24)],0)
        else:
            rgb=0x404040  # HUD dim background over 0x808080 input
        expected.append(rgb)
(root/'logo_expected.hex').write_text(''.join(f'{v:06x}\n' for v in expected))
print('logo words',sum(1 for v in idx.values() if v),'palette',len(pal),'expected pixels',len(expected))
