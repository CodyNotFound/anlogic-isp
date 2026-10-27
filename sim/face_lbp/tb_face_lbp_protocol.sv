`timescale 1ns/1ps
// Independent integral-image arithmetic check and wrapper handshake/overflow.
module tb_face_lbp_protocol;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_start=0,pixel_valid=0,model_select=0;
    reg [7:0] gray=0;
    wire ready,busy,result_valid,target_found,overflow;
    wire [7:0] target_x,target_y,target_size,target_votes;
    wire [8:0] target_center_x,target_center_y;
    wire [31:0] cycles,feature_count;
    face_detector_snapshot dut(.search_enable(1'b0),.search_x0(8'd0),.search_y0(8'd0),.search_x1(8'd0),.search_y1(8'd0),.search_scale_lo(4'd0),.search_scale_hi(4'd0),.*);
    integer x,y,idx,rsum,i;
    integer expected[0:14399];
    reg start2=0,end2=0,valid2=0;
    reg [7:0] x2=0,y2=0,w2=24;
    wire found2,result2,over2,busy2;
    wire [7:0] tx2,ty2,tw2,tv2;
    face_candidate_select #(.SLOTS(2)) small_selector(.clk(clk),.rst_n(rst_n),
        .frame_start(start2),.frame_done(end2),.candidate_valid(valid2),.box_x(x2),.box_y(y2),.box_size(w2),
        .result_valid(result2),.target_found(found2),.overflow(over2),.select_busy(busy2),
        .target_x(tx2),.target_y(ty2),.target_size(tw2),.target_votes(tv2),.target_center_x(),.target_center_y());
    task candidate(input integer bx,input integer by);
        begin while(busy2) @(negedge clk);@(negedge clk);valid2=1;x2=bx;y2=by;@(negedge clk);valid2=0;end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        @(negedge clk);frame_start=1;
        @(negedge clk);frame_start=0;
        for(y=0;y<90;y=y+1) begin
            rsum=0;
            for(x=0;x<160;x=x+1) begin
                idx=y*160+x;gray=(x*17+y*39+idx/7)%256;
                rsum=rsum+gray;expected[idx]=rsum+(y==0 ? 0 : expected[idx-160]);
                pixel_valid=1;@(negedge clk);
                if(idx%41==0) begin pixel_valid=0;repeat(2) @(negedge clk);end
            end
        end
        pixel_valid=0;repeat(2) @(negedge clk);
        for(i=0;i<14400;i=i+1)
            if(dut.core.integral[i]!==expected[i]) $fatal(1,"FAIL integral %0d got=%0d expected=%0d",i,dut.core.integral[i],expected[i]);
        // Reset a busy scan: no stale target may survive.
        rst_n=0;@(negedge clk);rst_n=1;@(negedge clk);
        if(!ready || busy || result_valid || target_found) $fatal(1,"FAIL wrapper reset");
        start2=1;@(negedge clk);start2=0;
        candidate(10,10);candidate(11,10);candidate(12,11);
        candidate(90,50);candidate(91,51);candidate(92,50);
        candidate(140,10); // Third distinct slot is rejected with overflow.
        @(negedge clk);end2=1;@(negedge clk);end2=0;
        while(!result2) @(negedge clk);
        if(!result2 || found2 || !over2) $fatal(1,"FAIL overflow must suppress target");
        // Clear overflow and ensure a lone candidate is not a target.
        start2=1;@(negedge clk);start2=0;candidate(10,10);
        @(negedge clk);end2=1;@(negedge clk);end2=0;
        while(!result2) @(negedge clk);
        if(!result2 || found2 || over2) $fatal(1,"FAIL lone candidate filter");
        // A last candidate and frame_done may coincide. Drain it before voting.
        start2=1;@(negedge clk);start2=0;
        candidate(10,10);candidate(11,10);
        while(busy2) @(negedge clk);
        @(negedge clk);valid2=1;x2=12;y2=11;end2=1;
        @(negedge clk);valid2=0;end2=0;
        while(!result2) @(negedge clk);
        if(!found2 || over2 || tv2!=3 || tx2!=10 || ty2!=10 || tw2!=24)
            $fatal(1,"FAIL last candidate and frame_done ordering");
        // A burst beyond the one-entry skid buffer must reject, never truncate.
        start2=1;@(negedge clk);start2=0;
        while(busy2) @(negedge clk);
        @(negedge clk);valid2=1;x2=10;y2=10;
        repeat(4) @(negedge clk);
        valid2=0;end2=1;@(negedge clk);end2=0;
        while(!result2) @(negedge clk);
        if(found2 || !over2)$fatal(1,"FAIL queue overrun must reject snapshot");
        $display("PASS protocol: all 14400 integral values, gaps, reset, overflow, lone candidate, pending final candidate, burst overrun");
        $finish;
    end
    initial begin #1000000;$fatal(1,"FAIL protocol watchdog");end
endmodule
