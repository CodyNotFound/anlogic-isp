`timescale 1ns/1ps
module tb_latency_v72;
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
  $display("PASS tb_latency_v72: modes0..10 measured application SOF latency and decimal-ms formatting");$finish;
 end

 initial begin #30000000;$fatal(1,"timeout");end
endmodule
