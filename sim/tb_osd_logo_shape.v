`timescale 1ns/1ps
module tb_osd_logo_shape;
 reg clk=0,rst_n=0,de=0,user=0,last=0;reg [23:0] pixel=24'h808080;
 wire vs,hs,ode,osof;wire [23:0] out;
 integer x,y,out_x=0,out_y=0,count=0,mismatch=0,unknown=0,foreground=0,actual_fd;
 reg [23:0] expected[0:33103];
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0),.ENABLE_OSD(1)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b0),.I_video_de(de),
 .I_video_user(user),.I_video_last(last),.I_debug_status(0),.I_cam_frame_tog(1'b0),
 .I_latency_frames(0),.I_mode(0),.I_isp_demo(4'd0),.I_feature_enable(4'b0000),.O_video_rd_en(),
 .I_video_rd_data(pixel),.O_hdmi_vsync(vs),.O_hdmi_hsync(hs),.O_hdmi_de(ode),
 .O_hdmi_data(out),.O_hdmi_sof(osof));
 always #3.333 clk=~clk;
 always @(posedge clk)begin
  #1;if(rst_n&&ode)begin
   if((^out)===1'bx)unknown++;
   if(out_y>=16&&out_y<134&&out_x>=16&&out_x<179)begin
    if(out!==expected[count])begin
     if(mismatch<20)$display("MISMATCH xy=%0d,%0d out=%h exp=%h",out_x,out_y,out,expected[count]);
     mismatch++;
    end
    if(out!==24'h404040)foreground++;$fwrite(actual_fd,"%06x\n",out);count++;
   end
   out_x++;if(out_x==1280)begin out_x=0;out_y++;end
  end
 end
 task drive;input integer xi,yi;
 begin @(negedge clk);de=1;user=(xi==0&&yi==0);last=(xi==1279);pixel=24'h808080;end endtask
 initial begin
  $readmemh("logo_expected.hex",expected);actual_fd=$fopen("logo_actual.hex","w");
  repeat(8)@(negedge clk);rst_n=1;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)drive(x,y);
   @(negedge clk);de=0;user=0;last=0;repeat(5)@(negedge clk);
  end
  repeat(10)@(negedge clk);
  if(actual_fd)$fclose(actual_fd);$display("DIAG count=%0d mismatch=%0d unknown=%0d foreground=%0d",count,mismatch,unknown,foreground);
  if(count!=19234||mismatch||unknown)$fatal(1,"logo shape failed");
  $display("PASS tb_osd_logo_shape real MIF pixels");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
