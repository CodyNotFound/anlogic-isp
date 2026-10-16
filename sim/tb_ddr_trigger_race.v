`timescale 1ns/1ps
module tb_ddr_trigger_race;
 reg clk=0,cam=0,pix=0,rst=0,ready=1;integer i,collisions=0,writes=0,reads=0;
 wire wb,rb,we,re;wire [24:0] wa,ra;wire [127:0] wd;
 always #7.5 clk=~clk;always #8.334 cam=~cam;always #6.6665 pix=~pix;
 video_in vi(.I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(1'b0),.I_camera_valid(1'b0),.I_camera_data(128'd0),.I_mipi_rx_error(1'b0),
 .I_ddr_clk(clk),.I_display_pause(1'b0),.I_video_out_rd_busy(rb),.O_video_in_wr_busy(wb),.O_video_out_rp(),
 .O_ddr_user_wr_en(we),.O_ddr_user_addr(wa),.O_ddr_user_wr_data(wd),.I_ddr_user_ready(ready));
 video_out vo(.I_rst_n(rst),.I_ddr_clk(clk),.O_video_out_rd_busy(rb),.I_video_in_wr_busy(wb),.I_video_out_rp(2'd0),
 .O_ddr_user_rd_en(re),.O_ddr_user_addr(ra),.I_ddr_user_ready(ready),.I_ddr_user_rd_valid(1'b0),.I_ddr_user_rd_data(128'd0),
 .I_dsi_clk(pix),.I_video_vsync(1'b0),.I_video_rd_en(1'b0),.O_vdieo_data());
 always @(posedge clk)if(rst)begin
  if(we)writes=writes+1;if(re)reads=reads+1;if(we&&re)collisions=collisions+1;
 end
 initial begin
  force vi.S_fifo_rd_num=240;force vo.reserved_read_words=0;
  repeat(10)@(negedge clk);rst=1;repeat(40)@(negedge clk);
  for(i=0;i<20000;i=i+1)begin
   @(negedge clk);ready=(i%17)>2;
   if((i%1100)<550)force vo.reserved_read_words=0;else force vo.reserved_read_words=1000;
   if((i%701)<350)force vi.S_fifo_rd_num=240;else force vi.S_fifo_rd_num=239;
  end
  $display("ACTUAL V27 INTERLOCK writes=%0d reads=%0d overlap=%0d",writes,reads,collisions);
  if(writes==0||reads==0||collisions!=0)$fatal(1,"interlock counterexample");
  $display("PASS tb_ddr_trigger_race actual combinational read-busy lookahead");$finish;
 end
endmodule
