module raw_matrix_3x3_buffer #(
 parameter integer IMG_HEIGHT=720,IMG_WIDTH=1280,data_complete_delay=50
)(
 input wire I_clk,I_rst_n,
 input wire [39:0] axi4s_video_tdata,input wire [9:0] axi4s_video_tdest,
 input wire axi4s_video_tlast,axi4s_video_tvalid,axi4s_video_tuser,
 output wire axi4s_video_tready,
 output reg O_tlast,O_tuser,O_tvalid,input wire O_tready,
 output reg bayer_ypos,
 output reg [95:0] matrix_last_line,matrix_cur_line,matrix_next_line
);
 function integer count_width;input integer count;integer value;
 begin value=count-1;count_width=0;while(value>0)begin count_width=count_width+1;value=value>>1;end
 if(count_width<1)count_width=1;end endfunction
 localparam integer WORDS_PER_ROW=IMG_WIDTH/4,H_WIDTH=count_width(WORDS_PER_ROW),V_WIDTH=count_width(IMG_HEIGHT+1);
 wire converter_ready,converted_last,converted_valid,converted_user;
 wire [31:0] converted_data,zh_data;
 wire zh_last,zh_valid,zh_user;
 assign axi4s_video_tready=O_tready;
 mipi_to_raw_converter u_mipi_to_raw_converter(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_raw_tdata(axi4s_video_tdata),.I_raw_tdest(axi4s_video_tdest),
 .I_raw_tlast(axi4s_video_tlast),.I_raw_tvalid(axi4s_video_tvalid),.I_raw_tuser(axi4s_video_tuser),
 .I_raw_tready(converter_ready),.O_raw_tdata(converted_data),.O_raw_tlast(converted_last),
 .O_raw_tvalid(converted_valid),.O_raw_tuser(converted_user),.O_raw_tready(O_tready));
 zhenghe #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.DATA_WIDTH(32),.data_complete_delay(data_complete_delay)) u_zhenghe(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tlast(converted_last),.I_tuser(converted_user),
 .I_tdata(converted_data),.I_tvalid(converted_valid),.O_tlast(zh_last),.O_tuser(zh_user),.O_tdata(zh_data),.O_tvalid(zh_valid));
 reg [V_WIDTH-1:0] real_row;
 reg [19:0] flush_wait;
 reg [19:0] line_period_count;
 reg line_end_seen;
 reg flush_active;
 reg [H_WIDTH-1:0] flush_word;
 wire source_valid=zh_valid|flush_active;
 wire source_user=zh_valid&zh_user;
 wire [31:0] source_data=zh_valid?zh_data:32'd0;
 wire [32:0] line_data0={source_user,source_data};
 // Preserve the measured line cadence for the synthesized bottom row.
 // A fixed eight-clock gap compressed the final two rows into one burst.
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin line_period_count<=0;line_end_seen<=0;end
  else if(zh_valid&&zh_user)begin line_period_count<=0;line_end_seen<=0;end
  else if(zh_valid&&zh_last)begin line_period_count<=0;line_end_seen<=1;end
  else if(line_end_seen&&line_period_count!=20'hfffff)
   line_period_count<=line_period_count+1'b1;
 end
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin real_row<=0;flush_wait<=0;flush_active<=0;flush_word<=0;end
 else if(zh_valid&&zh_user)begin real_row<=0;flush_wait<=0;flush_active<=0;flush_word<=0;end
 else begin
  if(zh_valid&&zh_last)begin
   if(real_row==IMG_HEIGHT-1)begin
    if(line_end_seen&&line_period_count>=WORDS_PER_ROW)
     flush_wait<=line_period_count+20'd1-WORDS_PER_ROW;
    else flush_wait<=20'd8;
   end else real_row<=real_row+1'b1;
  end
  if(flush_wait!=0)begin flush_wait<=flush_wait-1'b1;
   if(flush_wait==1)begin flush_active<=1;flush_word<=0;end
  end
  if(flush_active&&!zh_valid)begin
   if(flush_word==WORDS_PER_ROW-1)begin flush_active<=0;flush_word<=0;end
   else flush_word<=flush_word+1'b1;
  end
 end end
 wire line_valid1,line_valid2;
 wire [32:0] line_data1,line_data2;
 line_buffer_demosaic #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH)) u_line_buffer1(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(source_user),.I_valid(source_valid),.I_data(line_data0),.O_valid(line_valid1),.O_data(line_data1));
 line_buffer_demosaic #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH)) u_line_buffer2(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(line_data1[32]&&line_valid1),.I_valid(line_valid1),.I_data(line_data1),.O_valid(line_valid2),.O_data(line_data2));
 reg [32:0] data0_d1,data0_d2,data1_d1;
 reg valid0_d1,valid0_d2;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin data0_d1<=0;data0_d2<=0;data1_d1<=0;valid0_d1<=0;valid0_d2<=0;end
 else begin data0_d1<=line_data0;data0_d2<=data0_d1;data1_d1<=line_data1;
 valid0_d1<=source_valid;valid0_d2<=valid0_d1;end end
 reg [H_WIDTH-1:0] aligned_word;
 reg [V_WIDTH-1:0] aligned_row;
 wire aligned_sof=valid0_d2&&data0_d2[32];
 wire [H_WIDTH-1:0] word_now=aligned_sof?{H_WIDTH{1'b0}}:aligned_word;
 wire [V_WIDTH-1:0] row_now=aligned_sof?{V_WIDTH{1'b0}}:aligned_row;
 wire [31:0] above_now=(row_now==1)?data0_d2[31:0]:line_data2[31:0];
 wire [31:0] center_now=data1_d1[31:0];
 wire [31:0] below_now=(row_now==IMG_HEIGHT)?line_data2[31:0]:data0_d2[31:0];
 reg [31:0] previous_above,previous_center,previous_below;
 reg [7:0] previous_left_above,previous_left_center,previous_left_below;
 reg tail_pending,tail_ypos;
 // Active six bytes [71:24] are left, four current pixels, right.
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 aligned_word<=0;aligned_row<=0;
 previous_above<=0;previous_center<=0;previous_below<=0;
 previous_left_above<=0;previous_left_center<=0;previous_left_below<=0;
 tail_pending<=0;tail_ypos<=0;O_tlast<=0;O_tuser<=0;O_tvalid<=0;bayer_ypos<=0;
 matrix_last_line<=0;matrix_cur_line<=0;matrix_next_line<=0;
 end else begin
 O_tlast<=0;O_tuser<=0;O_tvalid<=0;tail_pending<=0;
 if(tail_pending)begin
  matrix_last_line<={24'd0,previous_left_above,previous_above,previous_above[15:8],24'd0};
  matrix_cur_line<={24'd0,previous_left_center,previous_center,previous_center[15:8],24'd0};
  matrix_next_line<={24'd0,previous_left_below,previous_below,previous_below[15:8],24'd0};
  O_tvalid<=1;O_tlast<=1;bayer_ypos<=tail_ypos;
 end
 if(valid0_d2)begin
  if(word_now==WORDS_PER_ROW-1)begin
   aligned_word<=0;if(row_now==IMG_HEIGHT)aligned_row<=0;else aligned_row<=row_now+1'b1;
  end else begin aligned_word<=word_now+1'b1;aligned_row<=row_now;end
  // Row zero only primes the line buffers. Input row y emits row y-1.
  if(row_now!=0)begin
   if(word_now==0)begin
    previous_above<=above_now;previous_center<=center_now;previous_below<=below_now;
    previous_left_above<=above_now[23:16];previous_left_center<=center_now[23:16];previous_left_below<=below_now[23:16];
   end else begin
    matrix_last_line<={24'd0,previous_left_above,previous_above,above_now[31:24],24'd0};
    matrix_cur_line<={24'd0,previous_left_center,previous_center,center_now[31:24],24'd0};
    matrix_next_line<={24'd0,previous_left_below,previous_below,below_now[31:24],24'd0};
    O_tvalid<=1;O_tuser<=(row_now==1)&&(word_now==1);bayer_ypos<=~row_now[0];
    previous_left_above<=previous_above[7:0];previous_left_center<=previous_center[7:0];previous_left_below<=previous_below[7:0];
    previous_above<=above_now;previous_center<=center_now;previous_below<=below_now;
    if(word_now==WORDS_PER_ROW-1)begin tail_pending<=1;tail_ypos<=~row_now[0];end
   end
  end
 end
 end end
endmodule
