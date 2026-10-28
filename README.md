# anlogic-isp

基于安路 HX1P35A / PH1P35MDG324 的端侧视觉云台。SC500CS 经 MIPI CSI-2 输入 RAW10，FPGA 完成 ISP、DDR 缓存、视觉定位与两轴 PWM 控制，HDMI 输出 1280×720@60 Hz。在线推理不依赖电脑或 MCU。

## 目录

| 目录 | 内容 |
| --- | --- |
| `rtl/app`、`rtl/control` | 系统集成、按键、串口屏与云台 |
| `rtl/isp`、`rtl/overlay` | 色彩校正、图像效果、OSD |
| `rtl/analytics` | 人脸网络、模板、颜色区域与运动检测 |
| `rtl/hardware` | 摄像头 ISP、DDR、HDMI、厂商 IP 和引脚约束 |
| `rtl/vendor` | 工程使用的官方平台核心及来源说明 |
| `td_project` | `anlogic-isp.al` 与 `anlogic-isp.sdc` |
| `scripts` | 当前构建、校准、字库与回归入口；校准数据位于 `scripts/calibration` |
| `sim`、`models` | 当前回归及参考数据、模型与许可证 |

## 构建与验证

使用 TD 6.2.168116；将 TD 的 bin 目录加入 PATH。仿真使用 ModelSim Altera 10.3c，ISP/DDR 回归还需将其 bin 目录加入 PATH。Python 工具按需使用 numpy、Pillow；校准和字库工具不会在正常综合时运行。

```powershell
./scripts/check_project.ps1
./scripts/build.ps1 -Stage Check
./scripts/build_verified.ps1 -DisableFsmInference -AllowSlicePackingProbe
./scripts/run_tests.ps1 -Tests controls,tracking,tone,osd,network,reliability,gimbal,isp,ddr
```

完整构建自动依次运行 Check、Synthesis、Implementation 和最终时序/资源校验。默认使用时间戳生成独立运行目录；若分阶段执行，必须传入同一个 `-RunName anlogic-isp_runs_...`。顶层模块仍为 `design_top_wrapper`，项目及输出文件名为 `anlogic-isp`。

构建输出位于 `td_project/anlogic-isp_runs_*/`，状态位于 `build/verification/`，仿真输出位于 `reports/`，均被 Git 忽略。`scripts/archive_build.py <RunName>` 只归档通过最终时序的构建。`scripts/build_font.py` 使用保留的像素字模；`scripts/export_calibration.py` 重新导出当前校准表。运行这两个生成工具会修改综合输入，需要重新构建。

## 功能与操作

00～14：色彩还原、灰度、反色、二值、增亮、锐化、模糊、边缘、浮雕、卡通、换色、人脸、模板、色区、固定机位运动检测。人脸采用定点 YuNet，其他分析任务互斥共享片上存储。

| 控件 | 功能 |
| --- | --- |
| SW1 / SW2 | 白平衡、曝光自动更新或锁定 |
| SW3 | 自动云台跟随 |
| SW4 | 四键切换为方向控制 |
| K4 / K3 / K2 / K1（方向） | 左 / 下 / 上 / 右 |
| K1 / K2（普通） | 下一 / 上一模式 |
| K4（普通） | 模板/颜色取样；运动模式重建参考 |

方向键临时接管，松开等待新定位恢复自动；目标丢失保持位置。串口屏可切模式、设置开关和方向，本地实体操作可接回控制权。

水平 PWM：J1-1（C18）；俯仰 PWM：J1-2（D15）；公共地 J1-12。舵机独立 6 V 供电。串口屏 TX 接 J1-3（E12，FPGA RX），RX 接 J1-4（E16，FPGA TX）；采用兼容 3.3 V 的信号电平、115200 8N1，屏幕按规格独立供电。

## 历史与验证边界

开发文档及通过版基线包见标签 `archive/pre-final-cleanup-20261028`。目录整理前源码和全部旧工具见 `archive/pre-layout-cleanup-20261028`，可用 `git restore --source=<标签> -- <路径>` 恢复指定文件。

原优化候选 v74_widget_r1 的最终时序未通过（setup WNS -0.122 ns、TNS -0.200 ns），不能作为通过版；通过版 `stable_controls_baseline` 的 bit、源码和证据在前述清理前历史的 `releases/` 中。目录检查、功能仿真、最终路由时序和实物显示是独立验证步骤。

## 主线与安全复核

本地开发统一到 `main`；整合没有生成 merge 提交。各旧分支原始提交保存在 `archive/consolidate-20261028/*` 标签，原工作树和外部构建证据保留。

PowerShell 入口使用 UTF-8 BOM，已在 Windows PowerShell 5.1 实测解析和执行。AE 数据先于事件发布，目的端延迟消费；PLL/外部复位按各时钟域异步断言、同步释放。FIFO 复位例外覆盖事件桥及视频 FIFO，不豁免 Gray 指针路径。零移位已有显式分支，构建时校验模型移位为 0..31；原始零移位饱和的报告未在仿真中复现。

`calibrate_lsc.py` 改为接收经验证的 720x1280 RAW10 `.npy`，生成与当前 17x13 BGGR 网格兼容的标定数组；不再从手机拍显示器的照片生成未接入的 `lsc_corr` 模块。生成后先检查，再显式更新室内/补光标定文件和导出表，不自动改写 RTL。

新构建 `anlogic-isp_runs_20261028_main_safety_r1` 使用独立源码快照；旧 layout 的 Check 不是当前版本的 P&R 证据。完成验证必须具备路由 timing/exception 报告、STA 覆盖率、最终 setup/hold、资源、输入 SHA256 与 bit 校验。保留 coverage 数值不等于声称未约束路径为零；最终结果以 `build/verification/` 中对应完整 RunName 的 completion.json 为准。
