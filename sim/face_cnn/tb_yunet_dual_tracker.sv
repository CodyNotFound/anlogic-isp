`timescale 1ns/1ps
module tb_yunet_dual_tracker;
 reg core_clk=0;always #2.5 core_clk=~core_clk;

 reg clk=0;always #5 clk=~clk;
 reg rst=0,owner=1,reseed=0,fs=0,sv=0,fe=0;reg[7:0]gray=0;
 wire rv,f,b;wire[7:0]x,y,q;wire[17:0]best,second;wire[31:0]cycles;wire[1:0]lost;
 wire we;wire[14:0]wa,ra;wire[7:0]wd,rd;wire[31:0]rw;
 vision_sad_tracker #(.WIDTH(160),.HEIGHT(90),.RADIUS(8),.SCALE_ENABLE(1),.REACQUIRE_ENABLE(1),.EXTERNAL_FRAME(1),.EXTERNAL_TEMPLATES(1),.EXTERNAL_SCORES(1)) dut(
 .clk(clk),.rst_n(rst&&owner),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),
 .result_valid(rv),.found(f),.center_x(x),.center_y(y),.quality(q),.best_sad(best),.second_sad(second),.busy(b),.compute_cycles(cycles),.lost_stage(lost),
 .shared_write_en(we),.shared_write_addr(wa),.shared_read_addr(ra),.shared_write_data(wd),.shared_read_data(rd),.shared_read_word(rw));
 face_video_cnn #(.CORE_CLK_X2(1),.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage(
  .core_clk(core_clk),.clk(clk),.rst_n(rst),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(owner),.shared_write_en(we),.shared_write_address(wa),.shared_read_address(ra),.shared_write_data(wd),.shared_read_data(rd),.shared_read_word(rw),.inference_cycles(),.capture_started());
 integer xx,yy,u,v,i,waits,frames=0,maxcycles=0,maxaddr=0;
 always @(posedge clk)if(rst&&we)begin if(wa>maxaddr)maxaddr=wa;if(wa>=20388)$fatal(1,"arena overflow %0d",wa);end
 task frame(input integer tx,input integer ty,input integer blank);begin
 fs=1;@(negedge clk);fs=0;
 for(yy=0;yy<90;yy=yy+1)for(xx=0;xx<160;xx=xx+1)begin
  u=xx-tx+16;v=yy-ty+16;
  gray=blank||u<0||u>=32||v<0||v>=32?40:((u*73)^(v*29)^(u*v*13));
  sv=1;fe=xx==159&&yy==89;@(negedge clk);
 end
 sv=0;fe=0;waits=0;
 while(b)begin @(negedge clk);waits=waits+1;if(waits>1500000)$fatal(1,"search stuck state%0d",dut.state);end
 repeat(3)@(negedge clk);frames=frames+1;$display("PROGRESS tracker frame%0d found%0d xy%0d,%0d cycles%0d",frames,f,x,y,cycles);if(cycles>maxcycles)maxcycles=cycles;
 end endtask
 initial begin
 repeat(5)@(negedge clk);rst=1;repeat(5)@(negedge clk);
 frame(80,45,0);if(!f||x!=80||y!=45)$fatal(1,"seed failed");
 frame(80,45,1);if(f||lost==0)$fatal(1,"absent target accepted");
 // More than one complete sweep with target absent must never lock background.
 // Full absent sweep is covered by64x48 regression. Reenter at initial tile0.
 i=0;while(!f&&i<3)begin frame(8,8,0);i=i+1;end
 if(!f||x!=8||y!=8||lost!=0)$fatal(1,"full-frame reacquire failed %0d,%0d after%0d",x,y,i);
 if(i<2)$fatal(1,"recovery bypassed confirmation");
 frame(8,8,0);if(!f||x!=8||y!=8)$fatal(1,"local tracking after recovery failed");
 reseed=1;@(negedge clk);reseed=0;if(f||lost!=0)$fatal(1,"K4 did not clear recovery");
 frame(80,45,0);if(!f||x!=80||y!=45)$fatal(1,"new K4 seed failed");
 owner=0;repeat(4)@(negedge clk);if(f||we)$fatal(1,"mode exit not reset");owner=1;repeat(4)@(negedge clk);
 frame(80,45,0);if(!f)$fatal(1,"mode reentry failed");
 $display("PASS tb_yunet_dual_tracker actual CNN shared frame/template/scores; blank sweep rejection; out-of-window reentry found after %0d frames; two-frame confirmation; K4/mode reset; max cycles%0d address%0d totalframes%0d",i,maxcycles,maxaddr,frames);$finish;
 end
 initial begin #250000000;$fatal(1,"watchdog");end
endmodule
