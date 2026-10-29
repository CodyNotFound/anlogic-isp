# YuNet 模型来源

本目录保存官方预训练模型 `yunet.onnx` 及其 MIT 许可证，来源为 OpenCV Zoo 的 face_detection_yunet。SHA256：`8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`。

最终板上权重来自这个预训练模型的 INT8 定点导出，没有采用自行微调的权重。FPGA 侧部署完整检测网络，输入为 160×96 BGR；在线推理不需要 OpenCV 或电脑。

- `scripts/yunet/`：可选离线训练、评测、量化和导出工具；与最终权重分开管理。
- `scripts/cnn/`：当前硬件使用的 ROM 打包、累加范围检查和计算周期分析。
- `rtl/analytics/face_cnn/`：当前已验证的硬件和配套 ROM 初始化数据。

`upstream_yunet.py` 保留上游接口参考，不在 FPGA 上执行。当前作品的优化包括并行计算、流水线和存储调度，不能据此称模型权重为自行训练。