`timescale 1ns/1ps
module tb_awb_deadband;
 reg clk=0,rst=0,valid=0,user=0,last=0,ready=1;
 reg [95:0] data=0; wire ir,ov,ou,ol;wire[95:0]od;
 frame_awb4 #(.INIT_R_Q8(276),.INIT_B_Q8(276),.MIN_SAMPLES(16)) dut(
 .I_bypass(1'b0),
 .I_auto_enable(1),.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),
 .I_tready(ir),.O_tready(ready),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(od));
 integer n,frame;
 task beat;input [95:0] pixels;input integer index;
 begin @(negedge clk);valid=1;user=index==0;last=index==15;data=pixels;@(posedge clk);#1;end endtask
 task frame16;input [23:0] pixel;begin for(n=0;n<16;n=n+1)beat({4{pixel}},n);@(negedge clk);valid=0;user=0;last=0;repeat(95)@(negedge clk);end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  // A +-4/256 target correction is sensor-sized noise and must not be published.
  for(frame=0;frame<5;frame=frame+1)begin frame16({8'd128,8'd136,8'd128});end
  #1;
  if(dut.gain_r_q8!==10'd276||dut.gain_b_q8!==10'd276)
   $fatal(1,"deadband failed gains=%0d/%0d",dut.gain_r_q8,dut.gain_b_q8);
  // A real illumination change moves smoothly by at most 2/256 on publication.
  for(frame=0;frame<3;frame=frame+1)begin frame16({8'd116,8'd136,8'd116});end
  #1;
  if(dut.gain_r_q8!==10'd278||dut.gain_b_q8!==10'd278)
   $fatal(1,"rate limit failed gains=%0d/%0d",dut.gain_r_q8,dut.gain_b_q8);
  $display("PASS tb_awb_deadband tiny correction held, real correction moves 2/256");
  $finish;
 end
 always #5 clk=~clk;
 initial begin #100000;$fatal(1,"timeout");end
endmodule
