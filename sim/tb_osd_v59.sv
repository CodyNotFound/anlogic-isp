`timescale 1ns/1ps
// Composition/control regression. Detector results are injected at interfaces;
// this test makes no claim about classifier accuracy.
module tb_osd_v59;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,sof=0,eol=0;reg [3:0] sw=11,keys=15;
 wire od,ov,oh;wire [23:0] out;
 vision_pipeline #(.ENABLE_OSD(1),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
 .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.rst_n(rst),.switches_n(sw),.buttons_n(keys),.video_vsync(sof),.video_hsync(eol),
 .video_de(de),.video_sof(sof),.video_eol(eol),.debug_status(4'd0),.pixel_in(24'h6080a0),
 .pixel_rd_en(),.video_vsync_out(ov),.video_hsync_out(oh),.video_de_out(od),.pixel_out(out),
 .frame_stat_y(),.frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(),.servo_pwm_v(),
 .panel_leds(),.panel_segments(),.panel_selects());
 defparam dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 defparam dut.u_gimbal.CLK_HZ=1000000;
 reg [23:0] expected[0:921599];
 integer f,x,y,n=0,starts=0,total=0,oldh,mismatch=0;
 reg checking=0;
 reg [511:0] filename;
 always @(posedge clk)begin #1;
  if(checking && od)begin
   if(out!==expected[n])begin
    if(mismatch<8)$display("PIX frame%0d (%0d,%0d) actual=%h expected=%h",f,n%1280,n/1280,out,expected[n]);
    mismatch=mismatch+1;
   end
   if(dut.mixer_sof)starts=starts+1;
   if(ov!==(n==0)||oh!==(n%1280==1279))$fatal(1,"video qualifiers frame%0d pixel%0d",f,n);
   n=n+1;total=total+1;
  end
 end
 task waitc;input integer count;begin repeat(count)@(negedge clk);end endtask
 initial begin
  waitc(5);rst=1;waitc(400);
  force dut.u_hdmi_mixer.S_fps_d1=6;force dut.u_hdmi_mixer.S_fps_d0=0;
  force dut.u_hdmi_mixer.I_ctl_state=1;
  force dut.u_panel.display_h=1500;force dut.u_panel.display_v=1500;
  force dut.u_panel.h_digits=24'h001500;force dut.u_panel.v_digits=24'h001500;
  force dut.u_face_position.found=1;force dut.u_face_position.box_x=848;force dut.u_face_position.box_y=368;
  force dut.u_face_position.box_size=224;force dut.u_face_position.center_x=960;force dut.u_face_position.center_y=480;
  force dut.u_face_position.position_valid=0;
  force dut.u_tasks.tf=1;force dut.u_tasks.tx=90;force dut.u_tasks.ty=55;force dut.u_tasks.t_lost=0;
  force dut.u_tasks.rc=1;force dut.u_tasks.rf=1;force dut.u_tasks.ro=0;force dut.u_tasks.picking=0;
  force dut.u_tasks.rx=92;force dut.u_tasks.ry=52;force dut.u_tasks.rw=16;force dut.u_tasks.rh=16;
  force dut.u_tasks.rcx=100;force dut.u_tasks.rcy=60;force dut.u_tasks.age=0;
  for(f=0;f<6;f=f+1)begin
   case(f)
    0:force dut.u_mode_ctrl.mode=0;
    1,2:force dut.u_mode_ctrl.mode=11;
    3:force dut.u_mode_ctrl.mode=12;
    default:force dut.u_mode_ctrl.mode=14;
   endcase
   if(f==5)sw=3;
   waitc(60);
   oldh=dut.pulse_h;
   if(f==1 || f==2)begin
    force dut.u_face_position.position_valid=1;waitc(2);force dut.u_face_position.position_valid=0;
   end
   $sformat(filename,"reports/osd_v43/expected_%0d.hex",f);$readmemh(filename,expected);
   n=0;starts=0;mismatch=0;checking=1;
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)begin
     de=1;sof=x==0&&y==0;eol=x==1279;@(negedge clk);
    end
    de=0;sof=0;eol=0;waitc(5);
    // Raw switch changes halfway through the frame must wait for next SOF.
    if(y==300 && f==1)sw=15;
    if(y==300 && f==2)sw=11;
   end
   waitc(35);checking=0;
   if(n!=921600 || starts!=1 || mismatch!=0)$fatal(1,"frame%0d count%0d sof%0d pixel mismatches%0d",f,n,starts,mismatch);
   if(f==2 && (dut.gimbal_auto_enable || dut.pulse_h!=oldh))$fatal(1,"SW3 OFF did not hold position");
   if(f==5 && !dut.manual_mode)$fatal(1,"manual switch ignored");
   $display("PASS compact frame%0d pixels%0d info%0d h%0d",f,n,dut.info_enabled_f,dut.pulse_h);
  end
  $display("PASS tb_osd_v59: 5529600 exact RGB pixels, real logo/font contents, AWB/AE HOLD and SW3 AUTO legend, FACE/TRACK/REGION overlays, manual legend, servo stopped with SW3 OFF");$finish;
 end
 initial begin #90000000;$fatal(1,"OSD watchdog");end
endmodule

// Match the actual synchronous font and two-stage palette ROM latencies.
module osd_font_bram(input wire I_clk,input wire [7:0] I_char,input wire [3:0] I_row,output reg [15:0] O_row_bits);
 reg [15:0] mem[0:2047];reg [6:0] ci;
 initial $readmemh("sim/osd_font_rom.hex",mem);
 always @*begin
  if(I_char>=48&&I_char<=57)ci=I_char-48;
  else if(I_char>=65&&I_char<=90)ci=I_char-65+10;
  else if(I_char==58)ci=36;else if(I_char==45)ci=37;else if(I_char==46)ci=38;
  else if(I_char>=128&&I_char<=206)ci=I_char-128+40;else ci=39;
 end
 always @(posedge I_clk)O_row_bits<=mem[{ci,I_row}];
endmodule
module logo_rom_bram(input wire I_clk,input wire [13:0] I_addr,output reg [7:0] O_idx,output reg [23:0] O_rgb);
 reg [7:0] idx[0:16383];reg [23:0] pal[0:255];
 initial begin $readmemh("sim/logo_idx.hex",idx);$readmemh("sim/logo_pal.hex",pal);end
 always @(posedge I_clk)begin O_idx<=idx[I_addr];O_rgb<=pal[O_idx];end
endmodule
