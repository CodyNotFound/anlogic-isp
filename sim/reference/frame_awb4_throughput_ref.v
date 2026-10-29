`timescale 1ns/1ps
module frame_awb4_throughput_ref #(parameter ENABLE=1,INIT_R_Q8=522,INIT_B_Q8=421,MIN_SAMPLES=4096,GAIN_MIN=128,GAIN_MAX=768)(
 input wire I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,I_auto_enable,I_bypass,input wire [95:0] I_tdata,
 output wire I_tready,input wire O_tready,output wire O_tvalid,O_tuser,O_tlast,output wire [95:0] O_tdata);
 // I_bypass: 帧首锁存, 锁存期间R/B增益强制256(Q8=1.0), 统计照常但不影响输出
 reg bypass_f;
 localparam [1:0] DIV_IDLE=0,DIV_R=1,DIV_B=2;
 reg [9:0] gain_r_q8,gain_b_q8,pending_r_q8,pending_b_q8;reg pending_valid;
 reg [31:0] sum_r,sum_g,sum_b;reg [21:0] sample_count;
 reg [1:0] div_state;reg [5:0] div_count;reg [39:0] div_quotient,saved_numerator;
 reg [32:0] div_remainder;reg [31:0] div_denominator,saved_b_sum;
 reg [9:0] saved_gain_r,saved_gain_b,calculated_r;
 reg stage1_valid,stage1_user,stage1_last,stage2_valid,stage2_user,stage2_last;
 reg [95:0] stage1_data,stage2_data;
 // Runtime OFF freezes adaptation and keeps white balance applied.
 wire commit_pending=I_tvalid&&I_tuser&&pending_valid&&I_auto_enable;
 wire [9:0] effective_r=commit_pending?pending_r_q8:gain_r_q8;
 wire [9:0] effective_b=commit_pending?pending_b_q8:gain_b_q8;
 assign I_tready=O_tready;assign O_tvalid=stage2_valid;assign O_tuser=stage2_user;
 assign O_tlast=stage2_last;assign O_tdata=stage2_data;
 function [9:0] filtered_gain;input [39:0] ratio;input [9:0] previous;
 integer target,difference,step,result;
 begin if(ratio<GAIN_MIN)target=GAIN_MIN;else if(ratio>GAIN_MAX)target=GAIN_MAX;else target=ratio[9:0];
 difference=target-previous;
 // Sensor noise around yellow areas otherwise makes R/B gains oscillate every
 // frame. Hold tiny corrections, and move by at most 2/256 per published frame.
 if(difference>-5 && difference<5)begin result=previous; end
 else begin
  if(difference>2)step=2;else if(difference<-2)step=-2;else step=difference;
  result=previous+step;
 end
 if(result<GAIN_MIN)result=GAIN_MIN;else if(result>GAIN_MAX)result=GAIN_MAX;
 filtered_gain=result[9:0];end endfunction
 reg [11:0] beat_sum_r,beat_sum_g,beat_sum_b;reg [2:0] beat_count;
 integer pixel_index;reg [7:0] candidate_r,candidate_g,candidate_b;
 reg [17:0] corrected_r_q8[0:3],corrected_b_q8[0:3];reg [17:0] lower_bound_q8,upper_bound_q8;
 function [7:0] clip_gain;input [17:0] product;
 begin clip_gain=(product[17:8]>255)?8'd255:product[15:8];end endfunction
 wire [95:0] effective_data={
  clip_gain(I_tdata[95:88]*effective_r),I_tdata[87:80],clip_gain(I_tdata[79:72]*effective_b),
  clip_gain(I_tdata[71:64]*effective_r),I_tdata[63:56],clip_gain(I_tdata[55:48]*effective_b),
  clip_gain(I_tdata[47:40]*effective_r),I_tdata[39:32],clip_gain(I_tdata[31:24]*effective_b),
  clip_gain(I_tdata[23:16]*effective_r),I_tdata[15:8],clip_gain(I_tdata[7:0]*effective_b)};
 always @* begin
 beat_sum_r=0;beat_sum_g=0;beat_sum_b=0;beat_count=0;
 for(pixel_index=0;pixel_index<4;pixel_index=pixel_index+1)begin corrected_r_q8[pixel_index]=0;corrected_b_q8[pixel_index]=0;end candidate_r=0;candidate_g=0;candidate_b=0;lower_bound_q8=0;upper_bound_q8=0;
 for(pixel_index=0;pixel_index<4;pixel_index=pixel_index+1)begin
 candidate_r=I_tdata[pixel_index*24+16+:8];candidate_g=I_tdata[pixel_index*24+8+:8];candidate_b=I_tdata[pixel_index*24+:8];
 corrected_r_q8[pixel_index]=candidate_r*effective_r;corrected_b_q8[pixel_index]=candidate_b*effective_b;
 lower_bound_q8={10'd0,candidate_g}*18'd192;upper_bound_q8={10'd0,candidate_g}*18'd320;
 if(ENABLE!=0&&candidate_g>=12&&candidate_r<240&&candidate_g<240&&candidate_b<240&&
 corrected_r_q8[pixel_index]<61440&&corrected_b_q8[pixel_index]<61440&&corrected_r_q8[pixel_index]>=lower_bound_q8&&corrected_r_q8[pixel_index]<=upper_bound_q8&&
 corrected_b_q8[pixel_index]>=lower_bound_q8&&corrected_b_q8[pixel_index]<=upper_bound_q8)begin
 beat_sum_r=beat_sum_r+{4'd0,candidate_r};beat_sum_g=beat_sum_g+{4'd0,candidate_g};
 beat_sum_b=beat_sum_b+{4'd0,candidate_b};beat_count=beat_count+3'd1;end end end
 wire [32:0] trial_remainder={div_remainder[31:0],div_quotient[39]};
 wire quotient_bit=trial_remainder>={1'b0,div_denominator};
 wire [32:0] next_remainder=quotient_bit?trial_remainder-{1'b0,div_denominator}:trial_remainder;
 wire [39:0] next_quotient={div_quotient[38:0],quotient_bit};
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin bypass_f<=0; stage1_valid<=0;stage1_user<=0;stage1_last<=0;stage1_data<=0;
 stage2_valid<=0;stage2_user<=0;stage2_last<=0;stage2_data<=0;end
 else if(O_tready)begin
 if(I_tvalid&&I_tuser)bypass_f<=I_bypass;
 stage2_valid<=stage1_valid;stage2_user<=stage1_user;stage2_last<=stage1_last;stage2_data<=stage1_data;
 stage1_valid<=I_tvalid;stage1_user<=I_tuser;stage1_last<=I_tlast;
 if(ENABLE!=0)stage1_data<=bypass_f?I_tdata:effective_data;
 else stage1_data<=I_tdata;end end
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 gain_r_q8<=INIT_R_Q8;gain_b_q8<=INIT_B_Q8;pending_r_q8<=INIT_R_Q8;pending_b_q8<=INIT_B_Q8;pending_valid<=0;
 sum_r<=0;sum_g<=0;sum_b<=0;sample_count<=0;div_state<=DIV_IDLE;div_count<=0;div_quotient<=0;
 div_remainder<=0;div_denominator<=0;saved_numerator<=0;saved_b_sum<=0;
 saved_gain_r<=INIT_R_Q8;saved_gain_b<=INIT_B_Q8;calculated_r<=INIT_R_Q8;
 end else if(ENABLE!=0&&I_auto_enable)begin
 if(I_tvalid&&O_tready)begin
 if(I_tuser)begin
 sum_r<={20'd0,beat_sum_r};sum_g<={20'd0,beat_sum_g};sum_b<={20'd0,beat_sum_b};sample_count<={19'd0,beat_count};
 if(pending_valid)begin gain_r_q8<=pending_r_q8;gain_b_q8<=pending_b_q8;pending_valid<=0;end
 if(div_state==DIV_IDLE&&sample_count>=MIN_SAMPLES&&sum_r!=0&&sum_b!=0&&sum_g!=0)begin
 saved_numerator<={sum_g,8'd0};saved_b_sum<=sum_b;saved_gain_r<=effective_r;saved_gain_b<=effective_b;
 div_quotient<={sum_g,8'd0};div_remainder<=0;div_denominator<=sum_r;div_count<=0;div_state<=DIV_R;end
 end else begin sum_r<=sum_r+{20'd0,beat_sum_r};sum_g<=sum_g+{20'd0,beat_sum_g};sum_b<=sum_b+{20'd0,beat_sum_b};
 sample_count<=sample_count+{19'd0,beat_count};end end
 case(div_state)
 DIV_R:begin if(div_count==39)begin calculated_r<=filtered_gain(next_quotient,saved_gain_r);
 div_quotient<=saved_numerator;div_remainder<=0;div_denominator<=saved_b_sum;div_count<=0;div_state<=DIV_B;
 end else begin div_quotient<=next_quotient;div_remainder<=next_remainder;div_count<=div_count+6'd1;end end
 DIV_B:begin if(div_count==39)begin pending_r_q8<=calculated_r;pending_b_q8<=filtered_gain(next_quotient,saved_gain_b);
 pending_valid<=1;div_state<=DIV_IDLE;div_count<=0;
 end else begin div_quotient<=next_quotient;div_remainder<=next_remainder;div_count<=div_count+6'd1;end end
 default:begin end
 endcase
 end else if(ENABLE!=0)begin
 // Drop stale estimates without resetting the last applied gains.
 sum_r<=0;sum_g<=0;sum_b<=0;sample_count<=0;
 pending_valid<=0;div_state<=DIV_IDLE;div_count<=0;
 end end
endmodule
