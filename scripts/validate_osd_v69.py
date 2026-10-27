from pathlib import Path
import sys,json,re
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'v45_face/.face_deps'))
import numpy as np
from PIL import Image
out=ROOT/'reports/osd_v69';meta=json.loads((out/'font_map.json').read_text(encoding='utf-8'))
words=[int(x,16) for x in (ROOT/'sim/osd_font_rom.hex').read_text().split()]
mif=[int(v,16) for _,v in re.findall(r'([0-9A-F]+)\s*:\s*([0-9A-F]+);',(ROOT/'user_source/hdl_source/osd_font_rom.mif').read_text())]
assert len(words)==2048 and words==mif
assert len(meta['ascii'])+len(meta['cjk'])==128
idx=np.loadtxt(ROOT/'sim/logo_idx.hex',dtype=np.uint8,converters={0:lambda x:int(x,16)})[:146*94].reshape(94,146)
pal=np.loadtxt(ROOT/'sim/logo_pal.hex',dtype=np.uint32,converters={0:lambda x:int(x,16)})
rgb=np.stack([(pal>>16)&255,(pal>>8)&255,pal&255],1).astype(np.uint8)
def mask(text,small=False):
 cols=[]
 for c in text:
  gi=42+meta['cjk'].index(c) if ord(c)>127 else meta['ascii'].index(c)
  if small:xs=np.arange(12);ys=np.arange(16)
  else:
   xs=np.arange(24)*2//3
   ys=(1+2*(np.arange(24)*7//24)) if ord(c)<128 else np.arange(24)*2//3
  cols.append(np.array([[(words[gi*16+int(y)]>>(15-int(x)))&1 for x in xs]for y in ys],bool))
 return np.concatenate(cols,axis=1)
checks=0
for i in range(3):
 pic=Image.open(out/f'frame{i}.ppm');pic.save(out/f'frame{i}.png');im=np.asarray(pic)
 assert np.all(im[24:118,24:170][idx!=0]==rgb[idx[idx!=0]])
 texts=[('11 人脸' if i==0 else '12 模板' if i==1 else '00 色彩还原',196,28,0xf0f5f5),('手动控制' if i==1 else '跟踪中' if i==0 else '等待',388,28,0x60ff90 if i==0 else 0xf0f5f5),('60 FPS',992,24,0xf0f5f5),('H1539 V1476',1112,600,0xf0f5f5)]
 if i<2:texts += [('X:0936 Y:0404',196,70,0xf0f5f5),('0267ms PROC' if i==0 else '0015ms PROC',992,60,0xf0f5f5)]
 positions=[696,808,920,1104]
 for group,text in enumerate(['手动 开' if i==1 else '手动 关','追踪 开','自动曝光 自动','白平衡 自动']):texts.append((text,positions[group],648,0xc0c0c0 if group==0 and i!=1 else 0x60ff90))
 for group,text in enumerate(['向左','向下','向上','向右'] if i==1 else ['无','无','上一项','下一项']):texts.append((text,positions[group],680,0xf0f5f5))
 assert np.all(im[24:118,24:170][idx==0]==[48,64,80]),'Logo transparent area needs unified backing'
 assert np.all(im[98:126,178:520]==[48,64,80]),'left plate must be continuous'
 for text,x,y,color in texts:
  m=mask(text,text.startswith("H1539"));expected=np.full((m.shape[0],m.shape[1],3),[48,64,80],np.uint8)
  expected[m]=[(color>>16)&255,(color>>8)&255,color&255]
  actual=im[y:y+m.shape[0],x:x+m.shape[1]]
  if not np.array_equal(actual,expected):
   bad=np.argwhere(np.any(actual!=expected,2));print(i,text,bad[:12].tolist(),[(actual[yy,xx].tolist(),expected[yy,xx].tolist()) for yy,xx in bad[:4]])
  assert np.array_equal(actual,expected),(i,text,int(np.any(actual!=expected,2).sum()))
  checks+=1
oldfont=[int(v,16)for _,v in re.findall(r'([0-9A-F]+)\s*:\s*([0-9A-F]+);',(ROOT/'releases/vision_hmi_v66_r2/source/user_source/hdl_source/osd_font_rom.mif').read_text())]
assert words[:42*16]==oldfont[:42*16],'Aurora ASCII must exactly match v66'
asset=json.loads((ROOT/'rtl/overlay/zlabs_pixel16_v67.json').read_text(encoding='utf-8'))
for i,c in enumerate(meta['cjk']):assert words[(42+i)*16:(43+i)*16]==asset['glyphs'][c]
record=dict(status='passed',gimbal_size=[160,144],unified_logo_backing=True,uppercase_digit_height=24,ascii_v66_exact=True,cjk_v67_exact=True,known_pixels=2764800,font_words=2048,glyphs=128,logo_exact=True,independent_text_rectangles=checks)
(out/'validation.json').write_text(json.dumps(record,indent=2));print(record)
