`timescale 1ns/1ps
// Inject known measurement interfaces for pixel/HUD inspection; no recognition
// claim is made by this display-only test. Real analytics are tested separately.
module tb_vision_hud;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,update=0;reg [3:0] mode=12;
 reg [11:0] bx,by,bw,bh,cx,cy;reg [19:0] metric;
 reg vs=0,hs=0,de=0,sof=0,eol=0;reg [23:0] rgb;
 wire ov,oh,od,os,oe;wire [23:0] op;
 vision_task_hud #(.WIDTH(512),.HEIGHT(384)) dut(clk,rst_n,mode,1'b1,update,1'b1,1'b1,1'b0,2'd0,
  bx,by,bw,bh,cx,cy,metric,vs,hs,de,sof,eol,rgb,ov,oh,od,os,oe,op,1'b0,1'b0);
 reg [7:0] tracker[0:3071];reg [23:0] region_rgb[0:3071];
 integer f,phase,x,y,index,pixels=0,green=0,red=0,text=0,starts=0;
 reg checking=0;
 always @(posedge clk)begin
  #1;
  if(checking&&od)begin
   if(os)starts=starts+1;
   if(op==24'h00ff40)green=green+1;if(op==24'hff4040)red=red+1;if(op==24'hf0ffff)text=text+1;
   $fwrite(f,"%c%c%c",op[23:16],op[15:8],op[7:0]);pixels=pixels+1;
  end
 end
 initial begin
  $readmemh("sim/vision_tasks/track_move.hex",tracker);$readmemh("sim/vision_tasks/region_components.hex",region_rgb);
  repeat(4)@(negedge clk);rst_n=1;
  for(phase=0;phase<2;phase=phase+1)begin
   mode=phase==0?12:14;bx=phase==0?232:160;by=phase==0?104:96;bw=phase==0?128:192;bh=phase==0?128:160;
   cx=phase==0?296:248;cy=168;metric=phase==0?255:30464;
   update=1;@(negedge clk);update=0;repeat(24)@(negedge clk);
   if(dut.x_digits!==(phase==0?24'h000296:24'h000248)||dut.y_digits!==24'h000168||
      dut.m_digits!==(phase==0?24'h000255:24'h030464))$fatal(1,"HUD decimal labels");
   f=$fopen(phase==0?"reports/vision_tasks/tracker_hud_rtl.ppm":"reports/vision_tasks/region_hud_rtl.ppm","wb");
   $fwrite(f,"P6\n512 384\n255\n");pixels=0;green=0;red=0;text=0;starts=0;checking=1;
   for(y=0;y<384;y=y+1)begin
    for(x=0;x<512;x=x+1)begin
     @(negedge clk);de=1;sof=x==0&&y==0;vs=sof;eol=x==511;hs=eol;index=(y/8)*64+x/8;
     rgb=phase==0?{tracker[index],tracker[index],tracker[index]}:region_rgb[index];
    end
    @(negedge clk);de=0;sof=0;vs=0;eol=0;hs=0;repeat(4)@(negedge clk);
   end
   repeat(8)@(negedge clk);checking=0;$fclose(f);
   if(pixels!=196608||starts!=1||red!=29||green!=(phase==0?1008:1392)||text<50)
    $fatal(1,"HUD pixel counts phase%0d pix%0d starts%0d green%0d red%0d text%0d",phase,pixels,starts,green,red,text);
   $display("PASS HUD phase%0d green%0d red%0d text%0d",phase,green,red,text);
  end
  $display("PASS tb_vision_hud: 393216 exported pixels, decimal labels and geometry; injected interface only");$finish;
 end
 initial begin #10000000;$fatal(1,"HUD timeout");end
endmodule
