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
    parameter integer FACE_CNN_ENABLE = 0,
    parameter integer DEBUG_MODE = `VISION_DEBUG_MODE,
    // TD resolves readmemh beside the source file containing that statement.
    // RTL simulation from the repo root can override these three parameters.
    parameter FACE_WEAK_FILE="human_weak.hex",
    parameter FACE_STAGE_FILE="human_stage.hex",
    parameter FACE_GEOMETRY_FILE="human_geometry.hex"
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
    output wire [3:0]  isp_demo_sel,
    output wire servo_pwm_h,servo_pwm_v,
    output wire [3:0] panel_leds,output wire [7:0] panel_segments,panel_selects
);
    wire [3:0] feature_requested;
    wire [3:0] normal_buttons_n,keys_pressed;
    wire manual_mode=feature_requested[3];
    // SW3 is a display switch. Detection and automatic control never depend
    // on it. Commit at input SOF, before the delayed overlay stages see SOF.
    reg info_enabled_f;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)info_enabled_f<=0;
        else if(video_sof)info_enabled_f<=ENABLE_OSD && feature_requested[2];
    end
    wire [11:0] pulse_h,pulse_v,display_h,display_v;
    wire [1:0] gimbal_state;
    wire [23:0] h_digits,v_digits;
    wire track_valid,track_found;wire [7:0] track_x,track_y;
    wire mix_vsync,mix_hsync,mix_de;
    gimbal_button_router u_button_router(.clk(clk),.rst_n(rst_n),.manual_mode(manual_mode),
        .buttons_n(buttons_n),.keys_pressed(keys_pressed),.normal_buttons_n(normal_buttons_n));
    wire [3:0] mode;
    wire [3:0] effective_mode;
    wire       demo_active;
    wire       task_action;
    wire [2:0] demo_step;
    wire [3:0] feature_enable;
    assign feature_enable={feature_requested[0],1'b0,1'b1,feature_requested[1]}; // SW1 AB, SW2 AE, AWB always on
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
    wire        mixer_sof,mixer_sof_raw;
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
    // pixel_algorithm has four registered clocks, including the RGB cartoon
    // renderer. Delay all qualifiers equally, including every bypass mode.
    reg       alg_de_1d;
    reg       alg_sof_1d;
    reg       alg_eol_1d;
    reg       alg_vsync_1d;
    reg       alg_hsync_1d;
    reg [2:0] alg_de_extra,alg_sof_extra,alg_eol_extra,alg_vsync_extra,alg_hsync_extra;
    // status_overlay registers its completed pixel to break the HDMI timing
    // path; delay the matching qualifiers by the same one cycle.
    reg       status_de_1d;
    reg       status_sof_1d;
    reg       status_eol_1d;
    reg       status_vsync_1d;
    reg       status_hsync_1d;
    // Registered normal-camera input to AB, ahead of all spatial effects.
    reg [23:0] ab_pixel_reg;
    reg ab_de_reg,ab_sof_reg,ab_eol_reg,ab_vsync_reg,ab_hsync_reg;
    wire face_enable=ENABLE_PIPELINE && !demo_active && mode==4'd11;
    wire face_found,face_position_valid;
    wire [11:0] face_x,face_y,face_size,face_center_x,face_center_y;
    wire face_de,face_sof,face_eol,face_vsync,face_hsync;
    wire [23:0] face_pixel;
    wire task_vsync,task_hsync,task_de,task_sof,task_eol;
    wire [23:0] task_pixel;
    wire [3:0] task_hud_status;

    wire pipeline_de        = de_pipe[2];
    wire pipeline_sof       = sof_pipe[2];
    wire pipeline_eol       = eol_pipe[2];
    wire pipeline_vsync     = vsync_pipe[2];
    wire pipeline_hsync     = hsync_pipe[2];
    wire post_alg_de        = alg_de_extra[2];
    wire post_alg_sof       = alg_sof_extra[2];
    wire post_alg_eol       = alg_eol_extra[2];
    wire post_alg_vsync     = alg_vsync_extra[2];
    wire post_alg_hsync     = alg_hsync_extra[2];
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
            alg_de_extra<=0;alg_sof_extra<=0;alg_eol_extra<=0;alg_vsync_extra<=0;alg_hsync_extra<=0;
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
            alg_de_extra<={alg_de_extra[1:0],alg_de_1d};
            alg_sof_extra<={alg_sof_extra[1:0],alg_sof_1d};
            alg_eol_extra<={alg_eol_extra[1:0],alg_eol_1d};
            alg_vsync_extra<={alg_vsync_extra[1:0],alg_vsync_1d};
            alg_hsync_extra<={alg_hsync_extra[1:0],alg_hsync_1d};
            alg_de_1d    <= ab_de_reg;
            alg_sof_1d   <= ab_sof_reg;
            alg_eol_1d   <= ab_eol_reg;
            alg_vsync_1d <= ab_vsync_reg;
            alg_hsync_1d <= ab_hsync_reg;
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

    algorithm_mode_ctrl #(.ENABLE_ISP_DEMO(0)) u_mode_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .buttons_n   (normal_buttons_n),
        .mode        (mode),
        .demo_active (demo_active),
        .demo_step   (demo_step),
        .action_pulse(task_action)
    );

    vision_switch_ctrl u_switch_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .switches_n     (switches_n),
        .feature_enable (feature_requested)
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
        .enable     (1'b0), // Main RAW-domain AWB is controlled by SW1.
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
        .enable     (feature_enable[2] && effective_mode!=13),
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
        .frame_start (ab_sof_reg),
        .line_end    (ab_eol_reg),
        .de          (ab_de_reg),
        .pixel_in    (brightness_pixel),
        .pixel_out   (algorithm_pixel)
    );

    // AB always observes normal camera pixels, before artistic transforms.
    // Its gain/statistics therefore do not change when entering inverse/edge.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ab_pixel_reg<=0;ab_de_reg<=0;ab_sof_reg<=0;ab_eol_reg<=0;
            ab_vsync_reg<=0;ab_hsync_reg<=0;
        end else begin
            ab_pixel_reg<=equalized_pixel;
            ab_de_reg<=pipeline_de;ab_sof_reg<=pipeline_sof;ab_eol_reg<=pipeline_eol;
            ab_vsync_reg<=pipeline_vsync;ab_hsync_reg<=pipeline_hsync;
        end
    end

    // Adjust only the camera/algorithm pixels, before OSD composition.
    adaptive_brightness u_adaptive_brightness (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (feature_enable[3] && effective_mode!=13),
        .frame_start(ab_sof_reg),
        .de         (ab_de_reg),
        .pixel_in   (ab_pixel_reg),
        .pixel_out  (brightness_pixel)
    );

    // Detect on the clean platform RGB, before effects, adaptive brightness,
    // labels and logo. Mode 11 falls through pixel_algorithm unchanged.
    wire lbp_found,lbp_valid;
    wire [11:0] lbp_x,lbp_y,lbp_size,lbp_cx,lbp_cy;
    face_video_position #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),
        .WEAK_FILE(FACE_WEAK_FILE),.STAGE_FILE(FACE_STAGE_FILE),.GEOMETRY_FILE(FACE_GEOMETRY_FILE)) u_face_position(
        .clk(clk),.rst_n(rst_n),.enable(face_enable && !FACE_CNN_ENABLE),.sof(video_sof),.eol(video_eol),.de(video_de),.rgb(pixel_in),
        .position_valid(lbp_valid),.found(lbp_found),
        .box_x(lbp_x),.box_y(lbp_y),.box_size(lbp_size),.center_x(lbp_cx),.center_y(lbp_cy),
        .busy(),.stream_error(),.timeout_error(),.accepted_frames(),.completed_frames());
    generate if(FACE_CNN_ENABLE)begin: cnn_mode
        face_video_cnn #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) u_cnn(
            .clk(clk),.rst_n(rst_n),.enable(face_enable),.sof(video_sof),.eol(video_eol),.de(video_de),.rgb(pixel_in),
            .position_valid(face_position_valid),.found(face_found),.box_x(face_x),.box_y(face_y),.box_size(face_size),
            .center_x(face_center_x),.center_y(face_center_y),.busy(),.stream_error(),.completed_frames());
    end else begin: lbp_mode
        assign face_position_valid=lbp_valid;assign face_found=lbp_found;
        assign face_x=lbp_x;assign face_y=lbp_y;assign face_size=lbp_size;assign face_center_x=lbp_cx;assign face_center_y=lbp_cy;
    end endgenerate
    face_position_overlay u_face_overlay(
        .clk(clk),.rst_n(rst_n),.enable(face_enable && info_enabled_f),
        .vsync(post_alg_vsync),.hsync(post_alg_hsync),.de(post_alg_de),.sof(post_alg_sof),.eol(post_alg_eol),
        .rgb(algorithm_pixel),.found(face_found),
        .box_x(face_x),.box_y(face_y),.box_size(face_size),.center_x(face_center_x),.center_y(face_center_y),
        .out_vsync(face_vsync),.out_hsync(face_hsync),.out_de(face_de),.out_sof(face_sof),.out_eol(face_eol),.out_rgb(face_pixel));

    vision_task_suite #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.HUD_TEXT_ENABLE(0)) u_tasks(
        .clk(clk),.rst_n(rst_n),.enabled(ENABLE_PIPELINE && !demo_active),.action(task_action),.mode(mode),
        .source_sof(video_sof),.source_eol(video_eol),.source_de(video_de),.source_rgb(pixel_in),
        .vsync(face_vsync),.hsync(face_hsync),.de(face_de),.sof(face_sof),.eol(face_eol),.rgb(face_pixel),
        .out_vsync(task_vsync),.out_hsync(task_hsync),.out_de(task_de),.out_sof(task_sof),.out_eol(task_eol),.out_rgb(task_pixel),
        .target_valid(track_valid),.target_found(track_found),.target_x(track_x),.target_y(track_y),.manual_mode(manual_mode),
        .osd_enable(info_enabled_f),.hud_status(task_hud_status));

    // Existing OSD remains last; analytics never process their own overlays.
    // Its three-stage internal pipeline keeps RGB and HDMI timing aligned.
    hdmi_mixer #(
        .H_OFFSET   (0),
        .V_OFFSET   (0),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .DEBUG_MODE (DEBUG_MODE),
        .ENABLE_OSD (ENABLE_OSD),
        .ENABLE_SWITCH_OSD(0),.COMPACT_OSD(1)
    ) u_hdmi_mixer (
        .I_clk            (clk),
        .I_rst_n          (rst_n),
        .I_video_vsync    (task_vsync),
        .I_video_hsync    (task_hsync),
        .I_video_de       (task_de),
        .I_video_user     (task_sof),
        .I_video_last     (task_eol),
        .I_debug_status   (debug_status),
        .I_cam_frame_tog  (osd_frame_toggle),
        .I_latency_frames (8'd0),
        .I_mode           (mode),
        .I_isp_demo       ({demo_active, demo_step}),
        .I_feature_enable (4'b0),
        .I_info_enable(info_enabled_f),.I_panel_features(feature_requested),
        .I_ctl_state(gimbal_state),.I_task_status(task_hud_status),
        .I_pulse_h(display_h),.I_pulse_v(display_v),.I_h_digits(h_digits),.I_v_digits(v_digits),
        .O_video_rd_en    (),
        .I_video_rd_data  (task_pixel),
        .O_hdmi_vsync     (mix_vsync),
        .O_hdmi_hsync     (mix_hsync),
        .O_hdmi_de        (mix_de),
        .O_hdmi_data      (mixed_pixel),
        .O_hdmi_sof       (mixer_sof_raw)
    );

    reg [3:0] gimbal_mode_d;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)gimbal_mode_d<=0;else gimbal_mode_d<=mode;
    end
    wire gimbal_auto_enable=ENABLE_PIPELINE && !demo_active &&
        gimbal_mode_d==mode && (mode==11 || mode==12 || mode==14);
    servo_gimbal_ctrl #(.IMG_W(IMG_WIDTH/8),.IMG_H(IMG_HEIGHT/8)) u_gimbal(.clk(clk),.rst_n(rst_n),
        .enable(gimbal_auto_enable),
        .result_valid(face_enable?face_position_valid:track_valid),.found(face_enable?face_found:track_found),
        .cx(face_enable?face_center_x[10:3]:track_x),.cy(face_enable?face_center_y[10:3]:track_y),
        .manual_mode(manual_mode),.keys_pressed(keys_pressed),.pwm_h(servo_pwm_h),.pwm_v(servo_pwm_v),
        .pulse_h_us(pulse_h),.pulse_v_us(pulse_v),.ctl_state(gimbal_state));
    gimbal_panel u_panel(.clk(clk),.rst_n(rst_n),.features(feature_requested),.pulse_h(pulse_h),.pulse_v(pulse_v),
        .leds(panel_leds),.segments(panel_segments),.selects(panel_selects),.h_digits(h_digits),.v_digits(v_digits),.display_h(display_h),.display_v(display_v));
    // Keep the existing two registered video clocks. All text/position drawing
    // now shares hdmi_mixer's font ROM and compositor; this instance is delay only.
    gimbal_osd #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.ENABLE(0)) u_gimbal_osd(
        .clk(clk),.rst_n(rst_n),.features(feature_requested),.mode(mode),.demo_active(demo_active),
        .ctl_state(gimbal_state),.pulse_h(display_h),.pulse_v(display_v),.h_digits(h_digits),.v_digits(v_digits),
        .vsync(mix_vsync),.hsync(mix_hsync),.de(mix_de),.sof(mixer_sof_raw),.rgb(mixed_pixel),
        .out_vsync(video_vsync_out),.out_hsync(video_hsync_out),.out_de(video_de_out),.out_rgb(pixel_out),.out_sof(mixer_sof));
    assign frame_stat_y = auto_exposure_stat_y;
    assign frame_stat_toggle = auto_exposure_stat_toggle;
    assign isp_demo_sel = {demo_active, demo_step};
endmodule
