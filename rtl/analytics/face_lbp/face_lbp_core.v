// Trained, categorical LBP cascade; no skin-color threshold or synthetic face.
// One snapshot at a time. frame_start is a preamble with no pixel_valid;
// then exactly WIDTH*HEIGHT raster gray pixels, with arbitrary valid gaps.
// Accept a new snapshot only when ready. busy snapshots must be dropped upstream.
// model_select: 0=OpenCV frontal human, 1=nagadomi anime (NOT all figurines).
// candidate_valid reports ALL accepted windows, not a qualified servo target.
module face_lbp_core #(
    parameter integer WIDTH = 160,
    parameter integer HEIGHT = 90,
    parameter integer STRIDE = 1,
    parameter integer HUMAN_ONLY = 0,
    parameter integer NUM_SCALES = 6,
    parameter integer SEARCH_SUPPORT = 0,
    parameter WEAK_FILE = "rtl/analytics/face_lbp/weak.hex",
    parameter STAGE_FILE = "rtl/analytics/face_lbp/stage.hex",
    parameter GEOMETRY_FILE = "rtl/analytics/face_lbp/geometry.hex"
)(
    input wire clk, rst_n,
    input wire frame_start, pixel_valid,
    input wire [7:0] gray,
    input wire model_select,
    output wire ready,
    output reg busy, done,
    output reg candidate_valid,
    output reg [7:0] box_x, box_y, box_size,
    output wire [8:0] center_x, center_y,
    output reg [31:0] cycles,
    output reg [31:0] feature_count,
    input wire search_enable,
    input wire [7:0] search_x0,search_y0,search_x1,search_y1,
    input wire [3:0] search_scale_lo,search_scale_hi
);
    localparam integer NW = HUMAN_ONLY ? 139 : 910;
    localparam IDLE=0,CAPTURE=1,DRAIN=2,START_WINDOW=3,LOAD_STAGE=4,
        LOAD_WEAK=5,LOAD_GEOM=6,READ_CORNER=7,TAKE_CORNER=8,
        MAKE_CELLS=9,MAKE_CODE=10,ADD_LEAF=11,CHECK_STAGE=12,NEXT_WINDOW=13;
    reg [3:0] state;
    reg [21:0] integral [0:WIDTH*HEIGHT-1];
    // TD SWUG106: use the documented "bram" value for compact ROMs. Without
    // this, the small human-only tables can expand into thousands of LUTs.
    (* rom_style="bram" *) reg [303:0] weak_rom [0:NW-1];
    reg [43:0] stage_rom [0:(HUMAN_ONLY ? 20 : 40)-1];
    (* rom_style="bram" *) reg [27:0] geometry_rom [0:NW*NUM_SCALES-1];
    initial begin
        $readmemh(WEAK_FILE,weak_rom);
        $readmemh(STAGE_FILE,stage_rom);
        $readmemh(GEOMETRY_FILE,geometry_rom);
    end
    reg [7:0] cap_x,cap_y;
    reg [13:0] cap_addr, write_addr;
    reg [15:0] row_sum, write_row_sum;
    reg write_pending,write_first_row;
    reg [21:0] ram_q;
    reg [13:0] ram_addr;
    reg [3:0] scale_index;
    reg [7:0] win_x,win_y,win_size;
    reg [7:0] search_left,search_top,search_right,search_bottom;
    reg [3:0] final_scale;
    wire [8:0] image_right=WIDTH-win_size,image_bottom=HEIGHT-win_size;
    wire [8:0] scan_right=search_right<image_right?search_right:image_right;
    wire [8:0] scan_bottom=search_bottom<image_bottom?search_bottom:image_bottom;
    wire window_in_bounds=win_x<=scan_right && win_y<=scan_bottom;
    reg [5:0] stage_index, last_stage;
    reg [9:0] weak_index, last_weak;
    reg [303:0] weak_data;
    reg [43:0] stage_data;
    reg [27:0] geom_data;
    reg signed [31:0] stage_sum;
    wire signed [23:0] stage_threshold = stage_data[23:0];
    wire signed [23:0] leaf_left = weak_data[47:24];
    wire signed [23:0] leaf_right = weak_data[23:0];
    reg [3:0] corner_index;
    reg [21:0] corner[0:15];
    reg [21:0] cell_sum[0:8];
    reg [7:0] lbp_code;
    reg corner_zero;
    integer k;
    reg [8:0] grid_x,grid_y;
    reg [8:0] offset_x,offset_y;
    reg [13:0] geometry_base;
    wire [8:0] grid_row=grid_y-1'b1;
    wire [6:0] fx=geom_data[27:21],fy=geom_data[20:14];
    wire [6:0] fw=geom_data[13:7],fh=geom_data[6:0];
    assign ready=(state==IDLE);
    assign center_x={1'b0,box_x}+({1'b0,box_size}>>1);
    assign center_y={1'b0,box_y}+({1'b0,box_size}>>1);
    function [7:0] size_at;
        input [3:0] index;
        begin
            case(index)
                0:size_at=24; 1:size_at=28; 2:size_at=32;
                3:size_at=40; 4:size_at=48; 5:size_at=64;
                6:size_at=72;7:size_at=80;default:size_at=88;
            endcase
        end
    endfunction
    // Shift/add column offsets avoid variable multipliers. WIDTH is constant.
    always @* begin
        case(corner_index[1:0])
            0:offset_x=0; 1:offset_x=fw;
            2:offset_x={fw,1'b0}; default:offset_x={fw,1'b0}+fw;
        endcase
        case(corner_index[3:2])
            0:offset_y=0; 1:offset_y=fh;
            2:offset_y={fh,1'b0}; default:offset_y={fh,1'b0}+fh;
        endcase
        grid_x=win_x+{2'b0,fx}+offset_x;
        grid_y=win_y+{2'b0,fy}+offset_y;
        case(scale_index)
            0:geometry_base=0;1:geometry_base=NW;2:geometry_base=NW*2;
            3:geometry_base=NW*3;4:geometry_base=NW*4;5:geometry_base=NW*5;
            6:geometry_base=NW*6;7:geometry_base=NW*7;default:geometry_base=NW*8;
        endcase
        ram_addr=0;
        if(state==CAPTURE && pixel_valid && cap_y!=0)
            ram_addr=cap_addr-WIDTH;
        else if(grid_x!=0 && grid_y!=0)
            if(WIDTH==160) ram_addr=({grid_row,7'b0}+{grid_row,5'b0})+grid_x-1;
            else ram_addr=(grid_y-1)*WIDTH+grid_x-1;
    end
    // A synchronous read and an independent synchronous write infer SDP ERAM.
    // Integral border at x=0/y=0 is virtual, and never reads uninitialized RAM.
    always @(posedge clk) begin
        ram_q<=integral[ram_addr];
        if(write_pending)
            integral[write_addr] <= write_row_sum + (write_first_row ? 22'd0 : ram_q);
    end
    // Synchronous, non-reset ROM outputs are required for ERAM inference.
    // State sequencing always loads a valid entry before consuming it; clearing
    // these data registers on reset is unnecessary and prevents TD BRAM mapping.
    always @(posedge clk) begin
        stage_data<=stage_rom[stage_index];
        weak_data<=weak_rom[weak_index];
        geom_data<=geometry_rom[geometry_base+weak_index];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;done<=0;candidate_valid<=0;
            cap_x<=0;cap_y<=0;cap_addr<=0;row_sum<=0;write_pending<=0;
            write_addr<=0;write_row_sum<=0;write_first_row<=0;
            scale_index<=0;win_x<=0;win_y<=0;win_size<=24;
            search_left<=0;search_top<=0;search_right<=WIDTH-24;search_bottom<=HEIGHT-24;final_scale<=NUM_SCALES-1;
            stage_index<=0;last_stage<=19;weak_index<=0;last_weak<=0;
            stage_sum<=0;
            corner_index<=0;corner_zero<=0;lbp_code<=0;
            box_x<=0;box_y<=0;box_size<=0;cycles<=0;feature_count<=0;
        end else begin
            done<=0;candidate_valid<=0;write_pending<=0;
            if(busy) cycles<=cycles+1'b1;
            case(state)
                IDLE:if(frame_start) begin
                    state<=CAPTURE;busy<=1;cycles<=0;feature_count<=0;
                    cap_x<=0;cap_y<=0;cap_addr<=0;row_sum<=0;
                    stage_index<=!HUMAN_ONLY && model_select ? 20 : 0;
                    last_stage<=!HUMAN_ONLY && model_select ? 39 : 19;
                    if(SEARCH_SUPPORT && search_enable)begin
                        scale_index<=search_scale_lo;final_scale<=search_scale_hi;
                        win_size<=size_at(search_scale_lo);
                        win_x<=search_x0;win_y<=search_y0;
                        search_left<=search_x0;search_top<=search_y0;search_right<=search_x1;search_bottom<=search_y1;
                    end else begin
                        scale_index<=0;final_scale<=NUM_SCALES-1;win_x<=0;win_y<=0;win_size<=24;
                        search_left<=0;search_top<=0;search_right<=WIDTH-24;search_bottom<=HEIGHT-24;
                    end
                end
                CAPTURE:if(pixel_valid) begin
                    write_pending<=1;write_addr<=cap_addr;
                    write_first_row<=(cap_y==0);
                    write_row_sum<=row_sum+gray;
                    cap_addr<=cap_addr+1'b1;
                    if(cap_x==WIDTH-1) begin
                        cap_x<=0;cap_y<=cap_y+1'b1;row_sum<=0;
                    end else begin cap_x<=cap_x+1'b1;row_sum<=row_sum+gray;end
                    if(cap_addr==WIDTH*HEIGHT-1) state<=DRAIN;
                end
                DRAIN:state<=START_WINDOW;
                START_WINDOW:begin
                    stage_index<=last_stage==39 ? 20 : 0;
                    state<=window_in_bounds?LOAD_STAGE:NEXT_WINDOW;
                end
                LOAD_STAGE:state<=LOAD_WEAK;
                LOAD_WEAK:begin
                    weak_index<=stage_data[43:34];last_weak<=stage_data[33:24];
                    stage_sum<=0;state<=LOAD_GEOM;
                end
                LOAD_GEOM:begin
                    corner_index<=0;feature_count<=feature_count+1'b1;
                    state<=READ_CORNER;
                end
                READ_CORNER:begin
                    if(corner_index!=0) corner[corner_index-1'b1]<=corner_zero ? 22'd0 : ram_q;
                    corner_zero<=(grid_x==0 || grid_y==0);
                    if(corner_index==15) state<=TAKE_CORNER;
                    else corner_index<=corner_index+1'b1;
                end
                TAKE_CORNER:begin
                    corner[corner_index]<=corner_zero ? 22'd0 : ram_q;
                    state<=MAKE_CELLS;
                end
                MAKE_CELLS:begin
                    for(k=0;k<9;k=k+1)
                        cell_sum[k]<=corner[(k/3)*4+k%3]+corner[(k/3)*4+k%3+5]
                                    -corner[(k/3)*4+k%3+1]-corner[(k/3)*4+k%3+4];
                    state<=MAKE_CODE;
                end
                MAKE_CODE:begin
                    lbp_code<={cell_sum[0]>=cell_sum[4],cell_sum[1]>=cell_sum[4],
                               cell_sum[2]>=cell_sum[4],cell_sum[5]>=cell_sum[4],
                               cell_sum[8]>=cell_sum[4],cell_sum[7]>=cell_sum[4],
                               cell_sum[6]>=cell_sum[4],cell_sum[3]>=cell_sum[4]};
                    state<=ADD_LEAF;
                end
                ADD_LEAF:begin
                    stage_sum<=stage_sum+(weak_data[48+lbp_code] ? leaf_left : leaf_right);
                    if(weak_index==last_weak) state<=CHECK_STAGE;
                    else begin weak_index<=weak_index+1'b1;state<=LOAD_GEOM;end
                end
                CHECK_STAGE:begin
                    if(stage_sum<stage_threshold) state<=NEXT_WINDOW;
                    else if(stage_index==last_stage) begin
                        candidate_valid<=1;box_x<=win_x;box_y<=win_y;box_size<=win_size;
                        state<=NEXT_WINDOW;
                    end else begin stage_index<=stage_index+1'b1;state<=LOAD_STAGE;end
                end
                NEXT_WINDOW:begin
                    if(window_in_bounds && win_x+STRIDE<=scan_right) begin win_x<=win_x+STRIDE;state<=START_WINDOW;end
                    else if(window_in_bounds && win_y+STRIDE<=scan_bottom) begin win_x<=search_left;win_y<=win_y+STRIDE;state<=START_WINDOW;end
                    else if(scale_index<final_scale) begin
                        win_x<=search_left;win_y<=search_top;scale_index<=scale_index+1'b1;
                        win_size<=size_at(scale_index+1'b1);state<=START_WINDOW;
                    end else begin state<=IDLE;busy<=0;done<=1;end
                end
                default:begin state<=IDLE;busy<=0;end
            endcase
        end
    end
endmodule
