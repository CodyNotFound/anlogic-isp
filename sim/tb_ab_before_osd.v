`timescale 1ns/1ps
module tb_ab_before_osd;
 reg clk=0,rst=0,de=0,sof=0,eol=0;
 wire [1:0] od,os;wire [23:0] px[0:1];
 integer x,y,n=0,fg=0,bg=0;reg hit,blend;
 always #5 clk=~clk;
 genvar g;
 generate for(g=0;g<2;g=g+1)begin: p
  vision_pipeline #(.ENABLE_PIPELINE(0)) dut(.clk(clk),.rst_n(rst),
  .switches_n(4'b1111),.buttons_n(4'b1111),.video_vsync(1'b0),.video_hsync(1'b0),
  .video_de(de),.video_sof(sof),.video_eol(eol),.debug_status(4'd0),.pixel_in(24'h204060),
  .pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(od[g]),
  .pixel_out(px[g]),.frame_stat_y(),.frame_stat_toggle());
 end endgenerate
 always @(posedge clk)begin
  hit=p[0].dut.u_hdmi_mixer.r2_hit;blend=p[0].dut.u_hdmi_mixer.r2_blend;
  #1;
  if(rst)begin
   if(od[0]!==od[1])$fatal(1,"AB changed DE latency");
   if(od[0])begin
    n=n+1;
    if(hit)begin
     fg=fg+1;if(px[0]!==px[1])$fatal(1,"AB altered opaque OSD foreground");
    end else if(!blend)begin
     bg=bg+1;
     if(px[0]!==24'h204060||px[1]!==24'h2e5c8a)
      $fatal(1,"AB image mismatch at output %0d unity=%h bright=%h",n,px[0],px[1]);
    end
   end
  end
 end
 initial begin
  // Hold gain at two legal settings to isolate placement from adaptation.
  force p[0].dut.feature_enable=4'b1000;force p[1].dut.feature_enable=4'b1000;
  force p[0].dut.u_adaptive_brightness.gain_q8=9'd256;
  force p[1].dut.u_adaptive_brightness.gain_q8=9'd368;
  repeat(20)@(negedge clk);rst=1;repeat(400)@(negedge clk);
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin
    @(negedge clk);de=1;sof=(x==0&&y==0);eol=(x==1279);
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(8)@(negedge clk);
  end
  repeat(30)@(negedge clk);
  if(n!=921600||fg<100||bg<800000)$fatal(1,"AB coverage counts n=%0d fg=%0d bg=%0d",n,fg,bg);
  $display("PASS tb_ab_before_osd pixels=%0d foreground=%0d background=%0d",n,fg,bg);$finish;
 end
 initial begin #15000000;$fatal(1,"timeout");end
endmodule
