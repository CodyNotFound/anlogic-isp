`timescale 1ns/1ps
module tb_yunet_address_exact;
 reg clk=0;always #5 clk=~clk;
 yunet_network dut(.clk(clk),.rst_n(1'b0),.start(1'b0),.load_valid(1'b0),.load_address(17'd0),.load_data(8'd0),.read_address(17'd0),.read_data(),.busy(),.done(),.operation_done(),.operation_index(),.cycles(),.read_word());
 integer i,c,n,w,seed=20261029;reg [7:0] y,x;reg [16:0] base,expected,actual;reg [6:0] ch;reg [2:0] cs;
 initial begin
  #1;
  for(i=0;i<200000;i=i+1)begin
   case(i%5)0:cs=0;1:cs=2;2:cs=4;3:cs=5;4:cs=6;endcase
   n=1<<cs;
   case((i/5)%6)0:w=160;1:w=80;2:w=40;3:w=20;4:w=10;5:w=5;endcase
   y=$random(seed);x=$random(seed);base=($random(seed)&17'h1ffff)&~(n-1);ch=$random(seed)&(n-1);
   expected=base+((y*w+x)<<cs)+ch;
   actual=dut.feature_index(base,y,x,w,ch,cs);
   if(actual!==expected)$fatal(1,"address mismatch case=%0d got=%0d expected=%0d",i,actual,expected);
  end
  $display("PASS tb_yunet_address_exact: 200000 aligned cases, all channel counts and row widths, wraparound included");$finish;
 end
endmodule
