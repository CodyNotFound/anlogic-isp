`timescale 1ns/1ps
module tb_controls_v59;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [3:0] sw=15,keys=15;wire [3:0] leds;wire h,v;
 vision_pipeline #(.ENABLE_OSD(0),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
 .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.rst_n(rst),.switches_n(sw),.buttons_n(keys),
 .video_vsync(1'b0),.video_hsync(1'b0),.video_de(1'b0),.video_sof(1'b0),.video_eol(1'b0),
 .debug_status(4'b0),.pixel_in(24'b0),.pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(),
 .pixel_out(),.frame_stat_y(),.frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(h),.servo_pwm_v(v),
 .panel_leds(leds),.panel_segments(),.panel_selects());
 defparam dut.u_gimbal.CLK_HZ=1000000;
 defparam dut.u_panel.CLK_HZ=1000000;
 defparam dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 defparam dut.u_button_router.DEBOUNCE_CYCLES=4;
 defparam dut.u_mode_ctrl.DEBOUNCE_CYCLES=4;
 task waitc;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
 initial begin
  waitc(5);rst=1;waitc(40);
  sw=14;waitc(40);if(leds!=1 || dut.feature_enable!=10)$fatal(1,"SW1 AB mapping");
  sw=13;waitc(40);if(leds!=2 || dut.feature_enable!=11)$fatal(1,"SW2 AE mapping");
  sw=11;waitc(40);if(leds!=4 || dut.feature_enable!=10 || dut.gimbal_auto_enable)$fatal(1,"SW3 auto mapping");
  force dut.u_mode_ctrl.mode=12;waitc(3);
  if(!dut.gimbal_auto_enable)$fatal(1,"TRACK must automatically enable gimbal");
  sw=15;waitc(40);if(dut.gimbal_auto_enable)$fatal(1,"SW3 OFF did not stop auto motion");
  release dut.u_mode_ctrl.mode;
  force dut.u_mode_ctrl.mode=0;waitc(3);release dut.u_mode_ctrl.mode;
  sw=7;waitc(40);keys=3;waitc(40);
  if(!dut.manual_mode || dut.mode!=0 || dut.demo_active || dut.task_action)$fatal(1,"manual key leak");
  waitc(20000);
  if(dut.pulse_h!=1504 || dut.pulse_v!=1504)$fatal(1,"manual K4/K3 motion %0d,%0d",dut.pulse_h,dut.pulse_v);
  sw=15;waitc(40);if(dut.mode!=0 || dut.demo_active)$fatal(1,"held-key exit leak");
  keys=15;waitc(40);keys=14;waitc(40);
  if(dut.mode!=1)$fatal(1,"normal K1 did not resume");
  keys=15;waitc(40);keys=11;waitc(40);if(dut.demo_active)$fatal(1,"K3 must not enter hidden ISP demo");
  $display("PASS tb_controls_v59: SW1 WB/SW2 AE/SW3 AUTO/SW4 manual, AB fixed on, motion gated independently of selection, Vim keys and release interlock");$finish;
 end
 initial begin #18000000;$fatal(1,"timeout");end
endmodule
