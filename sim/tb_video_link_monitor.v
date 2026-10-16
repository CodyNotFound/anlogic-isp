`timescale 1ns/1ps
module tb_video_link_monitor;
 reg c=0,d=0,p=0,r=0,hs=0,sof=0,iv=0,overflow=0,wr=0,req=0,rv=0,underflow=0;
 reg [15:0] hd=0;reg [127:0] id=0,rd=0;wire [3:0] status;
 integer f,i;reg [191:0] sample;
 always #8.334 c=~c;always #7.5 d=~d;always #6.6665 p=~p;
 video_link_monitor #(.FRAME_WORDS(4),.PAYLOAD_BYTES(24)) dut(.rst_n(r),.cam_clk(c),.ddr_clk(d),.pix_clk(p),
 .hs_valid(hs),.hs_data(hd),.lane_error(1'b0),.isp_sof(sof),.isp_valid(iv),.isp_data(id),
 .fifo_overflow(overflow),.wr_en(wr),.wr_addr(25'd0),.rd_req(req),.rd_addr(25'd0),
 .rd_valid(rv),.rd_data(rd),.fifo_underflow(underflow),.status(status));
 function [127:0] word;input integer j;begin word={32'h12340000+j,32'haabbccdd-j,32'h12345678+j,32'hffffff00-j};end endfunction
 task settle;begin repeat(12)@(negedge p);end endtask
 task packet;input [191:0] data;input [15:0] footer;input corrupt;integer j;reg [15:0] pair;begin
  @(negedge c);hs=1;hd=16'h2b18;@(negedge c);hd=0;
  for(j=0;j<12;j=j+1)begin
   @(negedge c);pair=data[191-j*16-:16];hd=(corrupt&&j==5)?(pair^16'h0001):pair;
  end
  @(negedge c);hd=footer;@(negedge c);hs=0;hd=0;settle;
 end endtask
 task read_frame;input corrupt;integer j;begin
  @(negedge d);req=1;@(negedge d);req=0;repeat(4)@(negedge d);
  for(j=0;j<4;j=j+1)begin @(negedge d);rv=1;rd=word(j);if(corrupt&&j==2)rd=rd^128'd1;end
  @(negedge d);rv=0;settle;
 end endtask
 initial begin
  repeat(10)@(negedge c);r=1;
  for(f=0;f<5;f=f+1)begin
   @(negedge c);sof=1;@(negedge c);sof=0;
   for(i=0;i<4;i=i+1)begin @(negedge c);iv=1;id=word(i);end
   @(negedge c);iv=0;
   for(i=0;i<4;i=i+1)begin @(negedge d);wr=1;end
   @(negedge d);wr=0;settle;
  end
  // Two published CSI-2 specification vectors; CRC bytes are constants,
  // independent of the RTL's CRC implementation (CSI-2 v3.0 section 9.6).
  packet(192'hff000002b9dcf372bbd4b85ac875c27c81f805dfff000001,16'hf000,0);
  packet(192'hff0000001ef01ec74f8278c582e08c70d23c78e9ff000001,16'h69e5,0);
  read_frame(0);if(status!==0)$fatal(1,"false error on good stream: %b",status);
  read_frame(1);if(status!==8)$fatal(1,"DDR bit error not detected: %b",status);
  @(negedge c);overflow=1;@(negedge c);overflow=0;settle;
  if(status!==10)$fatal(1,"write FIFO overflow not detected: %b",status);
  @(negedge p);underflow=1;@(negedge p);underflow=0;settle;
  if(status!==14)$fatal(1,"read underflow not detected: %b",status);
  packet(192'hff000002b9dcf372bbd4b85ac875c27c81f805dfff000001,16'hf000,1);
  if(status!==15)$fatal(1,"CSI payload bit error not detected: %b",status);
  $display("PASS tb_video_link_monitor official CRC vectors, clean stream, four fault flags");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
