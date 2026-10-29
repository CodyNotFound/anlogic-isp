# 可选 YuNet 训练工具

此目录整理保留既有原拓扑训练、ONNX 导出和量化工具。最终程序仍使用已验证的 ROM，本轮未训练、未更换权重。

依赖：PyTorch、onnx、onnxruntime、opencv-python-headless、numpy；WIDER Face 数据须放在仓库外。`train.py` 支持 CPU/CUDA/MPS，`export_onnx.py` 只写模型参数。

这些训练工具尚未对当前优化后的 DW tap-major ROM 布局做完整迁移，不能把 `schedule.py` 的旧布局输出直接覆盖当前硬件 ROM。评测器还沿用旧统计口径，不作为最终版的精度验收依据。将来换权重前必须补齐无人脸误检评测、布局转换、18/20 位累加范围、打包检查、55 层 RTL 一致性及整机编译；当前目录不执行自动换装。
