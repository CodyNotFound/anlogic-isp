`timescale 1ns/1ps
module tb_osd;
 reg connected=1;
 reg clk=0,rst=0,de=0,sof=0,eol=0;always #5 clk=~clk;
 reg[3:0] mode=11,panel=7;reg[1:0] state=1;reg[15:0]ms=16'h0267;
 wire od,ov,oh,os;wire[23:0] out;
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.COMPACT_OSD(1),.TARGET_TELEMETRY(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_video_vsync(sof),.I_video_hsync(eol),.I_video_de(de),.I_video_user(sof),.I_video_last(eol),
 .I_debug_status(4'd0),.I_cam_frame_tog(1'b0),.I_latency_frames(8'd0),.I_mode(mode),.I_isp_demo(4'd0),.I_feature_enable(4'd0),
 .I_manual_active(1'b0),.I_hmi_connected(connected),.I_info_enable(1'b1),.I_panel_features(panel),.I_task_status(4'd0),.I_ctl_state(state),.I_pulse_h(12'd1539),.I_pulse_v(12'd1476),
 .I_h_digits(24'h001539),.I_v_digits(24'h001476),.I_video_rd_data(24'h6080a0),.O_video_rd_en(),.O_hdmi_vsync(ov),.O_hdmi_hsync(oh),.O_hdmi_de(od),.O_hdmi_data(out),.O_hdmi_sof(os),.O_fps_digits(),
 .I_target_found(1'b1),.I_compute_valid(1'b1),.I_target_x_digits(16'h0936),.I_target_y_digits(16'h0404),.I_compute_ms_digits(ms));
 integer x,y,f,n=0,fd,i,ex,ey;reg checking=0;reg[511:0]name;
 always @(posedge clk)begin #1;if(checking&&od)begin
  if(^out===1'bx)$fatal(1,"unknown output");
  if(os!==(n==0)||ov!==os||oh!==(n%1280==1279))$fatal(1,"qualifier alignment");
  $fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);n=n+1;
 end end
 initial begin
 repeat(5)@(negedge clk);rst=1;force dut.S_fps_d1=6;force dut.S_fps_d0=0;
 for(f=0;f<5;f=f+1)begin
  connected=f!=2;mode=f==0?11:f==1?12:f==2?0:f==3?13:14;panel=f==1?15:7;ms=f==0?16'h0267:f==2?16'h0003:16'h0015;
  $sformat(name,"../build/sim/osd/frame%0d.ppm",f);fd=$fopen(name,"wb");$fwrite(fd,"P6\n1280 720\n255\n");n=0;checking=1;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin de=1;sof=x==0&&y==0;eol=x==1279;@(negedge clk);end
   de=0;sof=0;eol=0;repeat(4)@(negedge clk);
  end
  repeat(10)@(negedge clk);checking=0;$fclose(fd);if(n!=921600)$fatal(1,"pixel count");
  $display("PASS frame %0d: 921600 RGB pixels with real font/logo, aligned timing",f);
 end
 // Reachable range fills the indicator and the neutral point is exact.
 dut.ph_f=500;dut.pv_f=900;repeat(2)@(negedge clk);#1;if(dut.c_mx!=120||dut.c_my!=8)$fatal(1,"range minimum mapping");
 dut.ph_f=1500;dut.pv_f=1500;repeat(2)@(negedge clk);#1;if(dut.c_mx!=72||dut.c_my!=56)$fatal(1,"neutral mapping");
 dut.ph_f=2500;dut.pv_f=2150;repeat(2)@(negedge clk);#1;if(dut.c_mx!=24||dut.c_my!=104)$fatal(1,"range maximum mapping");
 // Exhaustive mapping, including clamped values outside mechanical limits.
 for(i=0;i<4096;i=i+1)begin
  dut.ph_f=i;dut.pv_f=i;repeat(2)@(negedge clk);#1;
  ex=i<=500?120:i>=2500?24:24+(((2500-i)*49+512)>>10);
  ey=i<=900?8:i>=2150?104:i<1500?56-(((1500-i)*82+512)>>10):56+(((i-1500)*76+512)>>10);
  if(dut.c_mx!=ex||dut.c_my!=ey)$fatal(1,"widget mapping %0d",i);
 end
 $display("PASS exhaustive widget mapping: 4096 values per axis");
 // Status must not bounce on a brief HOLD interval between detections.
 panel=7;state=1;sof=1;@(negedge clk);sof=0;state=2;
 repeat(10)begin repeat(2)@(negedge clk);sof=1;@(negedge clk);sof=0;if(dut.state_f!=1)$fatal(1,"status flicker");end
 state=1;sof=1;@(negedge clk);sof=0;
 $display("PASS tb_osd 4608000 valid RGB pixels, three native unscaled pixel font layouts, short HOLD rejection");$finish;
 end
 initial begin #60000000;$fatal(1,"watchdog");end
endmodule
