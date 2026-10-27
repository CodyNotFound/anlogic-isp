`timescale 1ns/1ps
// Compare unchanged tracker math with local RAM and the actual CNN feature RAM.
module tb_yunet_shared_tracker;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,owner=1,reseed=0,fs=0,sv=0,fe=0;reg [7:0] gray;
 wire trst=rst&&owner;
 wire rv0,f0,b0,rv1,f1,b1;wire [7:0] x0,y0,q0,x1,y1,q1;wire [17:0] best0,snd0,best1,snd1;
 wire [31:0] c0,c1;wire [1:0] lost0,lost1;wire we;wire [13:0] wa,ra;wire [7:0] wd,rd;
 vision_sad_tracker #(.WIDTH(64),.HEIGHT(48),.RADIUS(4),.SCALE_ENABLE(1),.RECOVERY_FRAMES(3)) local_tracker(
  .clk(clk),.rst_n(trst),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),
  .result_valid(rv0),.found(f0),.center_x(x0),.center_y(y0),.quality(q0),.best_sad(best0),.second_sad(snd0),.busy(b0),.compute_cycles(c0),.lost_stage(lost0),
  .shared_write_en(),.shared_write_addr(),.shared_read_addr(),.shared_write_data(),.shared_read_data(8'd0));
 vision_sad_tracker #(.WIDTH(64),.HEIGHT(48),.RADIUS(4),.SCALE_ENABLE(1),.RECOVERY_FRAMES(3),.EXTERNAL_FRAME(1)) shared_tracker(
  .clk(clk),.rst_n(trst),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),
  .result_valid(rv1),.found(f1),.center_x(x1),.center_y(y1),.quality(q1),.best_sad(best1),.second_sad(snd1),.busy(b1),.compute_cycles(c1),.lost_stage(lost1),
  .shared_write_en(we),.shared_write_addr(wa),.shared_read_addr(ra),.shared_write_data(wd),.shared_read_data(rd));
 face_video_cnn #(.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage(
  .clk(clk),.rst_n(rst),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(owner),.shared_write_en(we),.shared_write_address(wa),.shared_read_address(ra),.shared_write_data(wd),.shared_read_data(rd));
 integer x,y,phase,results=0,waits;reg monitoring=0;
 always @(posedge clk)begin #1;
  if(monitoring&&trst)begin
   if({rv0,f0,x0,y0,q0,best0,snd0,b0,c0,lost0}!=={rv1,f1,x1,y1,q1,best1,snd1,b1,c1,lost1})
    $fatal(1,"shared tracker diverged phase%0d state%0d/%0d rv%0d/%0d center%0d,%0d/%0d,%0d",phase,local_tracker.state,shared_tracker.state,rv0,rv1,x0,y0,x1,y1);
   if(rv0)results=results+1;
  end
 end
 task frame(input integer dx,input integer blank);
 integer xx;
 begin
  fs=1;@(negedge clk);fs=0;
  for(y=0;y<48;y=y+1)for(x=0;x<64;x=x+1)begin
   xx=x-dx;gray=blank||xx<0||xx>=64?0:((xx*73)^(y*29)^(xx*y*13));sv=1;fe=x==63&&y==47;@(negedge clk);
  end
  sv=0;fe=0;
  waits=0;while(b0||b1)begin @(negedge clk);waits=waits+1;if(waits>1000000)$fatal(1,"tracker watchdog");end
  repeat(5)@(negedge clk);
 end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(5)@(negedge clk);monitoring=1;
  phase=0;frame(0,0);if(!f0)$fatal(1,"seed did not lock");
  phase=1;frame(2,0);if(!f0||x0!=34||y0!=24)$fatal(1,"motion fixture did not track");
  phase=2;frame(2,1);if(f0)$fatal(1,"blank fixture accepted");
  // An ownership/mode change resets analytics, then requires a full new frame.
  monitoring=0;owner=0;repeat(5)@(negedge clk);owner=1;repeat(5)@(negedge clk);monitoring=1;
  phase=3;reseed=1;@(negedge clk);reseed=0;frame(0,0);if(!f0)$fatal(1,"mode-return reseed failed");
  if(results<4)$fatal(1,"missing tracker results");
  $display("PASS tb_yunet_shared_tracker: actual CNN BRAM reused for template capture/read, exact cycle/result/score equivalence, motion, blank rejection, ownership reset");$finish;
 end
 initial begin #60000000;$fatal(1,"shared memory watchdog");end
endmodule
