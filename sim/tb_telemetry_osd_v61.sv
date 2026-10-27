`timescale 1ns/1ps
module tb_telemetry_osd_v61;
 reg clk=0,rst=0,sof=0,found=1,cv=1;always #5 clk=~clk;
 reg[15:0] xd=16'h0936,yd=16'h0404,md=16'h0267;
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.COMPACT_OSD(1),.TARGET_TELEMETRY(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),.I_video_de(1'b0),.I_video_user(sof),.I_video_last(1'b0),
 .I_debug_status(4'd0),.I_cam_frame_tog(1'b0),.I_latency_frames(8'd0),.I_mode(4'd11),.I_isp_demo(4'd0),.I_feature_enable(4'd0),
 .I_info_enable(1'b1),.I_panel_features(4'd4),.I_task_status(4'd0),.I_ctl_state(2'd1),.I_pulse_h(12'd1500),.I_pulse_v(12'd1500),
 .I_h_digits(24'h001500),.I_v_digits(24'h001500),.I_video_rd_data(24'h6080a0),.O_video_rd_en(),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_hdmi_data(),.O_hdmi_sof(),
 .I_target_found(found),.I_compute_valid(cv),.I_target_x_digits(xd),.I_target_y_digits(yd),.I_compute_ms_digits(md));
 task latch;begin @(negedge clk);sof=1;@(negedge clk);sof=0;end endtask
 initial begin
 repeat(5)@(negedge clk);rst=1;latch;
 force dut.S_video_de_1d=1;force dut.S_x_1d=200;force dut.S_y_1d=78;#1;
 if(dut.c_text!=="X:0936 Y:0404           "||!dut.v_blend)$fatal(1,"XY row mismatch %h",dut.c_text);
 xd=16'h0001;yd=16'h0002;found=0;cv=0;#1;if(dut.c_text!=="X:0936 Y:0404           ")$fatal(1,"mid-frame text tear");
 force dut.S_y_1d=98;#1;if(dut.c_text!=="PROC 0267 MS            ")$fatal(1,"PROC row mismatch %h",dut.c_text);
 latch;#1;if(dut.c_text!=="PROC ---- MS            ")$fatal(1,"unmeasured time not blank");
 force dut.S_y_1d=78;#1;if(dut.c_text!=="X:---- Y:----           ")$fatal(1,"lost coordinate not blank");
 $display("PASS tb_telemetry_osd_v61 XY/PROC text, frame atomicity, lost/unknown placeholders, existing compact region");$finish;
 end
 initial begin #10000;$fatal(1,"watchdog");end
endmodule
