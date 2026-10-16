`ifndef VISION_CONFIG_VH
`define VISION_CONFIG_VH
// Single source of truth for application-level video settings.
`define VISION_WIDTH       1280
`define VISION_HEIGHT       720
`define VISION_PIXEL_BITS    24
`define VISION_ENABLE_PIPELINE 1
`define VISION_ENABLE_EDGE    1
`define VISION_ENABLE_OSD     1
`define VISION_BINARY_THRESHOLD 8'd96
`define VISION_EDGE_THRESHOLD   11'd80
`define VISION_DEBUG_MODE       0
`define VISION_ENABLE_AUTO_EXPOSURE 1
`define VISION_ENABLE_AUTO_WHITE_BALANCE 1
`define VISION_ENABLE_HISTOGRAM_EQUALIZER 1
`define VISION_ENABLE_ADAPTIVE_BRIGHTNESS 1
// Frame-global adaptive threshold for binary mode.
`define VISION_BINARY_ADAPTIVE 1
`define VISION_BINARY_BIAS     8
`endif
