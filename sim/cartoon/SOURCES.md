# 赛璐璐测试输入

四张照片使用本仓库已有的lena.jpg、fruits.jpg、grace_hopper.jpg、figurine.jpg，来源与署名见../face_lbp/SOURCES.md。手办照片作者Duong Tran Dinh，CC BY 2.0，沿用该文件的原始来源链接及署名。

照片经等比缩放、填充、整数滤镜生成测试向量与对比图；不是本项目自行拍摄，也不是识别准确率或真实视频质量数据集。921600个640×360像素逐值比对与原生720p链路测试只验证给定输入的算法与RTL一致。

色阶、色差边界、噪声、纯黑/纯白及梯度探针由scripts/cartoon_v41_reference.py确定性生成。无需下载数据、训练模型或运行外部推理程序。
