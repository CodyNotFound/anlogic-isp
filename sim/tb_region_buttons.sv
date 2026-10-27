`timescale 1ns/1ps
// Real K4 routing -> block sampler -> color flood fill -> servo PWM command.
module tb_region_buttons;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [3:0] sw=15,keys=15;reg de=0,sof=0,eol=0;reg [23:0] rgb=0;
 wire [3:0] leds;wire h,v;
 vision_pipeline #(.IMG_WIDTH(256),.IMG_HEIGHT(192),.ENABLE_OSD(0),
 .FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),.FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),
 .FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.rst_n(rst),.switches_n(sw),.buttons_n(keys),.video_vsync(sof),.video_hsync(eol),
 .video_de(de),.video_sof(sof),.video_eol(eol),.debug_status(4'b0),.pixel_in(rgb),
 .pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(),.pixel_out(),.frame_stat_y(),
 .frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(h),.servo_pwm_v(v),.panel_leds(leds),.panel_segments(),.panel_selects());
 defparam dut.u_gimbal.CLK_HZ=1000000;
 defparam dut.u_gimbal.HOLD_US=200000;
 defparam dut.u_panel.CLK_HZ=1000000;
 defparam dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 defparam dut.u_button_router.DEBOUNCE_CYCLES=4;
 defparam dut.u_mode_ctrl.DEBOUNCE_CYCLES=4;
 integer actions=0,picks=0,x,y,sx,sy,i,oldh,oldv;
 reg [23:0] color=24'h967d73;
 always @(posedge clk)begin
  if(dut.task_action)actions=actions+1;
  if(dut.u_tasks.rv && dut.u_tasks.rc)picks=picks+1;
 end
 task waitc;input integer n;begin repeat(n)@(negedge clk);end endtask
 task press;input integer k;begin keys[k]=0;waitc(24);keys[k]=1;waitc(24);end endtask
 task frame;input integer moved;
 begin
  for(y=0;y<192;y=y+1)begin
   for(x=0;x<256;x=x+1)begin
    sx=x/8;sy=y/8;
    rgb=(sx>=(moved?24:12)&&sx<(moved?32:20)&&sy>=(moved?16:8)&&sy<(moved?24:16))?color:24'he6e6e6;
    de=1;sof=x==0&&y==0;eol=x==255;@(negedge clk);
   end
   de=0;sof=0;eol=0;repeat(4)@(negedge clk);
  end
  waitc(60000);
 end endtask
 initial begin
  waitc(5);rst=1;waitc(40);
  press(1);if(dut.mode!=14)$fatal(1,"K2 must select REGION");
  press(2);if(dut.demo_active)$fatal(1,"K3 accidentally disabled analysis");
  press(3);if(actions!=1 || !dut.u_tasks.picking)$fatal(1,"K4 did not reach color sampler");
  frame(0);if(!dut.u_tasks.rc)$fatal(1,"low-chroma skin sample rejected");
  frame(0);if(!dut.u_tasks.rf || !dut.track_found)$fatal(1,"skin-colored target not found");
  sw=11;waitc(40);frame(1);waitc(20000);
  if(!dut.u_tasks.rf || dut.track_x<24 || dut.track_y<16)$fatal(1,"REGION position not exported");
  if(dut.pulse_h>=1500 || dut.pulse_v<=1500)$fatal(1,"REGION target did not move gimbal %0d,%0d",dut.pulse_h,dut.pulse_v);
  sw=15;waitc(40);oldh=dut.pulse_h;oldv=dut.pulse_v;waitc(250000);
  if(dut.pulse_h!=oldh||dut.pulse_v!=oldv||dut.u_gimbal.seen)$fatal(1,"AUTO OFF moved/home'd gimbal");
  color=24'h646464;press(3);frame(0);frame(0);
  if(!dut.u_tasks.rc || !dut.u_tasks.rf)$fatal(1,"gray clothing against white wall failed");
  sw=7;waitc(40);i=actions;press(3);
  if(actions!=i)$fatal(1,"manual left unexpectedly repicked");
  sw=15;waitc(40);press(3);if(actions!=i+1)$fatal(1,"K4 did not resume after manual exit");
  $display("PASS tb_region_buttons: actual K4, low-chroma/gray sample, REGION centroid to PWM, SW3 auto OFF holds, manual isolation");$finish;
 end
 initial begin #14000000;$fatal(1,"timeout");end
endmodule
