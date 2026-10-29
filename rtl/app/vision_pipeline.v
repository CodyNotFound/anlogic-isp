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
    parameter integer FACE_CORE_CLK_X2 = 0,
    parameter integer FACE_MOTION_ENABLE = 1,
    parameter integer ENABLE_HMI = 0,
    parameter integer DEBUG_MODE = `VISION_DEBUG_MODE,
    // TD resolves readmemh beside the source file containing that statement.
    // RTL simulation from the repo root can override these three parameters.
    parameter FACE_WEAK_FILE="human_weak.hex",
    parameter FACE_STAGE_FILE="human_stage.hex",
    parameter FACE_GEOMETRY_FILE="human_geometry.hex"
)(
    input  wire        clk,
    input  wire        cnn_core_clk,
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
    output wire [3:0] panel_leds,output wire [7:0] panel_segments,panel_selects,
    input wire hmi_rx,output wire hmi_tx
);
    wire [3:0] feature_requested,physical_features;
    wire [3:0] physical_keys,hmi_keys,hmi_mode;
    wire hmi_mode_set,hmi_action,hmi_connected;
    wire [7:0] fps_digits;
    wire [3:0] normal_buttons_n,keys_pressed;
    assign keys_pressed=(|physical_keys) ? physical_keys : hmi_keys;
    wire manual_mode=feature_requested[3];
    // SW4 changes key routing only; idle direction keys never inhibit SW3.
    wire manual_motion=manual_mode && (|keys_pressed);
    reg[3:0] local_buttons_prev;
    wire[3:0] local_buttons=(~normal_buttons_n)|physical_keys;
    wire local_takeover=|(local_buttons & ~local_buttons_prev);
    always @(posedge clk or negedge rst_n)begin
     if(!rst_n)local_buttons_prev<=0;else local_buttons_prev<=local_buttons;
    end
    // SW3 gates automatic motion only. Analytics and compact OSD stay active.
    reg info_enabled_f;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)info_enabled_f<=0;
        else if(video_sof)info_enabled_f<=ENABLE_OSD;
    end
    wire [11:0] pulse_h,pulse_v,display_h,display_v;
    wire [1:0] gimbal_state;
    wire [23:0] h_digits,v_digits;
    wire [31:0] face_compute_cycles,task_compute_cycles;
    wire track_valid,track_found;wire [7:0] track_x,track_y;
    wire mix_vsync,mix_hsync,mix_de;
    gimbal_button_router #(.SAMPLE_CYCLES(75000)) u_button_router(.clk(clk),.rst_n(rst_n),.manual_mode(manual_mode),
        .buttons_n(buttons_n),.keys_pressed(physical_keys),.normal_buttons_n(normal_buttons_n));
    wire [3:0] mode;
    wire [3:0] effective_mode;
    wire       demo_active;
    wire       task_action;
    wire [2:0] demo_step;
    wire [3:0] feature_enable;
    assign feature_enable={1'b0,1'b0,1'b1,feature_requested[1]}; // AB fixed off; SW1 AWB AUTO/HOLD, SW2 AE AUTO/HOLD
    wire [23:0] algorithm_pixel;
    wire [23:0] exposure_pixel;
    wire [23:0] white_balance_pixel;
    wire [23:0] equalized_pixel;
    wire [23:0] overlay_pixel;
    wire [23:0] status_pixel;
    wire [23:0] mixed_pixel;
    wire [23:0] camera_algorithm_pixel;
    wire [7:0]  auto_exposure_stat_y;
    wire        auto_exposure_stat_toggle;
    reg         osd_frame_toggle;
    wire        mixer_sof,mixer_sof_raw;
    reg latency_seen;reg         latency_active;
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
    reg [23:0] camera_pixel_reg;
    reg camera_de_reg,camera_sof_reg,camera_eol_reg,camera_vsync_reg,camera_hsync_reg;
    wire face_enable=ENABLE_PIPELINE && !demo_active && mode==4'd11;
    wire face_found,face_position_valid,face_capture_started;
    wire shared_track_write;
    wire [14:0] shared_track_waddr,shared_track_raddr;
    wire [7:0] shared_track_wdata,shared_track_rdata;wire [31:0] shared_track_word;
    wire [11:0] face_x,face_y,face_size,face_center_x,face_center_y;
    wire face_de,face_sof,face_eol,face_vsync,face_hsync;
    wire face_fast,face_fs,face_sv,face_fe,face_abort;
    wire [7:0] face_sx,face_sy,face_gray;
    wire raw_face_valid,raw_face_found;
    wire [11:0] raw_face_x,raw_face_y,raw_face_size,raw_face_cx,raw_face_cy;
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
            latency_seen<=0;latency_active  <= 1'b0;
            latency_counter <= 12'd0;
            latency_cycles  <= 12'd0;
        end else if (video_sof) begin
            latency_active  <= 1'b1;
            latency_counter <= 12'd0;
        end else if (latency_active) begin
            if (mixer_sof) begin
                latency_active <= 1'b0;
                latency_cycles <= latency_counter;latency_seen<=1;
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
            alg_de_1d    <= camera_de_reg;
            alg_sof_1d   <= camera_sof_reg;
            alg_eol_1d   <= camera_eol_reg;
            alg_vsync_1d <= camera_vsync_reg;
            alg_hsync_1d <= camera_hsync_reg;
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

    algorithm_mode_ctrl #(.ENABLE_ISP_DEMO(0),.LAST_MODE(4'd14),.BUTTONS_DEBOUNCED(1),.ENABLE_REMOTE(ENABLE_HMI)) u_mode_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .buttons_n   (normal_buttons_n),
        .mode        (mode),
        .demo_active (demo_active),
        .demo_step   (demo_step),
        .action_pulse(task_action),
        .remote_set(hmi_mode_set),.remote_mode(hmi_mode),.remote_action(hmi_action)
    );

    vision_switch_ctrl #(.SAMPLE_CYCLES(75000)) u_switch_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .switches_n     (switches_n),
        .feature_enable (physical_features)
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
        .frame_start (camera_sof_reg),
        .line_end    (camera_eol_reg),
        .de          (camera_de_reg),
        .pixel_in    (camera_algorithm_pixel),
        .pixel_out   (algorithm_pixel)
    );

    // Register camera pixels and sync together before artistic transforms.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            camera_pixel_reg<=0;camera_de_reg<=0;camera_sof_reg<=0;camera_eol_reg<=0;
            camera_vsync_reg<=0;camera_hsync_reg<=0;
        end else begin
            camera_pixel_reg<=equalized_pixel;
            camera_de_reg<=pipeline_de;camera_sof_reg<=pipeline_sof;camera_eol_reg<=pipeline_eol;
            camera_vsync_reg<=pipeline_vsync;camera_hsync_reg<=pipeline_hsync;
        end
    end

    // AB removed: retain the registered RGB stream and blanking behavior.
    assign camera_algorithm_pixel = camera_de_reg ? camera_pixel_reg : 24'd0;

    // Detect on the clean platform RGB, before effects,
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
        face_video_cnn #(.CORE_CLK_X2(FACE_CORE_CLK_X2),.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.SHARED_TRACK_FRAME(1)) u_cnn(
            .clk(clk),.core_clk(cnn_core_clk),.rst_n(rst_n),.enable(face_enable),.sof(video_sof),.eol(video_eol),.de(video_de),.rgb(pixel_in),
            .position_valid(raw_face_valid),.found(raw_face_found),.box_x(raw_face_x),.box_y(raw_face_y),.box_size(raw_face_size),
            .center_x(raw_face_cx),.center_y(raw_face_cy),.busy(),.stream_error(),.completed_frames(),
            .shared_enable(ENABLE_PIPELINE&&!demo_active&&(mode==12||mode==13||mode==14)),.shared_write_en(shared_track_write),
            .shared_write_address(shared_track_waddr),.shared_read_address(shared_track_raddr),
            .shared_write_data(shared_track_wdata),.shared_read_data(shared_track_rdata),.shared_read_word(shared_track_word),.inference_cycles(face_compute_cycles),.capture_started(face_capture_started));
        if(FACE_MOTION_ENABLE)begin: motion_assist
         face_motion_fusion #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) fusion(
          .clk(clk),.rst_n(rst_n),.enable(face_enable),.clear(task_action),
          .capture_start(face_capture_started),.cnn_valid(raw_face_valid),.cnn_found(raw_face_found),
          .cnn_cx(raw_face_cx),.cnn_cy(raw_face_cy),.cnn_size(raw_face_size),
          .frame_start(face_fs),.frame_end(face_fe),.frame_error(face_abort),.sample_valid(face_sv),
          .sample_x(face_sx),.sample_y(face_sy),.gray(face_gray),
          .result_valid(face_position_valid),.found(face_found),.box_x(face_x),.box_y(face_y),.box_size(face_size),
          .center_x(face_center_x),.center_y(face_center_y),.fast_source(face_fast),.match_cycles(),
          .accepted_corrections(),.rejected_corrections());
        end else begin: detector_only
         assign {face_position_valid,face_found,face_x,face_y,face_size,face_center_x,face_center_y}=
          {raw_face_valid,raw_face_found,raw_face_x,raw_face_y,raw_face_size,raw_face_cx,raw_face_cy};
         assign face_fast=1'b0;
        end
    end else begin: lbp_mode
        assign face_fast=1'b0;assign face_capture_started=1'b0;assign face_position_valid=lbp_valid;assign face_found=lbp_found;
        assign face_x=lbp_x;assign face_y=lbp_y;assign face_size=lbp_size;assign face_center_x=lbp_cx;assign face_center_y=lbp_cy;
        assign shared_track_rdata=8'd0;assign shared_track_word=32'd0;assign face_compute_cycles=32'd0;
    end endgenerate
    face_position_overlay u_face_overlay(
        .clk(clk),.rst_n(rst_n),.enable(face_enable && info_enabled_f),
        .vsync(post_alg_vsync),.hsync(post_alg_hsync),.de(post_alg_de),.sof(post_alg_sof),.eol(post_alg_eol),
        .rgb(algorithm_pixel),.found(face_found),
        .box_x(face_x),.box_y(face_y),.box_size(face_size),.center_x(face_center_x),.center_y(face_center_y),
        .out_vsync(face_vsync),.out_hsync(face_hsync),.out_de(face_de),.out_sof(face_sof),.out_eol(face_eol),.out_rgb(face_pixel));

    reg [11:0] motion_last_h,motion_last_v;reg [3:0] motion_settle_frames;
    wire motion_camera_moving=manual_motion||motion_settle_frames!=0;
    always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin motion_last_h<=1500;motion_last_v<=1500;motion_settle_frames<=15;end
     else begin
      motion_last_h<=pulse_h;motion_last_v<=pulse_v;
      if(pulse_h!=motion_last_h||pulse_v!=motion_last_v)motion_settle_frames<=15;
      else if(video_sof&&motion_settle_frames!=0)motion_settle_frames<=motion_settle_frames-1'b1;
     end
    end
    vision_task_suite #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.HUD_TEXT_ENABLE(0),.SHARED_TRACK_FRAME(FACE_CNN_ENABLE)) u_tasks(
        .clk(clk),.rst_n(rst_n),.enabled(ENABLE_PIPELINE && !demo_active),.action(task_action),.mode(mode),
        .source_sof(video_sof),.source_eol(video_eol),.source_de(video_de),.source_rgb(pixel_in),
        .vsync(face_vsync),.hsync(face_hsync),.de(face_de),.sof(face_sof),.eol(face_eol),.rgb(face_pixel),
        .out_vsync(task_vsync),.out_hsync(task_hsync),.out_de(task_de),.out_sof(task_sof),.out_eol(task_eol),.out_rgb(task_pixel),
        .target_valid(track_valid),.target_found(track_found),.target_x(track_x),.target_y(track_y),.manual_mode(manual_motion),
        .osd_enable(info_enabled_f),.hud_status(task_hud_status),
        .shared_write_en(shared_track_write),.shared_write_addr(shared_track_waddr),.shared_read_addr(shared_track_raddr),
        .shared_write_data(shared_track_wdata),.shared_read_data(shared_track_rdata),.shared_read_word(shared_track_word),.target_compute_cycles(task_compute_cycles),.camera_moving(motion_camera_moving),
        .face_assist(face_enable&&FACE_CNN_ENABLE&&FACE_MOTION_ENABLE),.face_fs(face_fs),.face_sv(face_sv),.face_fe(face_fe),.face_abort(face_abort),
        .face_sx(face_sx),.face_sy(face_sy),.face_gray(face_gray));

    wire tracking_mode=mode==11||mode==12||mode==13||mode==14;
    wire coordinate_found=tracking_mode&&(face_enable?face_found:track_found);
    wire [11:0] coordinate_x=face_enable?face_center_x:{1'b0,track_x,3'b0};
    wire [11:0] coordinate_y=face_enable?face_center_y:{1'b0,track_y,3'b0};
    reg [31:0] completed_compute_cycles;reg compute_seen;reg [3:0] compute_mode;
    always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin completed_compute_cycles<=0;compute_seen<=0;compute_mode<=0;end
     else begin
      compute_mode<=mode;
      if(mode!=compute_mode||!tracking_mode)compute_seen<=0;
      else if(face_enable?(FACE_CNN_ENABLE?raw_face_valid:face_position_valid):track_valid)begin
       completed_compute_cycles<=face_enable?face_compute_cycles:task_compute_cycles;
       compute_seen<=!face_enable||FACE_CNN_ENABLE;
      end
     end
    end
    wire [3:0] telemetry_mode;wire telemetry_found,telemetry_compute_valid;
    wire [15:0] target_x_digits,target_y_digits,compute_ms_digits;
    vision_telemetry #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) u_telemetry(
     .clk(clk),.rst_n(rst_n),.mode(mode),.found(coordinate_found),.compute_valid(tracking_mode?compute_seen:latency_seen),
     .x(coordinate_x),.y(coordinate_y),.compute_cycles(tracking_mode?completed_compute_cycles:{20'd0,latency_cycles}),
     .packet_mode(telemetry_mode),.packet_found(telemetry_found),.packet_compute_valid(telemetry_compute_valid),.packet_tick(),
     .x_digits(target_x_digits),.y_digits(target_y_digits),.ms_digits(compute_ms_digits));

    generate if(ENABLE_HMI)begin: g_hmi
     hmi_control_link u_link(.clk(clk),.rst_n(rst_n),.rx(hmi_rx),.tx(hmi_tx),
      .physical_features(physical_features),.features(feature_requested),.mode(mode),
      .mode_set(hmi_mode_set),.mode_value(hmi_mode),.action(hmi_action),.keys(hmi_keys),.connected(hmi_connected),.manual_active(manual_motion),.local_takeover(local_takeover),
      .target_found(telemetry_found&&telemetry_mode==mode&&coordinate_found),
      .compute_valid(telemetry_compute_valid&&telemetry_mode==mode),.task_status(task_hud_status),.ctl_state(gimbal_state),
      .x_digits(target_x_digits),.y_digits(target_y_digits),.ms_digits(mode<11?16'h0000:compute_ms_digits),
      .h_digits(h_digits[15:0]),.v_digits(v_digits[15:0]),.fps_digits(fps_digits));
    end else begin: g_no_hmi
     assign feature_requested=physical_features;assign hmi_tx=1'b1;
     assign hmi_connected=0;assign hmi_mode_set=0;assign hmi_mode=0;assign hmi_action=0;assign hmi_keys=0;
    end endgenerate

    // Existing OSD remains last; analytics never process their own overlays.
    // Its three-stage internal pipeline keeps RGB and HDMI timing aligned.
    hdmi_mixer #(
        .H_OFFSET   (0),
        .V_OFFSET   (0),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .DEBUG_MODE (DEBUG_MODE),
        .ENABLE_OSD (ENABLE_OSD),
        .ENABLE_SWITCH_OSD(0),.COMPACT_OSD(1),.TARGET_TELEMETRY(1)
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
        .I_manual_active(manual_motion),.I_hmi_connected(hmi_connected),.I_info_enable(info_enabled_f),.I_panel_features(feature_requested),
        .I_ctl_state(gimbal_state),.I_task_status(task_hud_status),
        .I_target_found(telemetry_found&&telemetry_mode==mode&&coordinate_found),
        .I_compute_valid(telemetry_compute_valid&&telemetry_mode==mode),
        .I_target_x_digits(target_x_digits),.I_target_y_digits(target_y_digits),.I_compute_ms_digits(compute_ms_digits),
        .I_pulse_h(display_h),.I_pulse_v(display_v),.I_h_digits(h_digits),.I_v_digits(v_digits),
        .O_video_rd_en    (),
        .I_video_rd_data  (task_pixel),
        .O_hdmi_vsync     (mix_vsync),
        .O_hdmi_hsync     (mix_hsync),
        .O_hdmi_de        (mix_de),
        .O_hdmi_data      (mixed_pixel),
        .O_hdmi_sof       (mixer_sof_raw),.O_fps_digits(fps_digits)
    );

    reg [3:0] gimbal_mode_d;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)gimbal_mode_d<=0;else gimbal_mode_d<=mode;
    end
    wire gimbal_auto_enable=ENABLE_PIPELINE && feature_requested[2] && !demo_active &&
        gimbal_mode_d==mode && (mode==11 || mode==12 || mode==13);
    // Register the entire visual-control command together. The mode decoder
    // no longer feeds through target planning into controller registers.
    reg gimbal_en_q,gimbal_valid_q,gimbal_found_q,gimbal_manual_q,gimbal_slow_q,gimbal_capture_q;
    reg [7:0] gimbal_cx_q,gimbal_cy_q;reg [3:0] gimbal_keys_q;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            gimbal_en_q<=0;gimbal_valid_q<=0;gimbal_found_q<=0;gimbal_manual_q<=0;
            gimbal_slow_q<=0;gimbal_capture_q<=0;gimbal_cx_q<=0;gimbal_cy_q<=0;gimbal_keys_q<=0;
        end else begin
            gimbal_en_q<=gimbal_auto_enable;
            gimbal_valid_q<=face_enable?face_position_valid:track_valid;
            gimbal_found_q<=face_enable?face_found:track_found;
            gimbal_cx_q<=face_enable?face_center_x[10:3]:track_x;
            gimbal_cy_q<=face_enable?face_center_y[10:3]:track_y;
            gimbal_manual_q<=manual_motion;gimbal_keys_q<=keys_pressed;
            gimbal_slow_q<=face_enable&&FACE_CNN_ENABLE&&!face_fast;
            gimbal_capture_q<=face_capture_started;
        end
    end
    servo_gimbal_ctrl #(.IMG_W(IMG_WIDTH/8),.IMG_H(IMG_HEIGHT/8)) u_gimbal(.clk(clk),.rst_n(rst_n),
        .enable(gimbal_en_q),.result_valid(gimbal_valid_q),.found(gimbal_found_q),
        .cx(gimbal_cx_q),.cy(gimbal_cy_q),.manual_mode(gimbal_manual_q),.keys_pressed(gimbal_keys_q),
        .pwm_h(servo_pwm_h),.pwm_v(servo_pwm_v),.pulse_h_us(pulse_h),.pulse_v_us(pulse_v),
        .ctl_state(gimbal_state),.slow_source(gimbal_slow_q),.capture_valid(gimbal_capture_q));
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
