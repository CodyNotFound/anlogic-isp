# anlogic-isp

2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 安路赛题二。
基于 PH1P35 FPGA + SC500CS MIPI 摄像头的实时 ISP 色彩还原系统。
在官方 lab_ex3 例程基座(SC500 720P MIPI→ISP→DDR→HDMI+OSD)上自研
传感器域色彩矫正链与交互演示。

## 功能
- 传感器域 ISP 链（自研）：黑电平(BLC) → 镜头阴影(LSC, 221点Q2.10标定网格) → 灰世界自动白平衡(AWB) → 饱和度/sRGB色调/去紫边
- 11 种 HDMI 域算法模式（K1/K2 切换）：色彩还原 / 灰度 / 反色 / 二值 / 增亮 / 锐化 / 模糊 / 边缘 / 浮雕 / 复古 / 换色
- K3 六步 ISP 分步演示：原图 → BLC → AWB → LSC → GAMMA → 饱和度，逐级呈现色彩还原全过程（终点=模式00）
- 蜂鸣器反馈：开机三音上行旋律，按键哔声
- OSD：118 字中文点阵字库、logo、CNT/FPS 状态栏、底部模式栏

## 目录
- `rtl/` 自研 RTL（ISP/控制/OSD/平台）
- `user_source/` 板级源码（例程基座 + 传感器配置、视频通路、IP）
- `vendor_reference/` 厂商参考设计
- `sim/` ModelSim 仿真验证集
- `calibration/` 标定数据（黑白场平拍、LSC 网格导出）
- `scripts/` 构建/仿真/标定脚本
- `td_project/` TD 工程（仅源，构建产物不入库）
- `tools/` RAW 采集与标定上位机工具
- `docs/` 全部说明文档（含前期基础线与调试线归档）
- `releases/` 归档 bit 与时序报告

## 构建与烧录
```powershell
& td_project/build_colorshading.ps1 -Stage Check -RunName run_v1 -DisableFsmInference -MinRippleLength 16
& td_project/build_colorshading.ps1 -Stage Synthesis -RunName run_v1 -DisableFsmInference -MinRippleLength 16 -AllowGateTimingExploration
& td_project/build_colorshading.ps1 -Stage Implementation -RunName run_v1 -DisableFsmInference -MinRippleLength 16 -AllowGateTimingExploration
```
最新交付：`releases/ispdemo_r5_awbfirst/`（时序全绿，SPI Flash 固化即可上电演示）。
