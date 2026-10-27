`timescale 1ns/1ps
module tb_face_selector;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_start=0,frame_done=0,candidate_valid=0;
 reg [7:0] box_x=0,box_y=0,box_size=0;
 wire result_valid,target_found,overflow,select_busy;
 wire [7:0] target_x,target_y,target_size,target_votes;
 wire [8:0] target_center_x,target_center_y;
 face_candidate_select dut(.*);
 integer fd,rc,n,ci,count,j,x,y,w,ef,eo,ex,ey,ew,ev;
 initial begin
  fd=$fopen("sim/face_lbp/selector_v40.txt","r");if(!fd)$fatal(1,"vectors missing");
  rc=$fscanf(fd,"%d",n);if(rc!=1)$fatal(1,"vector header");
  repeat(3)@(negedge clk);rst_n=1;
  for(ci=0;ci<n;ci=ci+1)begin
   rc=$fscanf(fd,"%d %d %d %d %d %d %d",count,ef,eo,ex,ey,ew,ev);
   if(rc!=7)$fatal(1,"case header %0d",ci);
   @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
   while(select_busy)@(negedge clk);
   for(j=0;j<count;j=j+1)begin
    rc=$fscanf(fd,"%d %d %d",x,y,w);if(rc!=3)$fatal(1,"case candidate");
    while(select_busy)@(negedge clk);
    @(negedge clk);box_x=x;box_y=y;box_size=w;candidate_valid=1;
    // Frame completion need not wait for the serial slot update.
    if(j==count-1)frame_done=1;
    @(negedge clk);candidate_valid=0;frame_done=0;
   end
   if(count==0)begin @(negedge clk);frame_done=1;@(negedge clk);frame_done=0;end
   while(!result_valid)@(negedge clk);
   if(target_found!==ef[0] || overflow!==eo[0] || target_x!==ex[7:0] || target_y!==ey[7:0] ||
      target_size!==ew[7:0] || target_votes!==ev[7:0])
    $fatal(1,"selector reference mismatch case %0d got %0d/%0d %0d,%0d,%0d votes%0d expected %0d/%0d %0d,%0d,%0d votes%0d",ci,target_found,overflow,target_x,target_y,target_size,target_votes,ef,eo,ex,ey,ew,ev);
   if(target_center_x!==ex+ew/2 || target_center_y!==ey+ew/2)$fatal(1,"center mapping");
  end
  $fclose(fd);$display("PASS tb_face_selector: %0d independent sequences; empty, overflow, ties, saturation, final-candidate drain",n);$finish;
 end
 initial begin #30000000;$fatal(1,"selector watchdog");end
endmodule
