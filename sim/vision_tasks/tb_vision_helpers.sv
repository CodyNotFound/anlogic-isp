`timescale 1ns/1ps
module tb_vision_helpers;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,bstart=0;reg [23:0] a,b;reg [19:0] value;
 wire done,busy;wire [23:0] q,digits;
 vision_unsigned_divider dut(clk,rst_n,start,a,b,busy,done,q);
 vision_bcd bcd(clk,rst_n,bstart,value,digits);
 integer i,j,v;reg [23:0] expected;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(i=0;i<200;i=i+1)begin
   @(negedge clk);a=$random&24'hffffff;b=($random&24'h00ffff)+1;start=1;
   @(negedge clk);start=0;wait(done);#1;if(q!==a/b)$fatal(1,"division %0d/%0d = %0d",a,b,q);
  end
  @(negedge clk);a=24'hffffff;b=0;start=1;@(negedge clk);start=0;
  if(!done||q!==24'hffffff)$fatal(1,"zero denominator handling");
  for(i=0;i<40;i=i+1)begin
   @(negedge clk);value=i==0?0:i==1?921600:($random&20'hfffff)%1000000;bstart=1;
   v=value;expected=0;for(j=0;j<6;j=j+1)begin expected[j*4+:4]=v%10;v=v/10;end
   @(negedge clk);bstart=0;repeat(22)@(negedge clk);
   if(digits!==expected)$fatal(1,"BCD %0d got %h expected %h",value,digits,expected);
  end
  $display("PASS tb_vision_helpers: 201 division and 40 decimal conversion cases");$finish;
 end
 initial begin #2000000;$fatal(1,"helper timeout");end
endmodule
