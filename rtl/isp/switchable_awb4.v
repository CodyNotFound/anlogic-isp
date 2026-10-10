// ON and OFF share the same data pipeline. OFF freezes current white balance.
module switchable_awb4 #(
 parameter ENABLE=1,INIT_R_Q8=522,INIT_B_Q8=421,
 MIN_SAMPLES=4096,GAIN_MIN=128,GAIN_MAX=768
)(
 input wire I_clk,I_rst_n,I_enable,I_bypass,I_tvalid,I_tuser,I_tlast,
 input wire [95:0] I_tdata,output wire I_tready,
 input wire O_tready,output wire O_tvalid,O_tuser,O_tlast,
 output wire [95:0] O_tdata
);
 (* async_reg="true" *) reg enable_sync1,enable_sync2;
 reg frame_auto_enable;
 wire accepted_sof=I_tvalid&&O_tready&&I_tuser;
 wire auto_enable=(I_tvalid&&I_tuser)?enable_sync2:frame_auto_enable;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   enable_sync1<=1'b1;enable_sync2<=1'b1;frame_auto_enable<=1'b1;
  end else begin
   enable_sync1<=I_enable;enable_sync2<=enable_sync1;
   if(accepted_sof)frame_auto_enable<=enable_sync2;
  end
 end
 frame_awb4 #(.ENABLE(ENABLE),.INIT_R_Q8(INIT_R_Q8),.INIT_B_Q8(INIT_B_Q8),
  .MIN_SAMPLES(MIN_SAMPLES),.GAIN_MIN(GAIN_MIN),.GAIN_MAX(GAIN_MAX)) u_frame_awb4(
  .I_clk(I_clk),.I_rst_n(I_rst_n),.I_auto_enable(auto_enable),.I_bypass(I_bypass),
  .I_tvalid(I_tvalid),.I_tuser(I_tuser),.I_tlast(I_tlast),.I_tdata(I_tdata),
  .I_tready(I_tready),.O_tready(O_tready),.O_tvalid(O_tvalid),
  .O_tuser(O_tuser),.O_tlast(O_tlast),.O_tdata(O_tdata));
endmodule
