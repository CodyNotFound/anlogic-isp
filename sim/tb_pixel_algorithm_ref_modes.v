`timescale 1ns/1ps
module tb_pixel_algorithm_ref_modes;
 reg clk=0,rst_n=0,de=0,sof=0,eol=0;
 reg [3:0] mode;
 reg [23:0] pixel;
 wire [23:0] out [0:10];
 reg [23:0] captured [0:10];
 integer x,y,m;
 genvar g;
 generate for(g=0;g<11;g=g+1) begin:dut_array
  pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(4),.ADAPTIVE_BINARY(1),.BINARY_BIAS(8)) dut(
   .clk(clk),.rst_n(rst_n),.mode(g[3:0]),.frame_start(sof),.line_end(eol),.de(de),
   .pixel_in(pixel),.pixel_out(out[g]));
 end endgenerate
 always #3.333 clk=~clk;
 task drive;input integer x_in,y_in;
 begin @(negedge clk);de=1;sof=(x_in==0&&y_in==0);eol=(x_in==15);pixel=24'h102030;@(posedge clk);#1;for(m=0;m<11;m=m+1)captured[m]=out[m];end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(y=0;y<4;y=y+1)begin
   for(x=0;x<16;x=x+1)drive(x,y);
   @(negedge clk);de=0;sof=0;eol=0;repeat(3)@(negedge clk);
  end
  @(negedge clk);#1;
  if(captured[0]!==24'h102030)$fatal(1,"mode0 restore/pass %h",captured[0]);
  if(captured[1]!==24'h202020)$fatal(1,"mode1 gray %h",captured[1]);
  if(captured[2]!==24'hefdfcf)$fatal(1,"mode2 invert %h",captured[2]);
  if(captured[3]!==24'h000000)$fatal(1,"mode3 binary %h",captured[3]);
  if(captured[4]!==24'h304050)$fatal(1,"mode4 bright %h",captured[4]);
  if(captured[5]!==24'h202020)$fatal(1,"mode5 sharpen %h",captured[5]);
  if(captured[6]!==24'h242424)$fatal(1,"mode6 blur %h",captured[6]);
  if(captured[7]!==24'h000000)$fatal(1,"mode7 edge %h",captured[7]);
  if(captured[8]!==24'h808080)$fatal(1,"mode8 emboss %h",captured[8]);
  if(captured[9]!==24'h161811)$fatal(1,"mode9 sepia %h",captured[9]);
  if(captured[10]!==24'h301020)$fatal(1,"mode10 swap %h",captured[10]);
  $display("PASS tb_pixel_algorithm_ref_modes outputs 0..10");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule



