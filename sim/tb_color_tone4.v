`timescale 1ns/1ps
module tb_color_tone4;
 reg clk=0,rst=0,valid=0,ready=1;reg[95:0]data=0;
 wire in_ready,out_valid,out_user,out_last;wire[95:0]out_data;
 color_tone4 #(.ENABLE(1),.SAT_Q8(384),.DEFRINGE_ENABLE(0),.TONE_ENABLE(0)) dut(
 .I_sat_on(1'b1),.I_tone_on(1'b1),.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(0),.I_tlast(0),.I_tdata(data),
 .I_tready(in_ready),.O_tready(ready),.O_tvalid(out_valid),.O_tuser(out_user),.O_tlast(out_last),.O_tdata(out_data));
 integer n;
 always #5 clk=~clk;
 initial begin
  repeat(4)@(negedge clk);rst=1;@(negedge clk);
  valid=1;data={4{24'hdcb428}};@(negedge clk);valid=0;data=0;
  while(out_data===96'd0)@(posedge clk);
  if(out_data!=={4{24'hf2b600}})
   $fatal(1,"1.5x yellow mismatch valid=%0d got=%h",out_valid,out_data);
  $display("PASS tb_color_tone4 SAT_Q8=384 yellow 220,180,40 -> 242,182,0");
  $finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
