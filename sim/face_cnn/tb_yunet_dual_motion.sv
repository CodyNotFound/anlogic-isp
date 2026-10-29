`timescale 1ns/1ps
module tb_yunet_dual_motion;
 parameter W=16,H=12;
 reg core_clk=0;always #2.5 core_clk=~core_clk;

 reg clk=0,rst=0,enable=1,reseed=0,suppress=0,fs=0,sv=0,fe=0,error=0;
 reg[7:0] sx,sy,gray;always #5 clk=~clk;
 wire rv,found,initialized;wire[2:0] status;wire[7:0] bx,by,bw,bh,cx,cy;
 wire[14:0] area;wire[31:0] cycles;wire we;wire[14:0] wa,ra;wire[7:0] wd,rd;
 vision_motion_diff #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,enable,reseed,suppress,fs,sv,fe,error,sx,sy,gray,rv,found,initialized,status,bx,by,bw,bh,cx,cy,area,cycles,we,wa,ra,wd,rd);
 face_video_cnn #(.CORE_CLK_X2(1),.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage(
  .core_clk(core_clk),.clk(clk),.rst_n(rst),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(enable),.shared_write_en(we),.shared_write_address(wa),.shared_read_address(ra),.shared_write_data(wd),.shared_read_data(rd),.shared_read_word(),.inference_cycles());

 integer x,y,kind,results=0,prior,max_address=0;
 always @(posedge clk)begin #1;if(rv)results=results+1;if(we&&wa>max_address)max_address=wa;end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task frame(input integer fixture);
 integer xx,yy;
 begin
 prior=results;fs=1;ticks(1);fs=0;
 for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
  sx=xx;sy=yy;gray=fixture>=4?80:40;
  if(fixture>=1&&fixture<=3&&yy>=3&&yy<=8&&xx>=(fixture==1?4:5)&&xx<=(fixture==1?9:10))gray=180;
  if(fixture==6&&((xx==1&&yy==1)||(xx==6&&yy==4)||(xx==13&&yy==9)))gray=200;
  sv=1;fe=xx==W-1&&yy==H-1;ticks(1);sv=0;fe=0;ticks(7);
 end
 ticks(10);
 if(!suppress&&results!=prior+1)$fatal(1,"missing/duplicate result fixture%0d %0d/%0d",fixture,results,prior);
 if(cycles>W*H*5+8)$fatal(1,"unbounded compute");
 end endtask
 initial begin
 ticks(5);rst=1;ticks(5);
 frame(0);if(found||!initialized||status!=0)$fatal(1,"reference warmup");
 frame(1);if(found)$fatal(1,"single frame not confirmed");
 frame(2);if(!found||bx!=4||by!=3||bw!=7||bh!=6||cx!=7||cy!=5||area!=12)$fatal(1,"motion box %0d,%0d %0d,%0d center%0d,%0d area%0d status%0d",bx,by,bw,bh,cx,cy,area,status);
 frame(3);if(found)$fatal(1,"static target still reported moving");
 frame(4);if(found||status!=3)$fatal(1,"global lighting change accepted");
 frame(5);if(found)$fatal(1,"lighting settled incorrectly");
 frame(6);if(found)$fatal(1,"isolated noise accepted");
 suppress=1;ticks(5);frame(7);if(found||initialized||status!=4||we)$fatal(1,"camera movement not suppressed");
 suppress=0;ticks(5);frame(5);if(found||!initialized||status!=0)$fatal(1,"resume must rebuild reference");
 fs=1;ticks(1);fs=0;sx=0;sy=0;gray=50;sv=1;ticks(1);sv=0;ticks(7);error=1;ticks(1);error=0;
 if(initialized||found||status!=5)$fatal(1,"partial frame did not invalidate reference");
 frame(5);if(found||status!=0)$fatal(1,"reference after abort");
 enable=0;ticks(5);if(initialized||found||we)$fatal(1,"mode ownership not released");enable=1;ticks(5);frame(5);
 if(max_address!=W*H-1)$fatal(1,"frame RAM range %d",max_address);
 $display("PASS tb_motion_v62 W%0d H%0d actual CNN RAM, warmup, confirmed slow motion, still, illumination rejection, isolated noise, camera suppression, abort, mode reset, exact box and bounded work",W,H);$finish;
 end
 initial begin #20000000;$fatal(1,"watchdog");end
endmodule
