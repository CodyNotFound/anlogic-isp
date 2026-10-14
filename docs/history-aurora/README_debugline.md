# Anlogic PH1P35 Vision

安路 2026 FPGA 创新设计赛道题二的正式工程。第一阶段目标是从 SC500CS 摄像头采集 1280x720@60fps 视频，经 MIPI CSI-2、RAW10/ISP、DDR2 帧缓存后，通过 HDMI 输出。

## 当前状态

- 阶段：Phase 1 - 官方平台基线 + 项目自有像素处理层
- 目标器件：`PH1P35MDG324`
- 开发板：HX1P35A
- 摄像头：SC500CS，2-lane MIPI CSI-2，RAW10
- 输出：HDMI，1280x720@60Hz
- 算法模式：K1 循环原图/二值化/灰度/边缘，K2 切换原图/卡通化
- 功能拨码：SW1 自动曝光、SW2 应用层自动白平衡、SW3 逐帧直方图均衡、SW4 HDMI 输出自适应亮度
- 顶层：`design_top_wrapper`
- TD 工程：`td_project/camera_to_dsi_display.al`

## 快速开始

1. 安装安路 Tang Dynasty TD 6.2.168116 或兼容版本。
2. 按官方 JTAG 文档安装 WinUSB，并确认 `hwserver.exe` 位于 TD 安装目录的 `bin` 中。
3. 在 TD 中打开 `td_project/camera_to_dsi_display.al`。
4. 确认器件为 `PH1P35MDG324`、顶层为 `design_top_wrapper`。
5. 执行 Synthesis，再执行 Physical Design/Place & Route。
6. 在 `td_project/camera_to_dsi_display_Runs/phy_1/` 找到新生成的 `.bit`。
7. 用 BitWriter 选择 `PROGRAM_SRAM` 下载验证；确认稳定后再生成 Flash 文件。

拨码功能按低有效持续电平工作，拨到一侧后保持使能，不会自动返回。原有按键 `I_button[3:0]` 仍使用 D5/A9/B9/C7；新增拨码端口 `I_switch[3:0]` 使用 SW1=A4、SW2=B4、SW3=E11、SW4=D11。

## 目录说明

`td_project/` 和 `user_source/` 保持安路 TD 相对路径兼容。`rtl/`、`sim/`、`scripts/` 和 `reports/` 保存项目自有模块、仿真和验证内容；不要为了“目录好看”复制或重命名官方平台 IP。

详细说明见：

- `docs/architecture.md`：第一阶段数据通路和模块边界
- `docs/build.md`：从源码重新编译和下载
- `docs/verification.md`：仿真、综合、实板验收标准
- `docs/change-impact.md`：修改分辨率、算法、约束时的影响范围

## 官方参考资料

官方例程和资料保存在 `[LOCAL_PATH]`，本仓库只记录来源，不复制整套资料。参考 Lab1/2/3 的说明见 `vendor_reference/README.md`。
