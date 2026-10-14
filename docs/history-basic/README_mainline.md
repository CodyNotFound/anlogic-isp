# fpgachina_basic_all — 赛题一基础要求整合工程

基于官方 example（lab_ex3_osd 为基底 + lab_ex2_edge 算法模块）合并而成，
一个工程同时覆盖赛题一全部 4 条基础要求，并扩展为 **14 个可切换模式 + 完整 OSD**：

| 基础要求 | 实现方式 |
|---|---|
| 1. MIPI 采集 + HDMI 实时显示 | SC520CS 摄像头 720P@60 → MIPI D-PHY RX → ISP → DDR → HDMI |
| 2. FPGA 图像处理算法 | **14 个模式**按键实时切换（见下表），模式 7 使用自研 Scharr |
| 3. 处理结果稳定输出 | 处理后视频经 DDR 帧缓存输出 HDMI，画面连续 |
| 4. OSD 信息叠加 + 安路 Logo | 安路 Logo + 帧计数器 + FPS/延迟 + 底部半透明模式栏 |

## 当前状态与风险（2026-10-02）

- 资源真实基线：**综合 LUT 18,178**（5c4924f 焊死全功能后基线 18,666，经
  dbcb828 SD 摘除 + 9163c00 引擎合并/音频摘除共 -488）。旧文档中的
  25,406 / 18,718 / 12,677 均为过时口径，勿再引用。
- SD 卡链路与音频链已整体摘除（参赛范围裁定 SD 不算入演示）；UDP 协议栈
  源码保留但已移出 `.al` 编译集，属未来可选（见下文 UDP 节）。
- 2026-10-02 审计整改批（2d37541）已修复：字库地址截断、检测框坐标恒 0、
  CNT 段错位、FPS 行尾多字、模式栏下重影、udp_telemetry 双驱地雷、bypass
  臂延迟不对齐、LAT 换算位宽回绕，并清死文件/死 reg；851a87e 完成
  track_assoc 两级流水时序修复；3e28984 字库扩至 85 字（"识别"二字预留
  模式 14 MNIST 用）。**这一整批尚未经过 TD 构建**——track_assoc 的
  "MIPI_RX_BYTE_CLK 域 WNS>0" 待综合确认。
- 摄像头模组 SC520CS 硬件损坏（官方确认），新模组未到；此前为排色做的
  GBRG 改写 / gamma 例化已回退（现为 BGGR + 无 gamma）。
- 上板验收未完成，已烧写的旧 bit 不含新字库与新排版。

## 算法模式表（KEY1 下一个 / KEY2 上一个，循环 0~13）

| 模式 | OSD名 | 算法 | 实现文件 |
|---|---|---|---|
| 0 | 原图 | 原始图像直通 | — |
| 1 | 灰度 | 灰度（r/4+g/2+b/4 免乘法） | `isp/pixel_fx_96.v` |
| 2 | 反色 | 反色 | `isp/pixel_fx_96.v` |
| 3 | 二值 | 二值化（阈值 96） | `isp/pixel_fx_96.v` |
| 4 | 增亮 | 亮度 +32 饱和 | `isp/pixel_fx_96.v` |
| 5 | 锐化 | 锐化（2*中心-8邻域均值） | `isp/fx_window_96.v`（I_fx_sel=1） |
| 6 | 模糊 | 3×3 均值模糊 | `isp/fx_window_96.v`（I_fx_sel=0） |
| 7 | 边缘 | Scharr 边缘检测（自研，非官方 Sobel） | `isp/fx_window_96.v`（I_fx_sel=3） |
| 8 | 浮雕 | 浮雕（中心-左上+128） | `isp/fx_window_96.v`（I_fx_sel=2） |
| 9 | 复古 | 复古棕调（移位加权矩阵） | `isp/pixel_fx_96.v` |
| 10 | 换色 | RGB 通道轮换 | `isp/pixel_fx_96.v` |
| 11 | 检测 | 目标检测（颜色分割 + blob + 跟踪标注） | `detect/color_seg_96.v` + `detect/blob_detect_96.v` + `detect/track_assoc.v` |
| 12 | 运动 | 帧差运动检测（1/32 网格历史帧） | `isp/motion_fx_96.v` |
| 13 | 均衡 | 直方图均衡（跨帧统计 + 映射表） | `isp/hist_eq_96.v` |

3×3 类滤波与 Scharr 共用一个窗口引擎 `isp/fx_window_96.v`（9163c00 将
filter3x3_96 / edge_scharr_96 两个逐行同构的模块合并为单实例，`I_fx_sel`
选择施算器），前端与官方例程同构：免除法器亮度近似 + 两行 BRAM 缓存，
每 4 像素 beat 取 2 个灰度采样对，结果复制回对应像素对。上电默认模式 7（边缘）。
fx_window_96 合并正确性有数值金标准回归兜底：`tb/tb_fx_window.v`
（4584 拍 0 失配，`bash sim/run_fx_window_sim.sh`）。

## 使用方法

1. 用 TD 6.2.x 打开 `td_project/camera_to_dsi_display.al`（器件 PH1P35MDG324，
   与 example 一致；61 个 File 条目）。
2. 综合 → 布局布线 → 生成比特流，烧写到 HX1P35A 开发板
   （BitWriter 先 SRAM 验证，通过后 SPI 固化）。
3. 上电默认显示**边缘检测**画面（含 Logo、计数器、FPS/延迟与底部模式栏 OSD）。
4. **KEY1（D5）** 切到下一个模式，**KEY2（A9）** 切到上一个，循环 0~13；
   切换在帧边界同步生效；底部模式栏同步显示 `模式:0X 汉字名`
   （14 个模式全部配两字中文名）。

## OSD 布局（287a3ea + f4b3578：原生 16px 像素字排版）

- 左上：160×160 Logo 窗口（实际墨迹 146×94）。Logo 与字库均走 ERAM：
  `logo_rom_bram.v`（索引 + 调色板两级 ERAM）、`osd_font_bram.v`
  （16×16 字模 ERAM，85 字符，含中文 45 字；"识别"二字预留模式 14 MNIST），
  mif 与 .v 同目录。
- Logo 右侧文字列（x=176，与 Logo 对齐，24px 行距）：
  `安路 CNT:xxxxxx` 帧计数行（120×16）；`FPS:xx`（绿）/ `LAT:xxxMS`（橙）
  两行状态区（72×36）。
- 底部（y≈686 起）：全宽半透明暗底模式栏，`模式:0X 汉字名`
  20 格 × 8 宽文字居中。

## 相对官方 example 的改动（git 历史可追溯）

1. `baseline` — 官方 lab_ex3_osd 原样复制
2. 合入 lab_ex2 边缘检测 + KEY1 切换（I_edge_en 版本），后替换为自研 Scharr
3. 模式扩到 0~13：新增 `pixel_fx_96.v`、`fx_window_96.v`（锐化/模糊/浮雕/Scharr
   共享窗口引擎）、`motion_fx_96.v`、`hist_eq_96.v` 与 `detect/` 检测跟踪五件套；
   `isp_top.v` 改为 `I_mode[3:0]` 多路处理后帧同步 MUX；pin.adc 增 KEY2=A9
4. OSD 像素化重做：ERAM 字库与 Logo、原生 16px 排版、中文模式名
5. AWB 重写为共享串行除法器 + 帧级增益（`user_source/hdl_source/awb.v`）
6. 范围裁剪：SD 卡链路（dbcb828）、音频链（9163c00）整体摘除；
   UDP 栈移出编译集（源码保留）
7. 审计整改批（2d37541）：修复 OSD 六项高危 bug 与 bypass/LAT 隐患、
   清死文件死代码、补 fx_window 数值 TB 与 ERAM 仿真模型；
   字库扩 85 字为模式 14（MNIST 识别，开发中）预留

## 目录结构

```
user_source/hdl_source/     ← 全部综合 RTL（含 detect/ 检测跟踪五件套；mif 与 .v 同目录）
sim/                        ← 既有仿真资产：tb_*.v + detect_demo_top.v + 数据/脚本/日志
  run_sim.sh                ← 算法/OSD 仿真（Windows ModelSim 入口）
  run_detect_sim.sh         ← 检测/跟踪/运动仿真（demo|video|cdc|track|motion|all）
  run_fx_window_sim.sh      ← fx_window_96 数值金标准回归（iverilog）
  data/ pics/ out/          ← 场景与视频帧数据 / 输出图 / 仿真输出 hex（gitignore）
tb/                         ← 新增独立 TB（tb_fx_window.v 等，2d37541 起）
td_project/                 ← TD 工程（.al / .sdc + syn_run.tcl 等脚本）
rtl/                        ← 工作流 skill 产物（top_skeleton.sv，非 TD 构建入口）
tools/                      ← OSD 字库/logo 资产流水线（mk_font.py、logo_editor.html 等）
doc/                        ← 工作流产物：intake / arch / spec / compile / hw / refs
docs/                       ← 旧文档 + 摄像头资料（QUICKSTART、SC520CS 手册与 lab zip）
host/                       ← PC 端脚本（telemetry.py 在用；sd_reader.py 属已摘除的 SD 链）
car/                        ← 小车跟随 C 代码（已裁定范围外，留作参考）
sc520_base/                 ← 官方例程新基线快照（96cda05）
```

## 仿真出图（无板演示真实 RTL 效果）

`sim/` 目录是一套仿真出图流程，不需要板卡即可向老师/评委展示
FPGA 代码的真实处理输出（非软件模拟算法）：

```bash
cd sim
bash run_sim.sh            # 全流程: 转图->算法仿真->OSD仿真->出图 (约6分钟)
bash run_sim.sh effects    # 只跑效果模式（当前覆盖 0~10）
bash run_sim.sh osd        # 只跑 HDMI 输出画面(Logo/OSD/模式栏)
```

- 依赖：ModelSim（Windows，`[LOCAL_PATH]`）+ Python Pillow；
  Mac 侧用 iverilog 直接编译（tb_isp_modes 先跑 `sim/prep_isp_iverilog.py`）
- 输入图 `sim/anlogic_logo.png`（安路官方宣传图 1280×720，可换任意图片）
- 产出（`sim/pics/`）：
  - `effects_montage_big.png` —— 效果模式对比大图（4×3，按 11 模式设计，
    模式 11~13 的检测/运动/均衡画面走 `run_detect_sim.sh` 出图）
  - `osd_00..10.png` —— 完整 HDMI 输出帧（Logo + 计数器 + FPS/LAT + 模式栏）
- testbench：`tb_effects.v`（通路与 isp_top AWB 后并行结构一致）、
  `tb_osd.v`（uivtc 720P 时序 + 完整 hdmi_mixer）。FPS 统计窗口在仿真下用
  `+define+SIM_SHORT_FPS` 缩短（`hdmi_mixer.v` 内 ifdef 保护，综合不受影响）。

## 注意

- KEY1/KEY2 为异步输入，工程内已有三拍同步 + 消抖，无需时序约束。
- `I_button[1:0]` 保留给曝光调节（ae_set），未占用。
- 若 TD 打开工程时提示文件时间戳异常（future time），重新保存工程即可。
- 新增源文件务必在 TD 工程 Sources 里可见（`camera_to_dsi_display.al` 已登记
  `fx_window_96.v` 等全部活跃源）；若 TD 报 black box，检查工程是否重新加载。
- ChipWatcher 残留导致 RUN-8001 卡死时：关 TD → 删除
  `td_project/camera_to_dsi_display_Runs/` 整目录 → 重开工程。

## UDP 网络遥测（未来可选，当前未接入）

`user_source/hdl_source/udp/` = 例33协议栈移植（uiudp_stack 全家桶 + 软 FIFO）+
`udp_telemetry.v`（自研）。**当前已整体移出 `.al` 编译集，顶层无实例、不占
资源**；其 initial+always 多重驱动问题已在 2d37541 修复。已验证部分与恢复
步骤备查：

- TX：检测遥测帧 `AA 55 mode n id cx cy ex ey seq xor 0D`；RX：UDP 指令帧
  `A5 <mode> <~mode> 5A` 远端切模式（与 UART 指令同语义）
- 契约级仿真 `sim/tb_udp_tel.v` PASS（两帧字段 + 补码 + XOR 全对）；
  GMII 全链路 `sim/tb_udp_gmii_wip.v`（ARP 握手 + 全包解析）调试中，
  上板终验用 Wireshark
- 恢复步骤：TD 重配 u_PLL 增 125MHz（+90° 相移，RGMII TX 用）→ YT8511
  RGMII 引脚（MDC=V9 MDIO=U10 RESET_N=V8 TXCLK=U9 RXD0-3=N9/T7/T8/T9
  TXD0-3=R11/P11/T10/R12 TXEN=R10 RXC_DV=N8）→ 顶层例化 rgmii_interface +
  uiphyrst + uiudp_stack + udp_telemetry（连线参考 `sim/tb_udp_gmii_wip.v`）→
  PC 端 192.0.2.1:6002 ↔ 192.0.2.1:6001
