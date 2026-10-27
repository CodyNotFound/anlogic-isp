`timescale 1ns/1ps
module tb_tracker_stream_v66;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,owner=1,reseed=0,fs=0,sv=0,fe=0;reg[7:0]gray=0;
 wire we0,we1;wire[14:0]wa0,wa1,ra0,ra1;wire[7:0]wd0,wd1,rd0,rd1;wire[31:0]rw0,rw1;
 wire f0,f1,b0,b1;wire[7:0]x0,x1,y0,y1,q0,q1;wire[17:0]best0,best1,second0,second1;wire[31:0]cycles0,cycles1;
 vision_sad_tracker_v65 #(.WIDTH(64),.HEIGHT(48),.RADIUS(4),.SCALE_ENABLE(1),.EXTERNAL_FRAME(1),.EXTERNAL_TEMPLATES(1),.EXTERNAL_SCORES(1)) old(
 .clk(clk),.rst_n(rst),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),.result_valid(),.found(f0),.center_x(x0),.center_y(y0),.quality(q0),.best_sad(best0),.second_sad(second0),.busy(b0),.compute_cycles(cycles0),.lost_stage(),
 .shared_write_en(we0),.shared_write_addr(wa0),.shared_read_addr(ra0),.shared_write_data(wd0),.shared_read_data(rd0),.shared_read_word(rw0));
 face_video_cnn #(.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage0(
  .clk(clk),.rst_n(rst),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(owner),.shared_write_en(we0),.shared_write_address(wa0),.shared_read_address(ra0),.shared_write_data(wd0),.shared_read_data(rd0),.shared_read_word(rw0),.inference_cycles(),.capture_started()); vision_sad_tracker #(.WIDTH(64),.HEIGHT(48),.RADIUS(4),.SCALE_ENABLE(1),.EXTERNAL_FRAME(1),.EXTERNAL_TEMPLATES(1),.EXTERNAL_SCORES(1)) dut(
 .clk(clk),.rst_n(rst),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),.result_valid(),.found(f1),.center_x(x1),.center_y(y1),.quality(q1),.best_sad(best1),.second_sad(second1),.busy(b1),.compute_cycles(cycles1),.lost_stage(),
 .shared_write_en(we1),.shared_write_addr(wa1),.shared_read_addr(ra1),.shared_write_data(wd1),.shared_read_data(rd1),.shared_read_word(rw1));
 face_video_cnn #(.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage1(
  .clk(clk),.rst_n(rst),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(owner),.shared_write_en(we1),.shared_write_address(wa1),.shared_read_address(ra1),.shared_write_data(wd1),.shared_read_data(rd1),.shared_read_word(rw1),.inference_cycles(),.capture_started());
 reg[17:0]score0[0:80],score1[0:80];reg[3:0]bank0[0:80],bank1[0:80];integer count0=0,count1=0;
 always @(negedge clk)if(rst)begin
  if(old.state==7)begin score0[old.candidate_index]=old.final_score;bank0[old.candidate_index]=old.final_bank;count0=count0+1;end
  if(dut.state==7)begin score1[dut.candidate_index]=dut.final_score;bank1[dut.candidate_index]=dut.final_bank;count1=count1+1;end
 end
 integer xx,yy,k,phase,waits,total=0;
 task frame(input integer dx,input integer dy,input integer blank);begin
 count0=0;count1=0;fs=1;@(negedge clk);fs=0;
 for(yy=0;yy<48;yy=yy+1)for(xx=0;xx<64;xx=xx+1)begin
 gray=blank?0:(((xx-dx)*73)^((yy-dy)*29)^((xx-dx)*(yy-dy)*13));sv=1;fe=xx==63&&yy==47;@(negedge clk);
 end
 sv=0;fe=0;waits=0;
 while(b0||b1)begin @(negedge clk);waits=waits+1;if(waits>500000)$fatal(1,"timeout");end
 repeat(3)@(negedge clk);
 if({f0,x0,y0,q0,best0,second0}!=={f1,x1,y1,q1,best1,second1})$fatal(1,"result mismatch phase%0d %h/%h",phase,{f0,x0,y0,q0,best0,second0},{f1,x1,y1,q1,best1,second1});
 if(count0!=count1)$fatal(1,"candidate count");
 for(k=0;k<count0;k=k+1)if({score0[k],bank0[k]}!=={score1[k],bank1[k]})$fatal(1,"candidate %0d score/bank mismatch %0d/%0d",k,score0[k],score1[k]);
 total=total+count0;$display("PASS phase%0d candidates%0d cycles old%0d new%0d",phase,count0,cycles0,cycles1);
 end endtask
 initial begin repeat(5)@(negedge clk);rst=1;repeat(5)@(negedge clk);
 phase=0;frame(0,0,0);phase=1;frame(2,0,0);phase=2;frame(-2,1,0);phase=3;frame(0,0,1);
 if(total<200)$fatal(1,"insufficient exact candidates");
 $display("PASS tb_tracker_stream_v66 %0d candidate SAD/bank values and all results exact with actual CNN arenas; no template bank removed",total);$finish;end
 initial begin #20000000;$fatal(1,"watchdog");end
endmodule
