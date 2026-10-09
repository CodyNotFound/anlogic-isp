`timescale 1ns/1ps
module raw_lsc_grid4 #(parameter integer ENABLE=1, BLACK_LEVEL=67)(
 input wire I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,I_blc_on,I_lsc_on,
 input wire [39:0] I_tdata,input wire [9:0] I_tdest,input wire O_tready,
 output wire I_tready,output reg O_tvalid,O_tuser,O_tlast,
 output reg [39:0] O_tdata,output reg [9:0] O_tdest);
 // I_blc_on/I_lsc_on: 运行时使能(帧首锁存), 分别控制黑电平减除与LSC增益——
 // ISP分步演示用(步2=+BLC, 步3=+LSC); 全关时数据几何/时序与全开完全一致
 reg blc_on_f,lsc_on_f;
 assign I_tready=O_tready;
 function [47:0] grid_word; input [7:0] addr; begin case(addr)
 `include "colorshading_lut_case.vh"
 default:grid_word=48'h400400400400; endcase end endfunction
 function [11:0] interp_gain;
 input [11:0] a,b;input [7:0] fraction;
 reg signed [12:0] delta;reg signed [8:0] weight;
 reg signed [21:0] product;reg signed [22:0] accumulator,result;
 begin delta=$signed({1'b0,b})-$signed({1'b0,a});weight=$signed({1'b0,fraction});
 product=delta*weight;accumulator=$signed({3'b000,a,8'b0})+$signed({product[21],product})+23'sd128;
 result=accumulator>>>8;interp_gain=result[11:0];end endfunction
 function [9:0] subtract_black;input [9:0] sample;
 begin if(sample>BLACK_LEVEL)subtract_black=sample-BLACK_LEVEL;else subtract_black=0;end endfunction
 function [9:0] apply_gain;input [9:0] sample;input [11:0] gain;
 reg [21:0] product;reg [22:0] rounded_product;
 begin product=sample*gain;rounded_product={1'b0,product}+23'd512;
 if(rounded_product>=23'd1048576)apply_gain=1023;else apply_gain=rounded_product[19:10];end endfunction
 function [7:0] fraction_x;input [6:0] offset;reg [14:0] numerator;
 begin numerator={offset,8'b0};fraction_x=numerator/15'd80;end endfunction
 function [7:0] fraction_y;input [5:0] offset;reg [13:0] numerator;
 begin numerator={offset,8'b0};fraction_y=numerator/14'd60;end endfunction
 reg [10:0] x_count;reg [9:0] y_count;
 wire [10:0] effective_x=I_tuser?11'd0:x_count;
 wire [9:0] effective_y=I_tuser?10'd0:y_count;
 wire [3:0] grid_x=effective_x/11'd80,grid_y=effective_y/10'd60;
 wire [10:0] cell_origin_x=grid_x*11'd80;wire [9:0] cell_origin_y=grid_y*10'd60;
 wire [6:0] offset_x=effective_x-cell_origin_x;wire [5:0] offset_y=effective_y-cell_origin_y;
 wire [7:0] address_tl=({4'd0,grid_y}*8'd17)+{4'd0,grid_x};
 wire [7:0] address_tr=address_tl+8'd1,address_bl=address_tl+8'd17,address_br=address_tl+8'd18;
 reg s1_valid,s1_user,s1_last,s1_odd_row;
 reg [9:0] s1_dest;reg [39:0] s1_pixels;reg [47:0] s1_tl,s1_tr,s1_bl,s1_br;
 reg [7:0] s1_y_fraction,s1_x_fraction0,s1_x_fraction1,s1_x_fraction2,s1_x_fraction3;
 reg s2_valid,s2_user,s2_last;reg [9:0] s2_dest;reg [39:0] s2_pixels;
 reg [11:0] s2_left_even,s2_right_even,s2_left_odd,s2_right_odd;
 reg [7:0] s2_x_fraction0,s2_x_fraction1,s2_x_fraction2,s2_x_fraction3;
 reg s3_valid,s3_user,s3_last;reg [9:0] s3_dest;reg [39:0] s3_pixels;
 reg [11:0] s3_gain0,s3_gain1,s3_gain2,s3_gain3;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 blc_on_f<=1;lsc_on_f<=1;
 x_count<=0;y_count<=0;
 s1_valid<=0;s1_user<=0;s1_last<=0;s1_dest<=0;s1_pixels<=0;
 s1_tl<=0;s1_tr<=0;s1_bl<=0;s1_br<=0;s1_odd_row<=0;s1_y_fraction<=0;
 s1_x_fraction0<=0;s1_x_fraction1<=0;s1_x_fraction2<=0;s1_x_fraction3<=0;
 s2_valid<=0;s2_user<=0;s2_last<=0;s2_dest<=0;s2_pixels<=0;
 s2_left_even<=0;s2_right_even<=0;s2_left_odd<=0;s2_right_odd<=0;
 s2_x_fraction0<=0;s2_x_fraction1<=0;s2_x_fraction2<=0;s2_x_fraction3<=0;
 s3_valid<=0;s3_user<=0;s3_last<=0;s3_dest<=0;s3_pixels<=0;
 s3_gain0<=0;s3_gain1<=0;s3_gain2<=0;s3_gain3<=0;
 O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;O_tdest<=0;
 end else if(O_tready)begin
 if(I_tvalid&&I_tuser)begin blc_on_f<=I_blc_on;lsc_on_f<=I_lsc_on;end
 if(I_tvalid)begin
 if(I_tlast)begin x_count<=0;y_count<=(effective_y==719)?0:effective_y+10'd1;end
 else begin x_count<=effective_x+11'd4;y_count<=effective_y;end end
 s1_valid<=I_tvalid;s1_user<=I_tuser;s1_last<=I_tlast;s1_dest<=I_tdest;
 if(I_tvalid)begin
 s1_tl<=grid_word(address_tl);s1_tr<=grid_word(address_tr);s1_bl<=grid_word(address_bl);s1_br<=grid_word(address_br);
 s1_odd_row<=effective_y[0];s1_y_fraction<=fraction_y(offset_y);
 s1_x_fraction0<=fraction_x(offset_x);s1_x_fraction1<=fraction_x(offset_x+7'd1);
 s1_x_fraction2<=fraction_x(offset_x+7'd2);s1_x_fraction3<=fraction_x(offset_x+7'd3);
 if(ENABLE!=0&&blc_on_f)begin
 s1_pixels[9:0]<=subtract_black(I_tdata[9:0]);s1_pixels[19:10]<=subtract_black(I_tdata[19:10]);
 s1_pixels[29:20]<=subtract_black(I_tdata[29:20]);s1_pixels[39:30]<=subtract_black(I_tdata[39:30]);
 end else s1_pixels<=I_tdata;end
 s2_valid<=s1_valid;s2_user<=s1_user;s2_last<=s1_last;s2_dest<=s1_dest;s2_pixels<=s1_pixels;
 s2_x_fraction0<=s1_x_fraction0;s2_x_fraction1<=s1_x_fraction1;s2_x_fraction2<=s1_x_fraction2;s2_x_fraction3<=s1_x_fraction3;
 if(s1_odd_row)begin
 s2_left_even<=interp_gain(s1_tl[11:0],s1_bl[11:0],s1_y_fraction);
 s2_right_even<=interp_gain(s1_tr[11:0],s1_br[11:0],s1_y_fraction);
 s2_left_odd<=interp_gain(s1_tl[35:24],s1_bl[35:24],s1_y_fraction);
 s2_right_odd<=interp_gain(s1_tr[35:24],s1_br[35:24],s1_y_fraction);
 end else begin
 s2_left_even<=interp_gain(s1_tl[23:12],s1_bl[23:12],s1_y_fraction);
 s2_right_even<=interp_gain(s1_tr[23:12],s1_br[23:12],s1_y_fraction);
 s2_left_odd<=interp_gain(s1_tl[47:36],s1_bl[47:36],s1_y_fraction);
 s2_right_odd<=interp_gain(s1_tr[47:36],s1_br[47:36],s1_y_fraction);end
 s3_valid<=s2_valid;s3_user<=s2_user;s3_last<=s2_last;s3_dest<=s2_dest;s3_pixels<=s2_pixels;
 s3_gain0<=interp_gain(s2_left_even,s2_right_even,s2_x_fraction0);
 s3_gain1<=interp_gain(s2_left_odd,s2_right_odd,s2_x_fraction1);
 s3_gain2<=interp_gain(s2_left_even,s2_right_even,s2_x_fraction2);
 s3_gain3<=interp_gain(s2_left_odd,s2_right_odd,s2_x_fraction3);
 O_tvalid<=s3_valid;O_tuser<=s3_user;O_tlast<=s3_last;O_tdest<=s3_dest;
 if(ENABLE!=0&&lsc_on_f)begin
 O_tdata[9:0]<=apply_gain(s3_pixels[9:0],s3_gain0);O_tdata[19:10]<=apply_gain(s3_pixels[19:10],s3_gain1);
 O_tdata[29:20]<=apply_gain(s3_pixels[29:20],s3_gain2);O_tdata[39:30]<=apply_gain(s3_pixels[39:30],s3_gain3);
 end else O_tdata<=s3_pixels;
 end end
endmodule
