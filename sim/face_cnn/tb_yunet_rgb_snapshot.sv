`timescale 1ns/1ps
module tb_yunet_rgb_snapshot;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=1,busy=0,sof=0,eol=0,de=0;reg [23:0] rgb=0;
 wire load,start,cap,error;wire [16:0] addr;wire [7:0] data;wire [31:0] accepted;
 yunet_rgb_snapshot #(.WIDTH(640),.HEIGHT(360)) dut(clk,rst,en,busy,sof,eol,de,rgb,load,addr,data,start,cap,error,accepted);
 reg [7:0] expected[0:61439];integer n=0,starts=0,x,y;
 always @(posedge clk)begin #1;
  if(load)begin
   if(n>=61440||addr!==n||data!==expected[n])$fatal(1,"sample byte%0d addr%0d got%h expected%h",n,addr,data,expected[n]);n=n+1;
  end
  if(start)begin if(n!=61440)$fatal(1,"started before complete load");starts=starts+1;end
 end
 task frame;
 begin
  for(y=0;y<360;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;sof=x==0&&y==0;eol=x==639;rgb={8'((x*3+y)&255),8'((x+y*5)&255),8'((x^y)&255)};
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(5)@(negedge clk);
  end
 end
 endtask
 initial begin
  $readmemh("reports/yunet_v45/sampler_expected.hex",expected);
  repeat(5)@(negedge clk);rst=1;
  // An early EOL aborts the snapshot; partial data cannot start inference.
  de=1;sof=1;eol=1;@(negedge clk);de=0;sof=0;eol=0;
  repeat(5)@(negedge clk);if(!error||start||cap)$fatal(1,"malformed raster not rejected");
  frame();wait(start);@(negedge clk);busy=1;repeat(8)@(negedge clk);
  frame();repeat(20)@(negedge clk);
  if(n!=61440||starts!=1||accepted!=2)$fatal(1,"capture/skip counts %0d %0d %0d",n,starts,accepted);
  $display("PASS tb_yunet_rgb_snapshot: 61440 exact BGR0 bytes, rounded color average, padding, malformed raster abort, busy-frame skip");$finish;
 end
 initial begin #7000000;$fatal(1,"sampler watchdog");end
endmodule
