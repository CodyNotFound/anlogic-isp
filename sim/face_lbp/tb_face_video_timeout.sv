`timescale 1ns/1ps
module tb_face_video_timeout;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,sof=0,eol=0,de=0;reg [23:0] rgb=0;
    wire found,busy,stream_error,timeout_error,position_valid;
    face_video_position #(.TIMEOUT_CYCLES(64)) dut(.clk(clk),.rst_n(rst_n),.enable(enable),
        .sof(sof),.eol(eol),.de(de),.rgb(rgb),.found(found),.busy(busy),
        .stream_error(stream_error),.timeout_error(timeout_error),.position_valid(position_valid),
        .box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.accepted_frames(),.completed_frames());
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        @(negedge clk);sof=1;
        @(negedge clk);sof=0;
        repeat(80)@(negedge clk);
        if(!timeout_error || found || busy || position_valid)$fatal(1,"FAIL stopped camera watchdog");
        // A new whole-frame marker is accepted after timeout recovery.
        @(negedge clk);sof=1;@(negedge clk);sof=0;
        repeat(3)@(negedge clk);
        if(!busy)$fatal(1,"FAIL watchdog recovery did not accept next frame");
        enable=0;repeat(3)@(negedge clk);
        if(found || busy || position_valid)$fatal(1,"FAIL disable");
        $display("PASS tb_face_video_timeout: stalled camera abort, recovery and disable");$finish;
    end
endmodule
