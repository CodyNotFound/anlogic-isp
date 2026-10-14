# 快速上手指南

> **状态（2026-10-02）**：SD 卡存档、小车跟随、UDP 推流均已移出参赛演示范围
> （SD/音频 RTL 已摘除，UDP 未接入）；本文已按当前范围修订，旧版本中这三者的
> 演示项与答辩表述作废。摄像头模组 SC520CS 已确认硬件损坏（官方确认），新模组
> 未到。3e28984（含 2d37541 审计整改批、851a87e track_assoc 时序二次修复）之后
> **尚未 TD 构建**，上板验收未完成。资源与风险现状见 `README.md`
> 「当前状态与风险」。

## 一键仿真验证（按优先级）

```bash
cd sim

# 核心功能回归 (~10分钟全部跑完)
bash run_detect_sim.sh all           # 检测+跟踪+运动 → 3个PASS
bash run_sim.sh                      # 效果模式+OSD → 出图
bash run_fx_window_sim.sh            # fx_window_96 数值金标准回归 (iverilog)

# 单项验证
bash run_detect_sim.sh demo         # 检测基础(demo场景)
bash run_detect_sim.sh track        # 跟踪ID连续性(红罐全程ID2)
bash run_detect_sim.sh motion       # 帧差运动检测
bash run_detect_sim.sh video        # 真实视频逐帧检测(建议用步进采样)
bash run_detect_sim.sh cdc          # 双时钟CDC集成

# Python端(秒级)
cd ../host && python test_telemetry.py     # 11/11 PASS
```

前两个为 Windows ModelSim 入口；Mac 侧用 iverilog 直接编译
（tb_isp_modes 先跑 `sim/prep_isp_iverilog.py`）。

## TD构建

1. 打开 `td_project/camera_to_dsi_display.al`（顶层 `design_top_wrapper`，61 文件源集）
2. 直接综合→布局布线→生成比特流。注意：3e28984 整批（审计整改 + track_assoc
   两级流水修复 + 字库 85 字）尚未构建过，本轮结果即为新基线——请记录
   LUT/FF/ERAM/DSP 与 WNS/TNS（尤其 track_assoc 修复后的 MIPI_RX_BYTE_CLK 域
   WNS，验收标准 WNS>0）
3. 预期: ~60条综合警告(官方地板), 1条critical(O_cam_24m时钟输出)
4. 若卡 RUN-8001（ChipWatcher 残留）：关 TD → 删除
   `td_project/camera_to_dsi_display_Runs/` 整目录 → 重开工程

## 上板演示

| 演示项 | 操作 |
|---|---|
| 14种模式切换 | KEY1(D5)下一个 / KEY2(A9)上一个, 底部模式栏显示 `模式:0X 汉字名` |
| 检测+跟踪 | 切到模式11(检测), 目标出现检测框+名称-ID标签 |
| 帧差运动 | 切到模式12(运动), 移动物体白色高亮 |
| 直方图均衡 | 切到模式13(均衡), 暗环境自动提亮 |
| PC上位机 | `python host/telemetry.py --uart COM3`（UART 遥测） |

烧写用 BitWriter：先 SRAM 模式验证，通过后 SPI 固化。

## 接线备注

- UART 已分配：J1-1=V2(TX) / J1-2=V1(RX)，115200
- KEY3=B9 / KEY4=C7（N2/J14 是假按键，勿接）
- UDP RGMII（YT8511）与 125MHz 时钟属"未来可选"，当前未接入；
  引脚表见 README「UDP 网络遥测」节

## 答辩要点

- **基础4/4**: 采集显示+算法+稳定输出+OSD(Logo/CNT/FPS/LAT/模式栏)
- **进阶**: 14 模式实时切换、检测+跟踪标注、帧差运动、直方图均衡、延迟可视化
- **工程创新**: 自研 Scharr 替换官方 Sobel；Scharr 与 3×3 滤波共享窗口引擎
  （单实例省一整套行缓存+前端）；字库/Logo ERAM 化（OSD 存储零 LUT 膨胀）；
  AWB 共享串行除法器（帧级增益）
- **分层话术**: 例程平台（MIPI/DDR/HDMI 基座）+ 自研算法（ISP/检测跟踪/OSD）

旧版本中"UDP 推流 + SD 存档 + 小车跟随"的演示项与答辩创新点表述已随范围
裁定作废（RTL 已摘除/未接入），不要再对外引用。
