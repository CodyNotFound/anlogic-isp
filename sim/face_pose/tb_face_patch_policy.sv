`timescale 1ns/1ps
// Cascade stub only for bounded-hold policy. This is NOT face-accuracy evidence.
// Snapshot reads, stored gradients, SAD search and pose FSM are real RTL.
module tb_face_patch_policy;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_start=0,pixel_valid=0;reg [7:0] gray;
 wire ready,busy,result_valid,target_found;wire [7:0] target_x,target_y,target_size,target_votes;
 wire [8:0] target_center_x,target_center_y;wire [2:0] target_view;wire [31:0] cycles,feature_count;
 face_pose_snapshot #(.TRACKING_ENABLE(1)) dut(.*);
 reg [7:0] image[0:14399];integer i,j,n,expected,x,y;
 always @(posedge clk)if(rst_n&&dut.read_addr>=14400)$fatal(1,"snapshot read outside frame");
 task frame;input flat;
 begin
  @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
  for(i=0;i<14400;i=i+1)begin pixel_valid=1;gray=flat?8'd100:image[i];@(negedge clk);end
  pixel_valid=0;n=0;
  while(!result_valid&&n<3000000)begin @(negedge clk);n=n+1;end
  if(!result_valid)$fatal(1,"patch policy completion");
  repeat(4)@(negedge clk);
 end endtask
 initial begin
  $readmemh("sim/face_pose/upright.hex",image);
  repeat(4)@(negedge clk);rst_n=1;
  frame(0);if(!target_found||!dut.patch_valid)$fatal(1,"patch initialization");
  for(j=0;j<64;j=j+1)begin
   x=83+j%8;y=45+j/8;expected=image[y*160+x+1]-image[y*160+x];
   if($signed(dut.patch_template[j])!=expected)$fatal(1,"gradient sign/read alignment at %0d",j);
  end
  frame(0);if(!target_found||!dut.patch_used||dut.patch_best!=0||target_center_x!=87||target_center_y!=49)$fatal(1,"first missed-cascade bridge");
  frame(0);if(!target_found||!dut.patch_used)$fatal(1,"second missed-cascade bridge");
  frame(0);if(target_found||dut.patch_valid)$fatal(1,"unbounded face hold after verification failures");
  rst_n=0;repeat(4)@(negedge clk);rst_n=1;
  frame(1);if(!target_found||dut.patch_valid)$fatal(1,"low texture gate");
  frame(1);if(target_found)$fatal(1,"flat patch sustained false face");
  $display("PASS tb_face_patch_policy: 64 signed gradients, real SAD, two-result hold limit, low texture, reset, address bounds; cascade stub only");$finish;
 end
endmodule

module face_detector_snapshot #(
 parameter HUMAN_ONLY=1,NUM_SCALES=9,SEARCH_SUPPORT=1,WEAK_FILE="",STAGE_FILE="",GEOMETRY_FILE=""
)(input wire clk,rst_n,frame_start,pixel_valid,model_select,input wire [7:0] gray,
 output reg ready,busy,result_valid,target_found,output wire overflow,
 output reg [7:0] target_x,target_y,target_size,target_votes,
 output wire [8:0] target_center_x,target_center_y,output wire [31:0] cycles,feature_count,
 input wire search_enable,input wire [7:0] search_x0,search_y0,search_x1,search_y1,
 input wire [3:0] search_scale_lo,search_scale_hi);
 integer count,requests;
 assign overflow=0;assign cycles=0;assign feature_count=0;
 assign target_center_x=target_x+target_size/2;assign target_center_y=target_y+target_size/2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ready<=1;busy<=0;result_valid<=0;target_found<=0;target_x<=0;target_y<=0;target_size<=0;target_votes<=0;count<=0;requests<=0;end
  else begin
   result_valid<=0;
   if(frame_start&&ready)begin ready<=0;busy<=1;count<=0;end
   if(busy&&pixel_valid)begin
    count<=count+1;
    if(count==14399)begin ready<=1;busy<=0;result_valid<=1;requests<=requests+1;
     target_found<=requests==0;target_x<=73;target_y<=35;target_size<=28;target_votes<=requests==0?6:0;
    end
   end
  end
 end
endmodule
