// SW6 must select seven-segment hardware. Left H us, right V us.
module gimbal_panel #(parameter CLK_HZ=75000000)(
 input wire clk,rst_n,input wire [3:0] features,
 input wire [11:0] pulse_h,pulse_v,
 output wire [3:0] leds,output reg [7:0] segments,selects,
 output reg [23:0] h_digits,v_digits,
 output reg [11:0] display_h,display_v
);
 reg [4:0] convert_count;
 reg [11:0] captured_h,captured_v;
 wire [23:0] h_work,v_work;
 wire start=convert_count==0;
 assign leds=features;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   convert_count<=0;captured_h<=1500;captured_v<=1500;display_h<=1500;display_v<=1500;
   h_digits<=24'h001500;v_digits<=24'h001500;
  end else begin
   convert_count<=convert_count+1'b1;
   if(start)begin captured_h<=pulse_h;captured_v<=pulse_v;end
   // Publish the positions and their BCD representation as one coherent packet.
   if(convert_count==22)begin
    display_h<=captured_h;display_v<=captured_v;h_digits<=h_work;v_digits<=v_work;
   end
  end
 end
 vision_bcd hconv(clk,rst_n,start,{8'b0,pulse_h},h_work);
 vision_bcd vconv(clk,rst_n,start,{8'b0,pulse_v},v_work);
 localparam SLOT=CLK_HZ/1000;
 localparam CW=(SLOT<2)?1:$clog2(SLOT);
 reg [CW-1:0] count;reg [2:0] index;
 reg [31:0] display_word;
 wire [3:0] digit=display_word>>((7-index)*4);
 function [7:0] encode;
 input [3:0] d;
 begin case(d)
 0:encode=8'hc0;1:encode=8'hf9;2:encode=8'ha4;3:encode=8'hb0;
 4:encode=8'h99;5:encode=8'h92;6:encode=8'h82;7:encode=8'hf8;
 8:encode=8'h80;9:encode=8'h90;default:encode=8'hff;
 endcase end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin count<=0;index<=0;display_word<=32'h15001500;segments<=8'hff;selects<=8'hff;end
  else begin
   if(count==SLOT-1)begin count<=0;index<=index+1'b1;end else count<=count+1'b1;
   // PNP digit enables are active-low (factory 5_seg_SCAN). Break before make: blank, update segments, then enable next digit.
   if(count==0)begin selects<=8'hff;if(index==0)display_word<={h_digits[15:0],v_digits[15:0]};end
   if(count==1)segments<=encode(digit);
   if(count==2)selects<=~(8'b1<<index);
  end
 end
endmodule
