`timescale 1ns/1ps
module tb_telemetry_pipeline_v61;
 reg clk=0,rst=0;always #5 clk=~clk;
 vision_pipeline #(.FACE_CNN_ENABLE(1),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),.FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
 .clk(clk),.rst_n(rst),.switches_n(4'b1111),.buttons_n(4'b1111),.video_vsync(1'b0),.video_hsync(1'b0),.video_de(1'b0),.video_sof(1'b0),.video_eol(1'b0),.debug_status(4'd0),.pixel_in(24'd0),
 .pixel_rd_en(),.video_vsync_out(),.video_hsync_out(),.video_de_out(),.pixel_out(),.frame_stat_y(),.frame_stat_toggle(),.isp_demo_sel(),.servo_pwm_h(),.servo_pwm_v(),.panel_leds(),.panel_segments(),.panel_selects());
 task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
 force dut.face_position_valid=0;force dut.track_valid=0;
 tick(5);rst=1;tick(5);force dut.u_mode_ctrl.mode=11;tick(5);
 force dut.face_center_x=936;force dut.face_center_y=404;force dut.face_found=1;force dut.face_compute_cycles=19992365;
 force dut.face_position_valid=1;tick(2);force dut.face_position_valid=0;tick(1000);
 if(dut.target_x_digits!=16'h0936||dut.target_y_digits!=16'h0404||dut.compute_ms_digits!=16'h0267||!dut.telemetry_compute_valid)$fatal(1,"FACE telemetry wrong");
 force dut.u_mode_ctrl.mode=12;tick(5);if(dut.compute_seen)$fatal(1,"old FACE time leaked across mode switch");
 force dut.track_x=90;force dut.track_y=55;force dut.track_found=1;force dut.task_compute_cycles=1113520;
 force dut.track_valid=1;tick(2);force dut.track_valid=0;tick(1000);
 if(dut.target_x_digits!=16'h0720||dut.target_y_digits!=16'h0440||dut.compute_ms_digits!=16'h0015)$fatal(1,"TRACK scaling/compute time wrong");
 force dut.track_found=0;tick(1);if(dut.coordinate_found)$fatal(1,"stale target not invalidated");
 force dut.u_mode_ctrl.mode=0;tick(1000);if(dut.compute_seen||dut.coordinate_found)$fatal(1,"mode exit did not clear telemetry");
 $display("PASS tb_telemetry_pipeline_v61 FACE native XY, TRACK grid x8, real clock-scale conversion, mode reset and loss invalidation; injected interface probe, not inference accuracy");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule
