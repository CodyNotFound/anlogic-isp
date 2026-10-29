`timescale 1ns/1ps
module tb_local_controls;
 reg clk=0,rst=0,core_clk=0;always #6.667 clk=~clk;always #3.333 core_clk=~core_clk;
 reg srcsof=0,srcde=0;reg rx=1;
 reg [3:0] sw=15,keys=15;wire [3:0] leds;wire h,v;
 vision_pipeline #(.ENABLE_OSD(0),.ENABLE_PIPELINE(1),.ENABLE_HMI(0),.FACE_CNN_ENABLE(1),.FACE_CORE_CLK_X2(1),.FACE_MOTION_ENABLE(0),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
 .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.cnn_core_clk(core_clk),.rst_n(rst),.switches_n(sw),.buttons_n(keys),
 .video_vsync(1'b0),.video_hsync(1'b0),.video_de(srcde),.video_sof(srcsof),.video_eol(1'b0),
 .debug_status(4'b0),.pixel_in(24'b0),.pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(),
 .pixel_out(),.frame_stat_y(),.frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(h),.servo_pwm_v(v),
 .hmi_rx(rx),.hmi_tx(),.panel_leds(leds),.panel_segments(),.panel_selects());
 defparam dut.u_hdmi_mixer.u_osd_font_bram.FONT_FILE="sim/osd_font_rom.hex";
 defparam dut.u_gimbal.CLK_HZ=1000000;
 defparam dut.u_panel.CLK_HZ=1000000;
 defparam dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 defparam dut.u_button_router.DEBOUNCE_CYCLES=4;
 defparam dut.u_mode_ctrl.DEBOUNCE_CYCLES=4;
 defparam dut.cnn_mode.u_cnn.PROGRAM_FILE="rtl/analytics/face_cnn/program.hex";
 defparam dut.cnn_mode.u_cnn.W0_FILE="rtl/analytics/face_cnn/weights0.hex";
 defparam dut.cnn_mode.u_cnn.W1_FILE="rtl/analytics/face_cnn/weights1.hex";
 defparam dut.cnn_mode.u_cnn.W2_FILE="rtl/analytics/face_cnn/weights2.hex";
 defparam dut.cnn_mode.u_cnn.W3_FILE="rtl/analytics/face_cnn/weights3.hex";
 defparam dut.cnn_mode.u_cnn.BIAS_FILE="rtl/analytics/face_cnn/bias.hex";
 defparam dut.cnn_mode.u_cnn.SHIFT_FILE="rtl/analytics/face_cnn/shift.hex";
 defparam dut.cnn_mode.u_cnn.SIGMOID_FILE="rtl/analytics/face_cnn/sigmoid.hex";
 defparam dut.cnn_mode.u_cnn.OFFSET_FILE="rtl/analytics/face_cnn/offset.hex";
 defparam dut.cnn_mode.u_cnn.SIZE_FILE="rtl/analytics/face_cnn/size.hex";
 task waitc;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask

 integer start_h,start_v,dh0,dv0;
 task direction(input [3:0] mask,input integer dh,input integer dv);begin
  keys=(~mask)&15;waitc(40);start_h=dut.pulse_h;start_v=dut.pulse_v;
  clocks(20000);keys=15;waitc(40);
  if((dh>0&&dut.pulse_h<=start_h)||(dh<0&&dut.pulse_h>=start_h)||
     (dv>0&&dut.pulse_v<=start_v)||(dv<0&&dut.pulse_v>=start_v))$fatal(1,"local direction %x",mask);
  if((dh==0&&dut.pulse_h!=start_h)||(dv==0&&dut.pulse_v!=start_v))$fatal(1,"uncommanded axis moved");
  if(dut.pulse_h<500||dut.pulse_h>2500||dut.pulse_v<900||dut.pulse_v>2150)$fatal(1,"mechanical limits");
 end endtask
 initial begin
  waitc(5);rst=1;waitc(40);
  if(dut.hmi_connected||dut.hmi_keys!=0)$fatal(1,"HMI must be disabled");
  sw=7;waitc(40);if(!dut.manual_mode)$fatal(1,"SW4 direction mapping");
  direction(8,1,0);direction(4,0,1);direction(2,0,-1);direction(1,-1,0);
  sw=3;waitc(40);
  force dut.gimbal_auto_enable=1'b1;force dut.track_found=1'b1;
  force dut.track_x=8'd0;force dut.track_y=8'd89;force dut.track_valid=1'b0;
  waitc(2);force dut.track_valid=1'b1;waitc(2);force dut.track_valid=1'b0;
  start_h=dut.pulse_h;start_v=dut.pulse_v;clocks(40000);
  if(!dut.manual_mode||dut.manual_motion||dut.pulse_h<=start_h||dut.pulse_v<=start_v)$fatal(1,"idle direction mapping blocked auto");
  keys=14;waitc(40);start_h=dut.pulse_h;clocks(20000);
  if(!dut.manual_motion||dut.pulse_h>=start_h)$fatal(1,"local key failed to override auto");
  keys=15;waitc(40);force dut.track_valid=1'b1;waitc(2);force dut.track_valid=1'b0;
  start_h=dut.pulse_h;clocks(40000);if(dut.pulse_h<=start_h)$fatal(1,"auto did not resume");
  release dut.gimbal_auto_enable;release dut.track_found;release dut.track_x;release dut.track_y;release dut.track_valid;
  sw=15;waitc(40);if(dut.manual_mode)$fatal(1,"manual mapping did not release");
  keys=14;waitc(40);keys=15;waitc(40);if(dut.mode!=1)$fatal(1,"local mode advance");
  $display("PASS tb_local_controls: production CNN150/no-HMI selection, four local directions, mechanical limits, SW4 idle/auto coexistence, manual priority and auto resume");$finish;
 end
 initial begin #30000000;$fatal(1,"local controls watchdog");end
endmodule
