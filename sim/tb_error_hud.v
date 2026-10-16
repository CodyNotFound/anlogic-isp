`timescale 1ns/1ps
module tb_error_hud;
 reg clk=0,rst=0,de=0,sof=0,eol=0;reg [3:0] flags=0;
 wire ode;wire [23:0] out;reg [15:0] font[0:2047];
 integer f,x,y,n=0,px,py,df,di,checks=0;reg [3:0] expected_flags;reg ink;reg [23:0] expected;
 always #5 clk=~clk;
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0)) dut(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),
 .I_video_hsync(1'b0),.I_video_de(de),.I_video_user(sof),.I_video_last(eol),
 .I_debug_status(flags),.I_cam_frame_tog(1'b0),.I_latency_frames(8'd0),.I_mode(4'd0),.I_isp_demo(4'd0),
 .I_feature_enable(4'd0),.O_video_rd_en(),.I_video_rd_data(24'h204060),.O_hdmi_vsync(),
 .O_hdmi_hsync(),.O_hdmi_de(ode),.O_hdmi_data(out),.O_hdmi_sof());
 function [3:0] state;input integer frame;begin
  case(frame)0:state=0;1:state=1;2:state=2;3:state=4;4:state=8;default:state=15;endcase
 end endfunction
 always @(posedge clk)begin #1;if(rst&&ode)begin
  df=n/(1280*220);py=(n%(1280*220))/1280;px=n%1280;
  if(py>=204&&py<220&&px>=56&&px<88)begin
   expected_flags=state(df);di=(px-56)/8;
   ink=font[(expected_flags[di]?16:0)+(py-204)][15-((px-56)%8)];
   expected=ink?((expected_flags==0)?24'h20ff50:24'hff4040):24'h204060;
   if(out!==expected)$fatal(1,"ERR HUD mismatch flags=%b digit=%0d xy=%0d,%0d got=%h expected=%h",expected_flags,di,px,py,out,expected);
   checks=checks+1;
  end
  n=n+1;
 end end
 initial begin
  $readmemh("osd_font_rom.hex",font);
  repeat(10)@(negedge clk);rst=1;
  for(f=0;f<6;f=f+1)begin
   flags=state(f);
   for(y=0;y<220;y=y+1)begin
    for(x=0;x<1280;x=x+1)begin @(negedge clk);de=1;sof=(x==0&&y==0);eol=(x==1279);end
    @(negedge clk);de=0;sof=0;eol=0;repeat(8)@(negedge clk);
   end
   repeat(20)@(negedge clk);
  end
  if(checks!=3072)$fatal(1,"HUD coverage %0d",checks);
  $display("PASS tb_error_hud six bit patterns, 3072 digit pixels");$finish;
 end
 initial begin #25000000;$fatal(1,"timeout");end
endmodule
