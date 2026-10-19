# Phase 1 架构

## 目标

先跑通一条不可破坏的官方基线：

```text
SC500CS
  -> 2-lane MIPI D-PHY RX
  -> CSI-2 unpacket
  -> RAW10 unpacket
  -> ISP（BLC/demosaic/AWB）
  -> DDR2 frame buffer / clock crossing
  -> HDMI timing / TMDS TX
```

视频模式固定为 SC500CS 1280x720@60fps，HDMI 有效区为 1280x720。第一阶段不切换 1080p30，不改 MIPI PHY、DDR、PLL 和 HDMI 物理层。

## 当前模块化边界

- `rtl/app/design_top_wrapper.v`：唯一板级顶层，连接平台层和项目应用层，不放算法实现。
- `vendor_reference/rtl/vendor_lab1_core.v`：官方平台核心，负责摄像头、MIPI、ISP、DDR、HDMI 时序和 HDMI TX；通过明确的 HDMI 像素域边界与应用层连接，禁止在此加入新的算法逻辑。
- `rtl/app/vision_pipeline.v`：项目自有视频处理层，负责模式控制、算法、Logo 和 HDMI 合成。
- `rtl/control/mode_ctrl.v`：K1/K2 消抖和算法模式状态机（模块名仍为 `algorithm_mode_ctrl`）。K1 循环原图/二值化/灰度/边缘，K2 切换原图/卡通化。
- `rtl/isp/pixel_algorithm.v`：RGB 直通、基于 BT.601 Y 分量的灰度、二值化、3x3 Sobel 边缘和色彩量化卡通化输出。
- `rtl/overlay/logo_overlay.v`：官方安路 Logo 叠加，位于算法输出之后，因此所有算法模式都显示 Logo。
- `rtl/overlay/anlogic_logo_rom.v`：从 Lab3 OSD 例程复制的 Logo ROM。
- `rtl/platform/`：平台相关封装与后续板级适配代码；不放算法业务逻辑。
- `rtl/config/vision_config.vh`：分辨率、功能开关等项目级配置的唯一来源。
- `rtl/control/switch_ctrl.v`：SW1-SW4 的同步、消抖和持续电平使能；拨码为低有效，拨到某方向后保持状态。
- `rtl/isp/auto_exposure.v`：应用层逐帧 Y 统计和数字微调；统计通过稳定总线/翻转事件跨到 24 MHz 摄像头域。
- `user_source/hdl_source/uiisp_beta/ae_set.v`：AE 控制器（增益表现为 SC520），按帧亮度优先调整曝光时间，再调整模拟增益，数字增益负责最后的小范围补偿。
- `user_source/hdl_source/uics520_cfg/uicfgcs520.v`：SC520CS 初始化和 AE 寄存器写回状态机（2026-10-08 自 lab3 合入，含传感器 ID 校验，ID 非 0xee4b/0x9e4b 时停在 ST_ERROR 不配置）。
- `rtl/isp/auto_white_balance.v`：应用层逐帧 RGB 自动白平衡，依据上一帧有效亮度区间内的通道均值调整 R/B 增益；黑场、过曝像素和样本不足帧不参与增益更新。
- `rtl/isp/histogram_equalizer.v`：基于上一帧 256 级灰度直方图生成 LUT，按帧更新，避免同帧统计和回读冲突。
- `rtl/overlay/adaptive_brightness.v`：HDMI mixer 后的显示端自适应亮度，仅修改最终显示像素。
- 应用层灰度、直方图、AE 和显示端亮度统一使用无乘法器移位加法实现的 BT.601 full-range Y：`Y=(77R+150G+29B)>>8`。
- `rtl/common/video_stream_if.vh`：自研模块之间的视频流接口约定。
- `user_source/hdl_source/uics520_cfg/`：SC520CS I2C 配置和 720p60 寄存器表（本合并工程使用；uics500_cfg 仅剩共用的 uii2c.v）。
- `user_source/hdl_source/mipi_dphy_rx/`：PH1P35 MIPI 接收 IP/封装。
- `user_source/hdl_source/isp/`：CSI/RAW10 解包、去马赛克和颜色处理。
- `user_source/hdl_source/isp/raw_black_level_correction.v`：RAW10 四路黑电平校正钩子，默认旁路；必须先用遮光实测每路偏置再启用。
- `user_source/hdl_source/ph1p35_ddr/`：DDR2 控制器及 PHY。
- `user_source/hdl_source/video_in.v`、`video_out.v`：帧缓存读写。
- `user_source/hdl_source/vtc/uivtc.v`、`hdmi_mixer.v`、`hdmi_tx.v`：HDMI 时序和发送。
- `user_source/constraints_source/pin.adc`：HX1P35A 引脚约束。

官方底层文件仍保留在 `user_source/hdl_source/`，因为这些文件包含 TD/IP 生成依赖；板级单体顶层已经移入 `vendor_reference` 并改名为 `vendor_lab1_core`。像素域比赛功能通过明确端口边界接入 `vision_pipeline`，现在由 `design_top_wrapper` 直接连接平台层和应用层，不再直接堆在官方核心的算法段中。

## 关键时钟域

| 时钟 | 用途 |
|---|---|
| `I_sys_clk` / `sys_clk_50m` | 顶层、控制和 PLL 输入 |
| `S_100m_clk` | MIPI LP/控制 |
| `S_24m_clk` | SC500 EXTCLK 和 I2C |
| `S_csi_rx_clk` | MIPI/CSI/RAW10/ISP 输入链 |
| `S_ddr_clk` | DDR2 用户接口和视频帧缓存 |
| `S_hdmi_pixel_clk` | HDMI 720p 像素时序 |
| `S_hdmi_serial_clk` | HDMI 串行发送 |

跨时钟域只能通过官方 FIFO、DDR 帧缓存或明确的同步器完成。不要把一个时钟域的 `valid` 直接送到另一个时钟域。

## 调试模式

`vision_config.vh` 当前将 `VISION_DEBUG_MODE` 设置为 `0`，默认输出摄像头画面。临时定位 HDMI 问题时可以改为 `1`（彩条）或 `3`（四段链路状态条），重新综合并生成 `.bit`；调试完成后恢复为 `0`。

## 按键算法模式

按键为低有效，约束对应 HX1P35A 四键图。当前只使用 K1/K2，K3/K4 保留：

```text
上电        -> 彩色原图
K1(D5)      -> 原图 -> 二值化 -> 灰度 -> 边缘 -> 原图（循环）
K2(A9)      -> 原图 <-> 卡通化
K2 在二值化/灰度/边缘状态 -> 原图
K1 在卡通化状态 -> 原图
K3(B9)      -> 当前版本预留
K4(C7)      -> 当前版本预留
```

算法处理位于 HDMI 像素时钟域，输出时序沿用官方视频读出链；MIPI、DDR、HDMI PHY 不改动。

## SW1-SW4 功能拨码

按键与拨码已经分离：原有 `I_button[3:0]` 保持 D5/A9/B9/C7，用于 K1-K4 按键；新增 `I_switch[3:0]` 使用 SW1=A4、SW2=B4、SW3=E11、SW4=D11。逻辑按低有效持续电平解释：

```text
SW1 / I_switch[0]：完整自动曝光（传感器曝光时间/模拟增益 + 数字微调）
SW2 / I_switch[1]：数字自动白平衡
SW3 / I_switch[2]：逐帧直方图均衡
SW4 / I_switch[3]：HDMI 最终输出自适应亮度
```

本次逻辑不再把 I_button[0:1] 传给旧的手动 AE 按键模块，避免按键状态被误解释为重复调节事件。底层官方 ISP 中已有的 AWB 仍属于平台基线；SW2 控制的是应用层的可选补偿，不修改 MIPI/ISP/DDR/HDMI PHY。SW1 的亮度统计来自摄像头画面，跨到 24 MHz I²C 域后才发起 SC500 寄存器更新。
