# 当前版本仿真

入口：`scripts/run_tests.ps1`（Windows PowerShell 5.1）。不保留独立版本号入口、无串口屏版本未启用的HMI/补帧测试或重复旧网络回归。

```powershell
./scripts/run_tests.ps1 -List
./scripts/run_tests.ps1 -Tests cnn-unit,effects,controls,reliability
./scripts/run_tests.ps1 -Tests network,dual-clock
./scripts/run_tests.ps1 -Tests isp -FullFrame
./scripts/run_tests.ps1 -Tests all
```

| 分组 | 检查范围 |
| --- | --- |
| tone / effects | 全RGB亮度恒等式、色彩/Gamma/背压；卡通/边缘/锐化/模糊/浮雕与边界同步 |
| isp | AWB、LSC逐值一致；实际ISP及视频入队的帧前导与背压；FullFrame扩展到720行 |
| cnn-unit | ROM解包、地址、18位DW量化、MAC流水/20位累加、向量Pool/Resize/Add、解码 |
| network | 当前150MHz原模型55层、659460个激活字节逐值比较，同时记录实际周期 |
| dual-clock | 时钟桥、64KiB共享arena、实际头扫描、运动/颜色/模板共享内存与重捕 |
| controls | 当前CNN150、HMI关闭、补帧关闭配置下的实体按键、手动优先/自动恢复及普通模式延迟 |
| tracking / reticle | 运动、颜色区域身份与中心取样标记；模板出窗重捕仅在dual-clock组执行一次 |
| osd | 实际字体和安路Logo、五帧逐像素参考、云台位置映射及状态稳定 |
| reliability / gimbal / ddr | I2C时钟使能、AE跨域/复位、零移位、PWM行为、DDR握手/背压 |

所有输出放入 `.agent/build/sim/<测试名>/`，每项保留编译日志、仿真日志和输入SHA256。编译要求零错误、零警告，仿真要求零错误和明确PASS；项目自有代码不允许警告。ISP/DDR仅允许 `vendor_fifo_warnings.json`、`vendor_isp_warnings.json` 中按源SHA256、警告编号及端口名核实的厂商FIFO和去马赛克RAM既有告警，原始日志和逐条告警均保留；不使用全局屏蔽。退出码0不足以判定通过。可用 `MODELSIM_BIN` 指定ModelSim目录。

`reference/`是当前逐值验证依赖的独立参考实现，`cnn/data/network_reference/`是原模型参考数据，`osd/reference/`是像素参考。它们不能按“旧文件”删除。头扫描夹具由 `cnn/check_head_offsets.py` 在执行双时钟回归前生成到build目录。

功能回归、综合、最终路由时序与上板效果分别验证。目录整理本身不改变已归档r5的RTL、ROM和约束。
