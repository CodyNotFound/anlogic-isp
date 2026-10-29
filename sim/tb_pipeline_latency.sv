`timescale 1ns/1ps
module tb_pipeline_latency;
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
 reg[3:0]test_mode;integer k,expected;reg[15:0]bcd;
 initial begin
  waitc(5);rst=1;waitc(40);force dut.u_mode_ctrl.mode=test_mode;
  for(k=0;k<11;k=k+1)begin
   test_mode=k;clocks(100);srcsof=1;srcde=1;clocks(1);srcsof=0;srcde=0;clocks(1000);
   expected=(dut.latency_cycles*2+7)/15;
   bcd=((expected/1000)%10)*4096+((expected/100)%10)*256+((expected/10)%10)*16+expected%10;
   if(!dut.latency_seen||dut.latency_cycles<5||!dut.telemetry_compute_valid||dut.compute_ms_digits!==bcd)$fatal(1,"ordinary mode %0d seen%0d cycles%0d valid%0d digits%x expected%x",k,dut.latency_seen,dut.latency_cycles,dut.telemetry_compute_valid,dut.compute_ms_digits,bcd);
  end
  release dut.u_mode_ctrl.mode;
  $display("PASS tb_pipeline_latency: modes0..10 measured application SOF latency and decimal-ms formatting");$finish;
 end

 initial begin #30000000;$fatal(1,"timeout");end
endmodule
