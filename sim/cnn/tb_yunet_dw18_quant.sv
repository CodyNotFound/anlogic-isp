`timescale 1ns/1ps
module tb_yunet_dw18_quant;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;reg signed [17:0] a;reg signed [6:0] sh;reg rel;
 wire [7:0] rd;wire [31:0] word;
 yunet_network dut(.clk(clk),.io_clk(clk),.rst_n(rst),.start(1'b0),.load_valid(1'b0),.load_address(17'd0),.load_data(8'd0),.read_address(17'd0),.read_data(rd),.busy(),.done(),.operation_done(),.operation_index(),.cycles(),.read_word(word));
 integer s,i,seed=291018,count=0;reg signed [63:0] q;reg signed [7:0] expected;
 task check;input signed [17:0] x;input [6:0] shift;input r;
 begin
  @(negedge clk);a=x;sh=shift;rel=r;
  q=$signed(x);if(shift>0)q=(q+(64'sd1<<(shift-1)))>>>shift;
  expected=(r&&q<0)?0:q>127?127:q< -128?-128:q[7:0];
  @(posedge clk);#1;
  if(dut.dw_quant_value!==expected)$fatal(1,"DW18 mismatch a%0d shift%0d relu%0d got%0d expected%0d",x,shift,r,$signed(dut.dw_quant_value),expected);
  count=count+1;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  force dut.state=5'd25;force dut.dw_drain=3'd2;
  force dut.dw_sum0=a;force dut.dw_shift0=sh;force dut.dw_relu_q=rel;
  for(s=0;s<32;s=s+1)begin
   check(-18'sd131072,s,0);check(-18'sd131072,s,1);
   check(18'sd131071,s,0);check(18'sd131071,s,1);
   check(-1,s,0);check(0,s,0);check(1,s,1);
   check(-128,s,0);check(127,s,0);
   for(i=0;i<1024;i=i+1)check($random(seed),s,i[0]);
  end
  $display("PASS tb_yunet_dw18_quant: %0d cases, 0..31 shifts, signed extrema and relu against 64-bit reference",count);$finish;
 end
endmodule