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
./scripts/run_tests.ps1 -Tests controls,tracking,tone,osd,network,isp,ddr
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
