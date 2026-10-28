// Frontal-face cascade with larger windows and rotation retries. One shared
// cascade/integral RAM, one 160x90 byte snapshot. No parallel CNN or rotator DSP.
// Upright success returns immediately; otherwise evaluate all four roll views
// and select the valid group with most votes (votes are not probabilities).
module face_pose_snapshot #(
    parameter integer TRACKING_ENABLE=0,
    parameter integer LOCAL_RADIUS=12,
    parameter WEAK_FILE="rtl/analytics/face_lbp/human_weak.hex",
    parameter STAGE_FILE="rtl/analytics/face_lbp/human_stage.hex",
    parameter GEOMETRY_FILE="rtl/analytics/face_lbp/human_geometry.hex"
)(
    input wire clk,rst_n,frame_start,pixel_valid,
    input wire [7:0] gray,
    output wire ready,busy,
    output reg result_valid,target_found,
    output reg [7:0] target_x,target_y,target_size,target_votes,
    output reg [8:0] target_center_x,target_center_y,
    output reg [2:0] target_view,
    output reg [31:0] cycles,feature_count
);
    localparam IDLE=0,CAPTURE=1,PREPARE=2,START=3,ADDRESS=4,READ=5,EMIT=6,
        WAIT_RESULT=7,MAP_CENTER=8,MAP_BOX=9,PUBLISH=10,
        PATCH_INIT=11,PATCH_REQ=12,PATCH_WA=13,PATCH_A=14,PATCH_WB=15,PATCH_B=16,
        PATCH_SCORE=17,PATCH_NEXT=18,PATCH_DONE=19,PATCH_PUBLISH=20;
    reg [4:0] state;
    reg [7:0] snapshot[0:14399];
    reg [13:0] capture_addr,read_addr;
    reg [7:0] snapshot_q;
    reg core_start,core_pixel_valid,in_bounds;
    reg [7:0] core_gray;
    wire core_ready,core_result,core_found,core_overflow;
    wire [7:0] core_x,core_y,core_size,core_votes;
    wire [8:0] core_cx,core_cy;
    wire [31:0] core_features;
    reg [2:0] view,best_view;
    reg history_valid,local_search;
    reg [2:0] history_view;
    reg [7:0] history_x,history_y,best_anchor_x,best_anchor_y;
    reg [3:0] history_scale,best_scale;
    // A small gradient template bridges at most two missed cascade results.
    // It shares the existing snapshot read port; no second frame RAM/cascade.
    (* ram_style="dram" *) reg signed [8:0] patch_template[0:63];
    reg signed [8:0] patch_q,patch_gradient;
    reg [7:0] patch_a;
    reg [5:0] patch_index;
    reg patch_valid,patch_seeding,patch_pass,patch_good,patch_used;
    reg [1:0] unverified_frames;
    reg [7:0] patch_x,patch_y,patch_left,patch_right,patch_top,patch_bottom,patch_best_x,patch_best_y;
    reg [15:0] patch_sad,patch_best,patch_second,patch_texture;
    wire signed [9:0] patch_error=$signed({patch_gradient[8],patch_gradient})-$signed({patch_q[8],patch_q});
    wire [9:0] patch_abs_error=patch_error[9]?-patch_error:patch_error;
    wire [8:0] patch_abs_gradient=patch_gradient[8]?-patch_gradient:patch_gradient;
    wire patch_far=patch_x+2<patch_best_x || patch_best_x+2<patch_x || patch_y+2<patch_best_y || patch_best_y+2<patch_y;
    wire [8:0] patch_cx={1'b0,patch_best_x}+9'd4,patch_cy={1'b0,patch_best_y}+9'd4;
    wire signed [10:0] patch_box_x=$signed({2'd0,patch_cx})-$signed({3'd0,target_size[7:1]});
    wire signed [10:0] patch_box_y=$signed({2'd0,patch_cy})-$signed({3'd0,target_size[7:1]});
    wire [7:0] local_x0=history_x<LOCAL_RADIUS?0:history_x-LOCAL_RADIUS;
    wire [7:0] local_y0=history_y<LOCAL_RADIUS?0:history_y-LOCAL_RADIUS;
    wire [7:0] local_x1=history_x+LOCAL_RADIUS>159?159:history_x+LOCAL_RADIUS;
    wire [7:0] local_y1=history_y+LOCAL_RADIUS>89?89:history_y+LOCAL_RADIUS;
    function [3:0] scale_of;
        input [7:0] size;
        begin case(size)24:scale_of=0;28:scale_of=1;32:scale_of=2;40:scale_of=3;
            48:scale_of=4;64:scale_of=5;72:scale_of=6;80:scale_of=7;default:scale_of=8;endcase end
    endfunction
    reg [7:0] best_size,best_votes,mapped_size;
    reg [8:0] best_cx,best_cy;
    reg [7:0] out_x,out_y;
    reg signed [17:0] sample_x,sample_y,row_x,row_y;
    wire signed [17:0] source_x=(sample_x+18'sd128)>>>8;
    wire signed [17:0] source_y=(sample_y+18'sd128)>>>8;
    wire valid_source=source_x>=0 && source_x<160 && source_y>=0 && source_y<90;
    // Q8 cos/sin for views 0,+30,-30,+15,-15 degrees. Inverse nearest-neighbor
    // sampling rotates about (80,45), pads with gray 96, and rounds +128 >> 8.
    function signed [9:0] cosine;
        input [2:0] v;
        begin case(v) 0:cosine=256;1,2:cosine=222;default:cosine=247;endcase end
    endfunction
    function signed [9:0] sine;
        input [2:0] v;
        begin case(v) 0:sine=0;1:sine=128;2:sine=-128;3:sine=66;default:sine=-66;endcase end
    endfunction
    function signed [17:0] origin_x;
        input [2:0] v;
        begin case(v)0:origin_x=0;1:origin_x=-3040;2:origin_x=8480;3:origin_x=-2250;default:origin_x=3690;endcase end
    endfunction
    function signed [17:0] origin_y;
        input [2:0] v;
        begin case(v)0:origin_y=0;1:origin_y=11770;2:origin_y=-8710;3:origin_y=5685;default:origin_y=-4875;endcase end
    endfunction
    function signed [17:0] cos_product;
        input signed [17:0] value;
        input [2:0] v;
        begin case(v)
            0:cos_product=value<<<8;
            1,2:cos_product=(value<<<8)-(value<<<5)-(value<<<1);
            default:cos_product=(value<<<8)-(value<<<3)-value;
        endcase end
    endfunction
    function signed [17:0] sin_product;
        input signed [17:0] value;
        input [2:0] v;
        reg signed [17:0] magnitude;
        begin
            magnitude=(v==1 || v==2) ? (value<<<7) : (value<<<6)+(value<<<1);
            sin_product=v==0 ? 18'sd0 : (v==2 || v==4) ? -magnitude : magnitude;
        end
    endfunction
    wire signed [17:0] dx=$signed({9'd0,best_cx})-18'sd80;
    wire signed [17:0] dy=$signed({9'd0,best_cy})-18'sd45;
    wire signed [17:0] mapped_x=(18'sd20480+cos_product(dx,best_view)+sin_product(dy,best_view)+18'sd128)>>>8;
    wire signed [17:0] mapped_y=(18'sd11520-sin_product(dx,best_view)+cos_product(dy,best_view)+18'sd128)>>>8;
    wire signed [17:0] size_sin=sin_product($signed({10'd0,best_size}),best_view);
    wire signed [17:0] envelope=(cos_product($signed({10'd0,best_size}),best_view)+
        (size_sin<0 ? -size_sin : size_sin)+18'sd255)>>>8;
    wire signed [10:0] left=$signed({2'd0,target_center_x})-$signed({4'd0,mapped_size[7:1]});
    wire signed [10:0] top=$signed({2'd0,target_center_y})-$signed({4'd0,mapped_size[7:1]});
    assign ready=state==IDLE;
    assign busy=state!=IDLE;
    always @(posedge clk) begin
        snapshot_q<=snapshot[read_addr];
        patch_q<=patch_template[patch_index];
        if(state==PATCH_SCORE && patch_seeding)patch_template[patch_index]<=patch_gradient;
        if(state==CAPTURE && pixel_valid) snapshot[capture_addr]<=gray;
    end
    face_detector_snapshot #(.HUMAN_ONLY(1),.NUM_SCALES(9),.SEARCH_SUPPORT(TRACKING_ENABLE),
        .WEAK_FILE(WEAK_FILE),.STAGE_FILE(STAGE_FILE),.GEOMETRY_FILE(GEOMETRY_FILE)) detector(
        .clk(clk),.rst_n(rst_n),.frame_start(core_start),.pixel_valid(core_pixel_valid),.gray(core_gray),.model_select(1'b0),
        .ready(core_ready),.busy(),.result_valid(core_result),.target_found(core_found),.overflow(core_overflow),
        .target_x(core_x),.target_y(core_y),.target_size(core_size),.target_votes(core_votes),
        .target_center_x(core_cx),.target_center_y(core_cy),.cycles(),.feature_count(core_features),
        .search_enable(local_search),.search_x0(local_x0),.search_y0(local_y0),.search_x1(local_x1),.search_y1(local_y1),
        .search_scale_lo(history_scale==0?4'd0:history_scale-4'd1),
        .search_scale_hi(history_scale==8?4'd8:history_scale+4'd1));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;capture_addr<=0;read_addr<=0;core_start<=0;core_pixel_valid<=0;core_gray<=0;in_bounds<=0;
            view<=0;best_view<=0;best_size<=0;best_votes<=0;best_cx<=0;best_cy<=0;mapped_size<=0;
            out_x<=0;out_y<=0;sample_x<=0;sample_y<=0;row_x<=0;row_y<=0;
            result_valid<=0;target_found<=0;target_x<=0;target_y<=0;target_size<=0;target_votes<=0;
            target_center_x<=0;target_center_y<=0;target_view<=0;cycles<=0;feature_count<=0;
            history_valid<=0;local_search<=0;history_view<=0;
            history_x<=0;history_y<=0;best_anchor_x<=0;best_anchor_y<=0;history_scale<=0;best_scale<=0;
            patch_a<=0;patch_gradient<=0;patch_index<=0;patch_valid<=0;patch_seeding<=0;patch_pass<=0;patch_good<=0;patch_used<=0;
            unverified_frames<=0;patch_x<=0;patch_y<=0;patch_left<=0;patch_right<=0;patch_top<=0;patch_bottom<=0;
            patch_best_x<=0;patch_best_y<=0;patch_sad<=0;patch_best<=0;patch_second<=0;patch_texture<=0;
        end else begin
            core_start<=0;core_pixel_valid<=0;result_valid<=0;
            if(busy)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(frame_start) begin
                    state<=CAPTURE;capture_addr<=0;best_votes<=0;best_size<=0;
                    local_search<=TRACKING_ENABLE && history_valid;
                    view<=TRACKING_ENABLE && history_valid?history_view:0;
                    patch_good<=0;patch_used<=0;
                    best_view<=0;best_cx<=0;best_cy<=0;cycles<=0;feature_count<=0;
                end
                CAPTURE:if(pixel_valid) begin
                    if(capture_addr==14399)state<=TRACKING_ENABLE && patch_valid && history_valid?PATCH_INIT:PREPARE;
                    else capture_addr<=capture_addr+1'b1;
                end
                PREPARE:if(core_ready)begin
                    sample_x<=origin_x(view);sample_y<=origin_y(view);
                    row_x<=origin_x(view);row_y<=origin_y(view);out_x<=0;out_y<=0;state<=START;
                end
                START:begin core_start<=1;state<=ADDRESS;end
                ADDRESS:begin
                    in_bounds<=valid_source;
                    read_addr<=valid_source ? ({source_y[8:0],7'b0}+{source_y[8:0],5'b0}+source_x[7:0]) : 14'd0;
                    state<=READ;
                end
                READ:state<=EMIT;
                EMIT:begin
                    core_pixel_valid<=1;core_gray<=in_bounds ? snapshot_q : 8'd96;
                    if(out_x==159 && out_y==89)state<=WAIT_RESULT;
                    else begin
                        if(out_x==159)begin
                            out_x<=0;out_y<=out_y+1'b1;
                            row_x<=row_x+sine(view);row_y<=row_y+cosine(view);
                            sample_x<=row_x+sine(view);sample_y<=row_y+cosine(view);
                        end else begin
                            out_x<=out_x+1'b1;sample_x<=sample_x+cosine(view);sample_y<=sample_y-sine(view);
                        end
                        state<=ADDRESS;
                    end
                end
                WAIT_RESULT:if(core_result)begin
                    feature_count<=feature_count+core_features;
                    if(core_found && !core_overflow && core_votes>best_votes)begin
                        best_votes<=core_votes;best_view<=view;best_size<=core_size;best_cx<=core_cx;best_cy<=core_cy;
                        best_anchor_x<=core_x;best_anchor_y<=core_y;best_scale<=scale_of(core_size);
                    end
                    if(local_search)begin
                        if(core_found && !core_overflow)state<=MAP_CENTER;
                        else if(patch_good && unverified_frames<2)state<=PATCH_PUBLISH;
                        else begin local_search<=0;view<=0;best_votes<=0;state<=PREPARE;end
                    end else if((view==0 && core_found && !core_overflow) || view==4)begin
                        if(view==4 && best_votes<3 && !(core_found && !core_overflow) && patch_good && unverified_frames<2)state<=PATCH_PUBLISH;
                        else state<=MAP_CENTER;
                    end
                    else begin view<=view+1'b1;state<=PREPARE;end
                end
                MAP_CENTER:begin
                    if(best_votes>=3)unverified_frames<=0;else patch_valid<=0;
                    history_valid<=best_votes>=3;history_view<=best_view;
                    history_x<=best_anchor_x;history_y<=best_anchor_y;history_scale<=best_scale;
                    target_found<=best_votes>=3;target_votes<=best_votes;target_view<=best_view;
                    mapped_size<=envelope>90 ? 90 : envelope[7:0];
                    target_center_x<=best_votes<3 ? 0 : mapped_x<0 ? 0 : mapped_x>159 ? 159 : mapped_x[8:0];
                    target_center_y<=best_votes<3 ? 0 : mapped_y<0 ? 0 : mapped_y>89 ? 89 : mapped_y[8:0];
                    state<=MAP_BOX;
                end
                MAP_BOX:begin
                    target_size<=best_votes<3 ? 0 : mapped_size;
                    target_x<=best_votes<3 ? 0 : left<0 ? 0 : left>160-mapped_size ? 160-mapped_size : left[7:0];
                    target_y<=best_votes<3 ? 0 : top<0 ? 0 : top>90-mapped_size ? 90-mapped_size : top[7:0];
                    if(TRACKING_ENABLE && best_votes>=3)begin
                        patch_x<=target_center_x<4?0:target_center_x>155?151:target_center_x-4;
                        patch_y<=target_center_y<4?0:target_center_y>86?82:target_center_y-4;
                        patch_seeding<=1;patch_index<=0;patch_texture<=0;state<=PATCH_REQ;
                    end else state<=PUBLISH;
                end
                PATCH_INIT:begin
                    patch_left<=target_center_x<12?0:target_center_x-12;
                    patch_right<=target_center_x+4>151?151:target_center_x+4;
                    patch_top<=target_center_y<12?0:target_center_y-12;
                    patch_bottom<=target_center_y+4>82?82:target_center_y+4;
                    patch_x<=target_center_x<12?0:target_center_x-12;
                    patch_y<=target_center_y<12?0:target_center_y-12;
                    patch_index<=0;patch_sad<=0;patch_best<=16'hffff;patch_second<=16'hffff;
                    patch_pass<=0;patch_seeding<=0;state<=PATCH_REQ;
                end
                PATCH_REQ:begin
                    read_addr<=(patch_y+patch_index[5:3])*160+patch_x+patch_index[2:0];state<=PATCH_WA;
                end
                PATCH_WA:state<=PATCH_A;
                PATCH_A:begin patch_a<=snapshot_q;read_addr<=read_addr+1'b1;state<=PATCH_WB;end
                PATCH_WB:state<=PATCH_B;
                PATCH_B:begin patch_gradient<=$signed({1'b0,snapshot_q})-$signed({1'b0,patch_a});state<=PATCH_SCORE;end
                PATCH_SCORE:begin
                    if(patch_seeding)patch_texture<=patch_texture+patch_abs_gradient;
                    else patch_sad<=patch_sad+patch_abs_error;
                    if(patch_index==63)begin
                        if(patch_seeding)begin patch_valid<=patch_texture+patch_abs_gradient>=256;state<=PUBLISH;end
                        else state<=PATCH_NEXT;
                    end else begin patch_index<=patch_index+1'b1;state<=PATCH_REQ;end
                end
                PATCH_NEXT:begin
                    if(!patch_pass && patch_sad<patch_best)begin patch_best<=patch_sad;patch_best_x<=patch_x;patch_best_y<=patch_y;end
                    if(patch_pass && patch_far && patch_sad<patch_second)patch_second<=patch_sad;
                    patch_index<=0;patch_sad<=0;
                    if(patch_x==patch_right && patch_y==patch_bottom)begin
                        if(patch_pass)state<=PATCH_DONE;
                        else begin patch_pass<=1;patch_x<=patch_left;patch_y<=patch_top;state<=PATCH_REQ;end
                    end else begin
                        if(patch_x==patch_right)begin patch_x<=patch_left;patch_y<=patch_y+1'b1;end
                        else patch_x<=patch_x+1'b1;
                        state<=PATCH_REQ;
                    end
                end
                PATCH_DONE:begin
                    patch_good<=patch_best<=512 && {1'b0,patch_second}>={1'b0,patch_best}+17'd64;state<=PREPARE;
                end
                PATCH_PUBLISH:begin
                    target_found<=1;target_votes<=0;target_view<=history_view;
                    target_center_x<=patch_cx;target_center_y<=patch_cy;
                    target_x<=patch_box_x<0?0:patch_box_x>160-target_size?160-target_size:patch_box_x[7:0];
                    target_y<=patch_box_y<0?0:patch_box_y>90-target_size?90-target_size:patch_box_y[7:0];
                    unverified_frames<=unverified_frames+1'b1;patch_used<=1;
                    state<=PUBLISH;
                end
                PUBLISH:begin result_valid<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
