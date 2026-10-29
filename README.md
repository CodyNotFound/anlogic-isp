# anlogic-isp

基于安路HX1P35A / PH1P35MDG324的端侧视觉云台。SC500CS经MIPI CSI-2输入RAW10，FPGA完成色彩处理、DDR缓存、人脸定位、模板/颜色跟踪、运动检测及两轴PWM控制，HDMI输出1280×720@60Hz，无需电脑参与在线推理。

## 当前发布配置

基线提交 `41149e4`，验证运行 `anlogic-isp_runs_20261029_cnn_vector_timing_r5_ripple24`：原模型YuNet、CNN150MHz、视频75MHz，AB移除，串口屏与人脸补帧关闭。完整55层659460字节逐值一致，10095464周期，计算耗时67.303ms。最终路由setup +0.101ns、hold +0.020ns，TNS均为0；19467/21216 Slice、107/108 ERAM、36/40 DSP。实物效果须单独上板确认。

已交付bit位于主仓库 `build/test_bits/20261029/original150_vector_r5_aboff_verified.bit`，源码与构建证据位于通过版工作树的 `releases/anlogic-isp_runs_20261029_cnn_vector_timing_r5_ripple24/`。这些生成物不进入Git；保留其校验值和匹配源快照。清理前内容可从提交 `41149e4` 恢复。

## 目录

| 目录 | 内容 |
| --- | --- |
| rtl/app、rtl/control | 应用集成、按键、云台与状态控制 |
| rtl/isp、rtl/overlay | 色彩校正、图像效果、OSD字模 |
| rtl/analytics | CNN、模板、颜色区域、运动分析及共享存储 |
| rtl/hardware、rtl/vendor | 摄像头、DDR、HDMI、厂商IP与引脚约束 |
| td_project | anlogic-isp.al、anlogic-isp.sdc |
| scripts | 构建、时序验证、校准、字库和当前回归入口 |
| sim、models | 当前测试、独立参考/夹具、模型与许可证 |

## 构建与验证

使用TD 6.2.168116与ModelSim Altera 10.3c；将TD bin加入PATH。ModelSim可由PATH或MODELSIM_BIN指定。校准/字库与OSD像素比较按需使用numpy、Pillow。

```powershell
./scripts/check_project.ps1
./scripts/build_verified.ps1 -DisableFsmInference -AllowSlicePackingProbe -MinRippleLength 24
./scripts/run_tests.ps1 -List
./scripts/run_tests.ps1 -Tests all
```

构建依次执行Check、Synthesis、Implementation、最终时序/资源/约束及输入哈希验证。分阶段构建须使用同一个RunName。TD命令错误即使返回0也会拒绝通过。输出分别进入 `td_project/anlogic-isp_runs_*/`、`build/verification/`；仿真输出统一为 `build/sim/`，详细分组见 [sim/README.md](sim/README.md)。只用 `scripts/archive_build.py <RunName>` 归档通过版。

`build_font.py`与`export_calibration.py`会修改综合输入；执行后须重新构建。优化参考源只供仿真，不加入TD工程。目录整理后通过135项源快照检查，可确认与r5 bit匹配的RTL、ROM及约束未变化。

## 操作

模式00～14：色彩还原、灰度、反色、二值、增亮、锐化、模糊、边缘、浮雕、卡通、换色、人脸、模板、色区、固定机位运动检测。主白平衡在ISP前级执行；普通色彩模式保留原色彩链输出。

| 控件 | 功能 |
| --- | --- |
| SW1 / SW2 | 白平衡、曝光自动更新/锁定 |
| SW3 | 自动云台跟随 |
| SW4 | 四键切换为方向控制；空闲时不阻止自动跟随 |
| K4 / K3 / K2 / K1（方向） | 左 / 下 / 上 / 右 |
| K1 / K2（普通） | 下一 / 上一模式 |
| K4（普通） | 模板/颜色取样；运动模式重建参考 |

方向键临时接管，松开后由新定位恢复自动；目标丢失保持位置。PWM：J1-1/C18水平，J1-2/D15俯仰，J1-12公共地；舵机独立6V供电。水平500～2500µs，俯仰900～2150µs（用户确认的现装配范围）。当前固件未启用串口屏。
