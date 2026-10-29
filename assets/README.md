# 图形与校准资源

- `fonts/`：原像素中文字模、补充字模和 Aurora 英文字模。没有重新栅格化或更换字体。
- `rom/`：同一份字体、安路 Logo 的硬件 MIF 与仿真 HEX；两个 BRAM 包装器与 MIF 放在一起，保留 TD 按源文件目录寻找初始化文件的行为。
- `calibration/`：已用的镜头平场数据与硬件校准参数。

字库生成：`python scripts/build_font.py`。Logo 预览：`python scripts/preview_logo.py --out .agent/build/logo.png`。修改资源后重新构建 FPGA。
