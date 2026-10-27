`timescale 1ns/1ps
module tb_gimbal_legacy_v64;
 reg clk=0,rst=0,en=1,valid=0,found=1,manual=0;reg[3:0] keys=0;reg[7:0] cx=159,cy=89;
 always #5 clk=~clk;
 wire[11:0] h,v;wire ph,pv;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) dut(clk,rst,en,valid,found,cx,cy,manual,keys,ph,pv,h,v,,1'b0,1'b0);
 integer prevh=1500,prevv=1500,dh,dv,n;integer changes=0;
 always @(negedge clk)if(rst)begin
  dh=$signed({1'b0,h})-prevh;dv=$signed({1'b0,v})-prevv;
  if((dh!=0||dv!=0)&&dut.phase_us!=0)$fatal(1,"non-atomic command change");
  if(!manual&&(dh>8||dh< -8||dv>8||dv< -8))$fatal(1,"automatic slew exceeded");
  if(h<500||h>2500||v<1050||v>2150)$fatal(1,"unsafe pulse");
  if(dh!=0||dv!=0)changes=changes+1;
  prevh=h;prevv=v;
 end
 task ticks(input integer count);begin repeat(count)@(negedge clk);end endtask
 task result;begin valid=1;ticks(2);valid=0;end endtask
 initial begin
 ticks(5);rst=1;ticks(2);result;
 ticks(20000);if(h!=1492||v!=1508)$fatal(1,"first bounded step %d/%d",h,v);
 ticks(60000);if(h!=1468||v!=1519)$fatal(1,"endpoint lost %d/%d",h,v);
 ticks(300000);if(h!=1468||v!=1519)$fatal(1,"stale result reintegrated");
 result;ticks(20000);en=0;n=h;ticks(200000);if(h!=n)$fatal(1,"auto-off completed queued move");
 en=1;ticks(2);result;ticks(20000);found=0;n=h;ticks(2200000);if(h!=n)$fatal(1,"loss moved or homed");
 found=1;cx=80;cy=45;result;ticks(80000);if(h!=n)$fatal(1,"center jitter moved axis");
 cx=0;cy=0;result;ticks(80000);if(h!=n+32)$fatal(1,"reverse did not converge");
 manual=1;keys=8;ticks(220000);n=h;ticks(20000);if(h!=n+32)$fatal(1,"manual acceleration changed");
 keys=0;manual=0;ticks(100000);n=h;ticks(150000);if(h!=n)$fatal(1,"manual exit reused target");
 $display("PASS tb_gimbal_legacy_v64 bounded 8us/PWM, original endpoint, stale hold, auto-off cancellation, loss hold, center deadband, reversal, manual acceleration");$finish;
 end
 initial begin #60000000;$fatal(1,"watchdog");end
endmodule
