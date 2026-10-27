# 模型与测试图片来源

仅作为算法开发的本地测试集。样本很少，不是准确率基准，未核查是否与旧模型训练数据重合。

- `models/frontal.xml`: OpenCV 4.12.0 的 `data/lbpcascades/lbpcascade_frontalface.xml`。
  https://github.com/opencv/opencv/blob/4.12.0/data/lbpcascades/lbpcascade_frontalface.xml
  OpenCV 项目许可证 https://github.com/opencv/opencv/blob/4.12.0/LICENSE 。
- `models/anime.xml`: nagadomi 的 `lbpcascade_animeface`，XML 内含完整 MIT 许可证。
  https://github.com/nagadomi/lbpcascade_animeface 。本地模型 SHA256 见 `reports/face_lbp/model_sha256.json`。
- `data/lena.jpg`, `data/messi5.jpg`, `data/fruits.jpg`: OpenCV 4.12.0 samples/data 原文件。
  https://github.com/opencv/opencv/tree/4.12.0/samples/data
  不应将这些样例图视作项目自行拍摄、无版权限制或独立测试数据。
- `data/grace_hopper.jpg`: Matplotlib v3.9.2 的 `lib/matplotlib/mpl-data/sample_data/grace_hopper.jpg`。
  https://github.com/matplotlib/matplotlib/blob/v3.9.2/lib/matplotlib/mpl-data/sample_data/grace_hopper.jpg
  https://github.com/matplotlib/matplotlib/blob/v3.9.2/LICENSE/LICENSE 。
- `data/figurine.jpg`: **KanColle Nendoroid - Kirishima**，摄影 Duong Tran Dinh，2021-03-25。
  https://commons.wikimedia.org/wiki/File:KanColle_Nendoroid_-_Kirishima.jpg
  原文件 https://upload.wikimedia.org/wikipedia/commons/4/43/KanColle_Nendoroid_-_Kirishima.jpg
  CC BY 2.0，https://creativecommons.org/licenses/by/2.0/ 。
  测试派生图转换为灰度、等比缩放并填边，结果图另绘检测框和注释。摄影者未背书本项目。

`*.hex` 是图片灰度像素，不包含人工坐标。`*.expected` 是软件全图搜索产生的
全部候选窗口，用于核对 RTL；`*.target` 是候选合并的整数参考结果。
人工标注在 `scripts/face_lbp_report.py`，仅用于事后评估，不参与识别算法。

LBP 位序与左右分支遵循 OpenCV `modules/objdetect/src/cascadedetect.hpp`；
加载阈值的 1e-5 容差遵循 `cascadedetect.cpp` 的 THRESHOLD_EPS。
特征几何缩放和候选合并是本项目实现，不能宣称与 OpenCV detectMultiScale 全流程等价。
