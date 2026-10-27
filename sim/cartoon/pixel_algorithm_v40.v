// Streaming pixel algorithms in the HDMI pixel clock domain.
// ref-compatible scalar modes: 0 color restore (ISP chain passed through untouched),
// then the legacy ladder: 1 gray, 2 invert, 3 fixed binary, 4 bright, 5 sharpen,
// 6 blur, 7 edge, 8 emboss, 9 sepia, 10 RGB rotation. (原"原图旁路"模式已删除,
// 改由 K3 ISP 分步演示承载, 见 mode_ctrl.)
module pixel_algorithm_v40 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer BINARY_TH = 8'd96,
    parameter integer EDGE_TH = 11'd80,
    parameter integer ADAPTIVE_BINARY = 1,
    parameter integer BINARY_BIAS = 8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] mode,
    input  wire       frame_start,
    input  wire       line_end,
    input  wire       de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    reg [10:0] x;
    reg [10:0] y;
    (* ram_style = "dram" *) reg [7:0] line1 [0:IMG_WIDTH-1];
    (* ram_style = "dram" *) reg [7:0] line2 [0:IMG_WIDTH-1];
    reg [7:0] top_prev2, top_prev1, mid_prev2, mid_prev1, bot_prev2, bot_prev1;
    reg [31:0] binary_luma_sum;
    reg [21:0] binary_pixel_count;
    reg [7:0]  binary_threshold;

    // Split the expensive luma conversion from the spatial operator.  The
    // source stream is registered here; all spatial state below consumes the
    // same delayed pixel and delayed qualifiers.
    reg [7:0]  gray_reg;
    reg [23:0] pixel_in_reg;
    reg        de_reg;
    reg        frame_start_reg;
    reg        line_end_reg;
    reg [3:0]  mode_reg;

    localparam [7:0] BINARY_TH_MIN = 8'd24;
    localparam [7:0] BINARY_TH_MAX = 8'd224;

    // R/4 + G/2 + B/4 (maximum 253 after per-channel truncation).


    wire [7:0] gray = {2'b0,pixel_in[23:18]} + {1'b0,pixel_in[15:9]} + {2'b0,pixel_in[7:2]};
    // 1280x720 has 921600 active pixels.  146/2^27 is its reciprocal to
    // better than 0.2%; the shift/add form avoids a run-time divider.
    wire [39:0] binary_avg_product =
                         ({8'd0,binary_luma_sum} << 7) +
                         ({8'd0,binary_luma_sum} << 4) +
                         ({8'd0,binary_luma_sum} << 1);
    wire [8:0] binary_avg_calc = (IMG_WIDTH==1280 && IMG_HEIGHT==720) ?
        binary_avg_product[35:27] : binary_luma_sum/(IMG_WIDTH*IMG_HEIGHT);

    function [7:0] make_binary_threshold;
        input [8:0] average;
        reg [9:0] candidate;
        begin
            candidate = average + BINARY_BIAS;
            if (candidate < BINARY_TH_MIN)
                make_binary_threshold = BINARY_TH_MIN;
            else if (candidate > BINARY_TH_MAX)
                make_binary_threshold = BINARY_TH_MAX;
            else
                make_binary_threshold = candidate[7:0];
        end
    endfunction

    wire [7:0] binary_threshold_target =
                         make_binary_threshold(binary_avg_calc);
    wire [7:0] binary_threshold_used = ADAPTIVE_BINARY ?
                                        binary_threshold : BINARY_TH;
    wire [10:0] spatial_x=frame_start_reg?11'd0:x;
    wire [10:0] spatial_y=frame_start_reg?11'd0:y;
    wire [7:0] top_now = line2[spatial_x];
    wire [7:0] mid_now = line1[spatial_x];
    wire [7:0] bot_now = gray_reg;
    // ref Scharr kernel, expressed as shifts to avoid multipliers.
    wire signed [8:0] sch_gx_d0 = $signed({1'b0,top_now}) - $signed({1'b0,top_prev2});
    wire signed [8:0] sch_gx_d1 = $signed({1'b0,mid_now}) - $signed({1'b0,mid_prev2});
    wire signed [8:0] sch_gx_d2 = $signed({1'b0,bot_now}) - $signed({1'b0,bot_prev2});
    wire signed [8:0] sch_gy_d0 = $signed({1'b0,bot_prev2}) - $signed({1'b0,top_prev2});
    wire signed [8:0] sch_gy_d1 = $signed({1'b0,bot_prev1}) - $signed({1'b0,top_prev1});
    wire signed [8:0] sch_gy_d2 = $signed({1'b0,bot_now}) - $signed({1'b0,top_now});
    wire signed [10:0] sch_gx_t0 = (sch_gx_d0 <<< 1) + sch_gx_d0;
    wire signed [12:0] sch_gx_t1 = (sch_gx_d1 <<< 3) + (sch_gx_d1 <<< 1);
    wire signed [10:0] sch_gx_t2 = (sch_gx_d2 <<< 1) + sch_gx_d2;
    wire signed [10:0] sch_gy_t0 = (sch_gy_d0 <<< 1) + sch_gy_d0;
    wire signed [12:0] sch_gy_t1 = (sch_gy_d1 <<< 3) + (sch_gy_d1 <<< 1);
    wire signed [10:0] sch_gy_t2 = (sch_gy_d2 <<< 1) + sch_gy_d2;
    wire signed [12:0] sch_gx = $signed({{2{sch_gx_t0[10]}},sch_gx_t0}) + sch_gx_t1 +
                                 $signed({{2{sch_gx_t2[10]}},sch_gx_t2});
    wire signed [12:0] sch_gy = $signed({{2{sch_gy_t0[10]}},sch_gy_t0}) + sch_gy_t1 +
                                 $signed({{2{sch_gy_t2[10]}},sch_gy_t2});
    wire [12:0] abs_sch_gx = sch_gx[12] ? (~sch_gx + 13'd1) : sch_gx;
    wire [12:0] abs_sch_gy = sch_gy[12] ? (~sch_gy + 13'd1) : sch_gy;
    wire [13:0] magnitude = {1'b0,abs_sch_gx} + {1'b0,abs_sch_gy};
    wire [12:0] scharr_scaled = magnitude[13:4];
    wire edge_valid = de_reg && (spatial_y >= 11'd2) && (spatial_x >= 11'd2);
    wire [11:0] window_sum9 = {4'd0,top_prev2}+{4'd0,top_prev1}+{4'd0,top_now}+
                               {4'd0,mid_prev2}+{4'd0,mid_now}+{4'd0,mid_prev1}+
                               {4'd0,bot_prev2}+{4'd0,bot_prev1}+{4'd0,bot_now};
    wire [11:0] neighbor_sum = window_sum9-{4'd0,mid_now};
    wire [11:0] neighbor_avg = neighbor_sum>>3;
    wire signed [11:0] sharpen_value = $signed({3'd0,mid_now}<<1)-$signed({3'd0,neighbor_avg});
    wire signed [11:0] emboss_value = $signed({3'd0,mid_now})-$signed({3'd0,top_prev2})+12'sd128;

    function [7:0] clip9;
        input [8:0] value;
        begin clip9=(value>9'd255)?8'd255:value[7:0]; end
    endfunction
    function [7:0] clip_signed12;
        input signed [11:0] value;
        begin
            if(value<0) clip_signed12=8'd0;
            else if(value>12'sd255) clip_signed12=8'd255;
            else clip_signed12=value[7:0];
        end
    endfunction
    function [7:0] bright8;
        input [7:0] value;
        reg [8:0] sum;
        begin sum={1'b0,value}+9'd32; bright8=clip9(sum); end
    endfunction
    // [2026-10-14] 模式0改名"色彩还原": 增色(1.5x饱和度sat_boost8)逻辑按用户指示移除,
    // 模式0与模式1同为直通, 区别只在ISP链是否被bypass(见vision_pipeline/isp_top)。
    // Separable [1 2 1]^T[1 2 1]/16 Gaussian. Balanced sums avoid a
    // constant-divide chain on the 75MHz pixel path and preserve DC exactly.
    wire [8:0] gc0={1'b0,top_prev2}+{1'b0,top_now},gc1={1'b0,bot_prev2}+{1'b0,bot_now};
    wire [8:0] ge0={1'b0,top_prev1}+{1'b0,mid_prev2},ge1={1'b0,mid_now}+{1'b0,bot_prev1};
    wire [9:0] corners={1'b0,gc0}+{1'b0,gc1},sides={1'b0,ge0}+{1'b0,ge1};
    wire [11:0] gaussian_sum={2'd0,corners}+{1'b0,sides,1'b0}+{2'd0,mid_prev1,2'd0}+12'd8;
    wire [7:0] blur_value=edge_valid?gaussian_sum[11:4]:gray_reg;
    wire [7:0] sharpen_value8=edge_valid?clip_signed12(sharpen_value):gray_reg;
    wire [7:0] emboss_value8=edge_valid?clip_signed12(emboss_value):gray_reg;
    wire [23:0] binary_pixel = (gray_reg >= binary_threshold_used) ? 24'hffffff : 24'h000000;
    wire [23:0] gray_pixel = {gray_reg,gray_reg,gray_reg};
    wire [23:0] invert_pixel = {~pixel_in_reg[23:16],~pixel_in_reg[15:8],~pixel_in_reg[7:0]};
    wire [23:0] bright_pixel = {bright8(pixel_in_reg[23:16]),bright8(pixel_in_reg[15:8]),bright8(pixel_in_reg[7:0])};
    wire [23:0] sharpen_pixel={sharpen_value8,sharpen_value8,sharpen_value8};
    wire [23:0] blur_pixel={blur_value,blur_value,blur_value};
    wire [23:0] edge_pixel = (edge_valid && scharr_scaled >= EDGE_TH) ? 24'hffffff : 24'h000000;
    wire [23:0] emboss_pixel={emboss_value8,emboss_value8,emboss_value8};
    wire [23:0] sepia_pixel={{1'b0,pixel_in_reg[23:17]}+{2'd0,pixel_in_reg[15:10]}+{3'd0,pixel_in_reg[7:3]},
                             {3'd0,pixel_in_reg[23:19]}+{1'b0,pixel_in_reg[15:9]}+{3'd0,pixel_in_reg[7:3]},
                             {4'd0,pixel_in_reg[23:20]}+{3'd0,pixel_in_reg[15:11]}+{2'd0,pixel_in_reg[7:2]}};
    wire [23:0] rgb_swap_pixel={pixel_in_reg[7:0],pixel_in_reg[23:16],pixel_in_reg[15:8]};

    always @* begin
        case (mode_reg)
            4'd0: pixel_out=pixel_in_reg;   // 色彩还原: ISP链输出直通
            4'd1: pixel_out=gray_pixel;
            4'd2: pixel_out=invert_pixel;
            4'd3: pixel_out=binary_pixel;
            4'd4: pixel_out=bright_pixel;
            4'd5: pixel_out=sharpen_pixel;
            4'd6: pixel_out=blur_pixel;
            4'd7: pixel_out=edge_pixel;
            4'd8: pixel_out=emboss_pixel;
            4'd9: pixel_out=sepia_pixel;
            4'd10: pixel_out=rgb_swap_pixel;
            default: pixel_out=pixel_in_reg;
        endcase
        if (!de_reg) pixel_out = 24'd0;
    end

    // One explicit write port per line RAM, including coincident SOF+DE.
    always @(posedge clk)begin
        if(de_reg)begin line2[spatial_x]<=mid_now;line1[spatial_x]<=bot_now;end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0; y <= 0;
            top_prev2 <= 0; top_prev1 <= 0; mid_prev2 <= 0; mid_prev1 <= 0; bot_prev2 <= 0; bot_prev1 <= 0;
            binary_luma_sum <= 32'd0;
            binary_pixel_count <= 22'd0;
            binary_threshold <= BINARY_TH;
            gray_reg <= 8'd0;
            pixel_in_reg <= 24'd0;
            de_reg <= 1'b0;
            frame_start_reg <= 1'b0;
            line_end_reg <= 1'b0;
            mode_reg <= 4'd0;
        end else begin
            // Stage 1: register the exact BT.601 Y value and stream control.
            // Stage 2 below performs the line-buffer/Sobel operation on the
            // previous registered sample.
            gray_reg        <= gray;
            pixel_in_reg    <= pixel_in;
            de_reg          <= de;
            frame_start_reg <= frame_start;
            line_end_reg    <= line_end;
            mode_reg        <= mode;

            if (frame_start_reg) begin
            x <= de_reg && !line_end_reg ? 11'd1 : 11'd0; y <= de_reg && line_end_reg ? 11'd1 : 11'd0;
            top_prev2 <= 0; top_prev1 <= 0; mid_prev2 <= 0; mid_prev1 <= 0; bot_prev2 <= 0; bot_prev1 <= de_reg?gray_reg:8'd0;
            if (binary_pixel_count != 0) begin
                // Limit movement to eight levels per frame so illumination
                // changes do not flip the whole binary image immediately.
                if (!ADAPTIVE_BINARY)
                    binary_threshold <= BINARY_TH;
                else if (binary_threshold < binary_threshold_target) begin
                    if ((binary_threshold_target - binary_threshold) > 8)
                        binary_threshold <= binary_threshold + 8;
                    else
                        binary_threshold <= binary_threshold_target;
                end else if (binary_threshold > binary_threshold_target) begin
                    if ((binary_threshold - binary_threshold_target) > 8)
                        binary_threshold <= binary_threshold - 8;
                    else
                        binary_threshold <= binary_threshold_target;
                end
            end
            binary_luma_sum <= de_reg ? {{24{1'b0}},gray_reg} : 32'd0;
            binary_pixel_count <= de_reg ? 22'd1 : 22'd0;
            end else if (de_reg) begin
            binary_luma_sum <= binary_luma_sum + gray_reg;
            if (binary_pixel_count != 22'h3fffff)
                binary_pixel_count <= binary_pixel_count + 1'b1;
            top_prev2 <= top_prev1; top_prev1 <= top_now;
            mid_prev2 <= mid_prev1; mid_prev1 <= mid_now;
            bot_prev2 <= bot_prev1; bot_prev1 <= bot_now;
            if (line_end_reg) begin
                x <= 0;
                if (y == IMG_HEIGHT-1) y <= 0; else y <= y + 1'b1;
                top_prev2 <= 0; top_prev1 <= 0; mid_prev2 <= 0; mid_prev1 <= 0; bot_prev2 <= 0; bot_prev1 <= 0;
            end else if (x == IMG_WIDTH-1) x <= 0;
            else x <= x + 1'b1;
            end
        end
    end
endmodule


