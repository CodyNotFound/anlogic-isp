`timescale 1ns/1ps
module tb_face_cadence_v64;
 reg clk=0,rst=0,en=1,rv=0,found=1,cap=0,manual=0;always #5 clk=~clk;
 reg[7:0]cx=159,cy=89;reg[3:0]keys=0;
 wire[11:0]h,v,oh,ov;wire[1:0]state,oldstate;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) dut(clk,rst,en,rv,found,cx,cy,manual,keys,,,h,v,state,1'b1,cap);
 servo_gimbal_ctrl_v62 #(.CLK_HZ(1000000)) old(clk,rst,en,rv,found,cx,cy,manual,keys,,,oh,ov,oldstate);
 integer previous=1500,oldprevious=1500,n,steps=0,oldsteps=0,holds=0,oldholds=0,save_h,save_v;
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task snapshot;begin cap=1;ticks(1);cap=0;end endtask
 task result;begin rv=1;ticks(1);rv=0;end endtask
 always @(negedge clk)if(rst)begin
  if(h<500||h>2500||v<1050||v>2150)$fatal(1,"unsafe pulse");
  if(h!=previous && dut.phase_us!=0)$fatal(1,"non-boundary motion");
  if(!manual&&(h>previous+8||h+8<previous))$fatal(1,"slew >8us");
  previous=h;
 end
 initial begin
 ticks(5);rst=1;snapshot;ticks(267000);result;
 // A new camera frame begins immediately after every completed inference.
 for(n=0;n<5;n=n+1)begin
  snapshot;
  repeat(14)begin
   save_h=h;oldprevious=oh;ticks(20000);
   if(h!=save_h)steps=steps+1;if(oh!=oldprevious)oldsteps=oldsteps+1;
   if(state==2)holds=holds+1;if(oldstate==2)oldholds=oldholds+1;
  end
  result;
 end
 if(steps<60||oldsteps>25||holds!=0||oldholds<15)$fatal(1,"cadence regression steps%0d old%0d hold%0d old%0d",steps,oldsteps,holds,oldholds);
 found=0;save_h=h;save_v=v;ticks(700000);if(h!=save_h||v!=save_v)$fatal(1,"loss moved");
 found=1;cx=80;cy=45;snapshot;result;ticks(340000);if(h!=save_h||v!=save_v)$fatal(1,"center moved");
 cx=159;cy=89;snapshot;result;ticks(40000);en=0;save_h=h;ticks(400000);if(h!=save_h)$fatal(1,"auto off moved");
 en=1;manual=1;keys=8;ticks(240000);save_h=h;ticks(20000);if(h!=save_h+32)$fatal(1,"manual acceleration");
 manual=0;keys=0;result;save_h=h;ticks(400000);if(h!=save_h)$fatal(1,"pre-manual measurement reused");
 $display("PASS face cadence: movement periods new=%0d old=%0d /70; false HOLD new=%0d old=%0d; safety/loss/auto/manual/center",steps,oldsteps,holds,oldholds);$finish;
 end
 initial begin #45000000;$fatal(1,"watchdog");end
endmodule
