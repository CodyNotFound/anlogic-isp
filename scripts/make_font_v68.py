"""Rebuild a <=128-glyph shared atlas; no additional font RAM."""
from pathlib import Path
import json,sys,hashlib
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'v45_face/.face_deps'))
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
MODES=['色彩还原','灰度','反色','二值','增亮','锐化','模糊','边缘','浮雕','卡通','换色','人脸','模板','均衡','色区','运动']
TEXTS=['安路模式原图','等待','跟踪中','目标丢失','手动控制','自动关闭','等待选取','正在取样','重新选取','运动检测','光照变化','云台移动','建立背景','暂无运动','SW4手动开','SW4手动关','SW3跟随开','SW3跟随关','SW2曝光自','SW2曝光锁','SW1白平衡自','SW1白平衡锁','K4向左','K3向下','K2向上','K1向右','K4重置','K4选取','K4无','K3无','K2上一项','K1下一项']
ASCII='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:-. ms'
CJK=''.join(dict.fromkeys(c for s in MODES+TEXTS for c in s if ord(c)>127))
assert len(ASCII)+len(CJK)<=128,(len(ASCII),len(CJK))
CJK=CJK.replace('均','搜').replace('随','追')+'索定'
assert len(ASCII)+len(CJK)<=128
CODES={c:0x80+i for i,c in enumerate(CJK)}
rows=[];sheet=Image.new('RGB',(16*16,((len(ASCII)+len(CJK)+15)//16)*24),'#162028')
glyphs=json.loads((ROOT/'rtl/overlay/zlabs_pixel16_v67.json').read_text(encoding='utf-8'))['glyphs']
# The user requested the earlier chunky Aurora ASCII and original pixel CJK.
aurora=json.loads((ROOT/'rtl/overlay/aurora_ascii_5x7.json').read_text(encoding='utf-8'))['glyphs']
for c in ASCII:
 g=[0]*16
 for y,bits in enumerate(aurora[c]):
  for x in range(5):
   if bits&(1<<(4-x)):
    for yy in [1+y*2,2+y*2]:g[yy]|=(3<<(15-(3+x*2)))
 glyphs[c]=g
assert all(c in glyphs for c in ASCII)
for i,c in enumerate(ASCII+CJK):
 im=Image.new('1',(16,16));d=ImageDraw.Draw(im)
 # Integer font grid captured from the original designer bitmap, no rasterizer.
 for y,bits in enumerate(glyphs[c]):
  for x in range(16):
   if bits&(1<<(15-x)):im.putpixel((x,y),1)
 for y in range(16):rows.append(sum(int(im.getpixel((x,y))!=0)<<(15-x) for x in range(16)))
 sheet.paste(im.convert('RGB'),((i%16)*16,(i//16)*24))
rows+= [0]*(2048-len(rows))
p=ROOT/'sim/osd_font_rom.hex';p.write_text(''.join(f'{v:04x}\n' for v in rows),encoding='ascii')
(ROOT/'user_source/hdl_source/osd_font_rom.mif').write_text('WIDTH=16;\nDEPTH=2048;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i:03X} : {v:04X};\n' for i,v in enumerate(rows))+'END;\n',encoding='ascii')
report=ROOT/'reports/osd_v68';report.mkdir(parents=True,exist_ok=True);sheet.resize((512,sheet.height*2),Image.Resampling.NEAREST).save(report/'font_atlas.png')
(report/'font_map.json').write_text(json.dumps(dict(ascii=ASCII,cjk=CJK,codes=CODES,glyphs=len(ASCII)+len(CJK)),ensure_ascii=False,indent=2),encoding='utf-8')
# Shared production ROM and test ROM use the exact same mapping.
branches="""if(I_char>=8'h30&&I_char<=8'h39)char_idx=I_char-8'h30;
  else if(I_char>=8'h41&&I_char<=8'h5A)char_idx=I_char-8'h41+7'd10;
  else if(I_char==8'h3A)char_idx=36;
  else if(I_char==8'h2D)char_idx=37;
  else if(I_char==8'h2E)char_idx=38;
  else if(I_char==8'h6D)char_idx=40;
  else if(I_char==8'h73)char_idx=41;
  else if(I_char>=8'h80&&I_char<=8'hLAST)char_idx={1'b0,I_char[6:0]}+7'd42;
  else char_idx=39;"""
branches=branches.replace('LAST',f'{0x80+len(CJK)-1:02X}')
for rel in ['user_source/hdl_source/osd_font_bram.v','sim/osd_rom_sim_models.v','sim/osd_rom_real_models.v']:
 p=ROOT/rel;s=p.read_text(encoding='utf-8');start=s.index('always @* begin')
 if rel.startswith('user_source'):
  end=s.index('    // ROM 读地址',start);s=s[:start]+'always @* begin\n  '+branches+'\n end\n\n'+s[end:]
 else:
  end=s.index(' initial $readmemh',start);s=s[:start]+'always @* begin\n  '+branches+'\n end\n'+s[end:]
 p.write_text(s,encoding='utf-8')
print('Font rebuilt:',len(ASCII),'ASCII +',len(CJK),'CJK, fixed 2048 words')
