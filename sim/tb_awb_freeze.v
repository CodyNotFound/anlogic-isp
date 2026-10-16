`timescale 1ns/1ps
module tb_awb_freeze;
 reg clk=0,rst=0,enable=1,valid=0,user=0,last=0;
 reg [95:0] data=0;
 wire [95:0] result;wire ov,ou,ol,ready;
 always #5 clk=~clk;
 switchable_awb4 #(.INIT_R_Q8(522),.INIT_B_Q8(421),.MIN_SAMPLES(16)) dut(
 .I_bypass(1'b0),.I_clk(clk),.I_rst_n(rst),.I_enable(enable),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
 .I_tdata(data),.I_tready(ready),.O_tready(1'b1),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(result));
 task idle;input integer count;integer n;
 begin for(n=0;n<count;n=n+1)begin @(negedge clk);valid=0;user=0;last=0;end end endtask
 task frame;input [23:0] pixel;integer n;
 begin for(n=0;n<20;n=n+1)begin
 @(negedge clk);valid=1;user=(n==0);last=(n==19);data={4{pixel}};
 end idle(100);end endtask
 task check_gain;input [9:0] r,b;
 begin #1;
 if(dut.u_frame_awb4.gain_r_q8!==r||dut.u_frame_awb4.gain_b_q8!==b)
  $fatal(1,"Gain expected %0d/%0d actual %0d/%0d",r,b,dut.u_frame_awb4.gain_r_q8,dut.u_frame_awb4.gain_b_q8);
 end endtask
 initial begin
 repeat(5)@(negedge clk);rst=1;idle(4);
 frame({8'd40,8'd80,8'd50});frame({8'd40,8'd80,8'd50});
 frame({8'd40,8'd80,8'd50});check_gain(520,419);
 if(!dut.u_frame_awb4.pending_valid)$fatal(1,"Need pending estimate to test OFF edge");
 enable=0;idle(4);
 frame({8'd35,8'd80,8'd60});check_gain(520,419);
 frame({8'd50,8'd80,8'd50});check_gain(520,419);
 if(dut.u_frame_awb4.pending_valid||dut.u_frame_awb4.sample_count!=0)$fatal(1,"AUTO OFF did not clear estimates");
 enable=1;idle(4);
 frame({8'd40,8'd80,8'd50});check_gain(520,419);
 frame({8'd40,8'd80,8'd50});check_gain(520,419);
 frame({8'd40,8'd80,8'd50});check_gain(518,417);
 $display("PASS tb_awb_freeze gains 522/421 -> 520/419 -> OFF hold -> ON 518/417");$finish;
 end
 initial begin #20000;$fatal(1,"Timeout");end
endmodule
