# OSD逻辑

最终显示合成入口是 `rtl/hardware/hdl_source/hdmi_mixer.v`，并使用本目录的状态与云台绘制逻辑。字体、安路Logo及BRAM初始化文件集中在 `assets/`。

本次整理仅搬迁资源和测试文件，没有重绘字体、Logo或修改布局。像素回归位于 `sim/osd/`，通过 `scripts/run_tests.ps1 -Tests osd` 执行。
