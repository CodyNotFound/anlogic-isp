`timescale 1ns/1ps
module tb_gimbal_osd;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [3:0] features=15,mode=0;reg demo=0;reg [1:0] state=0;
 reg [11:0] ph=1500,pv=1500;reg [23:0] hd=24'h001500,vd=24'h001500;
 reg vs=0,hs=0,de=0,sof=0;reg [23:0] rgb=24'h8090a0;
 wire ov,oh,od,os;wire [23:0] pixel;
 gimbal_osd dut(clk,rst,features,mode,demo,state,ph,pv,hd,vd,vs,hs,de,sof,rgb,ov,oh,od,pixel,os);
 integer x,y,f,fd=0,marked=0,texts=0,total=0,count=0,ox,oy,mx,my;reg [23:0] expected;
 always @(posedge clk)begin
  #2;
  if(rst && od)begin
   ox=count%1280;oy=count/1280;mx=1176+((2500-ph)>>5);my=560+((pv-500)>>5);
     if(od!==1 || ov!==0 || oh!==(ox==1279))$fatal(1,"qualifier mismatch");
     if((^pixel)===1'bx)$fatal(1,"unknown pixel");
     if(ox==mx&&oy==my)begin
      expected=(ph==500||ph==2500||pv==1050||pv==2150)?24'hff4040:f==0?24'h30e0ff:24'h60ff90;
      if(pixel!==expected)$fatal(1,"position marker %h exp %h",pixel,expected);marked=marked+1;
     end
     if(ox==0&&oy==0&&pixel!==rgb)$fatal(1,"background altered");
     if(ox>=880&&ox<1264&&oy>=664&&oy<700&&pixel!=24'h202428)texts=texts+1;
     if(f<2)$fwrite(fd,"%c%c%c",pixel[23:16],pixel[15:8],pixel[7:0]);
     total=total+1;
   count=count+1;
  end
 end
 task clock;begin @(posedge clk);#1;end endtask
 initial begin
  repeat(5)clock;rst=1;clock;
  for(f=0;f<5;f=f+1)begin
   if(f==0)fd=$fopen("reports/gimbal/manual.ppm","wb");
   if(f==1)fd=$fopen("reports/gimbal/auto.ppm","wb");
   if(f<2)$fwrite(fd,"P6\n1280 720\n255\n");
   features=f==0?15:7;mode=f==0?0:f==1?12:f==2?11:14;demo=f==4;state=f==3?2:1;
   count=0;
   ph=f==2?500:f==3?2500:1500;pv=f==2?1050:f==3?2150:1500;
   hd=f==2?24'h000500:f==3?24'h002500:24'h001500;
   vd=f==2?24'h001050:f==3?24'h002150:24'h001500;
   de=0;sof=1;vs=1;clock;sof=0;vs=0;
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)begin
     de=1;hs=x==1279;clock;
    end
    de=0;hs=0;clock;
   end
   repeat(3)clock;
   if(count!=921600)$fatal(1,"pixel count %0d",count);
   if(f<2)begin $fclose(fd);fd=0;end
  end
  if(marked!=5||texts<1000||total!=4608000)$fatal(1,"missing OSD coverage");
  $display("PASS tb_gimbal_osd: 4608000 pixels across manual/TRACK/FACE/REGION/ISP, marker and qualifiers");$finish;
 end
 initial begin #70000000;$fatal(1,"timeout");end
endmodule
