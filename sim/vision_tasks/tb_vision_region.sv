// Segmentation-only legacy vectors; default association covered separately.
`timescale 1ns/1ps
module tb_vision_region;
 parameter CAPACITY=3072;
 parameter CASE_FILE="sim/vision_tasks/region_cases.txt";
 parameter CSV_FILE="reports/vision_tasks/region_rtl.csv";
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,fs=0,sv=0,fe=0;reg [7:0] sx,sy;reg [23:0] rgb;
 wire rv,calibrated,found,overflow,busy;wire [7:0] bx,by,bw,bh,cx,cy;wire [14:0] area;wire [31:0] cycles;
 vision_color_region #(.WIDTH(64),.HEIGHT(48),.QUEUE_CAPACITY(CAPACITY),.ASSOCIATION(0)) dut(
  clk,rst_n,reseed,fs,sv,fe,sx,sy,rgb,rv,calibrated,found,overflow,bx,by,bw,bh,cx,cy,area,busy,cycles,,1'b0);
 reg [23:0] pixels[0:3071];string name;integer f,csv,n,action,ec,ef,eo,ex,ey,ew,eh,ecx,ecy,ea,i,waits,checked=0;
 initial begin
  f=$fopen(CASE_FILE,"r");csv=$fopen(CSV_FILE,"w");
  $fwrite(csv,"name,calibrated,found,overflow,x,y,w,h,cx,cy,area,cycles\n");
  repeat(4)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   n=$fscanf(f,"%s %d %d %d %d %d %d %d %d %d %d %d\n",name,action,ec,ef,eo,ex,ey,ew,eh,ecx,ecy,ea);
   if(n!=12)$fatal(1,"region case parse %0d",n);
   if(action==1)begin rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
   if(action==2)begin reseed=1;@(negedge clk);reseed=0;end
   $readmemh({"sim/vision_tasks/",name,".hex"},pixels);
   @(negedge clk);fs=1;@(negedge clk);fs=0;
   for(i=0;i<3072;i=i+1)begin
    sv=1;rgb=pixels[i];sx=i%64;sy=i/64;fe=i==3071;@(negedge clk);
    if(i%47==0)begin sv=0;fe=0;repeat(2)@(negedge clk);end
   end
   sv=0;fe=0;waits=0;
   while(!rv && waits<250000)begin @(negedge clk);waits=waits+1;fs=waits==20;end
   fs=0;
   if(!rv || calibrated!==ec || found!==ef || overflow!==eo || area!==ea ||
       (ef && (bx!==ex || by!==ey || bw!==ew || bh!==eh || cx!==ecx || cy!==ecy)))
    $fatal(1,"region %s cal=%b found=%b ov=%b box=%0d,%0d,%0d,%0d center=%0d,%0d area=%0d expected cal%0d f%0d ov%0d box%0d,%0d,%0d,%0d c%0d,%0d a%0d",name,calibrated,found,overflow,bx,by,bw,bh,cx,cy,area,ec,ef,eo,ex,ey,ew,eh,ecx,ecy,ea);
   $fwrite(csv,"%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",name,calibrated,found,overflow,bx,by,bw,bh,cx,cy,area,cycles);
   $display("PASS region %s cal=%0d found=%0d area=%0d cycles=%0d",name,calibrated,found,area,cycles);
   checked=checked+1;repeat(5)@(negedge clk);
  end
  $fclose(csv);if(checked!=(CAPACITY==32?2:16))$fatal(1,"region incomplete");
  $display("PASS tb_vision_region: capacity=%0d cases=%0d",CAPACITY,checked);$finish;
 end
 initial begin #50000000;$fatal(1,"region timeout");end
endmodule
