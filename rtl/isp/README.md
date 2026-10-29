# ISP与图像效果

当前发布配置采用采集侧RAW/RGB四像素流水线与HDMI域单像素效果流水线。

| 文件 | 当前用途 |
| --- | --- |
| `raw_lsc_grid4.v`、`colorshading_lut_case.vh` | RAW10黑电平、17×13镜头阴影标定；相邻像素共享插值乘法 |
| `switchable_awb4.v`、`frame_awb4.v` | 两级同步与帧首锁定、白平衡增益和自动更新/锁定 |
| `color_tone4.v`、`colorshading_gamma_case.vh` | 色彩校正、饱和度、Gamma与亮度计算 |
| `auto_exposure.v` | 亮度统计及供传感器控制使用的跨域事件；不同于已移除的AB |
| `pixel_algorithm.v`、`pixel_cartoon.v` | 00～10图像模式，包括彩色锐化/模糊、边缘、浮雕、赛璐璐卡通 |
| `auto_white_balance.v`、`histogram_equalizer.v` | 应用层旧处理级；当前常量关闭，仍提供RGB寄存延迟，不能作为无引用文件直接删除 |

实际前级连接见 `rtl/hardware/hdl_source/isp/isp_top.v`，显示域连接见 `rtl/app/vision_pipeline.v`。当前AB已经移除，主白平衡保留自动/锁定控制。

验证入口为 `scripts/run_tests.ps1` 的 `isp`、`tone`、`effects`、`reliability` 分组。优化前参考源保留在 `sim/reference`，仅用于逐值比较，不参与综合。
