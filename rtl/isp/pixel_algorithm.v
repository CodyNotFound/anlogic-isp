// Streaming pixel algorithms in the HDMI pixel clock domain.
// ref-compatible scalar modes: 0 color restore (ISP chain passed through untouched),
// then the legacy ladder: 1 gray, 2 invert, 3 fixed binary, 4 bright, 5 sharpen,
// 6 blur, 7 edge, 8 emboss, 9 cel cartoon, 10 RGB rotation.
// All modes have four registered clocks of latency; qualifiers must match.
module pixel_algorithm #(
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
    output wire [23:0] pixel_out
);
    localparam SUM_BITS=$clog2(IMG_WIDTH*IMG_HEIGHT*256+1);
    reg[SUM_BITS-1:0]binary_luma_sum;reg binary_any;
    reg[7:0]binary_threshold,gray_reg;reg[23:0]pixel_in_reg;
    reg de_reg,frame_start_reg;reg[3:0]mode_reg;
    localparam[7:0] BINARY_TH_MIN=24,BINARY_TH_MAX=224;
    // R/4 + G/2 + B/4 (maximum 253 after per-channel truncation).


    wire [7:0] gray = {2'b0,pixel_in[23:18]} + {1'b0,pixel_in[15:9]} + {2'b0,pixel_in[7:2]};
    // 1280x720 has 921600 active pixels.  146/2^27 is its reciprocal to
    // better than 0.2%; the shift/add form avoids a run-time divider.
    wire [39:0] binary_avg_product =
                         ({{(40-SUM_BITS){1'b0}},binary_luma_sum} << 7) +
                         ({{(40-SUM_BITS){1'b0}},binary_luma_sum} << 4) +
                         ({{(40-SUM_BITS){1'b0}},binary_luma_sum} << 1);
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

    function[7:0] bright8;input[7:0]value;reg[8:0]sum;begin sum={1'b0,value}+32;bright8=sum>255?255:sum[7:0];end endfunction
    reg[23:0]legacy_pixel,pixel_d2,pixel_d3,pixel_d4;
    reg[3:0]mode_d2,mode_d3,mode_d4;
    wire[23:0]cartoon_pixel,cartoon_edge,sharp_pixel,blur_pixel,emboss_pixel;wire cartoon_de;
    pixel_cartoon #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.EXTRA_EFFECTS(1)) u_cartoon(
     .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.line_end(line_end),.de(de),.pixel_in(pixel_in),
     .pixel_out(cartoon_pixel),.out_de(cartoon_de),.out_sof(),.out_eol(),.edge_out(cartoon_edge),.sharpen_out(sharp_pixel),.blur_out(blur_pixel),.emboss_out(emboss_pixel));
    assign pixel_out=!cartoon_de?24'd0:mode_d4==9?cartoon_pixel:mode_d4==7?cartoon_edge:
                     mode_d4==5?sharp_pixel:mode_d4==6?blur_pixel:mode_d4==8?emboss_pixel:pixel_d4;
    always @*begin
     case(mode_reg)
      1:legacy_pixel={gray_reg,gray_reg,gray_reg};
      2:legacy_pixel=~pixel_in_reg;
      3:legacy_pixel=gray_reg>=binary_threshold_used?24'hffffff:24'd0;
      4:legacy_pixel={bright8(pixel_in_reg[23:16]),bright8(pixel_in_reg[15:8]),bright8(pixel_in_reg[7:0])};
      10:legacy_pixel={pixel_in_reg[7:0],pixel_in_reg[23:16],pixel_in_reg[15:8]};
      default:legacy_pixel=pixel_in_reg;
     endcase
     if(!de_reg)legacy_pixel=0;
    end
    always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin
      pixel_d2<=0;pixel_d3<=0;pixel_d4<=0;mode_d2<=0;mode_d3<=0;mode_d4<=0;
      gray_reg<=0;pixel_in_reg<=0;de_reg<=0;frame_start_reg<=0;mode_reg<=0;
      binary_threshold<=BINARY_TH;binary_luma_sum<=0;binary_any<=0;
     end else begin
      pixel_d2<=legacy_pixel;pixel_d3<=pixel_d2;pixel_d4<=pixel_d3;mode_d2<=mode_reg;mode_d3<=mode_d2;mode_d4<=mode_d3;
      gray_reg<=gray;pixel_in_reg<=pixel_in;de_reg<=de;frame_start_reg<=frame_start;mode_reg<=mode;
      if(frame_start_reg)begin
       if(binary_any)begin
        if(!ADAPTIVE_BINARY)binary_threshold<=BINARY_TH;
        else if(binary_threshold<binary_threshold_target)binary_threshold<=binary_threshold_target-binary_threshold>8?binary_threshold+8:binary_threshold_target;
        else if(binary_threshold>binary_threshold_target)binary_threshold<=binary_threshold-binary_threshold_target>8?binary_threshold-8:binary_threshold_target;
       end
       binary_luma_sum<=de_reg?gray_reg:0;binary_any<=de_reg;
      end else if(de_reg)begin binary_luma_sum<=binary_luma_sum+gray_reg;binary_any<=1;end
     end
    end
endmodule
