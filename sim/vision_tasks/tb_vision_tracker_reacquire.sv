`timescale 1ns/1ps
// 自动重捕验证: 中心seed锁定 → 目标移出±8窗(Δ16) → 丢失扩窗 → rad16/32内自动找回
module tb_vision_tracker_reacquire;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,fs=0,sv=0,fe=0;reg [7:0] gray;
 wire rv,found,busy;wire [7:0] cx,cy,quality;wire [17:0] best,second;wire [31:0] cycles;wire [1:0] lost;
 vision_sad_tracker #(.WIDTH(64),.HEIGHT(48)) dut(clk,rst_n,reseed,fs,sv,fe,gray,rv,found,cx,cy,quality,best,second,busy,cycles,lost);
 reg [7:0] pixels[0:3071];integer i,j,waits,dbg_n=0,dbg_f;
 task send_frame(input [8*32-1:0] hex);
  begin
   $readmemh({"sim/vision_tasks/",hex,".hex"},pixels);
   @(negedge clk);fs=1;@(negedge clk);fs=0;
   for(i=0;i<3072;i=i+1)begin
    sv=1;gray=pixels[i];fe=(i==3071);@(negedge clk);
   end
   sv=0;fe=0;
   waits=0;dbg_n=dbg_n+1;dbg_f=$fopen({"sim/vision_tasks/rq_dbg_",dbg_n+48,".txt"},"w");
   while(busy && waits<9000000)begin @(negedge clk);waits=waits+1;
    if(dut.state==4'd7)$fwrite(dbg_f,"%0d %0d %0d %0d %0d %0d
",dut.candidate_index,dut.cand_x,dut.cand_y,dut.sad,dut.srad,dut.lost_cnt);
    if(dut.state==4'd12)$display("DECIDE: best=%0d second=%0d bestxy=%0d,%0d peak_ci=%0d cand_ci=%0d",dut.best,dut.second,dut.best_x,dut.best_y,dut.peak_index,dut.candidate_index);
    if(waits%1000000==0)$display("T=%0t st=%0d busy=%b waits=%0d",$time,dut.state,busy,waits);
   end
   $fclose(dbg_f);
   if(waits>=9000000)$fatal(1,"search did not finish");
   if(waits>=300000)$fatal(1,"search did not finish");
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  // 帧1: 中心seed+首搜(仍中心, found应=1)
  send_frame("reacq_seed");
  if(!found)$fatal(1,"seed frame failed to lock");
  if(cx!==8'd32 || cy!==8'd24)$fatal(1,"seed center %0d,%0d exp 32,24",cx,cy);
  $display("PASS reacquire step1: seed lock at 32,24");
  // 帧2: 目标移Δ16出rad8窗 → 丢, 扩窗升级
  send_frame("reacq_shift");
  if(found!==1'b0)$fatal(1,"should lose lock after target jumps out of r8");
  if(lost<2'd1)$fatal(1,"lost_stage should escalate, got %0d",lost);
  $display("PASS reacquire step2: lost, lost_stage=%0d",lost);
  // 帧3-5: 扩窗(rad16/32)内自动找回
  j=0;
  while(!found && j<4)begin send_frame("reacq_shift");
   $display("POST frame j=%0d: found=%b dut.found=%b state=%0d rv=%b",j,found,dut.found,dut.state,rv);
   j=j+1;
  end
  if(!found)$fatal(1,"auto reacquire failed after expansion");
  if(cx!==8'd48 || cy!==8'd36)$fatal(1,"reacquire center %0d,%0d exp 48,36",cx,cy);
  if(lost!==2'd0)$fatal(1,"lost_stage should reset on relock, got %0d",lost);
  $display("PASS reacquire step3: relocked at 48,36 after %0d extra frame(s), radius restored",j);
  $display("** TB_TRACKER_REACQUIRE PASS **");$finish;
 end
 initial begin #80000000;$fatal(1,"timeout");end
endmodule
