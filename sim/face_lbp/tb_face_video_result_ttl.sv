`timescale 1ns/1ps
// Result-boundary injection tests expiry only, not face recognition accuracy.
module tb_face_video_result_ttl;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1;wire found;
    face_video_position #(.RESULT_TTL_CYCLES(64),.CONFIRM_NEW_TARGET(0)) dut(.clk(clk),.rst_n(rst_n),.enable(enable),
        .sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),.found(found),
        .position_valid(),.box_x(),.box_y(),.box_size(),.center_x(),.center_y(),.busy(),
        .stream_error(),.timeout_error(),.accepted_frames(),.completed_frames());
    task result_event;
        begin
            @(negedge clk);force dut.core_result=1'b1;force dut.core_found=1'b1;
            @(negedge clk);release dut.core_result;release dut.core_found;
            if(!found)$fatal(1,"FAIL result not latched");
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;result_event();
        repeat(40)@(negedge clk);if(!found)$fatal(1,"FAIL result expired too early");
        result_event();repeat(40)@(negedge clk);if(!found)$fatal(1,"FAIL refresh did not reset result age");
        // No DE or SOF at all: a stalled camera must not leave a stale target.
        repeat(30)@(negedge clk);if(found)$fatal(1,"FAIL stale result survived a stopped camera");
        result_event();enable=0;repeat(3)@(negedge clk);if(found)$fatal(1,"FAIL mode exit");
        $display("PASS tb_face_video_result_ttl: hold, refresh, wall-clock expiry without SOF, mode exit");$finish;
    end
endmodule
