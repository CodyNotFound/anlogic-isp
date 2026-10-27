`timescale 1ns/1ps
module tb_face_delay_comp_v64;
 reg clk=0,rst=0,rv=0,cap=0,found=1;always #5 clk=~clk;
 reg[7:0]cx=112,cy=45;wire[11:0]h,v;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) dut(clk,rst,1'b1,rv,found,cx,cy,1'b0,4'd0,,,h,v,,1'b1,cap);
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task capture;begin cap=1;ticks(1);cap=0;end endtask
 task result;begin rv=1;ticks(1);rv=0;end endtask
 integer captured,measurement;
 initial begin
 ticks(5);rst=1;capture;result;ticks(80000);
 captured=h;capture;
 // Static target: pulse goal1444. Camera sees the residual before its slow inference.
 measurement=80+4+(captured-1444)/2;cx=measurement;
 ticks(267000);if(h!=1444)$fatal(1,"initial ramp incomplete %0d",h);
 result;ticks(340000);
 if(h!=1444||v!=1500)$fatal(1,"delayed residual reintegrated %0d/%0d",h,v);
 // One sample may authorize only a finite 16-period ramp, even if no loss packet arrives.
 cx=0;capture;result;ticks(340000);captured=h;ticks(700000);
 if(h!=captured)$fatal(1,"stale measurement moved indefinitely");
 $display("PASS delayed feedback: snapshot pulse compensation removes stationary-target overshoot; bounded ramp expires without new packets");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
