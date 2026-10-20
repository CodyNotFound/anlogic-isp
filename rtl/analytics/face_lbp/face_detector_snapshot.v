// Detection-only wrapper. All signals share clk. No camera CDC or servo PWM.
module face_detector_snapshot #(
    parameter integer HUMAN_ONLY=0,
    parameter integer NUM_SCALES=6,
    parameter integer SEARCH_SUPPORT=0,
    parameter WEAK_FILE="rtl/analytics/face_lbp/weak.hex",
    parameter STAGE_FILE="rtl/analytics/face_lbp/stage.hex",
    parameter GEOMETRY_FILE="rtl/analytics/face_lbp/geometry.hex"
)(
    input wire clk,rst_n,frame_start,pixel_valid,model_select,
    input wire [7:0] gray,
    output wire ready,busy,result_valid,target_found,overflow,
    output wire [7:0] target_x,target_y,target_size,target_votes,
    output wire [8:0] target_center_x,target_center_y,
    output wire [31:0] cycles,feature_count,
    input wire search_enable,
    input wire [7:0] search_x0,search_y0,search_x1,search_y1,
    input wire [3:0] search_scale_lo,search_scale_hi
);
    wire done,candidate_valid,core_ready,select_busy;
    wire [7:0] box_x,box_y,box_size;
    wire accepted_start=frame_start && ready;
    assign ready=core_ready && !select_busy && !done;
    face_lbp_core #(.HUMAN_ONLY(HUMAN_ONLY),.NUM_SCALES(NUM_SCALES),.SEARCH_SUPPORT(SEARCH_SUPPORT),
        .WEAK_FILE(WEAK_FILE),.STAGE_FILE(STAGE_FILE),.GEOMETRY_FILE(GEOMETRY_FILE)) core(
        .clk(clk),.rst_n(rst_n),.frame_start(accepted_start),.pixel_valid(pixel_valid),.gray(gray),.model_select(model_select),
        .ready(core_ready),.busy(busy),.done(done),.candidate_valid(candidate_valid),
        .box_x(box_x),.box_y(box_y),.box_size(box_size),.center_x(),.center_y(),.cycles(cycles),.feature_count(feature_count),
        .search_enable(search_enable),.search_x0(search_x0),.search_y0(search_y0),.search_x1(search_x1),.search_y1(search_y1),
        .search_scale_lo(search_scale_lo),.search_scale_hi(search_scale_hi));
    face_candidate_select select_target(
        .clk(clk),.rst_n(rst_n),.frame_start(accepted_start),.frame_done(done),
        .candidate_valid(candidate_valid),.box_x(box_x),.box_y(box_y),.box_size(box_size),
        .result_valid(result_valid),.target_found(target_found),.overflow(overflow),.select_busy(select_busy),
        .target_x(target_x),.target_y(target_y),.target_size(target_size),.target_votes(target_votes),
        .target_center_x(target_center_x),.target_center_y(target_center_y));
endmodule
