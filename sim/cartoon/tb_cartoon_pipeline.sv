`timescale 1ns/1ps
// Native-size application renderer; actual RGB source, no injected effect pixels.
module tb_cartoon_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,video_vsync=0,video_hsync=0,video_de=0,video_sof=0,video_eol=0;
 reg [23:0] pixel_in=0;
 wire pixel_rd_en,video_vsync_out,video_hsync_out,video_de_out;
 wire [23:0] pixel_out;wire [7:0] frame_stat_y;wire frame_stat_toggle;wire [3:0] isp_demo_sel;
 vision_pipeline #(.ENABLE_OSD(0),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
  .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
  .clk(clk),.rst_n(rst_n),.switches_n(4'b1111),.buttons_n(4'b1111),
  .video_vsync(video_vsync),.video_hsync(video_hsync),.video_de(video_de),.video_sof(video_sof),.video_eol(video_eol),
  .debug_status(4'd0),.pixel_in(pixel_in),.pixel_rd_en(pixel_rd_en),
  .video_vsync_out(video_vsync_out),.video_hsync_out(video_hsync_out),.video_de_out(video_de_out),.pixel_out(pixel_out),
  .frame_stat_y(frame_stat_y),.frame_stat_toggle(frame_stat_toggle),.isp_demo_sel(isp_demo_sel),.servo_pwm_h(),.servo_pwm_v(),.panel_leds(),.panel_segments(),.panel_selects());
 reg [23:0] image[0:921599],expected[0:921599];
 integer x,y,frame,pixels=0,ox,oy,sof_count=0,fd=0,total=0;
 reg checking=0;reg [23:0] want;
 always @(posedge clk)begin
  #1;
  if(rst_n && pixel_rd_en!==video_de)$fatal(1,"cartoon frame reader backpressure");
  if(checking && video_de_out)begin
   if(pixels>=921600)$fatal(1,"extra native output");
   ox=pixels%1280;oy=pixels/1280;
   want=frame==0?expected[pixels]:image[pixels];
   if(pixel_out!==want)$fatal(1,"native cartoon frame%0d %0d,%0d got%h expected%h",frame,ox,oy,pixel_out,want);
   if(video_vsync_out!==(ox==0&&oy==0) || video_hsync_out!==(ox==1279))$fatal(1,"native cartoon sync");
   if(dut.mixer_sof)sof_count=sof_count+1;
   if(fd)$fwrite(fd,"%c%c%c",pixel_out[23:16],pixel_out[15:8],pixel_out[7:0]);
   pixels=pixels+1;total=total+1;
  end
 end
 initial begin
  $readmemh("sim/cartoon/native720.hex",image);$readmemh("sim/cartoon/native720.expected",expected);
  repeat(5)@(negedge clk);rst_n=1;repeat(300)@(negedge clk);
  force dut.u_mode_ctrl.mode=4'd9;force dut.u_mode_ctrl.demo_active=0;
  for(frame=0;frame<2;frame=frame+1)begin
   if(frame==1)force dut.u_mode_ctrl.mode=0;
   if(frame==0)begin fd=$fopen("reports/cartoon_v41/native720_pipeline.ppm","wb");$fwrite(fd,"P6\n1280 720\n255\n");end
   repeat(10)@(negedge clk);pixels=0;sof_count=0;checking=1;
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)begin
     @(negedge clk);video_de=1;video_sof=x==0&&y==0;video_eol=x==1279;
     video_vsync=video_sof;video_hsync=video_eol;pixel_in=image[y*1280+x];
    end
    @(negedge clk);video_de=0;video_sof=0;video_eol=0;video_vsync=0;video_hsync=0;
    repeat(16)@(negedge clk);
   end
   repeat(40)@(negedge clk);checking=0;
   if(fd)begin $fclose(fd);fd=0;end
   if(pixels!=921600 || sof_count!=1)$fatal(1,"native frame count %0d/%0d",pixels,sof_count);
   $display("PASS native cartoon frame%0d pixels%0d",frame,pixels);
  end
  $display("PASS tb_cartoon_pipeline: %0d exact native RGB pixels, TOON then passthrough, complete rows/frames, sync, no backpressure",total);$finish;
 end
 initial begin #40000000;$fatal(1,"native cartoon watchdog");end
endmodule
