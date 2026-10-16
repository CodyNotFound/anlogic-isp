`timescale 1ns/1ps
module tb_demosaic_boundary #(parameter integer VECTOR_TEST=0, CHECK_FIRST=0, REAL_CADENCE=0);
 localparam WIDTH=1280,HEIGHT=6,BEATS_PER_LINE=320,EXPECTED_BEATS=3840,EXPECTED_PIXELS=7680;
 reg I_clk=0,I_rst_n=0;
 reg [39:0] raw_vectors[0:1919];
 reg [23:0] rgb_vectors[0:7679];
 initial if(VECTOR_TEST!=0)begin
 $readmemh("boundary_raw.hex",raw_vectors);
 $readmemh("boundary_rgb.hex",rgb_vectors);end
 reg [39:0] axi4s_video_tdata=0;
 reg [9:0] axi4s_video_tdest=0;
 reg axi4s_video_tlast=0,axi4s_video_tvalid=0,axi4s_video_tuser=0;
 wire axi4s_video_tready,O_tlast,O_tuser,O_tvalid;
 wire [95:0] O_tdata;
 integer csv_fd,frame_in,recorded_beats=0,row_in,beat_in,stat_row,output_beats=0,pixel_count=0;
 integer interior_bad_count=0,unknown_pixel_count=0,unknown_control_count=0;
 integer metadata_errors=0,output_user_count=0,observed_row,observed_x;
 integer bad_count[0:HEIGHT-1],row_pixel_count[0:HEIGHT-1],row_interior_bad_count[0:HEIGHT-1];
 always #8.334 I_clk=~I_clk;
 demosaic #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT),.data_complete_delay(50),.BAYER_MODE("BGGR")) dut (
 .I_clk(I_clk),.I_rst_n(I_rst_n),.axi4s_video_tdata(axi4s_video_tdata),
 .axi4s_video_tdest(axi4s_video_tdest),.axi4s_video_tlast(axi4s_video_tlast),
 .axi4s_video_tvalid(axi4s_video_tvalid),.axi4s_video_tuser(axi4s_video_tuser),
 .axi4s_video_tready(axi4s_video_tready),.O_tlast(O_tlast),.O_tuser(O_tuser),
 .O_tvalid(O_tvalid),.O_tdata(O_tdata),.O_tready(1'b1));
 task drive_cycle;
 input valid_value;input [39:0] data_value;input last_value,user_value;
 begin @(negedge I_clk);
  axi4s_video_tvalid=valid_value;axi4s_video_tdata=data_value;
  axi4s_video_tlast=last_value;axi4s_video_tuser=user_value;axi4s_video_tdest=0;
 end endtask
 task record_pixel;
 input integer row_value,x_value;input [23:0] rgb_value;
 reg [7:0] r_value,g_value,b_value;reg is_bad;
 begin
  r_value=rgb_value[23:16];g_value=rgb_value[15:8];b_value=rgb_value[7:0];
  $fwrite(csv_fd,"%0d,%0d,%0d,%0d,%0d\n",row_value,x_value,r_value,g_value,b_value);
  pixel_count=pixel_count+1;
  if((^rgb_value)===1'bx)unknown_pixel_count=unknown_pixel_count+1;
  if(VECTOR_TEST!=0)is_bad=(rgb_value!==rgb_vectors[row_value*WIDTH+x_value]);
  else is_bad=(r_value!==8'd60)||(g_value!==8'd100)||(b_value!==8'd40);
  if(row_value>=0&&row_value<HEIGHT)begin
   row_pixel_count[row_value]=row_pixel_count[row_value]+1;
   if(is_bad)bad_count[row_value]=bad_count[row_value]+1;
   if(is_bad&&x_value>=8&&x_value<1272)row_interior_bad_count[row_value]=row_interior_bad_count[row_value]+1;
  end
  if(is_bad&&x_value>=8&&x_value<1272)interior_bad_count=interior_bad_count+1;
  if(x_value<8)$display("DIAG first8 row=%0d x=%0d R=%0d G=%0d B=%0d",row_value,x_value,r_value,g_value,b_value);
 end endtask
 always @(posedge I_clk)begin
  #1;
  if(I_rst_n)begin
   if(O_tvalid===1'b1)begin
    if((CHECK_FIRST && output_beats<1920) || (!CHECK_FIRST && output_beats>=1920&&output_beats<3840))begin
    observed_row=recorded_beats/BEATS_PER_LINE;observed_x=(recorded_beats%BEATS_PER_LINE)*4;
    record_pixel(observed_row,observed_x,O_tdata[23:0]);
    record_pixel(observed_row,observed_x+1,O_tdata[47:24]);
    record_pixel(observed_row,observed_x+2,O_tdata[71:48]);
    record_pixel(observed_row,observed_x+3,O_tdata[95:72]);
    if(O_tlast!==1'b0&&O_tlast!==1'b1)unknown_control_count=unknown_control_count+1;
    if(O_tuser!==1'b0&&O_tuser!==1'b1)unknown_control_count=unknown_control_count+1;
    if(O_tlast!==((recorded_beats%BEATS_PER_LINE)==BEATS_PER_LINE-1))metadata_errors=metadata_errors+1;
    if(O_tuser===1'b1)output_user_count=output_user_count+1;
    if(O_tuser!==(recorded_beats==0))metadata_errors=metadata_errors+1;
    recorded_beats=recorded_beats+1;
    end
    output_beats=output_beats+1;
   end else if(O_tvalid!==1'b0)unknown_control_count=unknown_control_count+1;
  end
 end
 initial begin
  for(stat_row=0;stat_row<HEIGHT;stat_row=stat_row+1)begin
   bad_count[stat_row]=0;row_pixel_count[stat_row]=0;row_interior_bad_count[stat_row]=0;
  end
  csv_fd=$fopen("demosaic_boundary.csv","w");
  if(csv_fd==0)$fatal(1,"Cannot open CSV");
  $fwrite(csv_fd,"row,x,r,g,b\n");
  repeat(40)@(posedge I_clk);@(negedge I_clk);I_rst_n=1;
  repeat(64)drive_cycle(0,0,0,0);
  for(frame_in=0;frame_in<2;frame_in=frame_in+1)begin
  for(row_in=0;row_in<HEIGHT;row_in=row_in+1)begin
   for(beat_in=0;beat_in<BEATS_PER_LINE;beat_in=beat_in+1)begin
    if(VECTOR_TEST!=0)drive_cycle(1,raw_vectors[row_in*BEATS_PER_LINE+beat_in],beat_in==BEATS_PER_LINE-1,row_in==0&&beat_in==0);
    else if(row_in%2==0)drive_cycle(1,{10'd400,10'd160,10'd400,10'd160},beat_in==BEATS_PER_LINE-1,row_in==0&&beat_in==0);
    else drive_cycle(1,{10'd240,10'd400,10'd240,10'd400},beat_in==BEATS_PER_LINE-1,row_in==0&&beat_in==0);
    if(REAL_CADENCE)drive_cycle(0,0,0,0);
    if(beat_in%4==3)begin
     drive_cycle(0,0,0,0);
     if(REAL_CADENCE)drive_cycle(0,0,0,0);
    end
   end
   repeat(REAL_CADENCE?200:1000)drive_cycle(0,0,0,0);
  end
  repeat(2000)drive_cycle(0,0,0,0);
  end
  @(posedge I_clk);#2;
  for(stat_row=0;stat_row<HEIGHT;stat_row=stat_row+1)
   $display("DIAG row=%0d pixels=%0d bad_count=%0d interior_bad_count=%0d",stat_row,row_pixel_count[stat_row],bad_count[stat_row],row_interior_bad_count[stat_row]);
  $display("DIAG beats=%0d pixels=%0d interior_bad=%0d metadata_errors=%0d users=%0d",output_beats,pixel_count,interior_bad_count,metadata_errors,output_user_count);
  $fclose(csv_fd);
  if(unknown_pixel_count!=0||unknown_control_count!=0)$fatal(1,"Unknown output");
  if(output_beats!=EXPECTED_BEATS||pixel_count!=EXPECTED_PIXELS)$fatal(1,"Output count mismatch");
  for(stat_row=0;stat_row<HEIGHT;stat_row=stat_row+1)
   if(bad_count[stat_row]!=0)$fatal(1,"RGB mismatch row=%0d count=%0d",stat_row,bad_count[stat_row]);
  if(metadata_errors!=0)$fatal(1,"Metadata mismatch" );
  $display("PASS boundary verification complete");$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
