`timescale 1ns/1ps
// Closed-loop frame-buffer test: ISP-like camera stream -> video_in -> command
// FIFO -> deterministic DDR model -> video_out -> HDMI-like pixel requests.
module tb_frame_loop_abcd #(parameter STALL_MC=0);
 reg cam_clk=0,ddr_clk=0,pix_clk=0,rst_n=0;
 always #4 cam_clk=~cam_clk;      // 125? shortened model clock; ratios remain independent
 always #3 ddr_clk=~ddr_clk;
 always #2.5 pix_clk=~pix_clk;
 reg mc_rd_valid;reg [127:0] mc_rd_data;
 reg cam_sof=0,cam_valid=0;reg [127:0] cam_data=0;
 reg display_vsync=0,display_de=0;
 wire vi_busy,vo_busy;wire [1:0] rp;
 wire vi_wr_en,vo_rd_en;wire [24:0] vi_addr,vo_addr;wire [127:0] vi_data;
 wire write_ready,read_ready;
 wire user_ready,rd_valid;wire [127:0] rd_data;
 wire [23:0] pixel;
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
 function [23:0] pat_pixel;input integer x;integer g;begin
  g=(x%1280)/160;case(g)
   0:pat_pixel=24'hff2020;1:pat_pixel=24'h20ff20;2:pat_pixel=24'h2020ff;3:pat_pixel=24'hffff20;
   4:pat_pixel=24'ha020ff;5:pat_pixel=24'h20ffff;6:pat_pixel=24'hff20a0;default:pat_pixel=24'hffffff;
  endcase
 end endfunction
 function [127:0] pat_word;input integer wi;integer b,bi,p;reg [23:0] rgb;begin
  pat_word=0;for(b=0;b<16;b=b+1)begin bi=wi*16+b;p=bi/3;rgb=pat_pixel(p);
   case(bi%3)0:pat_word[127-b*8-:8]=rgb[23:16];1:pat_word[127-b*8-:8]=rgb[15:8];default:pat_word[127-b*8-:8]=rgb[7:0];endcase end
 end endfunction
 integer cam_frame,cam_word;
 task send_camera_frame;begin
  @(negedge cam_clk);cam_valid=0;cam_sof=1;
  repeat(2)@(negedge cam_clk);cam_sof=0;repeat(20)@(negedge cam_clk);
  for(cam_word=0;cam_word<172800;cam_word=cam_word+1)begin
   while(u_vi.U_w128_d512_fifo.wrusedw>380)@(negedge cam_clk);
   @(negedge cam_clk);cam_valid=1;cam_data=pat_word(cam_word);
   @(negedge cam_clk);cam_valid=0;
  end
  while(u_vi.U_w128_d512_fifo.wrusedw!=0)@(negedge cam_clk);
  repeat(100)@(negedge cam_clk);cam_data=0;
 end endtask
 integer display_frame,source_x,source_y,out_x,out_y,checked;
 integer mismatches[0:15],counts[0:15],first_bad_x[0:15],first_bad_y[0:15];
 reg [23:0] ref1,ref2;reg rv1,rv2;reg [23:0] pipe1;
 always @(posedge pix_clk)begin
  #1;if(!rst_n)begin rv1=0;rv2=0;source_x=0;source_y=0;out_x=0;out_y=0;checked=0;end
  else begin
   rv2=rv1;ref2=ref1;rv1=display_de;ref1=pat_pixel(source_x);
   if(display_de)begin source_x=source_x+1;if(source_x==1280)begin source_x=0;source_y=source_y+1;end end
   if(rv2)begin
    if(pixel!==ref2)begin mismatches[display_frame]=mismatches[display_frame]+1;if(mismatches[display_frame]<=8)$display("BAD frame=%0d src_xy=%0d,%0d out=%h exp=%h",display_frame,source_x,source_y,pixel,ref2);
     if(first_bad_x[display_frame]<0)begin first_bad_x[display_frame]=source_x-3;first_bad_y[display_frame]=source_y;end
    end
    counts[display_frame]=counts[display_frame]+1;checked=checked+1;
    out_x=out_x+1;if(out_x==1280)begin out_x=0;out_y=out_y+1;end
   end
  end
 end
 task pulse_display_vsync;begin @(negedge pix_clk);display_vsync=1;repeat(12)@(negedge pix_clk);display_vsync=0;repeat(800)@(negedge pix_clk);end endtask
 task display_one_frame;integer x,y;begin
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin @(negedge pix_clk);display_de=1;end
   @(negedge pix_clk);display_de=0;repeat(30)@(negedge pix_clk);
  end
  repeat(300)@(negedge pix_clk);
 end endtask
 initial begin
  for(i=0;i<16;i=i+1)begin mismatches[i]=0;counts[i]=0;first_bad_x[i]=-1;first_bad_y[i]=-1;end
  repeat(10)@(negedge ddr_clk);rst_n=1;
  fork
   begin for(cam_frame=0;cam_frame<8;cam_frame=cam_frame+1)send_camera_frame; end
   begin for(display_frame=0;display_frame<3;display_frame=display_frame+1)begin mismatches[display_frame]=0;counts[display_frame]=0;first_bad_x[display_frame]=-1;first_bad_y[display_frame]=-1;pulse_display_vsync;display_one_frame;end end
  join
  for(i=0;i<3;i=i+1)$display("FRAME %0d count=%0d mismatch=%0d first_xy=%0d,%0d",i,counts[i],mismatches[i],first_bad_x[i],first_bad_y[i]);
  if(counts[2]!=921600)$fatal(1,"display count mismatch");
  if(mismatches[2]!=0)$fatal(1,"closed-loop AB/CD order failed");
  $display("PASS tb_frame_loop_abcd full 1280x720 closed-loop order");$finish;
 end
 initial begin #60000000;$fatal(1,"timeout");end
endmodule

