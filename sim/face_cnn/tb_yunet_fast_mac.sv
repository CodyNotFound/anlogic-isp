`timescale 1ns/1ps
module tb_yunet_fast_mac;
 reg clk=0;always #3.333 clk=~clk;
 reg rst=0,start=0,iv=0,last=0,relu=0;reg signed [31:0] bias;reg signed [6:0] shift;
 reg [35:0] act=0;reg [31:0] wt=0;wire ready,ir,ov;wire signed [31:0] acc;wire signed [7:0] value;
 yunet_dot4 #(.MODEL_SHIFT(1),.FAST_PIPELINE(1)) dut(.clk(clk),.rst_n(rst),.start(start),.bias(bias),.shift(shift),.relu(relu),.ready(ready),.in_valid(iv),.in_ready(ir),.in_last(last),.activations(act),.weights(wt),.out_valid(ov),.out_ready(1'b1),.accumulator(acc),.value(value));
 integer seed=20261029,t,n,j,k,stall;reg signed [31:0] expected;reg signed [63:0] wide;reg signed [7:0] expected_value;reg signed [8:0] a;reg signed [7:0] w;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(t=0;t<2048;t=t+1)begin
   wait(ready);@(negedge clk);bias=$random(seed);shift=t%32;relu=t[0];expected=bias;start=1;
   @(negedge clk);start=0;n=1+($random(seed)&15);
   for(j=0;j<n;j=j+1)begin
    stall=$random(seed)&3;iv=0;repeat(stall)@(negedge clk);
    wait(ir);for(k=0;k<4;k=k+1)begin
     a=$random(seed);w=$random(seed);act[k*9+:9]=a;wt[k*8+:8]=w;expected=expected+a*w;
    end
    last=j==n-1;iv=1;@(negedge clk);iv=0;
   end
   wide={{32{expected[31]}},expected};if(shift>0)wide=(wide+(64'sd1<<(shift-1)))>>>shift;
   expected_value=(relu&&wide<0)?0:wide>127?127:wide< -128?-128:wide[7:0];
   wait(ov);@(negedge clk);
   if(acc!==expected||value!==expected_value)$fatal(1,"MAC mismatch t%0d shift%0d acc%0d expected%0d value%0d expected_value%0d",t,shift,acc,expected,value,expected_value);
  end
  $display("PASS tb_yunet_fast_mac: 2048 dots, shift0..31, signed overflow, ReLU and input stalls");$finish;
 end
 initial begin #10000000;$fatal(1,"fast MAC watchdog");end
endmodule
