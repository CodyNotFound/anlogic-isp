`timescale 1ns/1ps
module tb_vision_local_recovery;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,fs=0,sv=0,fe=0;reg [7:0] gray;
 wire rv,found,busy;wire [7:0] cx,cy;
 reg [7:0] image[0:3071];integer i,j,n;
 vision_sad_tracker #(.WIDTH(64),.HEIGHT(48),.RADIUS(4),.SCALE_ENABLE(1),.RECOVERY_FRAMES(3)) dut(
 .clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),
 .result_valid(rv),.found(found),.center_x(cx),.center_y(cy),.quality(),.best_sad(),.second_sad(),.busy(busy),.compute_cycles(),.lost_stage());
 task frame;input bad;input expect_result;
 begin
  @(negedge clk);fs=1;@(negedge clk);fs=0;
  for(i=0;i<3072;i=i+1)begin sv=1;fe=i==3071;gray=bad?8'd100:image[i];@(negedge clk);end
  sv=0;fe=0;n=0;
  if(expect_result)begin
   while(!rv&&n<800000)begin @(negedge clk);n=n+1;end
   if(!rv)$fatal(1,"recovery result timed out");
  end else begin
   repeat(1000)begin @(negedge clk);if(busy||rv||found)$fatal(1,"unbounded relock search");end
  end
  repeat(4)@(negedge clk);
 end endtask
 initial begin
  $readmemh("sim/vision_tasks/rotation/sequence_seed.hex",image);
  repeat(4)@(negedge clk);rst_n=1;
  frame(0,1);if(!found)$fatal(1,"initial seed");
  frame(1,1);if(found)$fatal(1,"occlusion accepted");
  frame(0,1);if(!found||cx!=32||cy!=24)$fatal(1,"brief occlusion did not recover locally");
  for(j=0;j<4;j=j+1)begin frame(1,1);if(found)$fatal(1,"bad frame accepted");end
  frame(0,0);
  reseed=1;@(negedge clk);reseed=0;
  frame(0,1);if(!found)$fatal(1,"K4 repick after recovery budget exhausted");
  $display("PASS tb_vision_local_recovery: short occlusion, local recovery, bounded retries, K4 reset");$finish;
 end
endmodule
