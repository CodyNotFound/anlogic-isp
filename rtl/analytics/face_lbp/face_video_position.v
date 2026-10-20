// 720p RGB stream -> rounded 8x8 box-average gray -> 160x90 LBP snapshot.
// No video backpressure. Whole frames are skipped while the detector is busy.
// All signals share the HDMI pixel clock. Detection uses pixels BEFORE OSD/effects.
module face_video_position #(
    parameter integer WIDTH=1280, HEIGHT=720,
    parameter integer TIMEOUT_CYCLES=70000000,
    parameter integer STALE_FRAMES=60,
    parameter integer RESULT_TTL_CYCLES=75000000,
    parameter integer CONFIRM_NEW_TARGET=1,
    parameter WEAK_FILE="rtl/analytics/face_lbp/human_weak.hex",
    parameter STAGE_FILE="rtl/analytics/face_lbp/human_stage.hex",
    parameter GEOMETRY_FILE="rtl/analytics/face_lbp/human_geometry.hex"
)(
    input wire clk,rst_n,enable,sof,eol,de,
    input wire [23:0] rgb,
    output reg position_valid,found,
    output reg [11:0] box_x,box_y,box_size,center_x,center_y,
    output wire busy,
    output reg stream_error,timeout_error,
    output reg [31:0] accepted_frames,completed_frames
);
    reg [10:0] x,y;
    wire [10:0] px=sof ? 11'd0 : x;
    wire [10:0] py=sof ? 11'd0 : y;
    reg capturing,abort_core,start_core,sample_valid;
    reg [7:0] sample_gray,age_frames;
    reg [26:0] watchdog;
    reg [26:0] result_age_cycles;
    wire core_ready,core_busy,core_result,core_found;
    wire [7:0] tx,ty,ts;
    wire [8:0] cx,cy;
    wire [7:0] core_votes;
    reg candidate_pending;
    reg [8:0] pending_cx,pending_cy;
    reg [7:0] pending_size;
    wire [8:0] candidate_dx=cx>=pending_cx?cx-pending_cx:pending_cx-cx;
    wire [8:0] candidate_dy=cy>=pending_cy?cy-pending_cy:pending_cy-cy;
    wire [8:0] candidate_ds=ts>=pending_size?ts-pending_size:pending_size-ts;
    wire candidate_consistent=candidate_pending && candidate_dx<=pending_size/2 &&
        candidate_dy<=pending_size/2 && candidate_ds<=pending_size/2;
    // A template-only bridge has votes=0. It can maintain an established
    // target, but must not serve as the second face-classifier confirmation.
    wire accepted_target=core_found && (!CONFIRM_NEW_TARGET ||
        (candidate_consistent && (found || core_votes>=3)));
    // Keep widths explicit: 255+2*255+255=1020; no truncation before >>2.
    wire [9:0] luma_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire [7:0] gray=luma_sum[9:2];
    reg [10:0] horizontal_sum;
    reg [13:0] columns[0:159];
    reg [13:0] column_q;
    wire [10:0] row_sum=(px[2:0]==0 ? 11'd0 : horizontal_sum)+{3'd0,gray};
    wire [13:0] block_sum=(py[2:0]==0 ? 14'd0 : column_q)+{3'd0,row_sum};
    wire [14:0] rounded_sum={1'b0,block_sum}+15'd32;
    wire accept_frame=sof && enable && core_ready && !capturing && !abort_core;
    wire capturing_now=capturing || accept_frame;
    wire bad_pixel=de && ((eol != (px==WIDTH-1)) || px>=WIDTH || py>=HEIGHT);
    wire core_rst_n=rst_n && enable && !abort_core;
    assign busy=core_busy || capturing || !core_ready;

    // Synchronous RAM read. Each column index stays unchanged for eight pixels,
    // leaving seven clocks before its value is consumed at the block boundary.
    always @(posedge clk) begin
        column_q<=columns[px[10:3]];
        if(enable && capturing_now && de && !bad_pixel && px[2:0]==7)
            columns[px[10:3]]<=block_sum;
    end
    face_pose_snapshot #(.TRACKING_ENABLE(1),.WEAK_FILE(WEAK_FILE),.STAGE_FILE(STAGE_FILE),.GEOMETRY_FILE(GEOMETRY_FILE)) detector(
        .clk(clk),.rst_n(core_rst_n),.frame_start(start_core),.pixel_valid(sample_valid),
        .gray(sample_gray),.ready(core_ready),.busy(core_busy),
        .result_valid(core_result),.target_found(core_found),
        .target_x(tx),.target_y(ty),.target_size(ts),.target_votes(core_votes),
        .target_center_x(cx),.target_center_y(cy),.target_view(),.cycles(),.feature_count());

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;capturing<=0;abort_core<=0;start_core<=0;
            sample_valid<=0;sample_gray<=0;horizontal_sum<=0;
            position_valid<=0;found<=0;box_x<=0;box_y<=0;box_size<=0;center_x<=0;center_y<=0;
            age_frames<=0;watchdog<=0;result_age_cycles<=0;stream_error<=0;timeout_error<=0;
            accepted_frames<=0;completed_frames<=0;
            candidate_pending<=0;pending_cx<=0;pending_cy<=0;pending_size<=0;
        end else begin
            start_core<=0;sample_valid<=0;abort_core<=0;position_valid<=0;
            // Wall-clock expiry also works if the camera stops sending SOFs
            // after a successful result. It must exceed the normal roll scan.
            if(candidate_pending && result_age_cycles<RESULT_TTL_CYCLES)result_age_cycles<=result_age_cycles+1'b1;
            else if(!candidate_pending)result_age_cycles<=0;
            if(candidate_pending && result_age_cycles>=RESULT_TTL_CYCLES-1)begin found<=0;candidate_pending<=0;end
            if(sof) begin x<=0;y<=0;end
            if(de) begin
                if(eol) begin x<=0;y<=py+1'b1;end
                else begin x<=px+1'b1;y<=py;end
            end
            if(!enable) begin
                capturing<=0;found<=0;age_frames<=0;watchdog<=0;result_age_cycles<=0;
                candidate_pending<=0;
                box_x<=0;box_y<=0;box_size<=0;center_x<=0;center_y<=0;
            end else begin
                if(sof && age_frames<STALE_FRAMES) age_frames<=age_frames+1'b1;
                if(sof && age_frames>=STALE_FRAMES-1) begin found<=0;candidate_pending<=0;end
                if(accept_frame) begin
                    start_core<=1;capturing<=1;accepted_frames<=accepted_frames+1'b1;
                    horizontal_sum<=0;
                end
                if(capturing_now && de && !bad_pixel) begin
                    horizontal_sum<=px[2:0]==7 ? 11'd0 : row_sum;
                    if(px[2:0]==7 && py[2:0]==7) begin
                        sample_gray<=rounded_sum[13:6];sample_valid<=1;
                    end
                    if(px==WIDTH-1 && py==HEIGHT-1) capturing<=0;
                end
                if(core_busy || start_core || capturing) watchdog<=watchdog+1'b1;
                else watchdog<=0;
                if(core_result) begin
                    position_valid<=1;completed_frames<=completed_frames+1'b1;
                    found<=accepted_target;age_frames<=0;watchdog<=0;result_age_cycles<=0;
                    candidate_pending<=core_found;
                    pending_cx<=cx;pending_cy<=cy;pending_size<=ts;
                    box_x<={1'b0,tx,3'b0};box_y<={1'b0,ty,3'b0};box_size<={1'b0,ts,3'b0};
                    center_x<={cx,3'b0};center_y<={cy,3'b0};
                end
                // A short/long row, premature frame marker or stalled source
                // invalidates the entire snapshot; it must never publish a box.
                if(bad_pixel || (sof && capturing) || watchdog>=TIMEOUT_CYCLES-1) begin
                    abort_core<=1;capturing<=0;start_core<=0;sample_valid<=0;found<=0;
                    candidate_pending<=0;
                    position_valid<=0;watchdog<=0;
                    if(bad_pixel || (sof && capturing)) stream_error<=1;
                    if(watchdog>=TIMEOUT_CYCLES-1) timeout_error<=1;
                end
            end
        end
    end
endmodule
