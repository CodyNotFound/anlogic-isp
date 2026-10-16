`timescale 1ns/1ps
module tb_ref_osd_mixer_demo;
 reg clk=0,rst_n=0,de=0,user=0,last=0,cam_tog=0;
 reg [3:0] feature=4'b0101;
 reg [23:0] pixel=24'h808080;
 wire vs,hs,ode,osof; wire [23:0] out;
 integer x,y,out_x=0,out_y=0,out_count=0,sof_count=0,unknown=0;
 integer mode_fg=0,sw_fg=0,sw_green=0,sw_gray=0,bad_bar_color=0,csv,fps_fg=0,old_lat_area=0;
 integer foreground;
 reg [7:0] r,g,b;
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0),.ENABLE_OSD(1)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
 .I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),
 .I_cam_frame_tog(cam_tog),.I_latency_frames(8'd0),.I_mode(4'd10),.I_isp_demo(4'b1000),
 .I_feature_enable(feature),.O_video_rd_en(),.I_video_rd_data(pixel),
 .O_hdmi_vsync(vs),.O_hdmi_hsync(hs),.O_hdmi_de(ode),.O_hdmi_data(out),.O_hdmi_sof(osof));
 always #3.333 clk=~clk;
 always @(posedge clk) begin
  #1;
  if(rst_n) begin
   if(osof===1'b1) sof_count=sof_count+1;
   if(ode===1'b1) begin
    out_count=out_count+1;
    if((^out)===1'bx) unknown=unknown+1;
    r=out[23:16];g=out[15:8];b=out[7:0];
    foreground=((r>8'h50)||(g>8'h50)||(b>8'h50));
    if(out_y>=154&&out_y<170&&out_x>=24&&out_x<72&&out===24'h00ff6a)fps_fg++;
    if(out_y>=174&&out_y<190&&out_x>=24&&out_x<96&&out!==24'h808080)old_lat_area++;
    if(out_y>=692 && out_y<708) begin
     if(out_x>=24 && out_x<120 && foreground) mode_fg++;
     if(out_x>=1152 && out_x<1248) begin
      if(out===24'h20ff50) begin sw_fg++;sw_green++;end
      else if(out===24'h707070) begin sw_fg++;sw_gray++;end
      else if(out!==24'h404040) bad_bar_color++;
     end
    end
    out_x=out_x+1;
    if(out_x==1280) begin out_x=0;out_y=out_y+1;end
   end
  end
 end
 task drive;input integer x_in,y_in;
 begin
  @(negedge clk);
  de=1;user=(x_in==0&&y_in==0);last=(x_in==1279);pixel=24'h808080;
 end endtask
 initial begin
  csv=0;
  repeat(8)@(negedge clk);rst_n=1;@(negedge clk);cam_tog=1;
  for(y=0;y<720;y=y+1) begin
   for(x=0;x<1280;x=x+1) begin
    drive(x,y);
    #1;
   end
   @(negedge clk);de=0;user=0;last=0;repeat(5)@(negedge clk);
  end
  repeat(20)@(negedge clk);
  $display("DIAG outputs=%0d sof=%0d unknown=%0d mode_fg=%0d sw_fg=%0d green=%0d gray=%0d bad=%0d",
           out_count,sof_count,unknown,mode_fg,sw_fg,sw_green,sw_gray,bad_bar_color);

  if(out_count!=921600)$fatal(1,"output count");
  if(sof_count!=1||unknown!=0)$fatal(1,"sof/unknown");
  if(mode_fg==0)$fatal(1,"mode text missing");
  if(sw_fg==0||sw_green==0||sw_gray==0)$fatal(1,"switch status missing");
  if(fps_fg==0)$fatal(1,"FPS text missing");
  if(old_lat_area!=0)$fatal(1,"removed LAT area altered camera pixels");
  $display("PASS tb_ref_osd_mixer_demo mode=10 SW=AE/HE on; LAT removed");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule




