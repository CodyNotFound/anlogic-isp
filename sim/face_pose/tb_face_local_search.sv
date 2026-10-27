`timescale 1ns/1ps
// Real gray snapshots and cascade: no injected detector results.
module tb_face_local_search #(parameter FULL_SEQUENCE=1,REQUIRE_ACCELERATION=1,REPORT_DIR="reports/face_pose/v40_local");
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_start=0,pixel_valid=0;reg [7:0] gray=0;
 wire ready,busy,result_valid,target_found;
 wire [7:0] target_x,target_y,target_size,target_votes;
 wire [8:0] target_center_x,target_center_y;
 wire [2:0] target_view;wire [31:0] cycles,feature_count;
 face_pose_snapshot #(.TRACKING_ENABLE(1)) dut(.*);
 reg [7:0] image[0:14399],negative[0:14399];
 string name;integer i,j,xx,yy,dx,waits,full_cycles,first_x,first_y,fd,local_cycles;
 task frame;input integer shift;input blank;
 begin
  @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
  for(i=0;i<14400;i=i+1)begin
   xx=i%160-shift;yy=i/160;
   gray=blank?negative[i]:(xx<0||xx>=160?8'd96:image[yy*160+xx]);
   pixel_valid=1;@(negedge clk);
  end
  pixel_valid=0;waits=0;
  while(!result_valid&&waits<70000000)begin @(negedge clk);waits=waits+1;end
  if(!result_valid||!ready||busy)$fatal(1,"local search completion");
 end endtask
 initial begin
  if(!$value$plusargs("CASE=%s",name))name="upright";
  $readmemh({"sim/face_pose/",name,".hex"},image);
  $readmemh("sim/face_pose/fruits.hex",negative);
  fd=$fopen({REPORT_DIR,"/",name,"_sequence.csv"},"w");
  $fdisplay(fd,"frame,found,x,y,size,view,cycles,local");
  repeat(4)@(negedge clk);rst_n=1;
  frame(0,0);if(!target_found)$fatal(1,"initial face missing");
  full_cycles=cycles;first_x=target_center_x;first_y=target_center_y;
  $fdisplay(fd,"0,%0d,%0d,%0d,%0d,%0d,%0d,0",target_found,target_center_x,target_center_y,target_size,target_view,cycles);
  for(j=1;j<=2;j=j+1)begin
   repeat(4)@(negedge clk);frame(j*3,0);
   if(!target_found||target_center_x<first_x+j*3-5||target_center_x>first_x+j*3+5||
      target_center_y<first_y-5||target_center_y>first_y+5)$fatal(1,"local face motion %s frame%0d %0d,%0d",name,j,target_center_x,target_center_y);
   if(REQUIRE_ACCELERATION && (cycles>=full_cycles/2 || !dut.local_search))$fatal(1,"local path did not accelerate %d vs %d",cycles,full_cycles);
   $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",j,target_found,target_center_x,target_center_y,target_size,target_view,cycles,dut.local_search);
  end
  if(FULL_SEQUENCE==2)begin
   for(j=3;j<=8;j=j+1)begin
    repeat(4)@(negedge clk);frame(6,0);
    if(!target_found || !dut.local_search)$fatal(1,"continuous verified local search lost");
    if(cycles>=full_cycles/2)$fatal(1,"unnecessary full scan stalled established face");
    $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",j,target_found,target_center_x,target_center_y,target_size,target_view,cycles,dut.local_search);
   end
  end
  if(FULL_SEQUENCE==1)begin
  repeat(4)@(negedge clk);frame(0,1);
  if(target_found||dut.local_search)$fatal(1,"negative fallback not executed");
  $fdisplay(fd,"3,%0d,%0d,%0d,%0d,%0d,%0d,0",target_found,target_center_x,target_center_y,target_size,target_view,cycles);
  repeat(4)@(negedge clk);frame(0,0);
  if(!target_found||dut.local_search)$fatal(1,"full reacquisition failed");
  $fdisplay(fd,"4,%0d,%0d,%0d,%0d,%0d,%0d,0",target_found,target_center_x,target_center_y,target_size,target_view,cycles);
  end
  $fclose(fd);$display("PASS tb_face_local_search %s: real cascade and moving face, full_loss_reacquisition_sequence=%0d",name,FULL_SEQUENCE);$finish;
 end
endmodule
