`timescale 1ns/1ps
module tb_switchable_awb4;
 reg clk=0,rst_n=0,enable=1,in_valid=0,in_user=0,in_last=0,out_ready=1;
 reg [95:0] in_data=0;
 wire in_ready,out_valid,out_user,out_last,bypass_in_ready,bypass_out_valid,bypass_out_user,bypass_out_last;
 wire [95:0] out_data,bypass_out_data;
 reg ref_sync1,ref_sync2,ref_frame_enable,ref_selected_enable;
 reg ref_valid_s1,ref_valid_s2,ref_user_s1,ref_user_s2,ref_last_s1,ref_last_s2;
 reg [95:0] ref_data_s1,ref_data_s2,ref_raw_s1,ref_raw_s2;
 reg [98:0] previous_output,previous_bypass_output;
 reg have_previous;
 integer checks=0,accepted_on=0,accepted_off=0,stalled_cycles=0;
 localparam [95:0] TEST_DATA={8'd40,8'd80,8'd60,8'd30,8'd80,8'd60,8'd20,8'd80,8'd60,8'd10,8'd80,8'd60};
 always #5 clk=~clk;
 switchable_awb4 #(.ENABLE(1),.INIT_R_Q8(512),.INIT_B_Q8(256),.MIN_SAMPLES(1000000)) dut (
 .I_bypass(1'b0),.I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_tvalid(in_valid),.I_tuser(in_user),.I_tlast(in_last),
 .I_tdata(in_data),.I_tready(in_ready),.O_tready(out_ready),.O_tvalid(out_valid),.O_tuser(out_user),.O_tlast(out_last),.O_tdata(out_data));
 switchable_awb4 #(.ENABLE(0),.INIT_R_Q8(512),.INIT_B_Q8(256),.MIN_SAMPLES(1000000)) dut_disabled (
 .I_bypass(1'b0),.I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_tvalid(in_valid),.I_tuser(in_user),.I_tlast(in_last),
 .I_tdata(in_data),.I_tready(bypass_in_ready),.O_tready(out_ready),.O_tvalid(bypass_out_valid),
 .O_tuser(bypass_out_user),.O_tlast(bypass_out_last),.O_tdata(bypass_out_data));
 function [95:0] apply_fixed_awb;input [95:0] value;integer lane;reg [95:0] result;reg [7:0] red;
 begin result=value;for(lane=0;lane<4;lane=lane+1)begin
 red=value[lane*24+16+:8];result[lane*24+16+:8]=red<<1;end apply_fixed_awb=result;end endfunction
 always @(posedge clk)begin
 if(!rst_n)begin
 ref_sync1=1;ref_sync2=1;ref_frame_enable=1;ref_selected_enable=0;
 ref_valid_s1=0;ref_valid_s2=0;ref_user_s1=0;ref_user_s2=0;ref_last_s1=0;ref_last_s2=0;
 ref_data_s1=0;ref_data_s2=0;ref_raw_s1=0;ref_raw_s2=0;
 previous_output=0;previous_bypass_output=0;have_previous=0;
 end else begin
 if(out_ready)begin
 ref_selected_enable=(in_valid&&in_user)?ref_sync2:ref_frame_enable;
 ref_valid_s2=ref_valid_s1;ref_user_s2=ref_user_s1;ref_last_s2=ref_last_s1;
 ref_data_s2=ref_data_s1;ref_raw_s2=ref_raw_s1;
 ref_valid_s1=in_valid;ref_user_s1=in_user;ref_last_s1=in_last;ref_raw_s1=in_data;
 ref_data_s1=apply_fixed_awb(in_data);
 if(in_valid)begin if(ref_selected_enable)accepted_on=accepted_on+1;else accepted_off=accepted_off+1;end
 if(in_valid&&in_user)ref_frame_enable=ref_sync2;
 end else stalled_cycles=stalled_cycles+1;
 ref_sync2=ref_sync1;ref_sync1=enable;#1;
 if(in_ready!==out_ready||bypass_in_ready!==out_ready)$fatal(1,"Ready mismatch");
 if(out_valid!==ref_valid_s2||bypass_out_valid!==ref_valid_s2)$fatal(1,"Valid mismatch");
 if({out_user,out_last}!=={ref_user_s2,ref_last_s2}||{bypass_out_user,bypass_out_last}!=={ref_user_s2,ref_last_s2})$fatal(1,"Metadata mismatch");
 if(ref_valid_s2)begin
 if(out_data!==ref_data_s2)$fatal(1,"AWB data expected=%h actual=%h",ref_data_s2,out_data);
 if(bypass_out_data!==ref_raw_s2)$fatal(1,"ENABLE=0 data mismatch");end
 if(!out_ready&&have_previous)begin
 if({out_valid,out_user,out_last,out_data}!==previous_output)$fatal(1,"AWB output changed during stall");
 if({bypass_out_valid,bypass_out_user,bypass_out_last,bypass_out_data}!==previous_bypass_output)$fatal(1,"Bypass changed during stall");end
 previous_output={out_valid,out_user,out_last,out_data};
 previous_bypass_output={bypass_out_valid,bypass_out_user,bypass_out_last,bypass_out_data};
 have_previous=1;checks=checks+1;
 end end
 task beat;input valid_value,user_value,last_value,ready_value,enable_value;
 begin @(negedge clk);in_valid=valid_value;in_user=user_value;in_last=last_value;
 in_data=TEST_DATA;out_ready=ready_value;enable=enable_value;@(posedge clk);#2;end endtask
 task idle;input integer cycles;input enable_value;integer cycle_index;
 begin for(cycle_index=0;cycle_index<cycles;cycle_index=cycle_index+1)beat(0,0,0,1,enable_value);end endtask
 initial begin
 repeat(4)@(negedge clk);rst_n=1;idle(4,1);
 beat(1,1,0,1,1);beat(1,0,0,1,1);
 beat(1,0,0,1,0);beat(1,0,0,1,0);beat(1,0,0,1,0);beat(1,0,1,1,0);
 beat(1,1,0,1,0);beat(1,0,0,1,0);
 beat(1,0,0,1,1);beat(1,0,0,1,1);beat(1,0,0,1,1);beat(1,0,1,1,1);
 beat(1,1,0,1,1);beat(1,0,1,1,1);
 beat(1,1,0,0,0);beat(1,1,0,0,0);beat(1,1,0,0,0);beat(1,1,0,0,0);
 beat(1,1,0,1,0);beat(1,0,1,1,0);
 beat(1,1,0,0,1);beat(1,1,0,0,1);beat(1,1,0,0,1);beat(1,1,0,0,1);
 beat(1,1,0,1,1);beat(1,0,0,1,1);
 beat(1,0,1,0,0);beat(1,0,1,0,0);beat(1,0,1,1,0);idle(6,0);
 if(checks<40||accepted_on==0||accepted_off==0||stalled_cycles<10)$fatal(1,"Coverage not reached");
 $display("PASS tb_switchable_awb4 checks=%0d on=%0d off=%0d stalls=%0d",checks,accepted_on,accepted_off,stalled_cycles);$finish;
 end
 initial begin #10000;$fatal(1,"Timeout");end
endmodule
