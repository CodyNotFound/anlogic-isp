`timescale 1ns/1ps
module tb_video_in_atomic;
 reg cam=0,clk=0,rst=0,sof=0,valid=0,ready=0;
 reg [127:0] data=0;
 always #8.334 cam=~cam;always #7.5 clk=~clk;
 wire en,busy;wire [24:0]addr;wire[127:0]outdata;wire[1:0]rp;
 video_in dut(rst,cam,sof,valid,data,1'b0,clk,1'b0,1'b0,busy,rp,en,addr,outdata,ready);
 integer expected=0,accepted=0,epoch=0,n,cycles=0;
 always @(posedge clk)if(rst)begin
  cycles=cycles+1;
  if(dut.S_fifo_rst && dut.S_fifo_rd_en)$fatal(1,"pop during FIFO reset");
  if(en)begin
   if(!ready)$fatal(1,"unaccepted write pulse");
   if(outdata!==128'(epoch*1000+expected))$fatal(1,"word mismatch epoch=%0d beat=%0d got=%h",epoch,expected,outdata);
   // First explicit SOF selects buffer zero; the initial reset also starts there.
   if(addr!==25'(expected*8))$fatal(1,"address mismatch got=%0d",addr);
   expected=expected+1;accepted=accepted+1;
  end
 end
 task send_row;integer i;begin
  for(i=0;i<240;i=i+1)begin @(negedge cam);valid=1;data=epoch*1000+i;end
  @(negedge cam);valid=0;
 end endtask
 initial begin
  repeat(10)@(negedge clk);rst=1;repeat(20)@(negedge cam);
  send_row;
  // Stop precisely between FIFO prefetch and external acceptance.
  @(negedge clk);ready=1;
  wait(dut.write_pending);@(negedge clk);ready=0;
  repeat(17)@(negedge clk);
  if(accepted!=0||!dut.write_pending)$fatal(1,"pending word was lost");
  ready=1;
  while(accepted<240)begin @(negedge clk);ready=(cycles%7>=3);end
  @(negedge clk);ready=0;
  send_row; // An interrupted burst must not survive the frame boundary.
  ready=1;wait(dut.write_pending);@(negedge clk);ready=0;
  @(negedge cam);sof=1;@(negedge cam);sof=0;
  repeat(64)@(negedge cam);
  epoch=1;expected=0;ready=1;send_row;
  wait(expected==240);repeat(20)@(negedge clk);
  $display("PASS tb_video_in_atomic held pending data across stalls; reset cancelled interrupted burst");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
