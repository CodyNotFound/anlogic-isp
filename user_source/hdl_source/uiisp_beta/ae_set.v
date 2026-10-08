/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

module ae_set
(
input wire I_clk,
input wire I_rst,
input wire [3:0]I_btn,
input wire I_ae_cfg_done,
input wire I_cam_cfg_done,
input wire I_auto_enable,
input wire [7:0] I_luma_avg,
input wire I_luma_valid,
output wire O_ae_req,
output wire [15:0] O_ae,
output wire [15:0] O_ag
);
	

reg 	[19:0] 	rc_ae_tick = 0; 
reg 			r_ae_tick = 0; 
reg 	[4:0] 	rc_ag_tick = 0; 
reg 			r_ag_tick = 0; 
	
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		rc_ae_tick <= 0; 
		r_ae_tick <= 0; 
		rc_ag_tick <= 0; 
		r_ag_tick <= 0; 
	end else begin
	//	Trigger AE Inc / Dec per 1 ms. 
		rc_ae_tick <= rc_ae_tick + 1; 
		r_ae_tick <= 0; 
		if(rc_ae_tick >= 99999) begin
			rc_ae_tick <= 0; 
			r_ae_tick <= 1; 
		end 
	//	Trigger AG Inc / Dec per 32 ms. 
		rc_ag_tick <= rc_ag_tick + r_ae_tick; 
		r_ag_tick <= (&rc_ag_tick) && r_ae_tick; 
	end
end
	
//	Use button to add / sub idelay values. I_button[0]:IncDatDly, [1]DecDatDly, [2]IncI_clkDly, [3]DecI_clkDly
reg 	[3:0] 	r_button_0 = 0, r_button_1 = 0; 
// HD 60 fps mode uses VTS=1000.  Exposure 1990 is about 995 lines
// (half-line units), already close to the legal maximum.  AG=48 maps through
// SC500GainTbl to 0x0f20, approximately 4x analogue gain.
reg 	[15:0] 	r_ae_set = 1990, r_ag_set = 80; 
reg         r_auto_was_enabled = 1'b0;
reg [3:0]   r_auto_cooldown = 4'd0;

localparam [15:0] AE_MIN = 16'd2;
localparam [15:0] AE_MAX = 16'd1990;
localparam [15:0] AG_MIN = 16'd16;
localparam [15:0] AG_MAX = 16'd89;
localparam [15:0] AE_STEP = 16'd32;
localparam [15:0] AG_STEP = 16'd2;
localparam [7:0]  TARGET_LOW = 8'd128;
localparam [7:0]  TARGET_HIGH = 8'd160;
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_button_0 <= 0; 
		r_button_1 <= 0; 
		r_ae_set <= 1990; 
		r_ag_set <= 80; 
		r_auto_was_enabled <= 1'b0;
		r_auto_cooldown <= 4'd0;
	end else begin
	//	When button pressed, r_button_1 bit is 1. 
		r_button_0 <= ~I_btn; 
		r_button_1 <= r_button_0; 

		if (I_auto_enable) begin
			r_auto_was_enabled <= 1'b1;
			// The cooldown is measured in received frame-statistic events,
			// not in 24 MHz clock cycles.
			if (I_luma_valid && (r_auto_cooldown != 0))
				r_auto_cooldown <= r_auto_cooldown - 1'b1;
			else if (I_luma_valid) begin
				// Dark scene: increase integration time first, then analogue gain.
				if (I_luma_avg < TARGET_LOW) begin
					if (r_ae_set < AE_MAX) begin
						if (r_ae_set <= (AE_MAX - AE_STEP))
							r_ae_set <= r_ae_set + AE_STEP;
						else
							r_ae_set <= AE_MAX;
					end else if (r_ag_set < AG_MAX) begin
						if (r_ag_set <= (AG_MAX - AG_STEP))
							r_ag_set <= r_ag_set + AG_STEP;
						else
							r_ag_set <= AG_MAX;
					end
					r_auto_cooldown <= 4'd8;
				// Bright scene: remove analogue gain first, then shorten exposure.
				end else if (I_luma_avg > TARGET_HIGH) begin
					if (r_ag_set > AG_MIN) begin
						if (r_ag_set >= (AG_MIN + AG_STEP))
							r_ag_set <= r_ag_set - AG_STEP;
						else
							r_ag_set <= AG_MIN;
					end else if (r_ae_set > AE_MIN) begin
						if (r_ae_set >= (AE_MIN + AE_STEP))
							r_ae_set <= r_ae_set - AE_STEP;
						else
							r_ae_set <= AE_MIN;
					end
					r_auto_cooldown <= 4'd8;
				end
			end
		end else begin
			r_auto_was_enabled <= 1'b0;
			r_auto_cooldown <= 4'd0;
			// Restore the known platform baseline on the switch-off edge.
			if (r_auto_was_enabled) begin
				r_ae_set <= AE_MAX;
				r_ag_set <= 16'd80;
			end else begin
				if(r_button_1[0]) begin
					r_ae_set <= (r_ae_set > AE_MIN) ? r_ae_set - r_ae_tick : r_ae_set;
				end else if(r_button_1[1]) begin
					r_ae_set <= (r_ae_set < AE_MAX) ? r_ae_set + r_ae_tick : r_ae_set;
				end
				if(r_button_1[2]) begin
					r_ag_set <= (r_ag_set > AG_MIN) ? r_ag_set - r_ag_tick : r_ag_set;
				end else if(r_button_1[3]) begin
					r_ag_set <= (r_ag_set < AG_MAX) ? r_ag_set + r_ag_tick : r_ag_set;
				end
			end
		end
	end
	end
	
//	Update AG / AE when changed. 
reg 	[15:0] 	r_ae ; 
reg 	[15:0] 	r_ag ; 
reg 			r_ae_req = 0; //synthesis keep
assign O_ae = r_ae;
assign O_ag = r_ag;
assign O_ae_req = r_ae_req;

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_ae_req <= 0; 
		r_ae     <= 1990; 
		r_ag     <= 80; 
	end else if(r_ae_req) begin
		r_ae_req <= 0; 
	end else if(((r_ae != r_ae_set) || (r_ag != r_ag_set))&&(I_cam_cfg_done==1'b1)&&(I_ae_cfg_done==1'b1)) begin
		r_ae     <= r_ae_set; 
		r_ag     <= r_ag_set; 
		r_ae_req <= 1; 
	end
end


endmodule


	
