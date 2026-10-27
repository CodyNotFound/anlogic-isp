`timescale 1ns/1ps
module tb_hmi_pipeline_v72;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg srcsof=0,srcde=0;reg rx=1;
 reg [3:0] sw=15,keys=15;wire [3:0] leds;wire h,v;
 vision_pipeline #(.ENABLE_OSD(0),.ENABLE_PIPELINE(0),.ENABLE_HMI(1),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
 .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.rst_n(rst),.switches_n(sw),.buttons_n(keys),
 .video_vsync(1'b0),.video_hsync(1'b0),.video_de(srcde),.video_sof(srcsof),.video_eol(1'b0),
 .debug_status(4'b0),.pixel_in(24'b0),.pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(),
 .pixel_out(),.frame_stat_y(),.frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(h),.servo_pwm_v(v),
 .hmi_rx(rx),.hmi_tx(),.panel_leds(leds),.panel_segments(),.panel_selects());
 defparam dut.u_hdmi_mixer.u_osd_font_bram.FONT_FILE="sim/osd_font_rom.hex";
 defparam dut.g_hmi.u_link.CLK_HZ=1000000;
 defparam dut.g_hmi.u_link.BAUD=100000;
 defparam dut.u_gimbal.CLK_HZ=1000000;
 defparam dut.u_panel.CLK_HZ=1000000;
 defparam dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 defparam dut.u_button_router.DEBOUNCE_CYCLES=4;
 defparam dut.u_mode_ctrl.DEBOUNCE_CYCLES=4;
 task waitc;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task send(input[7:0]b);integer j;begin rx=0;clocks(10);for(j=0;j<8;j=j+1)begin rx=b[j];clocks(10);end rx=1;clocks(10);end endtask
 task command(input[7:0]o,a);begin send(8'ha5);send(8'h5a);send(o);send(a);send(8'hff^o^a);send(8'h0d);clocks(5);end endtask
 integer start_h,start_v,nh=0,nv=0,wh=0,wv=0;reg ph=0,pv=0;
 always @(posedge clk)begin #2;
  if(!rst)begin ph=0;pv=0;nh=0;nv=0;end else begin
   if(h&&!ph)begin nh=1;wh=dut.pulse_h;end else if(h)nh=nh+1;
   if(v&&!pv)begin nv=1;wv=dut.pulse_v;end else if(v)nv=nv+1;
   if(!h&&ph&&nh!=wh)$fatal(1,"horizontal PWM width %0d != %0d",nh,wh);
   if(!v&&pv&&nv!=wv)$fatal(1,"vertical PWM width %0d != %0d",nv,wv);
   ph=h;pv=v;
  end
 end
 task direction(input[3:0]mask,input integer dh,dv);begin
  command(8'h16,mask);start_h=dut.pulse_h;start_v=dut.pulse_v;
  clocks(20000);command(8'h16,0);
  if(dut.pulse_h!=start_h+dh||dut.pulse_v!=start_v+dv)$fatal(1,"direction %x actual pulse %0d,%0d start %0d,%0d",mask,dut.pulse_h,dut.pulse_v,start_h,start_v);
 end endtask
 initial begin
  waitc(5);rst=1;waitc(40);
  command(8'h02,0);if(dut.manual_mode||!dut.hmi_connected)$fatal(1,"connect forced manual");
  command(8'h14,1);if(!dut.manual_mode||!leds[3])$fatal(1,"manual did not reach pipeline");
  direction(8,4,0);direction(1,-4,0);direction(4,0,4);direction(2,0,-4);
  command(8'h14,0);if(dut.manual_mode)$fatal(1,"screen manual off");
  start_h=dut.pulse_h;start_v=dut.pulse_v;command(8'h16,8);clocks(20000);
  if(dut.pulse_h!=start_h||dut.pulse_v!=start_v)$fatal(1,"motion outside manual");
  sw=7;waitc(40);if(!dut.manual_mode)$fatal(1,"physical edge manual");
  command(8'h14,0);if(dut.manual_mode)$fatal(1,"physical SW4 prevented remote exit");
  command(8'h14,1);command(8'h16,8);clocks(260000);if(dut.hmi_keys!=0)$fatal(1,"release lease");
  command(8'h14,0);clocks(1001000);
  if(!dut.hmi_connected||dut.manual_mode||dut.hmi_keys!=0)$fatal(1,"idle lost screen state");
  sw=15;waitc(40);sw=7;waitc(40);if(dut.hmi_connected||!dut.manual_mode)$fatal(1,"local switch takeover");
  start_v=dut.pulse_v;keys=11;waitc(40);clocks(20000);keys=15;waitc(40);
  if(dut.pulse_v!=start_v+4)$fatal(1,"local direction after disconnect");
  // SW4 selects direction keys, but must not inhibit automatic results at idle.
  keys=15;sw=3;waitc(40);
  force dut.gimbal_auto_enable=1'b1;force dut.track_found=1'b1;
  force dut.track_x=8'd0;force dut.track_y=8'd89;force dut.track_valid=1'b0;
  waitc(2);force dut.track_valid=1'b1;waitc(2);force dut.track_valid=1'b0;
  start_h=dut.pulse_h;start_v=dut.pulse_v;clocks(40000);
  if(!dut.manual_mode||dut.manual_motion||dut.pulse_h<=start_h||dut.pulse_v<=start_v)$fatal(1,"SW4 idle blocked automatic tracking");
  keys=14;waitc(40);start_h=dut.pulse_h;clocks(20000);
  if(!dut.manual_motion||dut.pulse_h>=start_h)$fatal(1,"direction did not override automatic motion");
  keys=15;waitc(40);force dut.track_valid=1'b1;waitc(2);force dut.track_valid=1'b0;
  start_h=dut.pulse_h;clocks(40000);if(dut.pulse_h<=start_h)$fatal(1,"automatic motion did not resume after release");
  release dut.gimbal_auto_enable;release dut.track_found;release dut.track_x;release dut.track_y;release dut.track_valid;
  sw=15;waitc(40);if(dut.manual_mode)$fatal(1,"local manual exit");
  keys=14;waitc(40);keys=15;waitc(40);if(dut.mode!=1)$fatal(1,"local mode after disconnect");
  clocks(1);srcsof=1;srcde=1;clocks(1);srcsof=0;srcde=0;clocks(500);
  if(!dut.latency_seen||dut.latency_cycles<5||!dut.telemetry_compute_valid)$fatal(1,"ordinary latency not measured/formatted");
  $display("PASS tb_hmi_pipeline_v72: UART to application to actual PWM, four directions, manual toggle, physical arbitration, disconnect and local control");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
