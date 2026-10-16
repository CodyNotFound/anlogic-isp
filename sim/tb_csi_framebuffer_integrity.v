`timescale 1ns/1ps
// Closed-loop frame-buffer test: ISP-like camera stream -> video_in -> command
// FIFO -> deterministic DDR model -> video_out -> HDMI-like pixel requests.
module tb_csi_framebuffer_integrity #(parameter STALL_MC=1);
 reg ddr_clk=0,pix_clk=0,rst_n=0;
 tb_csi_isp_frame_integrity #(.STOP_CLOCK(1),.USE_BRIDGE(1),.FINISH(0)) source();
 wire cam_clk=source.isp_clk;

 always #7.5 ddr_clk=~ddr_clk;
 always #6.734 pix_clk=~pix_clk;
 reg mc_rd_valid;reg [127:0] mc_rd_data;
  wire cam_sof,cam_valid;wire [127:0] cam_data;
 wire camera_done=source.source_done;
 assign cam_sof=source.ou;assign cam_valid=source.ov;assign cam_data=source.od;
 reg display_vsync=0,display_de=0;
 wire vi_busy,vo_busy;wire [1:0] rp;
 wire vi_wr_en,vo_rd_en;wire [24:0] vi_addr,vo_addr;wire [127:0] vi_data;
 wire write_ready,read_ready;
 wire user_ready,rd_valid;wire [127:0] rd_data;
 wire [23:0] pixel;
 integer write_words=0,wb,wp,wf;reg[127:0]write_expected;reg[23:0]write_rgb;reg[7:0]write_byte;
 always @(posedge ddr_clk)if(rst_n&&vi_wr_en)begin
  wf=write_words/1440;
  for(wb=0;wb<16;wb=wb+1)begin
   wp=((write_words%1440)*16+wb)/3;write_rgb=source.golden[wp];
   case(((write_words%1440)*16+wb)%3)
    0:write_byte=write_rgb[23:16]+wf*2;
    1:write_byte=write_rgb[15:8]+wf*2;
    2:write_byte=write_rgb[7:0]+wf*2;
   endcase
   write_expected[127-wb*8-:8]=write_byte;
  end
  if(vi_data!==write_expected||vi_addr!==25'((wf%4)*7000000+(write_words%1440)*8))
   $fatal(1,"write data/address mismatch frame=%0d word=%0d addr=%0d",wf,write_words%1440,vi_addr);
  write_words=write_words+1;
 end
 video_in u_vi(.I_rst_n(rst_n),.I_camera_clk(cam_clk),.I_camera_frame_start(cam_sof),
  .I_camera_valid(cam_valid),.I_camera_data(cam_data),.I_mipi_rx_error(1'b0),
  .I_ddr_clk(ddr_clk),.I_display_pause(1'b0),.I_video_out_rd_busy(vo_busy),
  .O_video_in_wr_busy(vi_busy),.O_video_out_rp(rp),.O_ddr_user_wr_en(vi_wr_en),
  .O_ddr_user_addr(vi_addr),.O_ddr_user_wr_data(vi_data),.I_ddr_user_ready(write_ready));
 video_out u_vo(.I_rst_n(rst_n),.I_ddr_clk(ddr_clk),.O_video_out_rd_busy(vo_busy),
  .I_video_in_wr_busy(vi_busy),.I_video_out_rp(rp),.O_ddr_user_rd_en(vo_rd_en),
  .O_ddr_user_addr(vo_addr),.I_ddr_user_ready(read_ready),.I_ddr_user_rd_valid(rd_valid),
  .I_ddr_user_rd_data(rd_data),.I_dsi_clk(pix_clk),.I_video_vsync(display_vsync),
  .I_video_rd_en(display_de),.O_vdieo_data(pixel));
 wire app_en;wire [24:0] app_addr;wire [2:0] app_cmd;wire app_wr;wire [127:0] app_wrdata;
 wire user_wr_en,user_rd_en;
 wire [24:0] user_addr;
 ddr_user_arbiter arb(.I_fifo_ready(user_ready),.I_wr_en(vi_wr_en),.I_wr_addr(vi_addr),.I_wr_data(vi_data),
 .I_rd_en(vo_rd_en),.I_rd_addr(vo_addr),.O_wr_ready(write_ready),.O_rd_ready(read_ready),
 .O_user_wr_en(user_wr_en),.O_user_rd_en(user_rd_en),.O_user_addr(user_addr),.O_user_wr_data());
 integer ddr_cycle=0;
 wire app_ready = !STALL_MC || ((ddr_cycle%13)!=0 && (ddr_cycle%13)!=1 && (ddr_cycle%13)!=2);
 mc_to_user_interface u_mc(.I_clk(ddr_clk),.I_rst_n(rst_n),.I_ddr_user_wr_en(user_wr_en),
  .I_ddr_user_rd_en(user_rd_en),.I_ddr_user_addr(user_addr),.I_ddr_user_wr_data(vi_data),
  .O_ddr_user_ready(user_ready),.O_ddr_user_rd_valid(rd_valid),.O_ddr_user_rd_data(rd_data),
  .O_mc_app_en(app_en),.O_mc_app_addr(app_addr),.O_mc_app_cmd(app_cmd),.I_mc_app_rdy(app_ready),
  .O_mc_app_wdf_wren(app_wr),.O_mc_app_wdf_data(app_wrdata),.O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),
  .I_mc_app_wdf_rdy(app_ready),.I_mc_app_rd_data_valid(mc_rd_valid),.I_mc_app_rd_data(mc_rd_data),.I_mc_app_rd_data_end(1'b0));

 reg [127:0] mem0[0:172799],mem1[0:172799],mem2[0:172799],mem3[0:172799];
 reg [127:0] due_data[0:127];reg [31:0] due_cycle[0:127];integer qh=0,qt=0,qcount=0,i;
 task write_mem;input [24:0] a;input [127:0] d;begin
  if(a<25'd7000000)mem0[a>>3]<=d;else if(a<25'd14000000)mem1[(a-25'd7000000)>>3]<=d;
  else if(a<25'd21000000)mem2[(a-25'd14000000)>>3]<=d;else mem3[(a-25'd21000000)>>3]<=d;
 end endtask
 function [127:0] read_mem;input [24:0] a;begin
  if(a<25'd7000000)read_mem=mem0[a>>3];else if(a<25'd14000000)read_mem=mem1[(a-25'd7000000)>>3];
  else if(a<25'd21000000)read_mem=mem2[(a-25'd14000000)>>3];else read_mem=mem3[(a-25'd21000000)>>3];
 end endfunction
 always @(posedge ddr_clk)begin
  if(!rst_n)begin qh=0;qt=0;qcount=0;ddr_cycle=0;end else begin
   ddr_cycle<=ddr_cycle+1;
   if(app_en && app_ready)begin
    if(app_wr)write_mem(app_addr,app_wrdata);
    else begin due_data[qt]<=read_mem(app_addr);due_cycle[qt]<=ddr_cycle+40;qt<=(qt+1)%128;qcount<=qcount+1;end
   end
  end
 end

 always @(negedge ddr_clk)begin mc_rd_valid=0;
  if(rst_n&&qcount>0&&due_cycle[qh]<=ddr_cycle)begin mc_rd_valid=1;mc_rd_data=due_data[qh];qh=(qh+1)%128;qcount=qcount-1;end
 end
 // The real interface consumes MC response directly in this closed-loop model.
 assign rd_valid=mc_rd_valid;assign rd_data=mc_rd_data;
 function [23:0] pat_pixel;input integer p;reg[23:0] v;begin
 v=source.golden[p%7680];
 // Eight source SOFs publish source frame five, two buffers behind the writer.
 pat_pixel={8'(v[23:16]+10),8'(v[15:8]+10),8'(v[7:0]+10)};
 end endfunction
 integer display_frame,source_x,source_y,out_x,out_y,checked;
 integer mismatches[0:15],counts[0:15],first_bad_x[0:15],first_bad_y[0:15];
 reg [23:0] ref1,ref2;reg rv1,rv2;reg [23:0] pipe1;
 always @(posedge pix_clk)begin
  #1;if(!rst_n)begin rv1=0;rv2=0;source_x=0;source_y=0;out_x=0;out_y=0;checked=0;end
  else begin
   rv2=rv1;ref2=ref1;rv1=display_de;ref1=pat_pixel(source_y*1280+source_x);
   if(display_de)begin source_x=source_x+1;if(source_x==1280)begin source_x=0;source_y=source_y+1;end end
   if(rv2)begin
    if(display_frame==8&&pixel!==ref2)begin mismatches[display_frame]=mismatches[display_frame]+1;if(mismatches[display_frame]<=8)$display("BAD frame=%0d src_xy=%0d,%0d out=%h exp=%h",display_frame,source_x,source_y,pixel,ref2);
     if(first_bad_x[display_frame]<0)begin first_bad_x[display_frame]=source_x-3;first_bad_y[display_frame]=source_y;end
    end
    counts[display_frame]=counts[display_frame]+1;checked=checked+1;
    out_x=out_x+1;if(out_x==1280)begin out_x=0;out_y=out_y+1;end
   end
  end
 end
 task pulse_display_vsync;begin @(negedge pix_clk);display_vsync=1;repeat(12)@(negedge pix_clk);display_vsync=0;repeat(800)@(negedge pix_clk);end endtask
 task display_one_frame;integer x,y;begin
  for(y=0;y<6;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin @(negedge pix_clk);display_de=1;end
   @(negedge pix_clk);display_de=0;repeat(370)@(negedge pix_clk);
  end
  repeat(300)@(negedge pix_clk);
 end endtask
 initial begin
  for(i=0;i<16;i=i+1)begin mismatches[i]=0;counts[i]=0;first_bad_x[i]=-1;first_bad_y[i]=-1;end
  repeat(10)@(negedge ddr_clk);rst_n=1;
  fork

   begin
    for(display_frame=0;display_frame<8;display_frame=display_frame+1)begin pulse_display_vsync;display_one_frame;end
    wait(camera_done);source_x=0;source_y=0;rv1=0;rv2=0;
    pulse_display_vsync;display_one_frame;
   end
  join
  $display("FINAL FRAME count=%0d mismatch=%0d accepted writes=%0d",counts[8],mismatches[8],write_words);
  if(counts[8]!=7680||write_words!=11520)$fatal(1,"display/write count mismatch");
  if(mismatches[8]!=0)$fatal(1,"closed-loop AB/CD order failed");
  $display("PASS tb_csi_framebuffer_integrity stopped RX clock -> continuous ISP -> DDR -> display pixels=7680 varying frame identity, MC stalls");$finish;
 end
 initial begin #60000000;$fatal(1,"timeout");end
endmodule


