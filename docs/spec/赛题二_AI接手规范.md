# 安路赛题二 FPGA 工程架构：AI 接手规范

版本：v1.0（2026-09-12）

## 0. 项目身份

- 赛题：2026 安路 FPGA 创新设计赛道，选题二：基于 PH1P35 的实时数字图像处理系统。
- 板卡：HX1P35A，器件 PH1P35MDG324。
- 输入：SC500CS，2-lane MIPI CSI-2，首选 RAW10、1280x720@60fps。
- 输出：HDMI 1280x720@60Hz。
- 官方基线：`lab_ex1_mipi_hdmi_SC500_720P`。
- 参考扩展：`lab_ex2_edge_SC500_720P`（边缘检测）、`lab_ex3_osd_SC500_720P`（OSD）。

## 1. 给新 AI 的最短上下文

先读本文件，再按以下顺序读取：

1. `[LOCAL_PATH]`
2. `[LOCAL_PATH]`
3. Lab1 的 `工程结构与功能说明.md`
4. Lab1/2/3 的 `td_project\camera_to_dsi_display.al`
5. 当前项目的 `docs\architecture.md`、`docs\verification.md`、`docs\change-impact.md`

不要先遍历整个资料库，也不要先读 TD 生成的 DDR/MIPI 加密源码。

## 2. 仓库目标目录

建议仓库名：`anlogic-ph1p35-vision`。

```text
anlogic-ph1p35-vision/
├─ README.md
├─ LICENSE
├─ .gitignore
├─ .gitattributes
├─ docs/
│  ├─ architecture.md
│  ├─ verification.md
│  ├─ change-impact.md
│  ├─ bringup.md
│  └─ decision-log.md
├─ rtl/
│  ├─ top/                 # 只放系统集成与顶层端口
│  ├─ platform/            # MIPI、SC500、HDMI、DDR、PLL 封装
│  ├─ stream/              # 视频流协议、宽度转换、CDC、FIFO
│  ├─ isp/                 # 灰度、BLC、demosaic、AWB、Sobel、颜色检测
│  ├─ analytics/           # 帧差、目标框、坐标、计数、统计
│  ├─ overlay/             # OSD、Logo、字体、状态栏
│  ├─ control/             # 按键消抖、模式状态机、参数寄存器
│  └─ common/              # reset、延时、计数器、通用包
├─ ip/
│  ├─ pll/ ddr/ fifo/      # 只保存可重生成 IP 的源文件和参数
│  └─ README.md
├─ constraints/
│  ├─ hx1p35a_pin.adc
│  └─ timing_720p60.sdc
├─ sim/
│  ├─ unit/                # 模块级仿真
│  ├─ integration/         # 视频链路仿真
│  └─ filelist/
├─ scripts/
│  ├─ export_sources.ps1
│  ├─ check_project.ps1
│  └─ gen_test_pattern.ps1
├─ assets/
│  ├─ fonts/ logos/ test_images/
│  └─ README.md
├─ reports/
│  ├─ timing/ area/ bringup/
│  └─ .gitkeep
└─ vendor_reference/
   └─ README.md            # 只记录官方例程位置，不把整套资料复制入仓库
```

## 3. 分层原则

### 3.1 不可随意改动层

`rtl/platform/mipi`、`rtl/platform/ddr`、`rtl/platform/hdmi`、`ip/` 中由 TD/IP 工具生成的文件属于平台层。除非重新生成 IP 或修复明确错误，不手改加密文件、PHY、DDR 校准逻辑和门级网表。

### 3.2 可复用基础层

`rtl/stream`、`rtl/common` 提供统一接口、CDC、FIFO、复位和计数。所有新算法只通过这些接口接入，不能直接在顶层堆寄存器。

### 3.3 赛题功能层

`rtl/isp`、`rtl/analytics`、`rtl/overlay` 是比赛创新功能。每个功能一个目录、一个顶层模块、一个仿真入口、一个 README，允许独立启停。

### 3.4 集成层

`rtl/top/design_top_wrapper.v` 只做时钟、复位、模块例化和信号连线。禁止在顶层编写 Sobel 算法、字符 ROM、复杂计数和长段时序逻辑。

## 4. 推荐数据通路

```text
SC500 I2C/27MHz
      │
MIPI D-PHY RX（官方）
      │
CSI-2 unpacket → RAW10 unpacket
      │  raw_pixel_stream
ISP：BLC → demosaic → AWB → RGB888
      │  video_stream
┌─────┴──────────────┐
│                    │
算法旁路/处理链       统计链
gray/Sobel/color      frame-diff/box/count/fps/latency
│                    │
└──────→ overlay compositor ←──────┘
                    │
              video_in → DDR2
                    │
              DDR2 → video_out
                    │
              HDMI timing/TX
```

默认采用“每像素一拍、有效信号随数据延迟”的流式结构。需要行缓存或帧缓存的模块必须在接口文档中注明延迟、缓存深度和 back-pressure 行为。

## 5. 统一视频流接口契约

所有自有算法模块优先使用以下端口命名：

```verilog
input  wire        clk;
input  wire        rst_n;
input  wire        s_valid;
input  wire        s_sof;       // 帧首，与第一个有效像素对齐
input  wire        s_eol;       // 行尾，与最后一个有效像素对齐
input  wire [23:0] s_data;      // RGB888，R[23:16],G[15:8],B[7:0]
output wire        s_ready;
output wire        m_valid;
output wire        m_sof;
output wire        m_eol;
output wire [23:0] m_data;
input  wire        m_ready;
```

如果官方模块没有 ready/valid，使用 `valid + sof + eol + 固定延迟` 的适配器，不要把两种协议混在同一模块内部。每次新增流水级，必须同时延迟 `valid/sof/eol/x/y`。

## 6. 模块边界与命名

- 顶层：`vision_system_top` 或保留官方 `design_top_wrapper`，只允许一个系统顶层。
- 摄像头配置：`sc500_cfg_720p60`；1080p30 作为独立 profile，不覆盖 720p60。
- ISP：`isp_pipeline`。
- 算法：`vision_sobel`, `vision_color_detect`, `vision_frame_diff`。
- OSD：`overlay_compositor`, `overlay_font_rom`, `overlay_status_panel`。
- 控制：`mode_ctrl`, `param_bank`, `key_filter`。
- 状态：统一后缀 `_busy/_valid/_ready/_sof/_eol/_overflow/_underflow`。

不要使用含义不清的 `temp1`、`data_new`、`flag2`、`test_module` 作为长期信号名。

## 7. 功能开关和参数

所有可选能力集中到一个配置文件或参数表，不在多个模块散落魔法数字：

```verilog
localparam ENABLE_SOBEL       = 1;
localparam ENABLE_COLOR_DET   = 1;
localparam ENABLE_FRAME_DIFF  = 1;
localparam ENABLE_OSD         = 1;
localparam IMG_WIDTH          = 1280;
localparam IMG_HEIGHT         = 720;
localparam PIXEL_BITS         = 24;
```

运行时参数通过 `param_bank` 管理：算法模式、阈值、目标颜色、OSD 开关、框线颜色、调试模式。按键只产生事件，不直接修改算法内部寄存器。

## 8. 变更规则

### 只改算法

只改 `rtl/isp` 或 `rtl/analytics`，先做模块仿真，再接入集成工程。不得同时改 PLL、MIPI、DDR、HDMI。

### 只改 OSD

只改 `rtl/overlay` 和 `assets/fonts`。OSD 输入使用 HDMI 像素坐标或与 `video_out` 同步的坐标，不回写 DDR。

### 改分辨率/帧率

必须同时检查：SC500 寄存器表、MIPI 带宽、RAW10 解包、ISP 宽高、DDR 帧地址、HDMI 时序、PLL、SDC、仿真尺寸。完成 `resolution-change` 检查表后才能合并。

### 改开发板引脚

只改 `constraints/`，并在 PR 中附上开发板版本、原理图页码和实测电平。禁止直接复制 HX1P35B 引脚到 HX1P35A。

## 9. 验证门禁

每个 PR 至少通过：

1. 静态检查：无未使用端口、宽度截断、组合环、锁存器警告。
2. 单元仿真：算法模块覆盖正常、边界、复位、帧首/行尾。
3. 集成仿真：720p 测试图输入后，`sof/eol/valid` 数量正确。
4. 综合：无 error；关键时钟全部有约束。
5. 实板：连续运行 ≥30 分钟；发布候选版本 ≥2 小时。
6. 记录：fps、延迟、丢帧、FIFO 水位、资源占用、时序裕量。

任何黑屏、花屏、FIFO 溢出、MIPI 错包、时序负裕量都不能以“偶尔能显示”作为通过。

## 10. GitHub 规范

分支：`main` 只放可复现版本；`develop` 集成；功能使用 `feature/<name>`；问题使用 `fix/<name>`；硬件/时序使用 `hw/<name>`。

提交格式：`<scope>: <imperative summary>`，例如：

```text
platform: lock SC500 720p60 baseline
isp: add pipelined sobel edge path
overlay: add fps and fifo status panel
sim: add frame-boundary assertions
docs: record MIPI bring-up result
```

PR 必须写明：目的、修改文件、接口变化、仿真证据、实板证据、资源/时序变化、回滚方法。生成物默认不提交：`*_Runs/`、`log/`、临时波形、用户目录绝对路径、编译缓存。保留可复现的 `.al`、约束、IP 参数和脚本。

## 11. AI 修改安全协议

AI 在动手前必须回答：

1. 当前问题属于平台、流、算法、OSD、控制还是约束层？
2. 目标模块的输入输出时钟域是什么？
3. `valid/sof/eol/data` 是否同拍对齐？
4. 是否需要行缓存、帧缓存或 CDC？
5. 失败时如何回退到官方 Lab1 基线？

AI 不得：

- 重写官方 MIPI/DDR/HDMI 复杂链路；
- 未读 `.al` 就假设文件会参与综合；
- 只把文件放进目录而不更新 TD 工程源文件列表；
- 在多个模块复制 `1280/720`、阈值和时序魔法数字；
- 未跑仿真和综合就宣称“已完成”；
- 删除官方基线或覆盖可工作的分支。

## 12. 推荐开发顺序

`baseline` → `gray` → `sobel` → `osd` → `color_detect` → `frame_diff` → `mode_ctrl` → `metrics` → `stability`。

每一步都要能单独编译、下载、演示和回滚。高阶功能延期时，基础链路仍可作为比赛交付版本。

## 13. 官方例程映射

| 官方例程 | 可复用内容 | 接入位置 |
|---|---|---|
| Lab1 | MIPI、I2C、RAW10、ISP、DDR、HDMI、约束 | `platform/` |
| Lab2 | `edge_detect_96.v` 及 ISP 接线方式 | `isp/` |
| Lab3 | `osd_char_lib.v` 与 HDMI mixer 字符叠加 | `overlay/` |
| `example\\32_cs500_mipi_hdmi` | 完整 SC500 MIPI→HDMI 参考 | 只作比对，不直接污染主线 |

## 14. 接手后的第一轮检查命令

```powershell
rg -n "module |IMG_WIDTH|IMG_HEIGHT|edge_detect|osd_char|video_in|video_out|hdmi_mixer" rtl
rg -n "UsedInSyn|AutoExcluded|design_top_wrapper" *.al td_project
git status --short
```

输出任何结论时，区分“官方文件明确写出”“从例程连接推断”“尚未实测”。
