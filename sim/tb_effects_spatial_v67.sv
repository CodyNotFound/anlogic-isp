`timescale 1ns/1ps
module tb_effects_spatial_v67;
 reg clk=0,rst=0,de=0,sof=0,eol=0;reg[23:0] rgb;
 always #5 clk=~clk;
 wire[23:0] cartoon;wire od,os,ol;reg[3:0] mode=5;
 reg[3:0] dp,fp,lp;
 always @(posedge clk)begin dp<={dp[2:0],de};fp<={fp[2:0],sof};lp<={lp[2:0],eol};end
 assign od=dp[3];assign os=fp[3];assign ol=lp[3];
 pixel_algorithm #(.IMG_WIDTH(96),.IMG_HEIGHT(48)) dut(clk,rst,mode,sof,eol,de,rgb,cartoon);
 reg[23:0] inputs[0:4607],expected[0:4607],edges[0:4607];reg[511:0] name;
 integer f,x,y,n=0,total=0,m;reg checking=0;
 always @(posedge clk)begin #1;
 if(checking&&od)begin
 if(^cartoon===1'bx||^expected[n]===1'bx)$fatal(1,"unknown pixel/fixture");
 if(cartoon!==expected[n])$fatal(1,"mode%0d case%0d index%0d actual %h expected %h",mode,f,n,cartoon,expected[n]);
 if(os!==(n==0)||ol!==(n%96==95))$fatal(1,"qualifier mismatch");n=n+1;total=total+1;
 end end
 initial begin
 repeat(5)@(negedge clk);rst=1;
 for(m=0;m<6;m=m+1)begin
 mode=m==0?0:m==1?5:m==2?6:m==3?8:m==4?7:9;
 for(f=0;f<12;f=f+1)begin
 $sformat(name,"reports/effects_v67/input_%0d.hex",f);$readmemh(name,inputs);
 $sformat(name,"reports/effects_v67/mode%0d_%0d.hex",mode,f);
$readmemh(name,expected);

 n=0;checking=1;
 for(y=0;y<48;y=y+1)begin
 for(x=0;x<96;x=x+1)begin de=1;sof=x==0&&y==0;eol=x==95;rgb=inputs[y*96+x];@(negedge clk);end
 de=0;sof=0;eol=0;repeat(5)@(negedge clk);
 end
 repeat(8)@(negedge clk);checking=0;if(n!=4608)$fatal(1,"pixel count");
 end
 end
 $display("PASS tb_effects_spatial_v67 331776 exact RGB pixels, twelve scenes, untouched color/sharpen/blur/emboss, SOF/EOL and frame restart");$finish;
 end
 initial begin #5000000;$fatal(1,"watchdog");end
endmodule
