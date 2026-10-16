from pathlib import Path
import re
root=Path(r'[LOCAL_PATH]');src=root.parent/'user_source/hdl_source'
def parse(path):
 d={}
 for l in path.read_text().splitlines():
  m=re.match(r'\s*(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',l)
  if m:d[int(m.group(1))]=int(m.group(2),16)
 return d
idx=parse(src/'osd_logo_idx.mif');pal=parse(src/'osd_logo_pal.mif')
out=[]
for y in range(16,201):
 for x in range(16,179):
  if 24<=x<170 and 24<=y<118 and idx.get((y-24)*146+x-24,0): rgb=pal[idx[(y-24)*146+x-24]]
  elif 16<=x<178 and 16<=y<196: rgb=0x404040
  else: rgb=0x808080
  out.append(rgb)
(root/'logo_expected.hex').write_text(''.join(f'{v:06x}\n' for v in out))
print('expected',len(out))
