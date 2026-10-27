`timescale 1ns/1ps
module tb_yunet_dot4;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,start=0,iv=0,last=0,oready=0,relu=0;
 reg signed [31:0] bias;reg signed [6:0] shift;
 reg [35:0] a;reg [31:0] w;
 wire ready,ir,ov;wire signed [31:0] acc;wire signed [7:0] value;
 yunet_dot4 dut(clk,rst,start,bias,shift,relu,ready,iv,ir,last,a,w,ov,oready,acc,value);
 integer fd,rc,beats,bi,sh,re,ea,ev,i,n=0,beat_count=0;
 integer a0,a1,a2,a3,w0,w1,w2,w3;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  fd=$fopen("reports/yunet_v45/dot_vectors.txt","r");if(!fd)$fatal(1,"missing vectors");
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%d %d %d %d %d %d\n",beats,bi,sh,re,ea,ev);
   if(rc==6)begin
    if(!ready)$fatal(1,"core not ready");
    @(negedge clk);bias=bi;shift=sh;relu=re;start=1;
    @(negedge clk);start=0;
    for(i=0;i<beats;i=i+1)begin
     rc=$fscanf(fd,"%d %d %d %d %d %d %d %d\n",a0,a1,a2,a3,w0,w1,w2,w3);
     if(rc!=8)$fatal(1,"truncated beat");
     if((i+n)%7==0)begin iv=0;repeat(2)@(negedge clk);end
     if(!ir)$fatal(1,"unexpected input stall");
     a={a3[8:0],a2[8:0],a1[8:0],a0[8:0]};w={w3[7:0],w2[7:0],w1[7:0],w0[7:0]};
     iv=1;last=i==beats-1;@(negedge clk);beat_count=beat_count+1;
    end
    iv=0;last=0;
    while(!ov)@(negedge clk);
    // Deliberate output backpressure must keep both results and ready stable.
    repeat(3)begin
     if(acc!==ea || value!==ev || ready || ir)$fatal(1,"dot%0d acc%0d/%0d value%0d/%0d",n,acc,ea,value,ev);
     @(negedge clk);
    end
    oready=1;@(negedge clk);oready=0;
    if(!ready||ov)$fatal(1,"output handshake failed");n=n+1;
   end
  end
  // Reset aborts an unfinished dot product and discards its pipeline beat.
  start=1;bias=123;shift=0;relu=0;@(negedge clk);start=0;iv=1;last=0;a=1;w=1;
  @(negedge clk);rst=0;iv=0;repeat(3)@(negedge clk);rst=1;
  repeat(3)@(negedge clk);if(!ready||ov)$fatal(1,"reset did not abort");
  $display("PASS tb_yunet_dot4: %0d actual-network/limit dots, %0d beats, stalls, rounding, saturation, reset",n,beat_count);$finish;
 end
 initial begin #50000000;$fatal(1,"watchdog");end
endmodule
