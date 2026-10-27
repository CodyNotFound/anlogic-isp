`timescale 1ns/1ps
module tb_yunet_region_capacity;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,frame_abort=0,fs=0,sv=0,fe=0;
 reg [7:0] sx=0,sy=0;reg [23:0] rgb=0;
 wire rv,cal,found,overflow,busy;wire [7:0] cx,cy;wire [14:0] area;
 vision_color_region #(.WIDTH(160),.HEIGHT(90)) dut(.clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_abort(frame_abort),
 .frame_start(fs),.sample_valid(sv),.frame_end(fe),.sample_x(sx),.sample_y(sy),.rgb(rgb),
 .result_valid(rv),.calibrated(cal),.found(found),.overflow(overflow),.center_x(cx),.center_y(cy),
 .box_x(),.box_y(),.box_w(),.box_h(),.area(area),.busy(busy),.compute_cycles(),.pick_pending());
 wire erv,ecal,efound,eoverflow,ebusy;wire [7:0] ecx,ecy;wire [14:0] earea;
 wire we;wire [14:0] wa,ra;wire [7:0] wd,rd;
 reg local_done=0,external_done=0;
 always @(posedge clk)begin
  if(!rst_n||fs)begin local_done<=0;external_done<=0;end
  else begin if(rv)local_done<=1;if(erv)external_done<=1;end
 end
 vision_color_region #(.WIDTH(160),.HEIGHT(90),.EXTERNAL_QUEUE(1)) external_region(.clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_abort(frame_abort),
 .frame_start(fs),.sample_valid(sv),.frame_end(fe),.sample_x(sx),.sample_y(sy),.rgb(rgb),
 .result_valid(erv),.calibrated(ecal),.found(efound),.overflow(eoverflow),.center_x(ecx),.center_y(ecy),
 .box_x(),.box_y(),.box_w(),.box_h(),.area(earea),.busy(ebusy),.compute_cycles(),.pick_pending(),.shared_write_en(we),.shared_write_addr(wa),.shared_read_addr(ra),.shared_write_data(wd),.shared_read_data(rd));
 face_video_cnn #(.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) storage(
  .clk(clk),.rst_n(rst_n),.enable(1'b0),.sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),
  .position_valid(),.found(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),.stream_error(),.completed_frames(),
  .shared_enable(1'b1),.shared_write_en(we),.shared_write_address(wa),.shared_read_address(ra),.shared_write_data(wd),.shared_read_data(rd));
 integer phase,i,waits,max_addr=0;
 always @(posedge clk)if(we && wa>max_addr)max_addr=wa;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(phase=0;phase<3;phase=phase+1)begin
   fs=1;@(negedge clk);fs=0;
   for(i=0;i<14400;i=i+1)begin
    sv=1;sx=i%160;sy=i/160;fe=i==14399;
    rgb=(phase<2 || (sx>=50&&sx<110&&sy>=25&&sy<65))?24'hd07020:24'h203050;
    @(negedge clk);
   end
   sv=0;fe=0;waits=0;
   while((!local_done||!external_done)&&waits<1200000)begin @(negedge clk);waits=waits+1;end
   if(!local_done||!external_done||{cal,found,overflow,cx,cy,area}!=={ecal,efound,eoverflow,ecx,ecy,earea})
    $fatal(1,"capacity phase%0d mismatch rv%0d/%0d found%0d/%0d center%0d,%0d/%0d,%0d area%0d/%0d",phase,local_done,external_done,found,efound,cx,cy,ecx,ecy,area,earea);
   if(overflow||!cal)$fatal(1,"capacity/calibration failed");
   if(phase==1 && (found || max_addr<28000))$fatal(1,"large component did not cross 16KiB boundary: %0d",max_addr);
   if(phase==2 && (!found || area<2000))$fatal(1,"small foreground did not lock");
   $display("PASS capacity phase%0d max_write_address%0d found%0d area%0d",phase,max_addr,found,area);
   repeat(5)@(negedge clk);
  end
  $display("PASS tb_yunet_region_capacity: 160x90 full-component queue, high address bit, oversize rejection and foreground match local oracle");$finish;
 end
 initial begin #50000000;$fatal(1,"capacity watchdog");end
endmodule
