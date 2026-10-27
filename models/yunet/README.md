# YuNet official pretrained model

Source: https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet

File: face_detection_yunet_2023mar.onnx

SHA256: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4

Retrieved 2026-10-25. MIT license retained verbatim in LICENSE. upstream_yunet.py is the original OpenCV Zoo adapter, retained for provenance, not deployed on the board.

scripts/yunet_integer.py prunes only unused landmark outputs, preserves all detection heads, and lowers the full graph to integer arithmetic. The official original model remains unmodified. The generated graph uses 160×96 BGR input (160×90 camera image plus six zero rows). Development probes calibrate and evaluate on the same small image collection; no independent accuracy claim.

Run with requirements.txt on the Python path: yunet_integer.py, yunet_dot_vectors.py, yunet_decode_vectors.py, yunet_schedule.py. Hardware uses the exported ROMs and does not use OpenCV/ONNX Runtime.
