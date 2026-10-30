# 项目工具

通常只用两个入口：`build_verified.ps1` 构建并检查时序；`run_tests.ps1` 执行仿真（`-List` 查看分组）。PowerShell 用于编排 Windows 上的 TD 与 ModelSim，Python 用于资源、数据和模型处理。

| 子目录 | 职责 |
| --- | --- |
| build | 分阶段编译、工程检查、时序审核、交付归档 |
| simulation | 当前分组仿真与像素比较，共享 ModelSim 调用逻辑 |
| resources | 字库生成和 Logo 预览 |
| calibration | 镜头平场标定、色彩表导出与检查 |
| cnn | ROM 打包、累加范围和周期分析 |
| yunet | 可选离线训练、评测、量化和导出；不参与当前在线推理 |
| common | 工具发现与项目根目录定位 |

仓库通过自身位置定位文件，不依赖特定用户名或桌面目录。Python、TD、ModelSim 从 PATH 或 PYTHON_EXE、TD_BIN、MODELSIM_BIN 获取。当前电脑的安装位置只写入被忽略的 `.agent/local.ps1`。日志、缓存均写入 `.agent/build`。

最终板上使用官方 YuNet 预训练权重的定点实现，经过并行化和流水优化；没有使用自行微调的权重。正式版尚未替换；完整微调流程使用yunet/pipeline.py，候选资源单独导出和验收。
