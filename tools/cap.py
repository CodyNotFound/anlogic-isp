# cap.py — 从传感器经UDP抓一帧RAW10, 存 <名字>.npy (+.bin +预览png)
# 用法: uv run --with numpy --with pillow python cap.py white   → white.npy
# 场景: 标定用——让相机对准目标(如白纸)再跑
import socket, time, sys
import numpy as np

name = sys.argv[1] if len(sys.argv) > 1 else ''
if not name:
    print(__doc__); sys.exit(1)
BOARD = ('192.0.2.1', 6002)
WIN_B = 51200; PKTS_WIN = 50; PKT_DATA = 1024
W, H = 1280, 720

rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.bind(('0.0.0.0', 6001)); rx.settimeout(0.05)
for _ in range(8):
    try: rx.recv(65535)
    except socket.timeout: break
rx.settimeout(0.3)
tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print(f'触发RAWC抓帧 → {name}.npy ...', flush=True)
tx.sendto(b'RAWC', BOARD)
pkts = {}; t0 = time.time(); last = 0
while time.time() - t0 < 7:
    try: d, _ = rx.recvfrom(65535)
    except socket.timeout:
        if pkts and time.time() - last > 1.5: break
        continue
    if len(d) >= 2:
        pkts[(d[0] << 8) | d[1]] = d[2:]
        last = time.time()
seqs = sorted(pkts)
print(f'{len(seqs)}包', end='')
if not seqs or seqs[0] != 0 or len(seqs) < 1800:
    miss = [s for s in range(1800) if s not in pkts]
    print(f' 不完整(缺{len(miss)}包, 首={seqs[0] if seqs else "-"}), 重跑一次!', flush=True)
    sys.exit(1)
stream = b''.join(pkts[s] for s in seqs)[:51200*36]
open(name + '.bin', 'wb').write(stream)

rows = np.zeros((H, W), np.float64)
for w in range(36):
    arr = np.frombuffer(stream[w*WIN_B:(w+1)*WIN_B], dtype=np.uint8).astype(np.int32)
    for ln in range(20):
        seg = arr[ln*2560:(ln+1)*2560]
        rows[w*20+ln] = seg[0::2] | (np.minimum(seg[1::2], 3) << 8)
img = np.clip(rows, 0, 1023).astype(np.uint16)
np.save(name + '.npy', img)

# 标定统计
f = np.maximum(img.astype(np.float64) - 64, 0)
R, Gt, Gb, B = f[1::2,1::2], f[0::2,1::2], f[1::2,0::2], f[0::2,0::2]
print(f' → {name}.npy [{H}x{W}] | RAW域: R/G={R.mean()/Gt.mean():.3f} B/G={B.mean()/Gt.mean():.3f} '
      f'Gb/Gt={Gb.mean()/Gt.mean():.3f} | Gt均值={Gt.mean():.1f}')

# 预览: 色差平滑demosaic
G = np.zeros((H, W)); G[0::2,1::2]=f[0::2,1::2]; G[1::2,0::2]=f[1::2,0::2]
Gp = np.pad(G,1,mode='edge')
gmiss = (Gp[:-2,1:-1]+Gp[2:,1:-1]+Gp[1:-1,:-2]+Gp[1:-1,2:])/4
m = np.zeros((H,W),bool); m[0::2,0::2]=True; m[1::2,1::2]=True
G = np.where(m, gmiss, G)
def bilin_nan(a):
    v = np.where(np.isnan(a),0,a); w = (~np.isnan(a)).astype(float)
    for _ in range(3):
        vp, wp = np.pad(v,1,mode='edge'), np.pad(w,1,mode='edge')
        v = (vp[:-2,1:-1]+vp[2:,1:-1]+vp[1:-1,:-2]+vp[1:-1,2:])/4
        w = (wp[:-2,1:-1]+wp[2:,1:-1]+wp[1:-1,:-2]+wp[1:-1,2:])/4
    return v/np.maximum(w,1e-9)
dR = np.full((H,W),np.nan); dR[1::2,1::2] = f[1::2,1::2]-G[1::2,1::2]
dB = np.full((H,W),np.nan); dB[0::2,0::2] = f[0::2,0::2]-G[0::2,0::2]
Ro = np.clip(G+bilin_nan(dR),0,1023); Bo = np.clip(G+bilin_nan(dB),0,1023)
from PIL import Image
lo, hi = np.percentile(G,[0.5,99.7]); rng = max(hi-lo,1)
s = lambda c: (np.clip((c-lo)/rng,0,1)**(1/2.2)*255).astype(np.uint8)
Image.fromarray(np.dstack([s(Ro),s(G),s(Bo)])).save(name + '_preview.png')
print(f'预览: {name}_preview.png | 原始流: {name}.bin')
