`timescale 1ns/1ps
module color_tone4 #(
 parameter integer ENABLE=1,SAT_Q8=384,DEFRINGE_ENABLE=1,TONE_ENABLE=1
)(
 input wire I_clk,I_rst_n,I_tvalid,input wire [95:0] I_tdata, input wire I_tuser,I_tlast,I_sat_on,I_tone_on,
 output wire I_tready,output wire O_tvalid,input wire O_tready,
 output wire O_tuser,O_tlast,output wire [95:0] O_tdata
);
 assign I_tready=O_tready;
 // I_sat_on/I_tone_on: 运行时使能(帧首锁存)——ISP分步演示用(步5=+饱和, 步6=+sRGB色调+去紫边)。
 // 三级各自门控, 全关时四级流水变成同延迟直通, 数据几何/时序与全开完全一致。
 reg sat_on_f,tone_on_f;
 wire [95:0] tone_out;
 assign O_tdata=tone_out;
 reg [95:0] s0_data_reg;reg s0_valid_reg,s0_user_reg,s0_last_reg;
 reg [23:0] s0_previous_left_reg;reg s0_neighbor_valid_reg;
 reg [95:0] s1_data_reg;reg s1_valid_reg,s1_user_reg,s1_last_reg;
 reg [95:0] s2_data_reg;reg s2_valid_reg,s2_user_reg,s2_last_reg;
 reg [95:0] s3_data_reg;reg s3_valid_reg,s3_user_reg,s3_last_reg;
 reg [23:0] input_previous_pixel_reg;reg input_previous_valid_reg;
 assign tone_out=s3_data_reg;assign O_tvalid=s3_valid_reg;
 assign O_tuser=s3_user_reg;assign O_tlast=s3_last_reg;

 function [7:0] pixel_luma;
 input [23:0] pixel;reg [7:0] r,g,b;reg [15:0] r_ext,g_ext,b_ext,sum;
 begin
  r=pixel[23:16];g=pixel[15:8];b=pixel[7:0];
  r_ext={8'd0,r};g_ext={8'd0,g};b_ext={8'd0,b};
  // Exact shift-add form; preserves the original truncation without rounding bias.
  sum=(r_ext<<6)+(r_ext<<3)+(r_ext<<2)+r_ext
     +(g_ext<<7)+(g_ext<<4)+(g_ext<<2)+(g_ext<<1)
     +(b_ext<<4)+(b_ext<<3)+(b_ext<<2)+b_ext;
  pixel_luma=sum[15:8];
 end endfunction

 function [23:0] defringe_pixel;
 input [23:0] pixel,left_pixel;input left_valid;
 reg [7:0] r,g,b,left_y,this_y,min_rb,purple,y_diff;reg [8:0] g_raised;
 begin
  r=pixel[23:16];g=pixel[15:8];b=pixel[7:0];
  left_y=pixel_luma(left_pixel);this_y=pixel_luma(pixel);
  min_rb=(r<b)?r:b;
  purple=(min_rb>g)?min_rb-g:8'd0;
  y_diff=(this_y>=left_y)?this_y-left_y:left_y-this_y;
  if(DEFRINGE_ENABLE!=0&&left_valid&&min_rb>g+8'd8&&purple!=0&&y_diff>8'd16)begin
   g_raised={1'b0,g}+{2'b00,purple[7:1]};
   if(g_raised>9'd255)g=8'd255;else g=g_raised[7:0];
  end
  defringe_pixel={r,g,b};
 end endfunction

 function[7:0]sat15;input[7:0]c,y;reg signed[8:0]d;reg signed[9:0]q;
 begin d=$signed({1'b0,c})-$signed({1'b0,y});q=$signed({1'b0,c})+(d>>>1);
 sat15=q[9]?8'd0:q[8]?8'd255:q[7:0];end endfunction

 function [23:0] saturation_pixel;
 input [23:0] pixel;
 reg [7:0] r,g,b,y,max_rgb,min_rgb;reg signed [10:0] dr,dg,db;
 reg [8:0] shadow_r,shadow_g,shadow_b;
 reg signed [20:0] dr_ext,dg_ext,db_ext,r_scaled,g_scaled,b_scaled,r_out,g_out,b_out;
 begin
  r=pixel[23:16];g=pixel[15:8];b=pixel[7:0];y=pixel_luma(pixel);
  shadow_r={1'b0,r}+{1'b0,y};shadow_g={1'b0,g}+{1'b0,y};shadow_b={1'b0,b}+{1'b0,y};
  max_rgb=r;if(g>max_rgb)max_rgb=g;if(b>max_rgb)max_rgb=b;
  min_rgb=r;if(g<min_rgb)min_rgb=g;if(b<min_rgb)min_rgb=b;
  // Suppress poorly conditioned shadow chroma before gamma lifts black noise.
  // Bright/color reference pixels retain the established saturation mapping.
  if(max_rgb-min_rgb<8||y<24)saturation_pixel=pixel;
  else begin
   dr=$signed({1'b0,r})-$signed({1'b0,y});
   dg=$signed({1'b0,g})-$signed({1'b0,y});
   db=$signed({1'b0,b})-$signed({1'b0,y});
   dr_ext={{10{dr[10]}},dr};dg_ext={{10{dg[10]}},dg};db_ext={{10{db[10]}},db};
   if(SAT_Q8==384)begin
    r_scaled=0;g_scaled=0;b_scaled=0;
   end else if(SAT_Q8==614)begin
    r_scaled=(dr_ext<<<9)+(dr_ext<<<6)+(dr_ext<<<5)+(dr_ext<<<2)+(dr_ext<<<1);
    g_scaled=(dg_ext<<<9)+(dg_ext<<<6)+(dg_ext<<<5)+(dg_ext<<<2)+(dg_ext<<<1);
    b_scaled=(db_ext<<<9)+(db_ext<<<6)+(db_ext<<<5)+(db_ext<<<2)+(db_ext<<<1);
   end else begin
    r_scaled=dr_ext*SAT_Q8;g_scaled=dg_ext*SAT_Q8;b_scaled=db_ext*SAT_Q8;
   end
   if(SAT_Q8==384)begin
    // y+floor(1.5*(c-y)) == c+floor((c-y)/2), including negative differences.
    r=sat15(r,y);g=sat15(g,y);b=sat15(b,y);
   end else begin
    r_out=$signed({1'b0,y})+(r_scaled>>>8);
    g_out=$signed({1'b0,y})+(g_scaled>>>8);
    b_out=$signed({1'b0,y})+(b_scaled>>>8);
    if(r_out<0)r=0;else if(r_out>255)r=255;else r=r_out[7:0];
    if(g_out<0)g=0;else if(g_out>255)g=255;else g=g_out[7:0];
    if(b_out<0)b=0;else if(b_out>255)b=255;else b=b_out[7:0];
   end
   saturation_pixel={r,g,b};
  end
 end endfunction

 function [7:0] tone_value;input [7:0] value;
 begin case(value)
 `include "colorshading_gamma_case.vh"
 default:tone_value=value;endcase end endfunction
 function [23:0] tone_pixel;input [23:0] pixel;
 begin if(TONE_ENABLE!=0)tone_pixel={tone_value(pixel[23:16]),tone_value(pixel[15:8]),tone_value(pixel[7:0])};
 else tone_pixel=pixel;end endfunction

 integer lane,tone_lane;reg [95:0] s1_data_next,s3_data_next;
 reg [23:0] current_pixel,left_pixel;reg left_valid;
 always @* begin
  s1_data_next=s0_data_reg;current_pixel=0;left_pixel=0;left_valid=0;
  for(lane=0;lane<4;lane=lane+1)begin
   current_pixel=s0_data_reg[(lane*24)+:24];
   if(lane==0)begin left_pixel=s0_previous_left_reg;left_valid=s0_neighbor_valid_reg;end
   else begin left_pixel=s0_data_reg[((lane-1)*24)+:24];left_valid=1;end
   s1_data_next[(lane*24)+:24]=defringe_pixel(current_pixel,left_pixel,left_valid);
  end
 end
 always @* begin
  s3_data_next=s2_data_reg;
  for(tone_lane=0;tone_lane<4;tone_lane=tone_lane+1)
   s3_data_next[(tone_lane*24)+:24]=tone_pixel(s2_data_reg[(tone_lane*24)+:24]);
 end

 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   sat_on_f<=1;tone_on_f<=1;
   s0_data_reg<=0;s0_valid_reg<=0;s0_user_reg<=0;s0_last_reg<=0;
   s0_previous_left_reg<=0;s0_neighbor_valid_reg<=0;
   s1_data_reg<=0;s1_valid_reg<=0;s1_user_reg<=0;s1_last_reg<=0;
   s2_data_reg<=0;s2_valid_reg<=0;s2_user_reg<=0;s2_last_reg<=0;
   s3_data_reg<=0;s3_valid_reg<=0;s3_user_reg<=0;s3_last_reg<=0;
   input_previous_pixel_reg<=0;input_previous_valid_reg<=0;
  end else if(O_tready)begin
   if(I_tvalid&&I_tuser)begin sat_on_f<=I_sat_on;tone_on_f<=I_tone_on;end
   s0_valid_reg<=I_tvalid;s0_user_reg<=I_tvalid&&I_tuser;s0_last_reg<=I_tvalid&&I_tlast;
   if(I_tvalid)begin
    s0_data_reg<=I_tdata;s0_previous_left_reg<=input_previous_pixel_reg;
    s0_neighbor_valid_reg<=input_previous_valid_reg&&!I_tuser;
    input_previous_pixel_reg<=I_tdata[95:72];input_previous_valid_reg<=!I_tlast;
   end else s0_neighbor_valid_reg<=0;

   s1_valid_reg<=s0_valid_reg;s1_user_reg<=s0_user_reg;s1_last_reg<=s0_last_reg;
   if(s0_valid_reg)begin if(ENABLE!=0&&tone_on_f)s1_data_reg<=s1_data_next;else s1_data_reg<=s0_data_reg;end
   s2_valid_reg<=s1_valid_reg;s2_user_reg<=s1_user_reg;s2_last_reg<=s1_last_reg;
   if(s1_valid_reg)begin
    if(ENABLE!=0&&sat_on_f)s2_data_reg<={
     saturation_pixel(s1_data_reg[95:72]),saturation_pixel(s1_data_reg[71:48]),
     saturation_pixel(s1_data_reg[47:24]),saturation_pixel(s1_data_reg[23:0])};
    else s2_data_reg<=s1_data_reg;
   end
   s3_valid_reg<=s2_valid_reg;s3_user_reg<=s2_user_reg;s3_last_reg<=s2_last_reg;
   if(s2_valid_reg)begin if(ENABLE!=0&&tone_on_f)s3_data_reg<=s3_data_next;else s3_data_reg<=s2_data_reg;end
  end
 end
endmodule

