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

## 文档

- [迁入记录](doc/history/README.md)
- [技术文档](doc/submission/01_技术文档初稿.md)
- [视频拍摄](doc/submission/02_视频拍摄与剪辑大纲.md)
- [按键与接线](doc/submission/04_按键交互与简明接线.md)
- [五点可行性](doc/submission/05_五点关键点可行性与数据口径.md)

官方平台来源见vendor_reference/README.md。
