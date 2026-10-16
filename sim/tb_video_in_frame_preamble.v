`timescale 1ns/1ps
// Uses real video_in and generated FIFO. Verifies the reset boundary only.
module tb_video_in_frame_preamble;
    reg rst_n,camera_clk,camera_frame_start,camera_valid,ddr_clk;
    reg [127:0] camera_data;
    wire video_in_wr_busy,ddr_user_wr_en;
    wire [1:0] video_out_rp;
    wire [24:0] ddr_user_addr;
    wire [127:0] ddr_user_wr_data;
    integer failures,case_count,phase_index,phase_ns,bad_used,good_used,bad_lost_total;
    video_in dut (
        .I_rst_n(rst_n),.I_camera_clk(camera_clk),
        .I_camera_frame_start(camera_frame_start),.I_camera_valid(camera_valid),
        .I_camera_data(camera_data),.I_mipi_rx_error(1'b0),.I_ddr_clk(ddr_clk),
        .I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),
        .O_video_in_wr_busy(video_in_wr_busy),.O_video_out_rp(video_out_rp),
        .O_ddr_user_wr_en(ddr_user_wr_en),.O_ddr_user_addr(ddr_user_addr),
        .O_ddr_user_wr_data(ddr_user_wr_data),.I_ddr_user_ready(1'b0)
    );
    // v7 routed clock periods: camera byte clock 16.668 ns, DDR user 15 ns.
    initial begin camera_clk=0;forever #8.334 camera_clk=~camera_clk;end
    initial begin ddr_clk=0;forever #7.5 ddr_clk=~ddr_clk;end
    function [127:0] make_word;
        input integer word_index;
        begin
            make_word={32'hCAFE0000|word_index,32'h12340000|word_index,
                       32'h56780000|word_index,32'hBEEF0000|word_index};
        end
    endfunction
    task align_camera_falling_edge;
        input integer requested_phase_ns;
        begin
            @(negedge camera_clk);
            while (($time%15)!=requested_phase_ns) @(negedge camera_clk);
        end
    endtask
    task warm_reset;
        begin
            @(negedge camera_clk);
            camera_valid=0;camera_data=0;camera_frame_start=1;
            @(negedge camera_clk);camera_frame_start=0;
            repeat(64) @(negedge camera_clk);
            #1;
            if(dut.U_w128_d512_fifo.wrusedw!==9'd0)begin
                failures=failures+1;
                $display("FAIL warm reset count=%0d at %0t",dut.U_w128_d512_fifo.wrusedw,$time);
            end
        end
    endtask
    task early_preamble;
        input integer requested_phase_ns;
        begin
            align_camera_falling_edge(requested_phase_ns);
            camera_frame_start=1;camera_valid=0;
            $display("INFO early SOF launch=%0t DDR_phase=%0d ns",$time,$time%15);
            @(negedge camera_clk);camera_frame_start=0;
            repeat(64) @(negedge camera_clk);
        end
    endtask
    task send_frame;
        input integer coincident_sof,requested_phase_ns;
        integer row,column,word_index;
        begin
            word_index=0;
            for(row=0;row<2;row=row+1)begin
                for(column=0;column<240;column=column+1)begin
                    if((word_index==0)&&coincident_sof)
                        align_camera_falling_edge(requested_phase_ns);
                    else @(negedge camera_clk);
                    camera_valid=1;camera_data=make_word(word_index);
                    camera_frame_start=coincident_sof&&(word_index==0);
                    if((word_index==0)&&coincident_sof)
                        $display("INFO coincident SOF launch=%0t DDR_phase=%0d ns",$time,$time%15);
                    word_index=word_index+1;
                    if((column%3)==2)begin
                        @(negedge camera_clk);camera_valid=0;camera_frame_start=0;
                    end
                end
                repeat(64) @(negedge camera_clk);
            end
            camera_valid=0;camera_frame_start=0;camera_data=0;
        end
    endtask
    task sample_count;
        output integer used_words;
        begin
            repeat(64) @(negedge camera_clk);
            #1;
            if((^dut.U_w128_d512_fifo.wrusedw)===1'bx)begin
                used_words=-1;failures=failures+1;
                $display("FAIL FIFO count X/Z at %0t",$time);
            end else used_words=dut.U_w128_d512_fifo.wrusedw;
        end
    endtask
    initial begin
        rst_n=0;camera_frame_start=0;camera_valid=0;camera_data=0;
        failures=0;case_count=0;bad_lost_total=0;
        repeat(8) @(negedge camera_clk);
        rst_n=1;repeat(8) @(negedge camera_clk);
        for(phase_index=0;phase_index<3;phase_index=phase_index+1)begin
            phase_ns=phase_index*2;
            warm_reset;send_frame(1,phase_ns);sample_count(bad_used);
            case_count=case_count+1;
            if((bad_used>400)&&(bad_used<480))begin
                if(dut.U_w128_d512_fifo.soft_fifo_al_4057d6b76aa6_Inst.ram_inst.memory[0] !== make_word(480-bad_used))begin
                    failures=failures+1;
                    $display("FAIL first retained payload does not match dropped-prefix length");
                end
                bad_lost_total=bad_lost_total+(480-bad_used);
                $display("PASS expected defect phase=%0d ns submitted=480 retained=%0d lost=%0d",phase_ns,bad_used,480-bad_used);
            end else begin
                failures=failures+1;
                $display("FAIL expected 400 < retained < 480 phase=%0d retained=%0d",phase_ns,bad_used);
            end
            warm_reset;early_preamble(phase_ns);send_frame(0,phase_ns);sample_count(good_used);
            case_count=case_count+1;
            if(good_used==480)
                $display("PASS early preamble phase=%0d ns submitted=480 retained=480 lost=0",phase_ns);
            else begin
                failures=failures+1;
                $display("FAIL early preamble phase=%0d expected=480 retained=%0d",phase_ns,good_used);
            end
            if(dut.U_w128_d512_fifo.soft_fifo_al_4057d6b76aa6_Inst.ram_inst.memory[0] !== make_word(0))begin
                failures=failures+1;
                $display("FAIL early preamble first payload was not preserved");
            end
        end
        if(failures==0)begin
            $display("PASS tb_video_in_frame_preamble cases=%0d expected_defect_total_lost=%0d early_total_lost=0",case_count,bad_lost_total);
            $finish;
        end else $fatal(1,"FAIL tb_video_in_frame_preamble failures=%0d cases=%0d",failures,case_count);
    end
    initial begin #1000000;$fatal(1,"FAIL tb_video_in_frame_preamble timeout");end
endmodule
