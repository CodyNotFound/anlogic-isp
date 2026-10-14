# 车牌字符分类器训练指南（Mac/MPS 侧，阶段1）

目标：65 类（31 省份汉字 + 24 字母无 I/O + 10 数字）单字符 INT8 分类器，
导出 `plate_weights.mif` 给 FPGA 的 plate_char_engine（阶段2 RTL）。

## 类别索引表（冻结，RTL/OSD 按此映射）

见 `cnn/plate_classes.txt`：
- 0..30 = 京津冀晋蒙辽吉黑沪苏浙皖闽赣鲁豫鄂湘粤桂琼渝川贵云藏陕甘青宁新
- 31..54 = ABCDEFGHJKLMNPQRSTUVWXYZ（无 I、O）
- 55..64 = 0123456789

## 快速验证路径（无需下载数据，~10 分钟）

```bash
cd <仓库根>
python3 -m venv cnn/.venv                     # 若已有则跳过
cnn/.venv/bin/pip install torch pillow
cnn/.venv/bin/python cnn/train_plate.py --synthetic 2000
```
合成模式用系统字体在车牌蓝底上渲染字符（亮度/旋转抖动），
预期 INT8 精度 90%+——只用于打通链路，不代表真实精度。

## 真实数据路径（精度优先）

1. 下载 CCPD 数据集（公开，GitHub: detectRecog/CCPD，约 12GB，可只下 ccpd_base 的一部分）
2. 切字符（Pillow 即可，无需 opencv）：
```bash
cnn/.venv/bin/python cnn/extract_ccpd_chars.py /path/to/ccpd_base --max 30000
# 看 cnn/plate_data_preview/ 前100张红框可视化, 框没套准字符就微调脚本里的 CELL_RATIOS 重跑
```
3. 训练：
```bash
cnn/.venv/bin/python cnn/train_plate.py --qat-epochs 15
```

## 验收标准
- INT8 硬件语义精度 ≥ 97%（脚本自动打印，并给出最差 5 类）
- 产物：`cnn/plate_weights.mif`（自动复制到 `user_source/hdl_source/plate_weights.mif`）
  + `cnn/plate_classes.txt`（类别索引表）

## 量化/布局约定（与 RTL 冻结规格一致，勿改）
- 网络：conv1 1→8 5x5 / conv2 8→16 5x5 / fc 256→65，输入 28x28 灰度 u8
- 权重偏置 s8 = round(w×64)；conv 出 ReLU 饱和 u8；fc 直接 argmax
- mif：DEPTH=16384, WIDTH=16（wht ERAM 32KB）
  w1@0 b1@200 w2@208 b2@3408 w3@3424(65×256) b3@20064(65) 补 0 到 32768
