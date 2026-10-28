`timescale 1ns/1ps
module tb_face_patch_motion;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,enable=1,seed_valid=0,fs=0,fe=0,err=0,sv=0;
 reg [7:0] seed_x=70,seed_y=40,sx=0,sy=0,g=0;
 wire valid,found,busy;wire [7:0] x,y;wire [31:0] cycles;wire [15:0] sad;
 face_patch_motion dut(clk,rst_n,enable,seed_valid,fs,fe,err,sv,seed_x,seed_y,sx,sy,g,valid,found,x,y,busy,cycles,sad,1'b0);
 integer tx,ty,light,i,j,f,seen=0,frame_seen=0;reg visible=1,expected_found=1,duplicate=0,noise=0;
 reg last_found;reg [7:0] last_x,last_y;reg [15:0] last_sad;reg [31:0] last_cycles;
 always @(negedge clk)if(valid)begin seen=seen+1;last_found=found;last_x=x;last_y=y;last_sad=sad;last_cycles=cycles;end
 function [7:0] image;input integer xx,yy;integer a,b;begin
  a=xx-(tx-4);b=yy-(ty-4);
  if(duplicate&&a>=8&&a<16&&b>=0&&b<8)a=a-8;
  if(visible&&a>=0&&a<8&&b>=0&&b<8)image=50+((a*47+b*73+a*b*11)%120)+light+(noise?((xx*13+yy*11+f)%7)-3:0);
  else image=28+((xx*3+yy*7)%12)+light;
 end endfunction
 task tick;begin @(negedge clk);end endtask
 task frame;begin
  frame_seen=seen;tick;fs=1;tick;fs=0;
  for(j=0;j<90;j=j+1)for(i=0;i<160;i=i+1)begin sx=i;sy=j;g=image(i,j);sv=1;fe=(i==159&&j==89);tick;end
  sv=0;fe=0;
 end endtask
 task wait_result;integer n;begin
  n=0;while(seen==frame_seen&&n<100000)begin tick;n=n+1;end
  if(seen==frame_seen)$fatal(1,"result timeout");
  if(expected_found&&(!last_found||last_x!=tx||last_y!=ty))$fatal(1,"position f=%0d want=%0d,%0d got=%0d,%0d found=%0d sad=%0d",f,tx,ty,last_x,last_y,last_found,last_sad);
  if(!expected_found&&last_found)$fatal(1,"occlusion accepted");
  if(last_cycles>60000)$fatal(1,"cycle budget exceeded");
  $display("frame=%0d found=%0d x=%0d y=%0d SAD=%0d cycles=%0d",f,last_found,last_x,last_y,last_sad,last_cycles);
  tick;
 end endtask
 initial begin
  repeat(5)tick;rst_n=1;tx=70;ty=40;light=0;
  tick;seed_valid=1;tick;seed_valid=0;
  for(f=0;f<10;f=f+1)begin if(f>0)begin tx=tx+3;ty=ty+(f%2==0?2:-1);light=f*3;noise=f>=4;end frame;wait_result;end
  f=10;visible=0;expected_found=0;frame;wait_result;
  // No invented updates after loss.
  frame;repeat(100)begin tick;if(valid)$fatal(1,"unexpected result after loss");end
  // Reseed, interrupted capture, then explicit reacquisition.
  visible=1;expected_found=1;noise=0;tx=45;ty=30;seed_x=45;seed_y=30;tick;seed_valid=1;tick;seed_valid=0;
  fs=1;tick;fs=0;repeat(20)tick;err=1;tick;err=0;
  if(found)$fatal(1,"malformed frame retains found");
  seed_valid=1;tick;seed_valid=0;f=11;frame;wait_result;
  f=12;duplicate=1;expected_found=0;frame;wait_result;
  $display("PASS tb_face_patch_motion");$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
