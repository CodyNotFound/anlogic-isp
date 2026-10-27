# 连接
ISP RAW入口 → raw_lsc_grid4 → 原demosaic → data128_96 → frame_awb4 → color_tone4 → data_96bit_to_128bit → 原DDR/HDMI。
ready沿逆向连接，valid/user/last/data同向逐级延迟。RAW dest经LSC同延迟。不再例化原始扫描awb。顶层引脚和MIPI/DDR/HDMI模块保持。
