`timescale 1ns/1ps
module tb_face_response_v67;
 reg clk=0,rst=0,rv=0,cap=0,found=1,en=1,manual_mode=0;always #5 clk=~clk;
 reg[7:0]cx=112,oldcx=112;reg[3:0]keys=0;
 wire[11:0]h,v,oldh,oldv;wire[1:0]state,oldstate;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) dut(clk,rst,en,rv,found,cx,8'd45,manual_mode,keys,,,h,v,state,1'b1,cap);
 servo_gimbal_ctrl_v66 #(.CLK_HZ(1000000)) before_fix(clk,rst,en,rv,found,oldcx,8'd45,manual_mode,keys,,,oldh,oldv,oldstate,1'b1,cap);
 integer cycles=0,previous=1500,oldprevious=1500,t90=0,old_t90=0,stage=0,world=1500,iae=0,oldiae=0,n,fd,saved;
 function integer abs_i(input integer x);begin abs_i=x<0?-x:x;end endfunction
 function[7:0] observation(input integer command,goal);integer x;begin x=80+(command-goal)/2;observation=x<0?0:x>159?159:x;end endfunction
 always @(negedge clk)if(rst)begin
  cycles=cycles+1;
  if(h<500||h>2500||v<1050||v>2150)$fatal(1,"unsafe pulse");
  if(h!=previous&&dut.phase_us!=0)$fatal(1,"non-boundary motion");
  if(!manual_mode&&abs_i(h-previous)>8)$fatal(1,"slew exceeded");previous=h;
  if(stage==1)begin if(t90==0&&h<=1450)t90=cycles;if(old_t90==0&&oldh<=1450)old_t90=cycles;end
  if(stage==2&&cycles%10000==0)begin
   iae=iae+abs_i(h-world);oldiae=oldiae+abs_i(oldh-world);
   $fwrite(fd,"%0d,%0d,%0d,%0d\n",cycles,world,h,oldh);
  end
 end else begin previous=1500;oldprevious=1500;end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task capture;begin cap=1;ticks(1);cap=0;end endtask
 task result;begin rv=1;ticks(1);rv=0;end endtask
 initial begin
  fd=$fopen("reports/fix_v67/face_closed_loop.csv","w");$fwrite(fd,"us,target_pulse,new_pulse,v66_pulse\n");
  ticks(5);rst=1;stage=1;capture;result;ticks(340000);
  if(h!=1444||oldh!=1444||v!=1500)$fatal(1,"finite endpoint mismatch");
  if(!t90||!old_t90||t90*4>=old_t90*3)$fatal(1,"short response not improved %0d/%0d",t90,old_t90);
  $display("PASS short endpoint: 90percent new=%0dus v66=%0dus; same final1444, max8us/PWM",t90,old_t90);
  rst=0;stage=0;ticks(5);rst=1;stage=2;cycles=0;
  for(n=0;n<20;n=n+1)begin
   world=1500-8*(n<=10?n:20-n);cx=observation(h,world);oldcx=observation(oldh,world);
   capture;ticks(267000);result;ticks(33000);
  end
  stage=0;$fclose(fd);if(iae>=oldiae)$fatal(1,"closed-loop tracking error did not improve new%0d old%0d",iae,oldiae);
  found=0;saved=h;ticks(700000);if(h!=saved)$fatal(1,"loss did not hold");
  $display("PASS tb_face_response_v67 ideal-actuator delayed closed-loop aggregate error new=%0d v66=%0d; 267ms inference, 300ms cadence; finite endpoints and loss limits",iae,oldiae);$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
