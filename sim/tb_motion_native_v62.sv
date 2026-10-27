`timescale 1ns/1ps
module tb_motion_native_v62;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[3:0] mode=15;reg action=0,suppress=0,fs=0,eol=0,de=0;reg[23:0] rgb;
 wire[31:0] rw;wire tv,tf,we;wire[7:0] tx,ty,wd,rd;wire[14:0] wa,ra;wire[3:0] status;wire[31:0] compute;
 wire od,os,oe;integer pixels=0,frames=0,results=0,prior,x,y,kind;
 vision_task_suite #(.WIDTH(128),.HEIGHT(96),.SHARED_TRACK_FRAME(1),.HUD_TEXT_ENABLE(0)) dut(
 .clk(clk),.rst_n(rst),.enabled(1'b1),.action(action),.mode(mode),.source_sof(fs),.source_eol(eol),.source_de(de),.source_rgb(rgb),
 .vsync(fs),.hsync(eol),.de(de),.sof(fs),.eol(eol),.rgb(rgb),.out_vsync(),.out_hsync(),.out_de(od),.out_sof(os),.out_eol(oe),.out_rgb(),
 .target_valid(tv),.target_found(tf),.target_x(tx),.target_y(ty),.manual_mode(1'b0),.osd_enable(1'b1),.hud_status(status),
 .shared_write_en(we),.shared_write_addr(wa),.shared_read_addr(ra),.shared_write_data(wd),.shared_read_data(rd),.shared_read_word(rw),.target_compute_cycles(compute),.camera_moving(suppress));
 face_video_cnn #(.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage(
  .clk(clk),.rst_n(rst),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(mode==12||mode==14||mode==15),.shared_write_en(we),.shared_write_address(wa),.shared_read_address(ra),.shared_write_data(wd),.shared_read_data(rd),.shared_read_word(rw),.inference_cycles());


 always @(posedge clk)begin #1;
  if(tv)results=results+1;
  if(od)begin if(os!==(pixels==0)||oe!==(pixels%128==127))$fatal(1,"native qualifiers");pixels=pixels+1;end
 end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task frame(input integer fixture);integer xx,yy,v;
 begin
 pixels=0;prior=results;
 for(yy=0;yy<96;yy=yy+1)begin
 for(xx=0;xx<128;xx=xx+1)begin
  de=1;fs=xx==0&&yy==0;eol=xx==127;v=fixture>=4?80:40;
  if(fixture>=1&&fixture<=3&&yy/8>=3&&yy/8<=8&&xx/8>=(fixture==1?4:5)&&xx/8<=(fixture==1?9:10))v=180;
  rgb={v[7:0],v[7:0],v[7:0]};ticks(1);
 end
 de=0;fs=0;eol=0;ticks(8);
 end
 ticks(32);if(pixels!=12288)$fatal(1,"native pixel count %d",pixels);
 if(!suppress&&mode==15&&results!=prior+1)$fatal(1,"native completion");frames=frames+1;
 end endtask
 initial begin
 ticks(5);rst=1;ticks(5);
 frame(0);if(tf||status!=9)$fatal(1,"native warmup status %d",status);
 frame(1);if(tf)$fatal(1,"native unconfirmed target");
 frame(2);if(!tf||tx!=7||ty!=5||status!=8)$fatal(1,"native frame difference %d %d %d status%d",tf,tx,ty,status);
 frame(3);if(tf)$fatal(1,"native stationary target");
 frame(4);if(tf||status!=10)$fatal(1,"native light change");
 suppress=1;ticks(5);frame(5);if(tf||status!=11||we)$fatal(1,"native camera suppression");
 suppress=0;ticks(5);frame(5);if(tf)$fatal(1,"native reference rebuild");
 mode=0;ticks(5);frame(5);if(tf||tv||we)$fatal(1,"motion output leaked outside mode15");
 $display("PASS tb_motion_native_v62: 98304 native RGB pixels, real8x8 sampler and actualCNN RAM, motion box, light/camera suppression, mode ownership and video qualifiers");$finish;
 end
 initial begin #3000000;$fatal(1,"watchdog");end
endmodule
