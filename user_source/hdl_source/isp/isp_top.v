`timescale 1ns/1ps
module isp_top #(parameter integer ENABLE_LSC=1,ENABLE_AWB=1,ENABLE_COLOR=1,BLACK_LEVEL=67,SAT_Q8=384,IMG_HEIGHT=720,IMG_WIDTH=1280)(
 input wire axi4s_video_aclk,I_rst_n,I_tlast,I_tuser,I_awb_enable,input wire [3:0] I_isp_demo,input wire [39:0] I_tdata,input wire I_tvalid,
 input wire [9:0] I_tdest,input wire O_tready,output wire [127:0] O_tdata,
 output wire O_tlast,O_tuser,O_tvalid,I_tready);
 // I_isp_demo = {demo_active, step[2:0]} 来自HDMI像素域(准静态): 2FF同步后,
 // 各处理模块在自己入口的tuser拍锁存各自使能(从demo_s2组合推导, tuser拍早已稳定,
 // 避免isp级再锁存一层造成的一帧延迟竞态)。
 // 分步语义(演示模式, 6步): 0=原图(去马赛克开+全矫正关, 整体偏绿+暗角) 1=+BLC
 //                          2=+AWB(全局绿被拉平, 露出"中间绿两边品红"渐变=例程同款中间态)
 //                          3=+LSC(边缘渐变+暗角消失) 4=+sRGB色调+去紫边 5=+饱和(全开) ;
 // 正常模式(demo_active=0)恒为全开(step=5)。灰度拜耳旁路保留RTL能力但当前演示不使用。
 (* async_reg = "true" *) reg [3:0] demo_s1,demo_s2;
 always @(posedge axi4s_video_aclk or negedge I_rst_n)begin
  if(!I_rst_n)begin demo_s1<=4'h5;demo_s2<=4'h5;end
  else begin
   demo_s1<=I_isp_demo;demo_s2<=demo_s1;
  end
 end
 wire demo_on  = demo_s2[3];
 wire [2:0] dstep = demo_s2[2:0];
 wire [2:0] eff_step = demo_on ? dstep : 3'd5;      // 正常模式=全链
 wire dem_gray   = 1'b0;                            // 灰度拜耳演示当前关闭(原图直接显示彩色偏色)
 wire blc_on     = (eff_step>=3'd1);
 wire awb_on     = (eff_step>=3'd2);                // AWB先于LSC解锁: step2呈现"例程同款"中间态画面
 wire lsc_on     = (eff_step>=3'd3);
 wire tone_on    = (eff_step>=3'd4);
 wire sat_on     = (eff_step>=3'd5);
 // 演示步4起强制AWB自适应(无视SW2), 避免SW2在关侧时增益冻在INIT值翻车
 wire awb_auto   = I_awb_enable || (demo_on && awb_on);
 wire [39:0] lsc_data;wire [9:0] lsc_dest;wire lsc_valid,lsc_user,lsc_last,lsc_ready;
 raw_lsc_grid4 #(.ENABLE(ENABLE_LSC),.BLACK_LEVEL(BLACK_LEVEL)) u_raw_lsc_grid4(
 .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_tvalid(I_tvalid),.I_tuser(I_tuser),.I_tlast(I_tlast),.I_blc_on(blc_on),.I_lsc_on(lsc_on),
 .I_tdata(I_tdata),.I_tdest(I_tdest),.O_tready(lsc_ready),.I_tready(I_tready),
 .O_tvalid(lsc_valid),.O_tuser(lsc_user),.O_tlast(lsc_last),.O_tdata(lsc_data),.O_tdest(lsc_dest));
 wire [95:0] demosaic_data;wire demosaic_valid,demosaic_user,demosaic_last,demosaic_ready;
 demosaic #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH),.data_complete_delay(50),.BAYER_MODE("BGGR")) u_demosaic(
 .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.axi4s_video_tdata(lsc_data),.axi4s_video_tdest(lsc_dest),
 .axi4s_video_tlast(lsc_last),.axi4s_video_tvalid(lsc_valid),.axi4s_video_tuser(lsc_user),.axi4s_video_tready(lsc_ready),
 .O_tlast(demosaic_last),.O_tuser(demosaic_user),.O_tdata(demosaic_data),.O_tvalid(demosaic_valid),.O_tready(demosaic_ready),
 .I_gray_bypass(dem_gray));
 wire [95:0] demosaic_rgb;
 assign demosaic_rgb=demosaic_data;
 wire [95:0] awb_data;wire awb_valid,awb_user,awb_last,awb_ready;
 switchable_awb4 #(.ENABLE(ENABLE_AWB),.INIT_R_Q8(522),.INIT_B_Q8(421),.MIN_SAMPLES(4096),.GAIN_MIN(128),.GAIN_MAX(768)) u_frame_awb4(.I_enable(awb_auto),.I_bypass(!awb_on),
 .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_tvalid(demosaic_valid),.I_tuser(demosaic_user),.I_tlast(demosaic_last),
 .I_tdata(demosaic_rgb),.O_tready(awb_ready),.I_tready(demosaic_ready),
 .O_tvalid(awb_valid),.O_tuser(awb_user),.O_tlast(awb_last),.O_tdata(awb_data));
 wire [95:0] color_data;wire color_valid,color_user,color_last;
 color_tone4 #(.ENABLE(ENABLE_COLOR),.SAT_Q8(SAT_Q8),.DEFRINGE_ENABLE(1),.TONE_ENABLE(1)) u_color_tone4(
 .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_tvalid(awb_valid),.I_tuser(awb_user),.I_tlast(awb_last),.I_tdata(awb_data),.I_sat_on(sat_on),.I_tone_on(tone_on),
 .O_tready(O_tready),.I_tready(awb_ready),.O_tvalid(color_valid),.O_tuser(color_user),.O_tlast(color_last),.O_tdata(color_data));
 // Legacy packer cannot stall outputs: continuous downstream ready is required.
 wire converter_input_valid=color_valid&&O_tready;
 wire converter_input_user=color_user&&converter_input_valid;
 wire packer_user;
 // Demosaic/ISP lanes are x0 in [23:0] through x3 in [95:72].
 // The byte-stream packer consumes the most significant byte first.
 wire [95:0] packer_pixels={color_data[23:0],color_data[47:24],color_data[71:48],color_data[95:72]};
 data_96bit_to_128bit u_data_96bit_to_128bit(.I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
 .I_96b_frame_start(converter_input_user),.I_96b_valid(converter_input_valid),.I_96b_data(packer_pixels),
 .O_128b_frame_start(packer_user),.O_128b_valid(O_tvalid),.O_128b_data(O_tdata));
 // Legacy video_in frame-reset preamble, not first-output-data sideband.
 assign O_tuser=I_tvalid&&I_tuser;
 reg [7:0] output_word_count;
 assign O_tlast=O_tvalid&&(output_word_count==8'd239);
 always @(posedge axi4s_video_aclk or negedge I_rst_n)begin
 if(!I_rst_n)output_word_count<=0;
 else if(O_tuser)output_word_count<=0;
 else if(O_tvalid)output_word_count<=(output_word_count==8'd239)?8'd0:output_word_count+8'd1;
 end
endmodule
