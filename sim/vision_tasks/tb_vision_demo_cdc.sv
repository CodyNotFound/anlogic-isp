`timescale 1ns/1ps
module tb_vision_demo_cdc;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0;reg [3:0] input_demo=5;wire [3:0] demo;
 vision_demo_cdc dut(clk,rst_n,input_demo,demo);
 integer i;
 initial begin
  #23;rst_n=1;repeat(10)@(negedge clk);if(demo!=5)$fatal(1,"CDC reset");
  for(i=0;i<6;i=i+1)begin
   #3;input_demo=8+i;
   repeat(10)@(negedge clk);if(demo!==8+i)$fatal(1,"CDC stable value %0d",i);
  end
  input_demo=8;repeat(10)@(negedge clk);if(demo!=8)$fatal(1,"CDC baseline");
  // Simulate bit skew across a two-bit change for less than one dst period.
  #3;input_demo=9;#6;input_demo=11;
  repeat(10)begin @(negedge clk);if(demo!=8 && demo!=11)$fatal(1,"CDC committed skew value %h",demo);end
  if(demo!=11)$fatal(1,"CDC target not committed");
  // Invalid active demo steps 6/7 are never committed.
  input_demo=15;repeat(12)@(negedge clk);if(demo!=11)$fatal(1,"CDC invalid step committed");
  input_demo=5;repeat(10)@(negedge clk);if(demo!=5)$fatal(1,"CDC exit");
  $display("PASS tb_vision_demo_cdc: stable steps, sub-cycle bit skew, invalid code, normal exit");$finish;
 end
 initial begin #100000;$fatal(1,"CDC timeout");end
endmodule
