// Final application top-level.
//
// Board pins stay stable while the implementation is split into:
//   vendor_reference : factory MIPI/ISP/DDR/HDMI implementation
//   rtl              : project-owned extension points and application logic
// This wrapper contains board wiring plus the explicit platform/application
// video boundary. Platform IP remains isolated in vendor_lab1_core; project
// algorithms remain isolated in vision_pipeline.
module design_top_wrapper (
    input wire        I_sys_clk,
    input wire        I_rst_n,
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
    inout  wire [3:0] I_button,
    input  wire [3:0] I_switch,
    output wire       O_screen_pwm,
    output wire       O_servo_h, O_servo_v,
    output wire [3:0] O_led,
    output wire [7:0] O_seg, O_sel,
    output wire       O_buzz,               // 板载蜂鸣器(C12), 按键哔一声反馈
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,
    inout  wire       IO_rx_clk_pad_n,
    inout  wire       IO_rx_clk_pad_p,
    inout  wire [3:0] IO_rx_data_pad_n,
    inout  wire [3:0] IO_rx_data_pad_p,
    output wire [12:0] ddr_addr,
    output wire [1:0]  ddr_ba,
    output wire [0:0]  ddr_cke,
    output wire [0:0]  ddr_odt,
    output wire [0:0]  ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire [0:0] ddr_ck_p,
    output wire [0:0] ddr_ck_n,
    inout  wire [1:0] ddr_dm,
    inout  wire [15:0] ddr_dq,
    inout  wire [1:0] ddr_dqs_p,
    inout  wire [1:0] ddr_dqs_n
);

    wire        hdmi_pixel_clk;
    wire        hdmi_rst_n;
    wire        hdmi_vsync;
    wire        hdmi_hsync;
    wire        hdmi_de;
    wire        hdmi_sof;
    wire        hdmi_eol;
    wire [3:0]  hdmi_debug_status;
    wire [23:0] video_rd_data;
    wire        video_rd_en;
    wire        hdmi_out_vsync;
    wire        hdmi_out_hsync;
    wire        hdmi_out_de;
    wire [23:0] hdmi_out_data;
    wire [7:0]  hdmi_ae_stat_y;
    wire        hdmi_ae_stat_toggle;
    wire [3:0]  isp_demo_sel;               // {demo_active, step[2:0]}

    // Platform layer: camera, MIPI, ISP, DDR frame buffer, HDMI timing, and
    // HDMI TX. It does not contain project-owned pixel algorithms.
    vendor_lab1_core u_vendor_pipeline (
        .I_sys_clk(I_sys_clk), .I_rst_n(I_rst_n),
        .O_cam_scl(O_cam_scl), .IO_cam_sda(IO_cam_sda),
        .O_cam_24m(O_cam_24m), .O_cam_rst(O_cam_rst),
        .I_ae_enable(O_led[1]),
        .I_awb_enable(1'b1),
        .I_isp_demo(isp_demo_sel),
        .I_ae_stat_y(hdmi_ae_stat_y),
        .I_ae_stat_toggle(hdmi_ae_stat_toggle),
        .I_button(I_button), .O_screen_pwm(O_screen_pwm),
        .O_tmds_ch0_p(O_tmds_ch0_p), .O_tmds_ch1_p(O_tmds_ch1_p),
        .O_tmds_ch2_p(O_tmds_ch2_p), .O_tmds_clk_p(O_tmds_clk_p),
        .O_hdmi_pixel_clk(hdmi_pixel_clk), .O_hdmi_rst_n(hdmi_rst_n),
        .O_hdmi_vsync(hdmi_vsync), .O_hdmi_hsync(hdmi_hsync),
        .O_hdmi_de(hdmi_de), .O_hdmi_sof(hdmi_sof), .O_hdmi_eol(hdmi_eol),
        .O_hdmi_debug_status(hdmi_debug_status),
        .O_video_rd_data(video_rd_data), .I_video_rd_en(video_rd_en),
        .I_hdmi_vsync(hdmi_out_vsync), .I_hdmi_hsync(hdmi_out_hsync),
        .I_hdmi_de(hdmi_out_de), .I_hdmi_data(hdmi_out_data),
        .IO_rx_clk_pad_n(IO_rx_clk_pad_n), .IO_rx_clk_pad_p(IO_rx_clk_pad_p),
        .IO_rx_data_pad_n(IO_rx_data_pad_n), .IO_rx_data_pad_p(IO_rx_data_pad_p),
        .ddr_addr(ddr_addr), .ddr_ba(ddr_ba), .ddr_cke(ddr_cke),
        .ddr_odt(ddr_odt), .ddr_cs_n(ddr_cs_n), .ddr_ras_n(ddr_ras_n),
        .ddr_cas_n(ddr_cas_n), .ddr_we_n(ddr_we_n), .ddr_ck_p(ddr_ck_p),
        .ddr_ck_n(ddr_ck_n), .ddr_dm(ddr_dm), .ddr_dq(ddr_dq),
        .ddr_dqs_p(ddr_dqs_p), .ddr_dqs_n(ddr_dqs_n)
    );

    // Application layer: mode control, pixel algorithms, Logo, and HDMI
    // composition. It runs in the platform-provided HDMI pixel clock domain.
    vision_pipeline u_vision_pipeline (
        .clk             (hdmi_pixel_clk),
        .rst_n           (hdmi_rst_n),
        .switches_n      (I_switch),
        .buttons_n       (I_button[3:0]),
        .video_vsync     (hdmi_vsync),
        .video_hsync     (hdmi_hsync),
        .video_de        (hdmi_de),
        .video_sof       (hdmi_sof),
        .video_eol       (hdmi_eol),
        .debug_status    (hdmi_debug_status),
        .pixel_in        (video_rd_data),
        .pixel_rd_en     (video_rd_en),
        .video_vsync_out (hdmi_out_vsync),
        .video_hsync_out (hdmi_out_hsync),
        .video_de_out    (hdmi_out_de),
        .pixel_out       (hdmi_out_data),
        .frame_stat_y    (hdmi_ae_stat_y),
        .frame_stat_toggle(hdmi_ae_stat_toggle),
        .isp_demo_sel(isp_demo_sel),
        .servo_pwm_h(O_servo_h),.servo_pwm_v(O_servo_v),
        .panel_leds(O_led),.panel_segments(O_seg),.panel_selects(O_sel)
    );

    // 板载蜂鸣器: 任意K1-K4按下沿哔~30ms@2.7kHz (板上SW5为物理使能开关, 低有效无源)
    buzz_ctrl #(.CLK_HZ(75_000_000)) u_buzz_ctrl (
        .I_clk   (hdmi_pixel_clk),
        .I_rst_n (hdmi_rst_n),
        .I_keys  (~I_button),
        .I_strobe(1'b0),
        .O_buzz  (O_buzz)
    );
endmodule
