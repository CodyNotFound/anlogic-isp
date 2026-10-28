# 安芯智视视觉跟踪云台系统

基于HX1P35A / PH1P35MDG324的FPGA视觉工程。SC500CS双通道MIPI CSI-2输入RAW10，经ISP与DDR2后输出1280×720@60 Hz视频，并驱动两轴云台。

## 功能与操作

ISP支持黑电平、17×13网格LSC、BGGR去马赛克、白平衡、色调和自动曝光。00～10依次为色彩还原、灰度、反色、二值、增亮、锐化、模糊、边缘、浮雕、卡通、换色；11人脸CNN、12模板、13色区、14固定机位运动。分析任务互斥共享片上存储。

| 控件 | 功能 |
| --- | --- |
| SW1 / SW2 | 白平衡、曝光自动更新或保持当前参数 |
| SW3 | 自动云台跟随使能 |
| SW4 | 四键用途切换，开启后K4/K3/K2/K1为左/下/上/右 |
| K1 / K2 | 非方向用途时下一/上一模式 |
| K4 | 模板/色区取样，运动模式重建参考 |

方向键临时接管，松开等待新的定位恢复自动；目标丢失保持指令位置。可选串口屏支持模式、功能与方向控制，本地仍可接管。公开模型与许可证保留在models/yunet。

## 构建与验证

TD入口为td_project/camera_to_dsi_display.al，顶层design_top_wrapper。保持rtl、user_source、td_project和vendor_reference相对目录。

```powershell
./scripts/run_td_verified.ps1 -RunName colorshading_runs_20261027_verify -DisableFsmInference -AllowSlicePackingProbe
./scripts/run_hmi_v72.ps1
```

每次使用新的RunName，源码快照、资源与最终建立/保持时序必须通过检查。主线迁入时128个构建输入与原通过归档逐字节一致：Slice20855/21216、RAM108/108、DSP39/40，setup+0.005ns、hold+0.020ns，TNS均0。原构建证据、目标目录重新构建与实物验证分别记录。

bit、数据库、仿真工作库和报告外部归档，不入源码历史。后续优化候选在独立分支验证。

## 工程目录

`rtl/` 为应用、控制和图像算法；`user_source/` 为摄像头、原始数据 ISP、DDR、HDMI 和厂商 IP。两者共同构成当前工程，不能互相替代。`vendor_reference/rtl/vendor_lab1_core.v` 是仍参与综合的平台核心。模型、ROM 初始化与许可证保留在原路径。

## 接线

水平 PWM：J1-1（C18）；俯仰 PWM：J1-2（D15）。两只舵机使用独立 6 V 电源，与 J1-12 共地。串口屏 TX 接 J1-3（E12，FPGA RX），RX 接 J1-4（E16，FPGA TX）；串口信号须兼容 FPGA 的 3.3 V 电平，屏幕按其规格独立供电。

## 历史与交付边界

过程文档、旧发布包和报告已从当前树移除。清理前完整资料见 Git 标签 `archive/pre-final-cleanup-20261028`；例如可用 `git restore --source=archive/pre-final-cleanup-20261028 -- doc docs reports releases` 恢复。

构建状态和时序结果新写入 `build/verification/`，不再混入文档目录；仿真脚本按需生成 `reports/`。清理没有更改 RTL、约束、模型或 ROM 数据，不代表新的综合或板上验收。

当前优化候选 v74_widget_r1 的最终时序未通过（setup WNS -0.122 ns、TNS -0.200 ns），不得当作通过版交付。通过版 `stable_controls_baseline` 的源码、bit 与证据保存在上述历史标签的 `releases/` 中。
