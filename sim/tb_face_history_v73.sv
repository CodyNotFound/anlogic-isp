`timescale 1ns/1ps
module tb_face_history_v73;
 reg clk=0,rst=0,sof=0,de=0,eol=0,found=0;always #5 clk=~clk;
 reg[11:0]bx=100,by=100,size=80,cx=140,cy=140;wire[23:0]a,b;wire ad,bd,asof,bsof;
 face_overlay_v63 old0(.clk(clk),.rst_n(rst),.enable(1'b1),.vsync(sof),.hsync(eol),.de(de),.sof(sof),.eol(eol),.rgb(24'h6080a0),.found(found),.box_x(bx),.box_y(by),.box_size(size),.center_x(cx),.center_y(cy),.out_vsync(),.out_hsync(),.out_de(ad),.out_sof(asof),.out_eol(),.out_rgb(a));
 face_position_overlay now0(.clk(clk),.rst_n(rst),.enable(1'b1),.vsync(sof),.hsync(eol),.de(de),.sof(sof),.eol(eol),.rgb(24'h6080a0),.found(found),.box_x(bx),.box_y(by),.box_size(size),.center_x(cx),.center_y(cy),.out_vsync(),.out_hsync(),.out_de(bd),.out_sof(bsof),.out_eol(),.out_rgb(b));
 integer f,x,updates=0;reg[11:0]last=0;
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 always @(posedge clk)begin #1;if(rst)begin
  if({ad,asof}!=={bd,bsof})$fatal(1,"video cadence changed");
  if({old0.bx,old0.by,old0.bs,old0.cx,old0.cy,old0.display_found}!=={now0.bx,now0.by,now0.bs,now0.cx,now0.cy,now0.display_found})$fatal(1,"coordinate/hold mismatch");
 end end
 initial begin clocks(5);rst=1;found=1;
  for(f=0;f<90;f=f+1)begin
   if(f%15==0)begin bx=bx+48;cx=cx+48;end
   sof=1;de=1;clocks(1);sof=0;
   for(x=0;x<128;x=x+1)begin eol=x==127;clocks(1);end
   de=0;eol=0;clocks(3);if(now0.bx!=last)updates=updates+1;last=now0.bx;
   if(f==70)found=0;
  end
  if(updates!=6)$fatal(1,"update count %0d",updates);
  $display("PASS tb_face_history_v73: 90 SOFs, six sparse detections, v63/current coordinate and hold cadence identical; only stroke geometry differs");$finish;
 end
endmodule
