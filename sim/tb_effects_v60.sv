`timescale 1ns/1ps
module tb_effects_v60;
 reg clk=0,rst=0,de=0,sof=0,eol=0;reg[23:0] rgb;
 always #5 clk=~clk;
 wire[23:0] cartoon,edge_rgb;wire od,os,ol;
 pixel_cartoon #(.IMG_WIDTH(96),.IMG_HEIGHT(48)) dut(clk,rst,sof,eol,de,rgb,cartoon,od,os,ol,edge_rgb);
 reg[23:0] inputs[0:4607],expected[0:4607],edges[0:4607];reg[511:0] name;
 integer f,x,y,n=0,total=0;reg checking=0;
 always @(posedge clk)begin #1;
 if(checking&&od)begin
 if(cartoon!==expected[n]||edge_rgb!==edges[n])$fatal(1,"case%0d index%0d cartoon %h/%h edge %h/%h",f,n,cartoon,expected[n],edge_rgb,edges[n]);
 if(os!==(n==0)||ol!==(n%96==95))$fatal(1,"qualifier mismatch");n=n+1;total=total+1;
 end end
 initial begin
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<8;f=f+1)begin
 $sformat(name,"reports/effects_v60/input_%0d.hex",f);$readmemh(name,inputs);
 $sformat(name,"reports/effects_v60/cartoon_%0d.hex",f);$readmemh(name,expected);
 $sformat(name,"reports/effects_v60/edge_%0d.hex",f);$readmemh(name,edges);
 n=0;checking=1;
 for(y=0;y<48;y=y+1)begin
 for(x=0;x<96;x=x+1)begin de=1;sof=x==0&&y==0;eol=x==95;rgb=inputs[y*96+x];@(negedge clk);end
 de=0;sof=0;eol=0;repeat(5)@(negedge clk);
 end
 repeat(8)@(negedge clk);checking=0;if(n!=4608)$fatal(1,"pixel count");
 end
 $display("PASS tb_effects_v60 36864 exact RGB pixels, eight scenes, cartoon/edge, SOF/EOL and frame restart");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
