`timescale 1ns/1ps
module tb_effect_compat #(parameter WIDTH=24,HEIGHT=12);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,sof=0,eol=0,de=0;reg [23:0] rgb=0;reg [3:0] mode=0;
 wire [23:0] pixel,old_pixel;
 pixel_algorithm #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) dut(clk,rst_n,mode,sof,eol,de,rgb,pixel);
 pixel_algorithm_v40 #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) old(clk,rst_n,mode,sof,eol,de,rgb,old_pixel);
 reg [23:0] p0=0,p1=0,p2=0;reg [3:0] modes=0,dh=0;reg [3:0] m0=0,m1=0,m2=0,m3=0;
 integer f,x,y,checked=0;
 always @(posedge clk)begin
  if(!rst_n)begin p0<=0;p1<=0;p2<=0;dh<=0;m0<=0;m1<=0;m2<=0;m3<=0;end
  else begin p0<=old_pixel;p1<=p0;p2<=p1;dh<={dh[2:0],de};m0<=mode;m1<=m0;m2<=m1;m3<=m2;
   #1;
   if(m3!=9 && pixel!==p2)$fatal(1,"legacy effect mismatch frame%0d mode%0d got%h expected%h",f,m3,pixel,p2);
   if(dh[3] && m3!=9)checked=checked+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(f=0;f<16;f=f+1)begin
   if(f%2)begin @(negedge clk);sof=1;de=0;@(negedge clk);sof=0;end
   for(y=0;y<HEIGHT;y=y+1)begin
    for(x=0;x<WIDTH;x=x+1)begin
     @(negedge clk);de=1;sof=!(f%2)&&x==0&&y==0;eol=x==WIDTH-1;mode=(f+x/5)%16;
     rgb={8'((x*17+y*31+f*13)%256),8'((x*3+y*53+f*29)%256),8'((x*67+y*7+f*5)%256)};
     if(x%7==3)begin @(negedge clk);de=0;sof=0;eol=0;repeat(2)@(negedge clk);end
    end
    @(negedge clk);de=0;sof=0;eol=0;repeat(5)@(negedge clk);
   end
  end
  repeat(8)@(negedge clk);
  if(checked<4000)$fatal(1,"missing coverage");
  $display("PASS tb_effect_compat: %0d non-cartoon RGB pixels exactly match v40 after three extra clocks; all modes, live mode changes, frame history, valid gaps",checked);$finish;
 end
 initial begin #10000000;$fatal(1,"compat watchdog");end
endmodule
