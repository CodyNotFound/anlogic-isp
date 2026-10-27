`timescale 1ns/1ps
module tb_outline_v64;
 reg clk=0,rst=0,de=0,sof=0,eol=0;always #5 clk=~clk;
 wire fd,td,fs,ts;wire[23:0]fp,tp;
 face_position_overlay face(.clk(clk),.rst_n(rst),.enable(1'b1),.vsync(sof),.hsync(eol),.de(de),.sof(sof),.eol(eol),.rgb(24'h666666),
 .found(1'b1),.box_x(12'd10),.box_y(12'd10),.box_size(12'd20),.center_x(12'd20),.center_y(12'd20),.out_vsync(),.out_hsync(),.out_de(fd),.out_sof(fs),.out_eol(),.out_rgb(fp));
 vision_task_hud #(.WIDTH(64),.HEIGHT(48),.TEXT_ENABLE(0)) taskhud(.clk(clk),.rst_n(rst),.mode(4'd15),.enable(1'b1),.result_valid(1'b0),.found(1'b1),.calibrated(1'b1),.overflow(1'b0),.lost(2'd0),
 .box_x(12'd10),.box_y(12'd10),.box_w(12'd20),.box_h(12'd20),.center_x(12'd20),.center_y(12'd20),.metric(20'd0),
 .vsync(sof),.hsync(eol),.de(de),.sof(sof),.eol(eol),.rgb(24'h666666),.out_vsync(),.out_hsync(),.out_de(td),.out_sof(ts),.out_eol(),.out_rgb(tp),.pick_pending(1'b0),.manual_mode(1'b0));
 function[23:0] expected;input integer n;input integer taskmode;integer x,y;reg border,cross_hit;begin
 x=n%64;y=n/64;border=x>=10&&x<30&&y>=10&&y<30&&(x<13||x>=27||y<13||y>=27);
 cross_hit=(x>=19&&x<=21&&y>=13&&y<=27)||(y>=19&&y<=21&&x>=13&&x<=27);
 expected=cross_hit?24'hff4040:border?24'h00ff40:24'h666666;
 end endfunction
 integer nf=0,nt=0,x,y;
 always @(posedge clk)begin #1;
 if(fd)begin if(fp!==expected(nf,0)||fs!==(nf==0))$fatal(1,"face outline pixel%0d actual%h",nf,fp);nf=nf+1;end
 if(td)begin if(tp!==expected(nt,1)||ts!==(nt==0))$fatal(1,"task outline pixel%0d actual%h",nt,tp);nt=nt+1;end
 end
 initial begin
 repeat(5)@(negedge clk);rst=1;
 for(y=0;y<48;y=y+1)begin for(x=0;x<64;x=x+1)begin de=1;sof=x==0&&y==0;eol=x==63;@(negedge clk);end de=0;sof=0;eol=0;repeat(3)@(negedge clk);end
 repeat(8)@(negedge clk);if(nf!=3072||nt!=3072)$fatal(1,"pixel count");
 $display("PASS three-pixel face/task outlines and center cross_hites: 6144 exact RGB pixels and frame alignment");$finish;
 end
endmodule
