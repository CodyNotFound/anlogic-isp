# 模块划分
raw_lsc_grid4负责RAW67减黑及四相位固定小表；现有BGGR去马赛克保持；frame_awb4替换扫描AWB，更新统一的下一帧全局增益；color_tone4负责轻量去紫边、颜色和固定显示曲线。isp_top保持外部接口并串联这些模块。显示应用层AWB、HE、自适应亮度关闭，避免重复处理；AE/模式/OSD沿用。
