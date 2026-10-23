`timescale 1ns/1ps
module tb_servo_gimbal;
 reg clk=0,rst_n=0,en=0,valid=0,found=0,manual=0;
 reg [3:0] keys=0;reg [7:0] cx=80,cy=45;
 wire h,v;wire [11:0] ph,pv;wire [1:0] st;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) dut(clk,rst_n,en,valid,found,cx,cy,manual,keys,h,v,ph,pv,st);
 always #5 clk=~clk;
 integer cycles=0,hlast=0,vlast=0,hrise=0,vrise=0,hrises=0,vrises=0;
 reg hd=0,vd=0;integer hp=0,vp=0;
 always @(negedge clk)if(rst_n)begin
  cycles=cycles+1;
  if(ph<500||ph>2500||pv<1050||pv>2150)$fatal(1,"unsafe clamp %0d %0d",ph,pv);
  if(h && !hd)begin
   if(hrises>0 && cycles-hrise!=20000)$fatal(1,"H period");
   hrise=cycles;hp=ph;hrises=hrises+1;
  end
  if(v && !vd)begin
   if(vrises>0 && cycles-vrise!=20000)$fatal(1,"V period");
   vrise=cycles;vp=pv;vrises=vrises+1;
  end
  if(!h && hd && cycles-hrise!=hp)$fatal(1,"H width %0d exp %0d",cycles-hrise,hp);
  if(!v && vd && cycles-vrise!=vp)$fatal(1,"V width");
  hd=h;vd=v;
 end
 task waitc;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
 task frame;begin waitc(20000);end endtask
 task reset;begin
  rst_n=0;waitc(5);keys=0;manual=0;en=0;valid=0;found=0;rst_n=1;
  cycles=0;hrises=0;vrises=0;hd=0;vd=0;
 end endtask
 integer i,bh,bv;
 initial begin
  reset;waitc(45000);if(ph!=1500||pv!=1500)$fatal(1,"center");
  en=1;found=1;cx=159;cy=89;valid=1;waitc(2);valid=0;frame;
  if(ph!=1468||pv!=1519)$fatal(1,"auto polarity / gain %0d %0d",ph,pv);
  bh=ph;bv=pv;valid=1;frame;bh=ph;bv=pv;frame;
  if(ph!=bh||pv!=bv)$fatal(1,"held valid re-used result");valid=0;
  bh=ph;bv=pv;cx=89;cy=52;waitc(2);valid=1;waitc(2);valid=0;frame;
  if(ph!=bh-1||pv!=bv+1)$fatal(1,"near-center correction must be 1us");
  bh=ph;bv=pv;cx=88;cy=51;valid=1;waitc(2);valid=0;frame;
  if(ph!=bh||pv!=bv)$fatal(1,"deadband must stop correction");
  manual=1;keys=4'b1010;frame;
  if(ph!=bh+4||pv!=bv-4)$fatal(1,"Vim left/up mapping");
  bh=ph;bv=pv;
  for(i=0;i<9;i=i+1)frame;
  if(ph!=bh+36||pv!=bv-36)$fatal(1,"fine motion before acceleration");
  bh=ph;bv=pv;frame;
  if(ph!=bh+32||pv!=bv-32)$fatal(1,"long hold did not accelerate");
  keys=4'b0101;bh=ph;bv=pv;frame;
  if(ph!=bh-4||pv!=bv+4)$fatal(1,"reverse did not restore fine motion");
  bh=ph;bv=pv;keys=0;valid=1;cx=0;cy=0;frame;
  if(ph!=bh||pv!=bv)$fatal(1,"manual no-key priority");valid=0;
  keys=15;frame;if(ph!=bh||pv!=bv)$fatal(1,"opposite keys must cancel");
  keys=4'b1100;
  for(i=0;i<260;i=i+1)frame;
  if(ph!=2500||pv!=2150)$fatal(1,"upper clamps %0d %0d",ph,pv);
  keys=4'b0011;
  for(i=0;i<510;i=i+1)frame;
  if(ph!=500||pv!=1050)$fatal(1,"lower clamps");
  keys=0;manual=0;frame;
  if(ph!=500||pv!=1050)$fatal(1,"stale result on manual exit");
  $display("PASS manual directions/priority/release/opposites/safe limits + atomic PWM");
  reset;manual=1;keys=8;frame;keys=0;manual=0;en=1;found=1;cx=80;cy=45;
  valid=1;waitc(2);valid=0;frame;bh=ph;found=0;
  // Real elapsed time, no result packets and no video frames during loss.
  bv=pv;waitc(1950000);if(ph!=bh||pv!=bv)$fatal(1,"loss moved axes before 2s");
  waitc(100000);if(ph!=bh||pv!=bv)$fatal(1,"loss homed after 2s");
  waitc(3000000);if(ph!=bh||pv!=bv)$fatal(1,"long loss drift");
  manual=1;keys=8;frame;if(ph!=bh+4)$fatal(1,"manual must work after long loss");
  keys=0;manual=0;found=1;cx=159;valid=1;waitc(2);valid=0;frame;
  if(ph>=bh+4)$fatal(1,"fresh reacquired result did not resume tracking");
  $display("PASS loss: over 5s no frames/results, no home/drift, manual override and fresh-result resume");
  $display("PASS tb_servo_gimbal");$finish;
 end
 initial begin #250000000;$fatal(1,"timeout");end
endmodule

module tb_servo_production;
 reg clk=0,rst=0;always #5 clk=~clk;
 wire h,v;wire [11:0] ph,pv;wire [1:0] state;
 servo_gimbal_ctrl dut(clk,rst,1'b0,1'b0,1'b0,8'd80,8'd45,1'b0,4'b0,h,v,ph,pv,state);
 integer c=0,last_rise=0,rises=0;reg previous=0;
 always @(negedge clk)if(rst)begin
  c=c+1;
  if(h!==v)$fatal(1,"center axes differ");
  if(h && !previous)begin
   if(rises && c-last_rise!=1500000)$fatal(1,"75MHz PWM period");
   rises=rises+1;last_rise=c;
  end
  if(!h && previous && c-last_rise!=112500)$fatal(1,"75MHz 1500us width");
  previous=h;
  if(c==4700000)begin
   if(rises!=3)$fatal(1,"missing PWM periods");
   $display("PASS tb_servo_production: 75MHz 20ms period and 1500us widths");$finish;
  end
 end
 initial begin repeat(4)@(negedge clk);rst=1;end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
