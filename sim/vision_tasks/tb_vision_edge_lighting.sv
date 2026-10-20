`timescale 1ns/1ps
module tb_vision_edge_lighting;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,sof=0,eol=0;reg [23:0] rgb=0;wire [23:0] out;
 pixel_algorithm #(.IMG_WIDTH(160),.IMG_HEIGHT(90)) dut(clk,rst,4'd7,sof,eol,de,rgb,out);
 reg [23:0] pixels[0:14399],expected[0:14399];reg [3:0] dh=0;
 integer file,i,n=0,total=0,frames=0,fd=0;string name;reg checking=0;
 always @(posedge clk)begin dh<={dh[2:0],de};#1;
  if(checking && dh[3])begin
   if(n>=14400 || out!==expected[n])$fatal(1,"edge %s pixel%0d got%h expected%h",name,n,out,expected[n]);
   if(fd)$fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);
   n=n+1;total=total+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;file=$fopen("sim/vision_tasks/v42_edge/cases.txt","r");
  while(!$feof(file))begin
   i=$fscanf(file,"%s\n",name);
   $readmemh({"sim/vision_tasks/v42_edge/",name,".hex"},pixels);$readmemh({"sim/vision_tasks/v42_edge/",name,".expected"},expected);
   fd=$fopen({"reports/field_v42/edge_",name,"_rtl.ppm"},"wb");$fwrite(fd,"P6\n160 90\n255\n");
   n=0;checking=1;
   for(i=0;i<14400;i=i+1)begin
    @(negedge clk);de=1;sof=i==0;eol=i%160==159;rgb=pixels[i];
    if(i%79==17)begin @(negedge clk);de=0;sof=0;eol=0;repeat(2)@(negedge clk);end
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(8)@(negedge clk);checking=0;
   $fclose(fd);fd=0;
   if(n!=14400)$fatal(1,"pixel count");frames=frames+1;
  end
  if(frames!=8)$fatal(1,"case count");
  $display("PASS tb_vision_edge_lighting: %0d exact RGB pixels, weak contrast, isoluma color, dark noise, borders and gaps",total);$finish;
 end
 initial begin #20000000;$fatal(1,"edge watchdog");end
endmodule
