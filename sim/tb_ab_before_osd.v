`timescale 1ns/1ps
module tb_ab_before_osd;
 reg clk=0,rst=0,de=0,sof=0,eol=0;
 wire [1:0] od,os;wire [23:0] px[0:1];
 integer x,y,n=0,fg=0,bg=0,dimmed=0;
 always #5 clk=~clk;
 genvar g;
 generate for(g=0;g<2;g=g+1)begin: p
  vision_pipeline #(.ENABLE_PIPELINE(0),.FACE_WEAK_FILE("../rtl/analytics/face_lbp/human_weak.hex"),
  .FACE_STAGE_FILE("../rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("../rtl/analytics/face_lbp/human_geometry.hex")) dut(.clk(clk),.rst_n(rst),
  .switches_n(4'b1110),.buttons_n(4'b1111),.video_vsync(1'b0),.video_hsync(1'b0),
  .video_de(de),.video_sof(sof),.video_eol(eol),.debug_status(4'd0),.pixel_in(24'h204060),
  .pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(od[g]),
  .pixel_out(px[g]),.frame_stat_y(),.frame_stat_toggle());
 end endgenerate
 defparam p[0].dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 defparam p[1].dut.u_switch_ctrl.DEBOUNCE_CYCLES=4;
 always @(posedge clk)begin
  #1;
  if(rst)begin
   if(od[0]!==od[1])$fatal(1,"AB changed DE latency");
   if(od[0])begin
    n=n+1;
    if(px[0]===24'h204060)begin
     bg=bg+1;if(px[1]!==24'h2e5c8a)$fatal(1,"AB camera gain mismatch at %0d",n);
    end else if(px[0]===px[1])fg=fg+1; // Opaque logo/text/position marker.
    else begin
     dimmed=dimmed+1;
     case(px[0])
      24'h102030:if(px[1]!==24'h172e45)$fatal(1,"legacy panel blend");
      24'h081018:if(px[1]!==24'h0b1722)$fatal(1,"gimbal panel blend");
      24'h04080c:if(px[1]!==24'h050b11)$fatal(1,"overlapping panel blend");
      default:$fatal(1,"OSD foreground changed with AB at %0d: %h/%h",n,px[0],px[1]);
     endcase
    end
   end
  end
 end
 initial begin
  // Hold gain at two legal settings to isolate placement from adaptation.
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
  if(n!=921600||fg<100||bg<800000||dimmed<100)$fatal(1,"AB coverage counts n=%0d fg=%0d bg=%0d",n,fg,bg);
  $display("PASS tb_ab_before_osd pixels=%0d foreground=%0d background=%0d",n,fg,bg);$finish;
 end
 initial begin #15000000;$fatal(1,"timeout");end
endmodule
