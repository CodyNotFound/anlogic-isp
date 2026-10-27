"""Independent pixel reference for the approved compact HUD and SW3 policy."""
from pathlib import Path
import re
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/osd_v43'
W,H=1280,720
BASE=0x6080a0

def mif(name):
    return {int(a):int(b,16) for a,b in re.findall(r'^\s*(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',
        (ROOT/'user_source/hdl_source'/name).read_text(),re.M)}

font=mif('osd_font_rom.mif');idx=mif('osd_logo_idx.mif');pal=mif('osd_logo_pal.mif')

def glyph(ch):
    if 48<=ch<=57:return ch-48
    if 65<=ch<=90:return ch-65+10
    if ch in [58,45,46]:return {58:36,45:37,46:38}[ch]
    if 128<=ch<=206:return ch-128+40
    return 39

def char(im,x,y,ch,color):
    for row in range(16):
        bits=font.get(glyph(ch)*16+row,0)
        for col in range(16):
            if bits & (1<<(15-col)) and 0<=x+col<W and 0<=y+row<H:im[y+row,x+col]=color

def text(im,x,y,s,color=0xf0f5f5):
    # ASCII halfwidth; the source font has a zero right half.
    for i,ch in enumerate(s):char(im,x+8*i,y,ord(ch),color)

def panel(im,x,y,w,h):im[y:y+h,x:x+w]=0x304050

def render(frame):
    mode=[0,11,11,12,14,14][frame]
    visible=frame!=2
    manual=frame==5
    im=np.full((H,W),BASE,dtype=np.uint32)
    if visible:
        if mode==11:x,y,size,cx,cy=848,368,224,960,480
        elif mode==12:x,y,size,cx,cy=656,376,128,720,440
        else:x,y,size,cx,cy=736,416,128,800,480
        if mode in (11,12,14):
            im[y:y+size,x:x+2]=im[y:y+size,x+size-2:x+size]=0x00ff40
            im[y:y+2,x:x+size]=im[y+size-2:y+size,x:x+size]=0x00ff40
            im[cy-7:cy+8,cx]=im[cy,cx-7:cx+8]=0xff4040
        if mode==14:
            # Color sampling rectangle remains available even with a lock.
            im[348:373,640]=im[360,628:653]=0xffff40
            im[352,632:656]=im[375,632:656]=0xffff40
            im[352:376,632]=im[352:376,655]=0xffff40
    # Opaque logo indices only, including when every other HUD element is off.
    for y in range(94):
        for x in range(146):
            n=idx.get(y*146+x,0)
            if n:im[y+24,x+24]=pal[n]
    if visible:
        panel(im,1200,24,64,20);text(im,1204,26,'60 FPS')
        panel(im,192,24,104,20);text(im,196,26,f'{mode:02}')
        names={0:[0x9c,0xcc,0xcd,0x97],11:list(map(ord,'FACE')),12:[0x8c,0x8d],14:[0x9c,0xce]}
        for i,ch in enumerate(names[mode]):char(im,220+16*i,26,ch,0xf0f5f5)
        panel(im,192,48,200,20)
        status='MANUAL H J K L' if manual else 'AUTO TRACK' if mode in (11,12,14) else 'IDLE'
        text(im,196,50,status,0x60ff90 if not manual and mode in (11,12,14) else 0xf0f5f5)
        panel(im,880,676,384,36)
        switches=['SW4 MAN ON' if manual else 'SW4 MAN OFF','SW3 OSD ON','SW2 AE OFF','SW1 AB OFF']
        keys=['K4 H LEFT','K3 J DOWN','K2 K UP','K1 L RIGHT'] if manual else ['K4 PICK' if mode in (12,14) else 'K4 NONE','K3 NONE','K2 PREV MODE','K1 NEXT MODE']
        for i,(sw,key) in enumerate(zip(switches,keys)):
            text(im,880+i*96,676,sw,0x60ff90 if i==1 or i==0 and manual else 0xc0c0c0)
            text(im,880+i*96,696,key)
        panel(im,1168,568,96,100)
        im[572:637,1184]=im[572:637,1248]=0x606870
        for yy in [572,636,604,589,623]:im[yy,1184:1249]=0x606870
        im[572:637,1216]=0x606870
        # Published command packet forced to 1500/1500 by this composition test.
        im[601:606,1213:1218]=0x30e0ff if manual else 0xffb050
        text(im,1168,644,'H1500 V1500')
    return im

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    for f in range(6):
        im=render(f)
        np.savetxt(OUT/f'expected_{f}.hex',im.reshape(-1),fmt='%06x')
        rgb=np.stack([(im>>16)&255,(im>>8)&255,im&255],axis=-1).astype(np.uint8)
        Image.fromarray(rgb).save(OUT/f'expected_{f}.png')
    print('Prepared six independent 720p reference frames; unchanged logo ROM data')

if __name__=='__main__':main()
