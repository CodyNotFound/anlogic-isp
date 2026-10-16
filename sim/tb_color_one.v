`timescale 1ns/1ps
module tb_color_one;
 reg clk=0,rst=0,valid=0,ready=1;reg[95:0]data=0;
 wire ir,ov,ou,ol;wire[95:0]od;
 color_tone4 #(.ENABLE(1),.SAT_Q8(384),.DEFRINGE_ENABLE(0),.TONE_ENABLE(0)) dut(.I_sat_on(1'b1),.I_tone_on(1'b1),.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(0),.I_tlast(0),.I_tdata(data),.I_tready(ir),.O_tready(ready),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(od));
 integer n;
 always #5 clk=~clk;
 initial begin
  repeat(3)@(negedge clk);rst=1;@(negedge clk);valid=1;data={4{24'hdcb428}};@(negedge clk);valid=0;data=0;
  for(n=0;n<8;n=n+1)begin @(posedge clk);$display("%0d v=%0d out=%h s0=%h s1=%h s2=%h s3=%h",n,ov,od,dut.s0_data_reg,dut.s1_data_reg,dut.s2_data_reg,dut.s3_data_reg);end
  $finish;
 end
endmodule
