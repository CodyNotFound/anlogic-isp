`timescale 1ns/1ps
// Verify the application integration separately from the actual detector photo
// test: inject a result at its boundary, then check every output video pixel.
module tb_face_pipeline;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,video_vsync=0,video_hsync=0,video_de=0,video_sof=0,video_eol=0;
    reg [23:0] pixel_in=24'h102030;
    wire pixel_rd_en,video_vsync_out,video_hsync_out,video_de_out;
    wire [23:0] pixel_out;wire [7:0] frame_stat_y;wire frame_stat_toggle;wire [3:0] isp_demo_sel;
    vision_pipeline #(.ENABLE_OSD(0),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
        .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
        .clk(clk),.rst_n(rst_n),.switches_n(4'b1111),.buttons_n(4'b1111),
        .video_vsync(video_vsync),.video_hsync(video_hsync),.video_de(video_de),.video_sof(video_sof),.video_eol(video_eol),
        .debug_status(4'd0),.pixel_in(pixel_in),.pixel_rd_en(pixel_rd_en),
        .video_vsync_out(video_vsync_out),.video_hsync_out(video_hsync_out),.video_de_out(video_de_out),.pixel_out(pixel_out),
        .frame_stat_y(frame_stat_y),.frame_stat_toggle(frame_stat_toggle),.isp_demo_sel(isp_demo_sel),.servo_pwm_h(),.servo_pwm_v(),.panel_leds(),.panel_segments(),.panel_selects());
    integer x,y,frame,pixels=0,ox,oy,sof_count=0,green=0,red=0;
    reg checking=0,border,crosshair;reg [23:0] expected;
    always @(posedge clk) begin
        #1;
        if(rst_n && pixel_rd_en!==video_de)$fatal(1,"FAIL frame reader backpressure");
        if(checking && video_de_out) begin
            ox=pixels%1280;oy=pixels/1280;
            border=ox>=400 && ox<624 && oy>=224 && oy<448 &&
                (ox<402 || ox>=622 || oy<226 || oy>=446);
            crosshair=(ox==512 && oy>=329 && oy<=343)||(oy==336 && ox>=505 && ox<=519);
            expected=frame==0 ? crosshair ? 24'hff4040 : border ? 24'h00ff40 : 24'h102030 : 24'h102030;
            if(pixel_out!==expected)$fatal(1,"FAIL integrated pixel frame=%0d x=%0d y=%0d got=%h expected=%h",frame,ox,oy,pixel_out,expected);
            if(video_vsync_out!==(ox==0&&oy==0) || video_hsync_out!==(ox==1279))$fatal(1,"FAIL integrated sync position");
            if(dut.mixer_sof)sof_count=sof_count+1;
            if(pixel_out==24'h00ff40)green=green+1;if(pixel_out==24'hff4040)red=red+1;
            pixels=pixels+1;
        end
    end
    initial begin
        // The existing histogram block initializes 256 RAM entries after reset.
        repeat(5)@(negedge clk);rst_n=1;repeat(300)@(negedge clk);
        force dut.u_mode_ctrl.mode=4'd11;
        // Isolate box rendering with compositor disabled; SW3 behavior has its
        // own full-RGB regression, rather than changing this injected-box test.
        force dut.info_enabled_f=1'b1;
        force dut.u_mode_ctrl.demo_active=1'b0;
        force dut.u_face_position.found=1'b1;
        force dut.u_face_position.box_x=12'd400;force dut.u_face_position.box_y=12'd224;
        force dut.u_face_position.box_size=12'd224;force dut.u_face_position.center_x=12'd512;force dut.u_face_position.center_y=12'd336;
        for(frame=0;frame<2;frame=frame+1) begin
            if(frame==1)force dut.u_mode_ctrl.mode=4'd0;
            repeat(10)@(negedge clk);pixels=0;sof_count=0;green=0;red=0;checking=1;
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<1280;x=x+1) begin
                    @(negedge clk);video_de=1;video_sof=x==0&&y==0;video_eol=x==1279;
                    video_vsync=video_sof;video_hsync=video_eol;
                end
                @(negedge clk);video_de=0;video_sof=0;video_eol=0;video_vsync=0;video_hsync=0;
                repeat(16)@(negedge clk);
            end
            repeat(30)@(negedge clk);checking=0;
            if(pixels!=921600 || sof_count!=1)$fatal(1,"FAIL frame pixel/SOF count %0d/%0d",pixels,sof_count);
            if(frame==0 && (green==0 || red!=29))$fatal(1,"FAIL face overlay not connected");
            if(frame==1 && (green!=0 || red!=0))$fatal(1,"FAIL overlay survived mode exit");
            $display("PASS integrated application frame=%0d pixels=%0d green=%0d red=%0d",frame,pixels,green,red);
        end
        $display("PASS tb_face_pipeline: 1843200 pixels, FACE wiring, passthrough, mode exit, sync and no backpressure");$finish;
    end
endmodule

// ENABLE_OSD=0 above: isolate application timing from vendor ROM primitives.
// The separate run_osd_checks.ps1 regression exercises the real font contents.
module osd_font_bram(input wire I_clk,input wire [7:0] I_char,input wire [3:0] I_row,output wire [15:0] O_row_bits);
    assign O_row_bits=16'd0;
endmodule
module logo_rom_bram(input wire I_clk,input wire [13:0] I_addr,output wire [7:0] O_idx,output wire [23:0] O_rgb);
    assign O_idx=8'd0;assign O_rgb=24'd0;
endmodule
