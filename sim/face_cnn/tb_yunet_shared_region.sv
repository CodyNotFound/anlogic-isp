`timescale 1ns/1ps
module tb_yunet_shared_region;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,frame_abort=0,fs=0,sv=0,fe=0;
 reg [7:0] sx=0,sy=0;reg [23:0] rgb=0;
 wire rv,cal,found,overflow,busy;wire [7:0] cx,cy;wire [14:0] area;
 vision_color_region #(.WIDTH(64),.HEIGHT(48)) dut(.clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_abort(frame_abort),
 .frame_start(fs),.sample_valid(sv),.frame_end(fe),.sample_x(sx),.sample_y(sy),.rgb(rgb),
 .result_valid(rv),.calibrated(cal),.found(found),.overflow(overflow),.center_x(cx),.center_y(cy),
 .box_x(),.box_y(),.box_w(),.box_h(),.area(area),.busy(busy),.compute_cycles(),.pick_pending(),.shared_write_en(),.shared_write_addr(),.shared_read_addr(),.shared_write_data(),.shared_read_data(8'd0));
 wire erv,ecal,efound,eoverflow,ebusy;wire [7:0] ecx,ecy;wire [14:0] earea;
 wire we;wire [14:0] wa,ra;wire [7:0] wd,rd;
 reg local_done=0,external_done=0;
 always @(posedge clk)begin
  if(!rst_n||fs)begin local_done<=0;external_done<=0;end
  else begin if(rv)local_done<=1;if(erv)external_done<=1;end
 end
 vision_color_region #(.WIDTH(64),.HEIGHT(48),.EXTERNAL_QUEUE(1)) external_region(.clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_abort(frame_abort),
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
 reg [23:0] pixels[0:3071];string name;integer file,n,i,waits,action,ec,ef,ex,ey,ea,checked=0;
 initial begin
  file=$fopen("sim/vision_tasks/v42_color/cases.txt","r");if(!file)$fatal(1,"missing cases");
  repeat(4)@(negedge clk);rst_n=1;
  while(!$feof(file))begin
   n=$fscanf(file,"%s %d %d %d %d %d %d\n",name,action,ec,ef,ex,ey,ea);
   if(n!=7)$fatal(1,"parse case");
   if(action==1)begin reseed=1;@(negedge clk);reseed=0;end
   $readmemh({"sim/vision_tasks/v42_color/",name,".hex"},pixels);
   @(negedge clk);fs=1;@(negedge clk);fs=0;
   for(i=0;i<3072;i=i+1)begin
    sv=1;sx=i%64;sy=i/64;rgb=pixels[i];fe=i==3071;@(negedge clk);
    if(action==2 && i==500)begin sv=0;fe=0;frame_abort=1;@(negedge clk);frame_abort=0;i=3072;end
    else if(i%47==0)begin sv=0;fe=0;repeat(2)@(negedge clk);end
   end
   sv=0;fe=0;if(action!=2)repeat(3)@(negedge clk);
   if(name=="dim_tilt" && dut.raw_mask[3071]!==1'b1)$fatal(1,"last mask bit did not drain");
   if(name=="neutral_glint" && dut.raw_mask[3071]!==1'b0)$fatal(1,"last mask bit leaked from previous frame");
   waits=0;
   while((!local_done||!external_done) && waits<300000)begin @(negedge clk);waits=waits+1;end
   if(!local_done||!external_done||overflow||cal!==ec||found!==ef||area!==ea || ef&&(cx!==ex||cy!==ey))
    $fatal(1,"%s cal%0d f%0d center%0d,%0d area%0d expected cal%0d f%0d c%0d,%0d area%0d",name,cal,found,cx,cy,area,ec,ef,ex,ey,ea);
   if({cal,found,overflow,cx,cy,area}!=={ecal,efound,eoverflow,ecx,ecy,earea})
    $fatal(1,"external queue differs %s local%0d,%0d,%0d external%0d,%0d,%0d",name,cx,cy,area,ecx,ecy,earea);
   $display("PASS lighting %s found%0d center%0d,%0d area%0d",name,found,cx,cy,area);
   checked=checked+1;repeat(4)@(negedge clk);
  end
  if(checked!=25)$fatal(1,"coverage %0d",checked);
  $display("PASS tb_yunet_shared_region: actual CNN RAM external queue agrees across 25 lighting cases; tilt, 0.35x-1.0x RGB gain, neutral highlights, loss memory, two-frame global reacquire, ambiguity, stream abort, explicit new color");$finish;
 end
 initial begin #80000000;$fatal(1,"lighting watchdog");end
endmodule
