// DDR frame reader. Reserve FIFO space for requests until their data returns.
// A frame switch drains and discards all old responses before FIFO reset.
module video_out (
 input wire I_rst_n,I_ddr_clk,
 output wire O_video_out_rd_busy,input wire I_video_in_wr_busy,
 input wire [1:0] I_video_out_rp,
 output wire O_ddr_user_rd_en,output reg [24:0] O_ddr_user_addr,
 input wire I_ddr_user_ready,I_ddr_user_rd_valid,
 input wire [127:0] I_ddr_user_rd_data,
 input wire I_dsi_clk,I_video_vsync,I_video_rd_en,
 output reg [23:0] O_vdieo_data
);
 wire ddr_reset_n;
 reset_sync u_reset_ddr(.clk(I_ddr_clk),.async_rst_n(I_rst_n),.rst_n(ddr_reset_n));
 localparam [1:0] RUN=0,DRAIN=1,RESET_FIFO=2,RELEASE_FIFO=3;
 reg [1:0] frame_state;
 reg S_fifo_rst;
 reg [4:0] reset_count;
 reg [24:0] next_frame_base;
 reg S_video_vsync_1d,S_video_vsync_2d,S_video_vsync_3d;
 wire S_video_frame_start=~S_video_vsync_3d&S_video_vsync_2d;
 reg S_ddr_rd_valid;
 reg [7:0] S_ddr_rd_cnt;
 reg [10:0] read_words_in_flight;
 wire [8:0] S_fifo_wr_num;
 wire [11:0] reserved_read_words={3'd0,S_fifo_wr_num}+{1'b0,read_words_in_flight};
 wire S_ddr_rd_trig=(frame_state==RUN)&&!S_fifo_rst&&ddr_reset_n&&
     !S_video_frame_start&&!I_video_in_wr_busy&&!S_ddr_rd_valid&&
     (reserved_read_words<=12'd211);
 // Retain 300 free slots for a 240-word burst, now INCLUDING outstanding words.
 assign O_ddr_user_rd_en=S_ddr_rd_valid&&I_ddr_user_ready&&
     (frame_state==RUN)&&!S_video_frame_start;
 assign O_video_out_rd_busy=S_ddr_rd_trig|S_ddr_rd_valid;
 function [24:0] frame_base;input [1:0] pointer;
 begin case(pointer)
  0:frame_base=25'd0;1:frame_base=25'd7000000;
  2:frame_base=25'd14000000;3:frame_base=25'd21000000;
 endcase end endfunction
 always @(posedge I_ddr_clk or negedge ddr_reset_n)begin
  if(!ddr_reset_n)begin
   S_video_vsync_1d<=0;S_video_vsync_2d<=0;S_video_vsync_3d<=0;
  end else begin
   S_video_vsync_1d<=I_video_vsync;
   S_video_vsync_2d<=S_video_vsync_1d;
   S_video_vsync_3d<=S_video_vsync_2d;
  end
 end
 always @(posedge I_ddr_clk or negedge ddr_reset_n)begin
  if(!ddr_reset_n)begin
   read_words_in_flight<=0;
  end else begin
   case({O_ddr_user_rd_en,I_ddr_user_rd_valid})
    2'b10:read_words_in_flight<=read_words_in_flight+1'b1;
    2'b01:if(read_words_in_flight!=0)read_words_in_flight<=read_words_in_flight-1'b1;
    default:read_words_in_flight<=read_words_in_flight;
   endcase
  end
 end
 always @(posedge I_ddr_clk or negedge ddr_reset_n)begin
  if(!ddr_reset_n)begin
   frame_state<=RESET_FIFO;S_fifo_rst<=1;reset_count<=0;
   next_frame_base<=0;O_ddr_user_addr<=0;
   S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;
  end else begin
   if(S_video_frame_start)next_frame_base<=frame_base(I_video_out_rp);
   case(frame_state)
    RUN:begin
     if(S_video_frame_start)begin
      // Stop issuing old-frame commands. Already accepted commands must drain.
      frame_state<=DRAIN;S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;
     end else if(S_ddr_rd_valid)begin
      if(O_ddr_user_rd_en)begin
       O_ddr_user_addr<=O_ddr_user_addr+25'd8;
       if(S_ddr_rd_cnt==8'd239)begin S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;end
       else S_ddr_rd_cnt<=S_ddr_rd_cnt+1'b1;
      end
     end else if(S_ddr_rd_trig)begin S_ddr_rd_valid<=1;S_ddr_rd_cnt<=0;end
    end
    DRAIN:begin
     if(read_words_in_flight==0&&!I_ddr_user_rd_valid)begin
      S_fifo_rst<=1;reset_count<=0;frame_state<=RESET_FIFO;
     end
    end
    RESET_FIFO:begin
     if(reset_count==5'd10)begin
      S_fifo_rst<=0;reset_count<=0;frame_state<=RELEASE_FIFO;
     end else reset_count<=reset_count+1'b1;
    end
    RELEASE_FIFO:begin
     // Allow both clock domains to release FIFO reset and synchronize pointers.
     if(reset_count==5'd8)begin
      O_ddr_user_addr<=S_video_frame_start?frame_base(I_video_out_rp):next_frame_base;
      frame_state<=RUN;reset_count<=0;
     end else reset_count<=reset_count+1'b1;
    end
    default:begin frame_state<=DRAIN;S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;end
   endcase
  end
 end
 wire [127:0] S_fifo_rd_data;
 wire S_fifo_empty;
 wire pixel_async_reset_n=I_rst_n&&!S_fifo_rst;
 (* async_reg="true" *) reg pixel_reset_sync1,pixel_reset_sync2;
 wire pixel_reset_n=pixel_reset_sync2;
 always @(posedge I_dsi_clk or negedge pixel_async_reset_n)begin
  if(!pixel_async_reset_n)begin pixel_reset_sync1<=0;pixel_reset_sync2<=0;end
  else begin pixel_reset_sync1<=1;pixel_reset_sync2<=pixel_reset_sync1;end
 end
 reg [3:0] S_fifo_rd_cnt,S_fifo_rd_cnt_1d;
 reg S_video_rd_en_1d;
 reg [127:0] S_fifo_rd_data_1d;
 reg read_underflow_latched;
 wire word_slot=(S_fifo_rd_cnt==0)||(S_fifo_rd_cnt==5)||(S_fifo_rd_cnt==10);
 wire S_fifo_rd_en=I_video_rd_en&&word_slot&&!read_underflow_latched&&pixel_reset_n;
 wire accept_return=I_ddr_user_rd_valid&&(frame_state==RUN)&&
     !S_video_frame_start&&!S_fifo_rst&&(read_words_in_flight!=0);
 w128_d512_fifo U_w128_d512_fifo(
  .rst(S_fifo_rst),.clkw(I_ddr_clk),.we(accept_return),.di(I_ddr_user_rd_data),
  .wrusedw(S_fifo_wr_num),.afull(),.full_flag(),.clkr(I_dsi_clk),
  .re(S_fifo_rd_en),.dout(S_fifo_rd_data),.rdusedw(),.valid(),
  .empty_flag(S_fifo_empty),.aempty());
 always @(posedge I_dsi_clk or negedge pixel_reset_n)begin
  if(!pixel_reset_n)begin
   S_fifo_rd_cnt<=0;read_underflow_latched<=0;
  end else begin
   if(I_video_rd_en)S_fifo_rd_cnt<=S_fifo_rd_cnt+1'b1;else S_fifo_rd_cnt<=0;
   // HDMI cannot stall. A lost 128-bit word changes RGB byte phase; blank the
   // remainder of this frame instead of emitting misaligned rainbow pixels.
   if(S_fifo_rd_en&&S_fifo_empty)read_underflow_latched<=1;
  end
 end
 always @(posedge I_dsi_clk or negedge pixel_reset_n)begin
  if(!pixel_reset_n)begin
   S_video_rd_en_1d<=0;S_fifo_rd_cnt_1d<=0;S_fifo_rd_data_1d<=0;O_vdieo_data<=0;
  end else begin
   S_video_rd_en_1d<=I_video_rd_en;
   S_fifo_rd_cnt_1d<=S_fifo_rd_cnt;
   S_fifo_rd_data_1d<=S_fifo_rd_data;
   if(read_underflow_latched||(S_fifo_rd_en&&S_fifo_empty)||!S_video_rd_en_1d)O_vdieo_data<=0;
   else case(S_fifo_rd_cnt_1d)
    0:O_vdieo_data<=S_fifo_rd_data[127:104];
    1:O_vdieo_data<=S_fifo_rd_data[103:80];
    2:O_vdieo_data<=S_fifo_rd_data[79:56];
    3:O_vdieo_data<=S_fifo_rd_data[55:32];
    4:O_vdieo_data<=S_fifo_rd_data[31:8];
    5:O_vdieo_data<={S_fifo_rd_data_1d[7:0],S_fifo_rd_data[127:112]};
    6:O_vdieo_data<=S_fifo_rd_data[111:88];
    7:O_vdieo_data<=S_fifo_rd_data[87:64];
    8:O_vdieo_data<=S_fifo_rd_data[63:40];
    9:O_vdieo_data<=S_fifo_rd_data[39:16];
    10:O_vdieo_data<={S_fifo_rd_data_1d[15:0],S_fifo_rd_data[127:120]};
    11:O_vdieo_data<=S_fifo_rd_data[119:96];
    12:O_vdieo_data<=S_fifo_rd_data[95:72];
    13:O_vdieo_data<=S_fifo_rd_data[71:48];
    14:O_vdieo_data<=S_fifo_rd_data[47:24];
    15:O_vdieo_data<=S_fifo_rd_data[23:0];
   endcase
  end
 end
endmodule
