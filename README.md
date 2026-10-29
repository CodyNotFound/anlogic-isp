# anlogic-isp

基于安路 HX1P35A / PH1P35MDG324 的端侧视觉云台。SC500CS 经 MIPI 输入 RAW10，FPGA 完成色彩校正、图像处理、人脸定位、模板与颜色跟踪、运动检测及两轴控制，HDMI 输出 1280×720@60Hz。

## 最终程序

采用已通过整机布线的完整 YuNet 模型，CNN 150MHz，视频 75MHz；AB 移除，串口屏与人脸补帧关闭。推理 10,095,464 周期（67.303ms）；Slice 19,467/21,216，ERAM 107/108，DSP 36/40；最终 setup +0.101ns、hold +0.020ns，TNS 均为零。上板效果单独验证。

目录整理保留原硬件、模型 ROM 与约束的字节内容，仅调整资源路径；已有 bit 对应整理前的源快照。独立交付与验证证据保存在项目旁的 `../anlogic-isp-artifacts/verified/`，其中 `anlogic-isp.bit` 的 SHA256 为 `1E283535A59DB5BE81D14AC453A63832E15D0F3DBB4B7EF955EFB62BBCD80D90`。旧工作树的 Git 提交、未提交文件和必要构建证据在该目录的 `recovery/` 中，不放入最终源目录。

## 目录

| 目录 | 用途 |
| --- | --- |
| rtl | 应用、ISP、检测跟踪、OSD 逻辑、厂商接口及 IP |
| assets | 模型及许可证、字模、Logo、ROM 初始化文件与色彩校准数据；ROM 包装器与 MIF 同目录以保持 TD 的文件解析方式 |
| scripts | 构建、仿真、字库/Logo生成、校准及ROM工具；yunet子目录保留可选训练导出工具 |
| sim | 按 cnn、isp、osd、control、tracking、video 分组的当前测试及独立参考 |
| td_project | 仅工程与时序约束 |
| .agent | 临时监视器与可重建输出：TD 中间文件、仿真缓存和日志；全部不入 Git |

## 构建与验证

使用 TD 6.2.168116、ModelSim Altera 10.3c 和 Windows PowerShell 5.1。Python 工具按需使用 numpy、Pillow。

```powershell
./scripts/build/check_project.ps1
./scripts/build_verified.ps1 -DisableFsmInference -AllowSlicePackingProbe -MinRippleLength 24
./scripts/run_tests.ps1 -List
./scripts/run_tests.ps1 -Tests all
```

TD 输出统一在 `.agent/build/td/`，仿真输出在 `.agent/build/sim/`；构建记录在 `.agent/build/verification/`。通过最终时序、资源、约束和源哈希检查后，用 `python scripts/build/archive_build.py <RunName>` 保存交付到项目外。不能仅凭进程退出码判定通过。`scripts/resources/build_font.py`、`scripts/calibration/export_calibration.py` 会修改综合输入，执行后须重新构建。

## 操作

模式 00～14：色彩还原、灰度、反色、二值、增亮、锐化、模糊、边缘、浮雕、卡通、换色、人脸、模板、色区、固定机位运动检测。

| 控件 | 功能 |
| --- | --- |
| SW1 / SW2 | 白平衡 / 曝光自动更新与锁定 |
| SW3 | 自动云台跟随 |
| SW4 | 四键作为方向键；空闲不阻止自动跟随 |
| K4 / K3 / K2 / K1（方向） | 左 / 下 / 上 / 右 |
| K1 / K2（普通） | 下一 / 上一模式 |
| K4（普通） | 模板、颜色取样或重建运动背景 |

目标丢失保持位置。PWM：J1-1/C18 水平、J1-2/D15 俯仰、J1-12 公共地，舵机独立 6V 供电。水平 500～2500µs，俯仰 900～2150µs（用户确认的当前装配范围）。
