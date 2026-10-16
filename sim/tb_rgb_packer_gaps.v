`timescale 1ns/1ps
module tb_rgb_packer_gaps;
 reg clk=0,rst=0,v=0,sof=0;reg [95:0] data=0;wire ov,ou;wire [127:0] out;
 integer f,b,j,g,words=0,bad=0;reg [127:0] expected;
 always #5 clk=~clk;
 data_96bit_to_128bit dut(.I_clk(clk),.I_rst_n(rst),.I_96b_frame_start(sof),.I_96b_valid(v),
 .I_96b_data(data),.O_128b_frame_start(ou),.O_128b_valid(ov),.O_128b_data(out));
 function [7:0] byte_value;input integer frame,n;begin byte_value=(frame*31+n)&255;end endfunction
 always @(posedge clk)begin #1;if(rst&&ov)begin
  for(j=0;j<16;j=j+1)expected[127-j*8-:8]=byte_value(words/12,(words%12)*16+j);
  if(out!==expected)begin bad=bad+1;if(bad<3)$display("BAD packed word=%0d got=%h expected=%h",words,out,expected);end
  words=words+1;
 end end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<3;f=f+1)begin
   if(f==2)begin // Abandon an incomplete old frame at a new SOF.
    @(negedge clk);v=1;sof=0;data=96'hdeadbeef;
    @(negedge clk);v=0;repeat(4)@(negedge clk);
   end
   if(f!=1)begin @(negedge clk);sof=1;v=0;@(negedge clk);sof=0;end
   for(b=0;b<16;b=b+1)begin
    @(negedge clk);v=1;sof=(f==1&&b==0);
    for(g=0;g<12;g=g+1)data[95-g*8-:8]=byte_value(f,b*12+g);
    @(negedge clk);v=0;sof=0;data=96'hbad0;
    repeat((b%5)+1)@(negedge clk);
   end
   repeat(8)@(negedge clk);
  end
  if(words!=36||bad!=0)$fatal(1,"packer holes lost bytes words=%0d bad=%0d",words,bad);
  $display("PASS tb_rgb_packer_gaps 3 frames, holes at every phase, SOF discards old residual");$finish;
 end
endmodule
