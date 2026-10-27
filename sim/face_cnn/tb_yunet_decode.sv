`timescale 1ns/1ps
module tb_yunet_decode;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,sof=0,valid=0,last=0;
 reg [1:0] level;reg [7:0] gx,gy,cls,obj,bx,by,bw,bh;
 wire done,found;wire [13:0] score;wire [11:0] x,y,size,cx,cy;
 yunet_decode dut(clk,rst,sof,valid,last,level,gx,gy,cls,obj,bx,by,bw,bh,done,found,score,x,y,size,cx,cy);
 integer fd,rc,count,ef,es,ex,ey,ez,ecx,ecy,i,n=0;
 integer l,gxi,gyi,cl,ob,bxi,byi,bwi,bhi;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  fd=$fopen("reports/yunet_v45/decode_vectors.txt","r");if(!fd)$fatal(1,"missing decoder vectors");
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%d %d %d %d %d %d %d %d\n",count,ef,es,ex,ey,ez,ecx,ecy);
   if(rc==8)begin
    sof=1;@(negedge clk);sof=0;
    for(i=0;i<count;i=i+1)begin
     rc=$fscanf(fd,"%d %d %d %d %d %d %d %d %d\n",l,gxi,gyi,cl,ob,bxi,byi,bwi,bhi);
     if(rc!=9)$fatal(1,"truncated anchor");
     if(i%13==0)begin valid=0;repeat(2)@(negedge clk);end
     valid=1;last=i==count-1;level=l;gx=gxi;gy=gyi;cls=cl;obj=ob;bx=bxi;by=byi;bw=bwi;bh=bhi;@(negedge clk);
    end
    valid=0;last=0;while(!done)@(negedge clk);
    if(found!==ef || score!==es || x!==ex || y!==ey || size!==ez || cx!==ecx || cy!==ecy)
     $fatal(1,"frame%0d found%0d/%0d score%0d/%0d box %0d,%0d,%0d vs %0d,%0d,%0d center%0d,%0d/%0d,%0d",n,found,ef,score,es,x,y,size,ex,ey,ez,cx,cy,ecx,ecy);
    n=n+1;repeat(4)@(negedge clk);
   end
  end
  $display("PASS tb_yunet_decode: %0d complete real-network head streams, three strides, clipped 720p coordinates, blanking gaps",n);$finish;
 end
 initial begin #1000000;$fatal(1,"decoder watchdog");end
endmodule
