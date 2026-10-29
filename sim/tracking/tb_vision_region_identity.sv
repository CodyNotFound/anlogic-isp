`timescale 1ns/1ps
module tb_vision_region_identity;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,fs=0,sv=0,fe=0;
 reg [7:0] sx,sy;reg [23:0] rgb;
 wire rv,cal,found,overflow,busy;wire [7:0] cx,cy;wire [14:0] area;
 vision_color_region #(.WIDTH(64),.HEIGHT(48)) dut(
 .clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),
 .sample_x(sx),.sample_y(sy),.rgb(rgb),.result_valid(rv),.calibrated(cal),.found(found),
 .overflow(overflow),.box_x(),.box_y(),.box_w(),.box_h(),.center_x(cx),.center_y(cy),
 .area(area),.busy(busy),.compute_cycles(),.pick_pending(),.frame_abort(1'b0),.shared_write_en(),.shared_write_addr(),.shared_read_addr(),.shared_write_data(),.shared_read_data(8'd0));
 integer x,y,n;
 task frame;input integer kind;
 begin
  @(negedge clk);fs=1;@(negedge clk);fs=0;
  for(y=0;y<48;y=y+1)for(x=0;x<64;x=x+1)begin
   sx=x;sy=y;sv=1;fe=(x==63&&y==47);rgb=24'h203050;
   // Larger equally colored distractor, present even during initial pick.
   if(x>=2&&x<=17&&y>=2&&y<=16)rgb=24'hb45030;
   if(kind==0 && x>=29&&x<=35&&y>=21&&y<=27)rgb=24'hb45030;
   if((kind==1||kind==3) && x>=33&&x<=39&&y>=21&&y<=27)
    rgb=kind==3?24'hffa080:24'hb45030;
   if(kind==4 && ((x>=25&&x<=31)||(x>=41&&x<=47))&&y>=21&&y<=27)rgb=24'hb45030;
   @(negedge clk);
  end
  sv=0;fe=0;n=0;
  while(!rv&&n<200000)begin @(negedge clk);n=n+1;end
  if(!rv||overflow)$fatal(1,"region completion/overflow");
  repeat(3)@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  frame(0);if(!cal||found)$fatal(1,"pick");
  frame(0);if(!found||cx!=32||cy!=24)$fatal(1,"selected larger lamp instead of picked component %d %d",cx,cy);
  frame(1);if(!found||cx!=36)$fatal(1,"continuous movement");
  frame(2);if(found)$fatal(1,"jumped to distractor after loss");
  frame(3);if(!found||cx!=36)$fatal(1,"neutral highlight changed the selected hue");
  frame(1);if(!found||cx!=36)$fatal(1,"local recovery");
  frame(4);if(found)$fatal(1,"ambiguous pair accepted");
  @(negedge clk);reseed=1;@(negedge clk);reseed=0;
  frame(0);frame(0);if(!found||cx!=32)$fatal(1,"repick failed");
  $display("PASS tb_vision_region_identity: picked identity, bigger lamp, motion, loss, highlight, recovery, ambiguity, repick");$finish;
 end
 initial begin #30000000;$fatal(1,"region identity timeout");end
endmodule
