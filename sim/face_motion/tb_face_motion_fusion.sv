`timescale 1ns/1ps
module tb_face_motion_fusion;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=1,clear=0,capture=0,cv=0,cf=1,fs=0,fe=0,err=0,sv=0;
 reg [11:0] ccx=560,ccy=320,cs=128;
 reg [7:0] sx=0,sy=0,g=0;
 wire valid,found,fast;wire [11:0] bx,by,sz,x,y;wire [31:0] cycles;wire [15:0] accepted,rejected;
 face_motion_fusion dut(clk,rst,en,clear,capture,cv,cf,ccx,ccy,cs,fs,fe,err,sv,sx,sy,g,
  valid,found,bx,by,sz,x,y,fast,cycles,accepted,rejected);
 integer tx=70,ty=40,i,j,f,results=0;reg visible=1,big_patch=0;
 task tick;begin @(negedge clk);end endtask
 always @(negedge clk)if(valid)results=results+1;
 function [7:0] image;input integer xx,yy;integer a,b;begin
  a=xx-(tx-4)+(big_patch?8:0);b=yy-(ty-4)+(big_patch?8:0);
  image=visible&&a>=0&&a<8&&b>=0&&b<8?50+((a*47+b*73+a*b*11)%120):28+((xx*3+yy*7)%12);
 end endfunction
 task frame;input cap;begin
  tick;capture=cap;tick;capture=0;fs=1;tick;fs=0;
  for(j=0;j<90;j=j+1)for(i=0;i<160;i=i+1)begin
   sv=1;sx=i;sy=j;g=image(i,j);fe=i==159&&j==89;tick;
  end
  sv=0;fe=0;repeat(65000)tick;
 end endtask
 task cnn;input good;input integer xx,yy,side;begin
  tick;cf=good;ccx=xx;ccy=yy;cs=side;cv=1;tick;cv=0;tick;
 end endtask
 task check;input integer xx,yy;begin
  if(!found||!fast||x!=xx||y!=yy)$fatal(1,"frame%0d got=%0d,%0d expected=%0d,%0d found=%0d fast=%0d",f,x,y,xx,yy,found,fast);
  if(cycles>56000)$fatal(1,"patch compute budget");
 end endtask
 initial begin
  repeat(5)tick;rst=1;
  f=0;frame(1);cnn(1,560,320,128);
  f=1;frame(0);check(560,320);
  f=2;tx=73;frame(1);check(584,320);
  f=3;tx=76;frame(0);check(608,320);
  f=4;tx=79;frame(0);check(632,320);
  // Delayed result belongs to frame2 (x=73), not frame5 (x=82).
  cnn(1,592,320,192);
  if(accepted!=1)$fatal(1,"valid historical association rejected");
  f=5;tx=82;frame(0);check(664,320);
  if(sz!=136)$fatal(1,"size correction was not bounded");
  f=6;tx=85;frame(1);check(688,320);
  f=7;tx=88;frame(0);check(712,320);
  cnn(1,1000,320,192);
  if(rejected!=1)$fatal(1,"different target accepted");
  f=8;tx=91;frame(1);check(736,320);
  cnn(0,0,0,0);
  f=9;tx=94;frame(1);check(760,320);
  f=10;visible=0;frame(0);
  if(found||fast)$fatal(1,"occlusion not rejected");
  cnn(1,752,320,128); // snapshot predates loss: must not resurrect stale face.
  if(dut.seed_valid||dut.confirmed)$fatal(1,"pre-loss CNN result resurrected stale target");
  clear=1;tick;clear=0;cnn(1,560,320,128);
  if(dut.confirmed)$fatal(1,"clear accepted a pre-clear CNN result");
  f=11;tx=50;visible=1;frame(1);cnn(1,400,320,128);
  f=12;frame(0);check(400,320);
  // A second detector snapshot overlaps a still-applying earlier correction.
  f=13;frame(1);cnn(1,424,320,128);
  f=14;frame(1);check(408,320);
  f=15;frame(0);check(416,320);
  f=16;frame(0);check(424,320);
  cnn(1,400,320,128);
  f=17;frame(0);check(416,320);
  f=18;frame(0);check(408,320);
  f=19;frame(0);check(400,320);
  clear=1;tick;clear=0;big_patch=1;
  f=13;frame(1);cnn(1,400,320,400);
  f=14;frame(0);check(400,320);
  if(dut.px!=42||dut.py!=32)$fatal(1,"adaptive texture anchor not selected");
  f=15;tx=53;frame(0);check(424,320);
  // Frame age expiry must stop output even without fresh CNN or patch results.
  repeat(46)begin fs=1;tick;fs=0;tick;end
  if(found||fast)$fatal(1,"unconfirmed tracking did not expire");
  // An unsupported weak patch must fall back to CNN, not hide every face.
  clear=1;tick;clear=0;visible=0;big_patch=0;tx=70;ty=40;
  frame(1);cnn(1,560,320,400);frame(0);
  if(!dut.suspended||fast)$fatal(1,"weak seed did not suspend assistance");
  frame(1);cnn(1,568,320,400);
  if(!found||fast||x!=568||y!=320)$fatal(1,"detector-only fallback lost face");
  frame(1);cnn(0,0,0,0);
  if(found)$fatal(1,"fallback ignored negative CNN");
  // Explicit reselect restores assistance when useful texture becomes available.
  clear=1;tick;clear=0;visible=1;frame(1);cnn(1,560,320,128);frame(0);check(560,320);
  // Processing never changes video qualifiers: module has no video output ports.
  $display("PASS tb_face_motion_fusion results=%0d; delayed CNN, bounded correction, target association, loss, clear, reacquire",results);$finish;
 end
 initial begin #50000000;$fatal(1,"watchdog");end
endmodule
