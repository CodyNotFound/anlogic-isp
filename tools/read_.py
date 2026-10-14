# read_.py — 快速查看npy文件: 用法 uv run --with numpy --with pillow python read_.py <名字>
# 例: read_.py white → 读 white.npy (带.npy后缀也行)
import sys, os
import numpy as np

name = sys.argv[1] if len(sys.argv) > 1 else ''
if not name:
    print(__doc__); sys.exit(1)
path = name if name.endswith('.npy') else name + '.npy'
if not os.path.exists(path):
    print(f'找不到 {path}'); sys.exit(1)

a = np.load(path)
print(f'文件: {path}')
print(f'shape={a.shape} dtype={a.dtype} 共{a.size}元素 {a.nbytes/1e6:.2f}MB')
if a.size:
    f = a.astype(np.float64)
    print(f'min={a.min()} max={a.max()} mean={f.mean():.3f}')
    print(f'p1={np.percentile(f,1):.1f} p50={np.percentile(f,50):.1f} p99={np.percentile(f,99):.1f}')

# 2D灰度或3D图像 → 顺手出预览PNG
if a.ndim >= 2 and a.dtype in (np.uint8, np.uint16, np.int16, np.float32, np.float64):
    from PIL import Image
    img = f if a.ndim == 2 else f[..., :3].mean(-1)   # 3D取前3通道均值做亮度
    lo, hi = np.percentile(img, [0.5, 99.7])
    q = np.clip((img - lo) / max(hi - lo, 1e-9), 0, 1)
    out = path[:-4] + '_preview.png'
    Image.fromarray((q ** (1/2.2) * 255).astype(np.uint8)).save(out)
    print(f'预览已存: {out}')

# 前5个/角上3x3样本
print('样本 前5:', np.ravel(a)[:5].tolist())
if a.ndim >= 2:
    print('样本 左上3x3:\n', a[:3, :3])
