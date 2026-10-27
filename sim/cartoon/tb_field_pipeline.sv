`timescale 1ns/1ps
module tb_field_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,sof=0,eol=0;wire od;wire [23:0] out;
 vision_pipeline #(.IMG_WIDTH(320),.IMG_HEIGHT(240),.ENABLE_OSD(0),
 .FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),.FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.rst_n(rst),.switches_n(4'b1110),.buttons_n(4'b1111),.video_vsync(sof),.video_hsync(eol),.video_de(de),.video_sof(sof),.video_eol(eol),
 .debug_status(4'd0),.pixel_in(24'h080808),.pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(od),.pixel_out(out),
 .frame_stat_y(),.frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(),.servo_pwm_v(),.panel_leds(),.panel_segments(),.panel_selects());
 defparam dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 integer f,x,y,n=0,total=0;reg checking=0;reg [23:0] want;
 always @(posedge clk)begin #1;if(checking && od)begin
  want=f==0?24'h0b0b0b:24'hf4f4f4;
  if(out!==want)$fatal(1,"AB inverse overshoot frame%0d pixel%0d got%h expected%h",f,n,out,want);
  if(dut.u_adaptive_brightness.gain_q8!=368)$fatal(1,"effect changed camera brightness statistics");
  n=n+1;total=total+1;
 end end
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(300)@(negedge clk);
  dut.u_adaptive_brightness.gain_q8=368;
  for(f=0;f<3;f=f+1)begin
   if(f==0)force dut.u_mode_ctrl.mode=0;else force dut.u_mode_ctrl.mode=2;
   repeat(10)@(negedge clk);n=0;checking=1;
   for(y=0;y<240;y=y+1)begin
    for(x=0;x<320;x=x+1)begin @(negedge clk);de=1;sof=x==0&&y==0;eol=x==319;end
    @(negedge clk);de=0;sof=0;eol=0;repeat(8)@(negedge clk);
   end
   repeat(30)@(negedge clk);checking=0;
   if(n!=76800)$fatal(1,"frame count %0d",n);
  end
  $display("PASS tb_field_pipeline: 230400 RGB pixels, dark AB gain retained across inverse switch, no inherited clipping or effect-statistics feedback");$finish;
 end
 initial begin #6000000;$fatal(1,"AB watchdog");end
endmodule
