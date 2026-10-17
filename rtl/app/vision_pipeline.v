`include "../config/vision_config.vh"
// Project-owned processing layer in the HDMI pixel clock domain.
// The platform owns MIPI, ISP, DDR, timing, and HDMI TX. This block owns
// runtime mode control, pixel algorithms, overlay, and display composition.
module vision_pipeline #(
    parameter integer IMG_WIDTH = `VISION_WIDTH,
    parameter integer IMG_HEIGHT = `VISION_HEIGHT,
    parameter integer ENABLE_PIPELINE = `VISION_ENABLE_PIPELINE,
    parameter integer ENABLE_EDGE = `VISION_ENABLE_EDGE,
    parameter integer ENABLE_OSD = `VISION_ENABLE_OSD,
    parameter integer DEBUG_MODE = `VISION_DEBUG_MODE
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  switches_n,
    input  wire [3:0]  buttons_n,        // K1..K4 active-low
    input  wire        video_vsync,
    input  wire        video_hsync,
    input  wire        video_de,
    input  wire        video_sof,
    input  wire        video_eol,
    input  wire [3:0]  debug_status,
    input  wire [23:0] pixel_in,
    output wire        pixel_rd_en,
    output wire        video_vsync_out,
    output wire        video_hsync_out,
    output wire        video_de_out,
    output wire [23:0] pixel_out,
    // Stable frame statistic for the sensor-domain AE controller.  The
    // toggle is the CDC event; frame_stat_y remains unchanged between events.
    output wire [7:0]  frame_stat_y,
    output wire        frame_stat_toggle,
    // ISP step-demo select {demo_active, step[2:0]}: sensor-domain chain runs
    // the staged demo (0 raw gray .. 6 full chain); normal modes keep full chain.
    output wire [3:0]  isp_demo_sel
);
    wire [3:0] mode;
    wire [3:0] effective_mode;
    wire       demo_active;
    wire [2:0] demo_step;
    wire [3:0] feature_enable;
    wire [23:0] algorithm_pixel;
    wire [23:0] exposure_pixel;
    wire [23:0] white_balance_pixel;
    wire [23:0] equalized_pixel;
    wire [23:0] overlay_pixel;
    wire [23:0] status_pixel;
    wire [23:0] mixed_pixel;
    wire [23:0] brightness_pixel;
    wire [7:0]  auto_exposure_stat_y;
    wire        auto_exposure_stat_toggle;
    reg         osd_frame_toggle;
    wire        mixer_sof;
    reg         latency_active;
    reg [11:0]  latency_counter;
    reg [11:0]  latency_cycles;
    // AE/AWB/HE each add one registered pixel stage. Keep the video
    // qualifiers in the same three-cycle pipeline so pixels, coordinates,
    // status text, and HDMI timing remain aligned.
    reg [2:0] de_pipe;
    reg [2:0] sof_pipe;
    reg [2:0] eol_pipe;
    reg [2:0] vsync_pipe;
    reg [2:0] hsync_pipe;
    // pixel_algorithm now has an internal registered luma stage.  Delay the
    // downstream timing qualifiers by the matching cycle so the overlay and
    // HDMI mixer consume the pixel belonging to the same stream position.
    reg       alg_de_1d;
    reg       alg_sof_1d;
    reg       alg_eol_1d;
    reg       alg_vsync_1d;
    reg       alg_hsync_1d;
    // status_overlay registers its completed pixel to break the HDMI timing
    // path; delay the matching qualifiers by the same one cycle.
    reg       status_de_1d;
    reg       status_sof_1d;
    reg       status_eol_1d;
    reg       status_vsync_1d;
    reg       status_hsync_1d;
    // Separate the spatial algorithm from AB's scaler and frame-luma sum.
    reg [23:0] ab_pixel_reg;
    reg ab_de_reg,ab_sof_reg,ab_eol_reg,ab_vsync_reg,ab_hsync_reg;

    wire pipeline_de        = de_pipe[2];
    wire pipeline_sof       = sof_pipe[2];
    wire pipeline_eol       = eol_pipe[2];
    wire pipeline_vsync     = vsync_pipe[2];
    wire pipeline_hsync     = hsync_pipe[2];
    wire post_alg_de        = alg_de_1d;
    wire post_alg_sof       = alg_sof_1d;
    wire post_alg_eol       = alg_eol_1d;
    wire post_alg_vsync     = alg_vsync_1d;
    wire post_alg_hsync     = alg_hsync_1d;
    wire mixer_de           = post_alg_de;
    wire mixer_sof_in       = post_alg_sof;
    wire mixer_eol          = status_eol_1d;
    wire mixer_vsync        = post_alg_vsync;
    wire mixer_hsync        = post_alg_hsync;

    // Measure the application/display stream latency in the HDMI pixel
    // clock domain. This is the number of pixel-clock cycles from the
    // platform frame marker to the marker emitted by hdmi_mixer.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latency_active  <= 1'b0;
            latency_counter <= 12'd0;
            latency_cycles  <= 12'd0;
        end else if (video_sof) begin
            latency_active  <= 1'b1;
            latency_counter <= 12'd0;
        end else if (latency_active) begin
            if (mixer_sof) begin
                latency_active <= 1'b0;
                latency_cycles <= latency_counter;
            end else if (latency_counter != 12'hfff) begin
                latency_counter <= latency_counter + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_pipe    <= 3'b000;
            sof_pipe   <= 3'b000;
            eol_pipe   <= 3'b000;
            vsync_pipe <= 3'b000;
            hsync_pipe <= 3'b000;
            alg_de_1d    <= 1'b0;
            alg_sof_1d   <= 1'b0;
            alg_eol_1d   <= 1'b0;
            alg_vsync_1d <= 1'b0;
            alg_hsync_1d <= 1'b0;
            status_de_1d    <= 1'b0;
            status_sof_1d   <= 1'b0;
            status_eol_1d   <= 1'b0;
            status_vsync_1d <= 1'b0;
            status_hsync_1d <= 1'b0;
        end else begin
            de_pipe    <= {de_pipe[1:0], video_de};
            sof_pipe   <= {sof_pipe[1:0], video_sof};
            eol_pipe   <= {eol_pipe[1:0], video_eol};
            vsync_pipe <= {vsync_pipe[1:0], video_vsync};
            hsync_pipe <= {hsync_pipe[1:0], video_hsync};
            alg_de_1d    <= pipeline_de;
            alg_sof_1d   <= pipeline_sof;
            alg_eol_1d   <= pipeline_eol;
            alg_vsync_1d <= pipeline_vsync;
            alg_hsync_1d <= pipeline_hsync;
            status_de_1d    <= post_alg_de;
            status_sof_1d   <= post_alg_sof;
            status_eol_1d   <= post_alg_eol;
            status_vsync_1d <= post_alg_vsync;
            status_hsync_1d <= post_alg_hsync;
        end
    end

    // The frame reader must be enabled during every active HDMI pixel.
    assign pixel_rd_en = video_de;
    // ISP 分步演示时 HDMI 域逐像素算法强制直通(等效模式00), 正常模式照旧
    assign effective_mode = ENABLE_PIPELINE ? (demo_active ? 4'd0 : mode) : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) osd_frame_toggle <= 1'b0;
        else if (video_sof) osd_frame_toggle <= ~osd_frame_toggle;
    end

    algorithm_mode_ctrl u_mode_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .buttons_n   (buttons_n),
        .mode        (mode),
        .demo_active (demo_active),
        .demo_step   (demo_step)
    );

    vision_switch_ctrl u_switch_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .switches_n     (switches_n),
        .feature_enable (feature_enable)
    );

    auto_exposure #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .TARGET_LOW (128),
        .TARGET_HIGH(160),
        .GAIN_MIN   (256),
        .GAIN_MAX   (256),
        .GAIN_STEP  (4)
    ) u_auto_exposure (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (feature_enable[0]),
        .frame_start       (video_sof),
        .de                (video_de),
        .pixel_in          (pixel_in),
        .pixel_out         (exposure_pixel),
        .frame_stat_y      (auto_exposure_stat_y),
        .frame_stat_toggle (auto_exposure_stat_toggle)
    );

    auto_white_balance u_auto_white_balance (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (1'b0), // Main RAW-domain AWB is controlled by SW2.
        .frame_start(sof_pipe[0]),
        .de         (de_pipe[0]),
        .pixel_in   (exposure_pixel),
        .pixel_out  (white_balance_pixel)
    );

    histogram_equalizer #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT)
    ) u_histogram_equalizer (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (feature_enable[2]),
        .frame_start(sof_pipe[1]),
        .de         (de_pipe[1]),
        .pixel_in   (white_balance_pixel),
        .pixel_out  (equalized_pixel)
    );

    pixel_algorithm #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .BINARY_TH  (`VISION_BINARY_THRESHOLD),
        .EDGE_TH    (`VISION_EDGE_THRESHOLD),
        .ADAPTIVE_BINARY(`VISION_BINARY_ADAPTIVE),
        .BINARY_BIAS(`VISION_BINARY_BIAS)
    ) u_pixel_algorithm (
        .clk         (clk),
        .rst_n       (rst_n),
        .mode        (effective_mode),
        .frame_start (pipeline_sof),
        .line_end    (pipeline_eol),
        .de          (pipeline_de),
        .pixel_in    (equalized_pixel),
        .pixel_out   (algorithm_pixel)
    );

    // Keep the camera pixel and all qualifiers together across this stage.
    // Without it, algorithm -> AB luma -> frame sum exceeds one pixel period.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ab_pixel_reg<=0;ab_de_reg<=0;ab_sof_reg<=0;ab_eol_reg<=0;
            ab_vsync_reg<=0;ab_hsync_reg<=0;
        end else begin
            ab_pixel_reg<=algorithm_pixel;
            ab_de_reg<=post_alg_de;ab_sof_reg<=post_alg_sof;ab_eol_reg<=post_alg_eol;
            ab_vsync_reg<=post_alg_vsync;ab_hsync_reg<=post_alg_hsync;
        end
    end

    // Adjust only the camera/algorithm pixels, before OSD composition.
    adaptive_brightness u_adaptive_brightness (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (feature_enable[3]),
        .frame_start(ab_sof_reg),
        .de         (ab_de_reg),
        .pixel_in   (ab_pixel_reg),
        .pixel_out  (brightness_pixel)
    );

    // ref OSD mixer owns logo, CNT/FPS/LAT, bottom mode bar, and switch state.
    // Its three-stage internal pipeline keeps RGB and HDMI timing aligned.
    hdmi_mixer #(
        .H_OFFSET   (0),
        .V_OFFSET   (0),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .DEBUG_MODE (DEBUG_MODE),
        .ENABLE_OSD (ENABLE_OSD)
    ) u_hdmi_mixer (
        .I_clk            (clk),
        .I_rst_n          (rst_n),
        .I_video_vsync    (ab_vsync_reg),
        .I_video_hsync    (ab_hsync_reg),
        .I_video_de       (ab_de_reg),
        .I_video_user     (ab_sof_reg),
        .I_video_last     (ab_eol_reg),
        .I_debug_status   (debug_status),
        .I_cam_frame_tog  (osd_frame_toggle),
        .I_latency_frames (8'd0),
        .I_mode           (mode),
        .I_isp_demo       ({demo_active, demo_step}),
        .I_feature_enable (feature_enable),
        .O_video_rd_en    (),
        .I_video_rd_data  (brightness_pixel),
        .O_hdmi_vsync     (video_vsync_out),
        .O_hdmi_hsync     (video_hsync_out),
        .O_hdmi_de        (video_de_out),
        .O_hdmi_data      (mixed_pixel),
        .O_hdmi_sof       (mixer_sof)
    );

    assign pixel_out = mixed_pixel;
    assign frame_stat_y = auto_exposure_stat_y;
    assign frame_stat_toggle = auto_exposure_stat_toggle;
    assign isp_demo_sel = {demo_active, demo_step};
endmodule
