`timescale 1ns/1ps
module tb_yunet_position;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,start=0,load=0;reg [16:0] addr;reg [7:0] data;
 wire ready,busy,result,found;wire [11:0] x,y,size,cx,cy;wire [13:0] score;wire [31:0] cycles;
 yunet_position_snapshot dut(clk,rst,start,load,addr,data,ready,busy,result,found,x,y,size,cx,cy,score,cycles);
 reg [7:0] pixels[0:61439];integer fd,rc,ef,es,ex,ey,ez,ecx,ecy;string name,path;
 initial begin
  if(!$value$plusargs("CASE=%s",name))name="lena";
  path={"reports/yunet_v45/input_",name,".hex"};$readmemh(path,pixels);
  fd=$fopen({"reports/yunet_v45/position_",name,".txt"},"r");if(!fd)$fatal(1,"missing expected position");
  rc=$fscanf(fd,"%d %d %d %d %d %d %d",ef,es,ex,ey,ez,ecx,ecy);if(rc!=7)$fatal(1,"expected position invalid");
  repeat(5)@(negedge clk);rst=1;
  for(integer i=0;i<61440;i=i+1)begin load=1;addr=i;data=pixels[i];@(negedge clk);end
  load=0;start=1;@(negedge clk);start=0;
  wait(result);@(negedge clk);
  if(found!==ef||score!==es||x!==ex||y!==ey||size!==ez||cx!==ecx||cy!==ecy||!ready||busy)
   $fatal(1,"position %s got %0d %0d %0d,%0d,%0d %0d,%0d expected %0d %0d %0d,%0d,%0d %0d,%0d",name,found,score,x,y,size,cx,cy,ef,es,ex,ey,ez,ecx,ecy);
  $display("PASS tb_yunet_position %s: actual RGB bytes -> all 55 CNN operations -> three-scale integer decode -> 720p face position; found%0d box%0d,%0d,%0d center%0d,%0d cycles%0d",name,found,x,y,size,cx,cy,cycles);$finish;
 end
 initial begin #500000000;$fatal(1,"position watchdog");end
endmodule
