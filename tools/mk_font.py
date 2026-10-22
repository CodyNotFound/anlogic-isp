#!/usr/bin/env python3
# mk_font.py: 像素字体TTF -> FPGA OSD字库BRAM初始化hex + 预览PNG
# 原理: 该像素字体每个点亮点画成独立方块轮廓, 点坐标严格落在 (26+64k, 826-64r)
#       的16px设计格上(1024em/64=16格)。直接读轮廓坐标换算行列, 原样抄录设计师
#       位图——无渲染无采样无插值(此前PIL渲染实测格距漂移7.5~7.9px, 会丢笔画)。
# 依赖: fonttools (pip3 install --user --break-system-packages fonttools)
#       Pillow 仅用于画预览PNG
# 字模格式: 每字符16行, 每行1个16bit字(4个hex字符), bit15=最左像素
#           $readmemh进 16bit宽x(16*N)深的BRAM; 字符序=CHARS定义序
import sys, os
try:
    from fontTools.ttLib import TTFont
    from fontTools.pens.recordingPen import RecordingPen
except ImportError:
    sys.exit("需要fonttools: pip3 install --user --break-system-packages fonttools")
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("预览需要Pillow: python3 -m pip install --user --break-system-packages pillow")

FONT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'fonts/ZLabsRoundPix_16px_MD_CN.ttf')
PREFIX = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), 'font_rom')

GRID = 16
ASCII_SET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:-. "
CJK_SET   = ("安路模式检测运动均衡帧延跟踪云台红蓝三角方形圆"   # 基础24字
             "原图灰度反色二值增亮锐化糊边缘浮雕复古换"            # 模式名20字
             "识别"                                                # MNIST模式名
             "京津冀晋蒙辽吉黑沪苏浙皖闽赣鲁豫鄂湘粤桂琼渝川贵云藏陕甘青宁新"  # 31省车牌
             "彩还"                                                # 色彩还原(模式名, 彩=0xCC 还=0xCD)
             "区")                                                 # 色区(REGN模式名), 区=0xCE
CHARS = ASCII_SET + CJK_SET

tt = TTFont(FONT)
GLYPH_SET = tt.getGlyphSet()
CMAP = tt.getBestCmap()
PITCH = tt['head'].unitsPerEm // GRID   # 1024/16 = 64 设计单位/格

def glyph_points(ch):
    pen = RecordingPen()
    GLYPH_SET[CMAP[ord(ch)]].draw(pen)
    return [args[0] for op, args in pen.value if op in ('moveTo', 'lineTo')]

# 全字符点集 -> 推导共享窗口原点: OX=最左列, OY=最顶行(全体字符共用, 保相对位置)
_all = [p for ch in CHARS if ch != ' ' for p in glyph_points(ch)]
OX = min(p[0] for p in _all)
OY = max(p[1] for p in _all)

def glyph2(ch):
    if ch == ' ':
        return [0] * GRID
    rows = [0] * GRID
    for x, y in glyph_points(ch):
        if (x - OX) % PITCH or (OY - y) % PITCH:
            print(f"错误: {ch!r} 点({x},{y})不在{PITCH}格点上")
            continue
        c = (x - OX) // PITCH
        r = (OY - y) // PITCH
        if 0 <= c < GRID and 0 <= r < GRID:
            rows[r] |= 1 << (GRID - 1 - c)
    lit = sum(bin(v).count('1') for v in rows)
    if lit == 0:
        print(f"错误: {ch!r} 字模全空")
    elif lit > GRID * GRID * 7 // 10:
        print(f"警告: {ch!r} 点亮{lit}格疑似实心块")
    return rows

# 生成hex
words = []
for ch in CHARS:
    words += glyph2(ch)
with open(PREFIX + '.hex', 'w') as f:
    for i in range(0, len(words), 16):
        f.write(' '.join(f'{w:04x}' for w in words[i:i + 16]) + '\n')

# 索引表打印(供RTL的字符码->ROM地址映射参考)
print(f"窗口原点({OX},{OY}) 格距{PITCH} | 字符总数: {len(CHARS)}  总深度: {len(words)} (16bit字)")
print(f"索引: ASCII段 '{ASCII_SET[:10]}...' 0..{len(ASCII_SET)-1}; 中文段 '{CJK_SET[:4]}...' {len(ASCII_SET)}..{len(CHARS)-1}")
print(f"建议RTL编码: ASCII用其ASCII码(0x20-0x5A直接映射), 中文从0x80起: ", {c: hex(0x80 + i) for i, c in enumerate(CJK_SET[:6])})

# 预览PNG: 12列网格, 每格带序号标签(按CHARS顺序), 放大10倍
SC = 10
COLS = 12
LABEL_H = 14
rows_n = (len(CHARS) + COLS - 1) // COLS
CELL = GRID + 3
try:
    lf = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 10)
except OSError:
    lf = ImageFont.load_default()
pv = Image.new('RGB', (COLS * CELL * SC, rows_n * (GRID + 3) * SC + LABEL_H), (12, 16, 22))
pd = ImageDraw.Draw(pv)
for idx, ch in enumerate(CHARS):
    cx = (idx % COLS) * CELL * SC
    cy = (idx // COLS) * (GRID + 3) * SC + LABEL_H
    pd.rectangle([cx, cy, cx + GRID * SC, cy + GRID * SC], outline=(40, 52, 66))
    pd.text((cx + 2, cy - LABEL_H), str(idx), font=lf, fill=(120, 140, 160))
    for y, bits in enumerate(glyph2(ch)):
        for x in range(GRID):
            if (bits >> (GRID - 1 - x)) & 1:
                pd.rectangle([cx + x * SC, cy + y * SC, cx + x * SC + SC - 1, cy + y * SC + SC - 1], fill=(57, 211, 83))
pv.save(PREFIX + '_preview.png')
print(f"输出: {PREFIX}.hex + {PREFIX}_preview.png")
