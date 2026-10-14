#!/usr/bin/env python3
# calibrate_lsc.py - 拍白纸屏幕照片 → 径向剖面 → 直接生成 lsc_corr.v 增益表
# 用法: python calibrate_lsc.py <photo.jpg> <output_lsc_corr.v>
# 原理: 与 sim/photo_radial_profile.ps1 相同的径向采样, 但输出Verilog case常量
import sys, os, math
try:
    from PIL import Image
except ImportError:
    sys.exit("需要Pillow: 已在cnn/.venv中安装")

photo_path = sys.argv[1]
v_path = sys.argv[2]

img = Image.open(photo_path).convert('RGB')
W, H = img.size
print(f"照片: {photo_path} ({W}x{H})")

# 屏幕区域(粗估: 照片中央80%x80%)
x0, x1 = int(W*0.10), int(W*0.90)
y0, y1 = int(H*0.10), int(H*0.90)
cx, cy = (x0+x1)/2, (y0+y1)/2
rx, ry = (x1-x0)/2, (y1-y0)/2

def sample_bucket(b):
    """采样第b个径向桶的R/G/B中位数"""
    rho = math.sqrt(((b+0.5)*512.0)/14500.0)
    Rs, Gs, Bs = [], [], []
    for k in range(24):
        th = 2*math.pi*k/24
        px, py = cx + rho*rx*math.cos(th), cy + rho*ry*math.sin(th)
        if px < x0+5 or px > x1-5 or py < y0+5 or py > y1-5:
            continue
        r, g, bl = 0, 0, 0
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                ix, iy = int(px+dx), int(py+dy)
                ix = max(0, min(W-1, ix)); iy = max(0, min(H-1, iy))
                pr, pg, pb = img.getpixel((ix, iy))
                r += pr; g += pg; bl += pb
        Rs.append(r/25); Gs.append(g/25); Bs.append(bl/25)
    if len(Rs) < 6:
        return None
    Rs.sort(); Gs.sort(); Bs.sort()
    n = len(Rs)
    return Rs[n//2], Gs[n//2], Bs[n//2]

# 采样所有桶
buckets = []
for b in range(29):
    res = sample_bucket(b)
    if res:
        buckets.append((b, res[0], res[1], res[2]))
    else:
        # 边角桶可能超出采样区, 用最近的有效桶
        if buckets:
            last = buckets[-1]
            buckets.append((b, last[1], last[2], last[3]))

if len(buckets) < 20:
    sys.exit("有效桶太少, 照片可能没拍到屏幕或对比度太低")

# 计算增益: G基准, R/B追G, 均值归一
rat_G = [g/r for _, r, g, b in buckets]  # G/R
rat_B = [g/b for _, r, g, b in buckets]  # G/B
mG = sum(rat_G)/len(rat_G)
mB = sum(rat_B)/len(rat_B)

gains = []
for i, (_, r, g, b) in enumerate(buckets):
    gr = int(round(256 * rat_G[i] / mG))
    gb = int(round(256 * rat_B[i] / mB))
    gg = 256
    gr = max(200, min(312, gr))
    gb = max(200, min(312, gb))
    gains.append((gr, gg, gb))
    if i < 5 or i >= len(buckets)-3:
        print(f"  bucket {b:2d}: R={r:5.0f} G={g:5.0f} B={b:5.0f}  gainR={gr} gainG={gg} gainB={gb}")

# 生成lsc_corr.v (只替换增益case表, 其余照抄现有模块结构)
header = '''// 径向LSC: 由calibrate_lsc.py自动生成于 {time}
// 校准方法: 摄像头对白纸→手机拍显示器→运行calibrate_lsc.bat→自动重编
module lsc_corr #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid
);
    // 坐标计数
    reg [8:0] xbeat;
    reg [9:0] y;
    always @(posedge I_clk) begin
        if (!I_rst_n) begin xbeat <= 0; y <= 0; end
        else if (I_tvalid) begin
            if (I_tuser) begin xbeat <= 1; y <= 0; end
            else if (xbeat == 319) begin
                xbeat <= 0;
                y <= (y == 719) ? 0 : y + 1;
            end else xbeat <= xbeat + 1;
        end
    end
    wire [8:0] cur_xbeat = I_tuser ? 0 : xbeat;
    wire [9:0] cur_y = I_tuser ? 0 : y;

    // 半径量化: dxn=|x-640|>>3, dyn=|y-360|>>2, r2=dxn²+dyn², bucket=r2[13:9]
    wire [10:0] dy = (cur_y >= 360) ? (cur_y - 360) : (360 - cur_y);
    wire [7:0]  dyn = dy >> 2;
    wire [4:0] bucket[0:3];
    genvar gi;
    generate for (gi = 0; gi < 4; gi = gi + 1) begin : g_r
        wire [10:0] px_x = cur_xbeat * 4 + gi;
        wire [10:0] dx = (px_x >= 640) ? (px_x - 640) : (640 - px_x);
        wire [7:0] dxn = dx >> 3;
        wire [13:0] r2 = dxn*dxn + dyn*dyn;
        assign bucket[gi] = r2[13:9];
    end endgenerate

    // A拍寄存
    reg [4:0] bucket_a[0:3];
    reg [95:0] tdata_a;
    reg tvalid_a, tuser_a, tlast_a;
    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            bucket_a[0]<=0; bucket_a[1]<=0; bucket_a[2]<=0; bucket_a[3]<=0;
            tdata_a<=0; tvalid_a<=0; tuser_a<=0; tlast_a<=0;
        end else begin
            bucket_a[0]<=bucket[0]; bucket_a[1]<=bucket[1]; bucket_a[2]<=bucket[2]; bucket_a[3]<=bucket[3];
            tdata_a<=I_tdata; tvalid_a<=I_tvalid; tuser_a<=I_tuser; tlast_a<=I_tlast;
        end
    end

    // 增益表 (自动生成, 29桶 × 3通道, Q0.8)
    function [8:0] lsc_gain_r;
        input [4:0] b;
        begin
            case (b)
'''.format(time=os.path.basename(photo_path))

r_case = '\n'.join(f"                5'd{i}: lsc_gain_r = 9'd{gr};" for i, (gr, _, _) in enumerate(gains))
g_case = '\n'.join(f"                5'd{i}: lsc_gain_g = 9'd{gg};" for i, (_, gg, _) in enumerate(gains))
b_case = '\n'.join(f"                5'd{i}: lsc_gain_b = 9'd{gb};" for i, (_, _, gb) in enumerate(gains))

footer = '''                default: lsc_gain_r = 9'd256;
            endcase
        end
    endfunction

    function [8:0] lsc_gain_g;
        input [4:0] b;
        begin
            case (b)
GAIN_G_CASE
                default: lsc_gain_g = 9'd256;
            endcase
        end
    endfunction

    function [8:0] lsc_gain_b;
        input [4:0] b;
        begin
            case (b)
GAIN_B_CASE
                default: lsc_gain_b = 9'd256;
            endcase
        end
    endfunction

    function [7:0] lsc_mul_sat;
        input [7:0] v; input [8:0] g;
        reg [16:0] prod;
        begin
            prod = v * g;
            lsc_mul_sat = prod[16] ? 8'd255 : prod[15:8];
        end
    endfunction

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            O_tlast<=0; O_tuser<=0; O_tvalid<=0; O_tdata<=0;
        end else begin
            O_tlast<=tlast_a; O_tuser<=tuser_a; O_tvalid<=tvalid_a;
            if (tvalid_a) begin
                O_tdata <= {
                    lsc_mul_sat(tdata_a[88+:8], lsc_gain_r(bucket_a[3])),
                    lsc_mul_sat(tdata_a[80+:8], lsc_gain_g(bucket_a[3])),
                    lsc_mul_sat(tdata_a[72+:8], lsc_gain_b(bucket_a[3])),
                    lsc_mul_sat(tdata_a[64+:8], lsc_gain_r(bucket_a[2])),
                    lsc_mul_sat(tdata_a[56+:8], lsc_gain_g(bucket_a[2])),
                    lsc_mul_sat(tdata_a[48+:8], lsc_gain_b(bucket_a[2])),
                    lsc_mul_sat(tdata_a[40+:8], lsc_gain_r(bucket_a[1])),
                    lsc_mul_sat(tdata_a[32+:8], lsc_gain_g(bucket_a[1])),
                    lsc_mul_sat(tdata_a[24+:8], lsc_gain_b(bucket_a[1])),
                    lsc_mul_sat(tdata_a[16+:8], lsc_gain_r(bucket_a[0])),
                    lsc_mul_sat(tdata_a[8+:8],  lsc_gain_g(bucket_a[0])),
                    lsc_mul_sat(tdata_a[0+:8],  lsc_gain_b(bucket_a[0]))
                };
            end else O_tdata <= 0;
        end
    end
endmodule
'''

text = header + r_case + footer
text = text.replace('GAIN_G_CASE', g_case).replace('GAIN_B_CASE', b_case)

with open(v_path, 'w') as f:
    f.write(text)
print(f"\n增益表已写入: {v_path}")
print(f"R增益范围: {min(g[0] for g in gains)}~{max(g[0] for g in gains)} (256=1.0)")
print(f"B增益范围: {min(g[2] for g in gains)}~{max(g[2] for g in gains)} (256=1.0)")
print("下一步: 双击 calibrate_lsc.bat 或等编译完成")
