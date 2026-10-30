# 完整 YuNet 微调与 FPGA 导出流程

唯一入口为 `pipeline.py`。保持当前完整网络的层数、通道数和算子，不剪枝、不换slim模型。正式项目的权重不会被自动覆盖。

## 安装与执行

建议使用独立 Python 环境（Python 3.10 以上），安装：

```sh
python -m pip install -r scripts/yunet/requirements.txt
python scripts/yunet/pipeline.py all --work .agent/yunet --steps 1000
```

首次自动下载官方原模型、WIDER train/val及标注；固定SHA256校验，支持HTTP断点续传。输出都在指定work中。默认准备4000个训练视场、400个选模视场、800个最终测试视场；完整WIDER压缩包仍会下载。可通过 `--train-samples`、`--val-samples`、`--test-samples`、`--steps`、`--batch`调整。

Mac自动使用MPS，支持CUDA和CPU；可用 `--device`指定。ModelSim可从PATH、MODELSIM_BIN或 `--modelsim-bin`读取；`--verify-rtl require`要求本机完成RTL验证，`auto`在缺少工具时保留pending，`skip`明确跳过。未验证的包不会被标成可进入整机编译。

只检查流程的小规模运行：

```sh
python scripts/yunet/pipeline.py all --work .agent/yunet-smoke --smoke
```

smoke只做8步训练、40/10/10个样本，永远不作为精度验收通过。需要ModelSim时网络逐层仿真耗时明显长于这几步训练。

## 阶段与恢复

| 阶段 | 实际工作 |
| --- | --- |
| download | 下载原ONNX和WIDER，核对固定哈希、安全解压、保留来源及模型许可证 |
| prepare | 按来源/内容隔离集合，生成16:9视场裁剪坐标、框、忽略区和无脸背景；输出预览与校准样本 |
| train | 完整预训练模型小学习率微调；高清增强后执行实际整数8×8块平均；保存模型、优化器及随机状态 |
| quantize | 固定部署激活/输出头量纲的INT8导出；原模型量化必须复现当前正式ROM |
| evaluate | 原版/新模型分别在val/test上执行真实整数LUT单目标解码；不使用NMS，不跳过无脸图 |
| export | tap优先DW布局、四bank权重、bias/shift打包、头偏移、LUT、位宽证明及55层golden成套输出 |
| verify | 用候选权重跑真实150MHz双时钟RTL；逐层核对55个操作的659460个字节 |

例如恢复完整任务，或仅跑某一阶段：

```sh
python scripts/yunet/pipeline.py all --work .agent/yunet --resume
python scripts/yunet/pipeline.py prepare --work .agent/yunet --resume
python scripts/yunet/pipeline.py verify --work .agent/yunet --resume --verify-rtl require
```

恢复会沿用work里的配置，并核对数据、原模型和影响训练的脚本指纹；配置或训练代码改变时必须用新work，避免混用旧检查点。`--eval-every`控制选模频率，`--checkpoint-every`控制恢复间隔。最终test不参与选模。

已有数据可以用 `--downloads <压缩包缓存目录>`、`--data-root <已解压目录>`复用；`--model`允许使用SHA256一致的本地原模型。离线模式 `--offline`要求缓存完整。data-root结构为 `WIDER_train/images`、`WIDER_val/images`、`splits/wider_face_split`。

prepare保存裁剪清单，训练时才读取原图、裁出高清视场并增强，避免复制几千张1280×720图。`prepared/preview`给出实际模型看到的裁剪，`prepared/calibration`是无增强的定点校准样本。小脸、模糊或不完整标注保留为忽略区；只有与全部人脸标注不相交的裁剪才作为明确无脸背景。

## 输出及使用边界

`work/fpga/`包含：

- `rtl/analytics/face_cnn/`：完整匹配的权重、program、头偏移、sigmoid/offset/size LUT、packed bias/shift及解包头；不能只换weights。
- `sim/cnn/data/network_reference/`：一幅输入和全部55层golden。
- `candidate.onnx`、训练与整数评测报告、位宽证明、来源、SHA256清单。
- `verify.py`：只需Python标准库与ModelSim即可在另一台电脑独立验证。
- `status.json`：明确smoke、样本量、指标、RTL是否通过，以及是否可进入新的整机编译。

标为可进入整机编译的前提：非smoke、测试集至少200个有脸视场和100个无脸视场、候选在val/test上通过非退化阈值且RTL通过。非退化容差分别是precision降低不超过0.015、有脸命中率降低不超过0.02、无脸误接纳率升高不超过0.025；这些是初始工程门槛，不是统计显著改善证明。实际指标均保留，坏模型也会保留资源以便排查，但不标为合格。

资源包不是bit文件。新的整机资源、最终路由时序及实物效果仍须另验。公开WIDER的预处理近似板端图像，不等于已经完成真实SC500CS域适配；实际墙面/灯光和人物视频还需要上板验证。训练样本的噪声、曝光与色偏增强是近似模型，不伪装成真实摄像头数据。

## 来源与验证

原模型来自 [OpenCV Zoo](https://huggingface.co/opencv/opencv_zoo/tree/main/models/face_detection_yunet)，模型SHA固定；数据来自 [CUHK-CSE WIDER Face](https://huggingface.co/datasets/CUHK-CSE/wider_face)，固定版本和三个压缩包SHA记录在download.py。原始数据不打进FPGA资源包。

```sh
python -m unittest discover -s scripts/yunet/tests -v
```

输入、输出与量化细节见 [DEPLOYMENT.md](DEPLOYMENT.md)。`yunet_torch.py`、定点数学核心和ROM调度保留已验证实现；下载、数据、训练、评测及阶段编排已重写并统一接口。
