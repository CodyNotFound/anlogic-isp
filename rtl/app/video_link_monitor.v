`timescale 1ns/1ps
// Passive monitors: never gates camera pixels or DDR commands.
// ERR digits, left to right: RX payload/length, input frame/FIFO, read underflow,
// source-to-DDR ordered signature mismatch. Sticky until reset, after warm-up.
module video_link_monitor #(
 parameter integer FRAME_WORDS=172800, PAYLOAD_BYTES=1600
)(
 input wire rst_n,cam_clk,ddr_clk,pix_clk,
 input wire hs_valid,input wire [15:0] hs_data,input wire lane_error,
 input wire isp_sof,isp_valid,input wire [127:0] isp_data,input wire fifo_overflow,
 input wire wr_en,input wire [24:0] wr_addr,
 input wire rd_req,input wire [24:0] rd_addr,input wire rd_valid,input wire [127:0] rd_data,
 input wire fifo_underflow,output reg [3:0] status
);
 function [15:0] crc_byte;input [15:0] c;input [7:0] b;integer i;reg [15:0] t;
 begin t=c;for(i=0;i<8;i=i+1)t=(t>>1)^((t[0]^b[i])?16'h8408:16'd0);crc_byte=t;end endfunction
 function [31:0] signature;input [31:0] s;input [127:0] d;
 begin signature={s[26:0],s[31:27]}^d[127:96]^{d[86:64],d[95:87]}^
                 {d[45:32],d[63:46]}^{d[4:0],d[31:5]};end endfunction
 function [1:0] bank;input [24:0] a;
 begin if(a<7000000)bank=0;else if(a<14000000)bank=1;else if(a<21000000)bank=2;else bank=3;end endfunction
 wire base_request=rd_req&&(rd_addr==0||rd_addr==7000000||rd_addr==14000000||rd_addr==21000000);
 reg [2:0] frames;
 wire warm=frames>=3;
 reg hs_d,raw_packet,crc_seen,rx_error,input_error;
 reg [10:0] packet_word;
 reg [7:0] wc_low;
 reg [15:0] remaining,crc;
 reg [17:0] cam_count,completed_count;
 reg [31:0] cam_signature,completed_signature;
 reg frame_toggle;
 always @(posedge cam_clk or negedge rst_n)begin
  if(!rst_n)begin
   frames<=0;hs_d<=0;raw_packet<=0;crc_seen<=0;rx_error<=0;input_error<=0;
   packet_word<=0;wc_low<=0;remaining<=0;crc<=16'hffff;
   cam_count<=0;completed_count<=0;cam_signature<=0;completed_signature<=0;frame_toggle<=0;
  end else begin
   hs_d<=hs_valid;
   if(isp_sof)begin
    if(frames!=7)frames<=frames+1'b1;
    if(warm&&cam_count!=FRAME_WORDS)input_error<=1;
    completed_count<=cam_count;completed_signature<=cam_signature;frame_toggle<=!frame_toggle;
    cam_count<=isp_valid?1:0;cam_signature<=isp_valid?signature(0,isp_data):0;
   end else if(isp_valid)begin
    if(cam_count!=18'h3ffff)cam_count<=cam_count+1'b1;
    cam_signature<=signature(cam_signature,isp_data);
   end
   if(warm&&fifo_overflow)input_error<=1;
   if(warm&&lane_error)rx_error<=1;
   if(hs_valid&&!hs_d)begin
    raw_packet<=hs_data[13:8]==6'h2b;wc_low<=hs_data[7:0];packet_word<=1;
    crc_seen<=0;crc<=16'hffff;remaining<=0;
   end else if(hs_valid)begin
    if(packet_word!=11'h7ff)packet_word<=packet_word+1'b1;
    if(packet_word==1)begin
     remaining<={hs_data[15:8],wc_low};
     if(warm&&raw_packet&&{hs_data[15:8],wc_low}!=PAYLOAD_BYTES)rx_error<=1;
    end else if(raw_packet)begin
     if(remaining>=2)begin
      crc<=crc_byte(crc_byte(crc,hs_data[15:8]),hs_data[7:0]);remaining<=remaining-2;
     end else if(!crc_seen)begin
      crc_seen<=1;
      // First wire byte is CRC low byte; lane merge places it in [15:8].
      if(warm&&(remaining!=0||{hs_data[7:0],hs_data[15:8]}!=crc))rx_error<=1;
     end
    end
   end
   if(hs_d&&!hs_valid&&warm&&raw_packet&&(!crc_seen||remaining!=0))rx_error<=1;
  end
 end
 (* async_reg="true" *) reg ft1,ft2,ft3;
 reg [1:0] last_write_bank;
 reg [31:0] expected[0:3];reg [3:0] expected_valid;
 reg reading,check_enabled,ddr_error;
 reg [17:0] read_count;reg [31:0] read_signature,read_expected;
 integer j;
 always @(posedge ddr_clk or negedge rst_n)begin
  if(!rst_n)begin
   ft1<=0;ft2<=0;ft3<=0;last_write_bank<=0;expected_valid<=0;
   for(j=0;j<4;j=j+1)expected[j]<=0;
   reading<=0;check_enabled<=0;ddr_error<=0;read_count<=0;read_signature<=0;read_expected<=0;
  end else begin
   ft1<=frame_toggle;ft2<=ft1;ft3<=ft2;
   if(wr_en)last_write_bank<=bank(wr_addr);
   // Bundled metadata stays stable for a whole frame after the toggle.
   if(ft2!=ft3)begin
    expected[last_write_bank]<=completed_signature;
    expected_valid[last_write_bank]<=completed_count==FRAME_WORDS;
   end
   if(base_request)begin
    reading<=1;read_count<=0;read_signature<=0;
    read_expected<=expected[bank(rd_addr)];check_enabled<=expected_valid[bank(rd_addr)];
   end else if(rd_valid&&reading)begin
    read_signature<=signature(read_signature,rd_data);
    if(read_count==FRAME_WORDS-1)begin
     reading<=0;
     if(check_enabled&&signature(read_signature,rd_data)!=read_expected)ddr_error<=1;
    end else read_count<=read_count+1'b1;
   end
  end
 end
 (* async_reg="true" *) reg [3:0] err_sync1,err_sync2;
 (* async_reg="true" *) reg warm1,warm2;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin err_sync1<=0;err_sync2<=0;warm1<=0;warm2<=0;status<=0;end
  else begin
   err_sync1<={ddr_error,1'b0,input_error,rx_error};err_sync2<=err_sync1;
   warm1<=warm;warm2<=warm1;
   status<=status|err_sync2|((warm2&&fifo_underflow)?4'b0100:4'b0000);
  end
 end
endmodule
