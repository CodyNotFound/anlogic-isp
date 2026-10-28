`timescale 1ns/1ps
// Commit a complete input row before reading it as a contiguous pixel stream.
// The existing 2048x32 RAM holds two row banks (1024 addresses per bank).
// Input bubbles and the previous frame's line duration never determine addresses.
module zhenghe #(
 parameter [12:0] IMG_WIDTH=640, IMG_HEIGHT=480,
 parameter [8:0] DATA_WIDTH=32, data_complete_delay=50
)(
 input wire I_clk,I_rst_n,I_tlast,I_tuser,
 input wire [DATA_WIDTH-1:0] I_tdata,input wire I_tvalid,
 output reg O_tlast,O_tuser,output wire [DATA_WIDTH-1:0] O_tdata,
 output reg O_tvalid
);
 localparam integer WORDS=IMG_WIDTH/4;
 reg write_bank,line_user;
 reg [9:0] write_word;
 reg pending,pending_bank,pending_user;
 reg read_active,read_bank,read_user;
 reg [9:0] read_word;
 reg [8:0] wait_count;
 wire [10:0] write_address=I_tuser?11'd0:{write_bank,write_word};
 wire [10:0] read_address={read_bank,read_word};
 wire [31:0] ram_data;
 assign O_tdata=ram_data;
 blk_mem_gen_zhenghe row_ram(
  .clka(I_clk),.wea(I_rst_n&&I_tvalid),.addra(write_address),.dia(I_tdata),
  .clkb(I_clk),.addrb(read_address),.dob(ram_data),
  .web(1'b0),.dib(32'd0),.doa());
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n)begin
   write_bank<=0;write_word<=0;line_user<=0;
   pending<=0;pending_bank<=0;pending_user<=0;
   read_active<=0;read_bank<=0;read_user<=0;read_word<=0;wait_count<=0;
   O_tvalid<=0;O_tuser<=0;O_tlast<=0;
  end else begin
   // RAM is synchronous with NOREG: these qualifiers match its read edge.
   O_tvalid<=read_active;
   O_tuser<=read_active&&read_user&&(read_word==0);
   O_tlast<=read_active&&(read_word==WORDS-1);
   if(read_active)begin
    if(read_word==WORDS-1)begin read_active<=0;read_word<=0;end
    else read_word<=read_word+1'b1;
   end else if(wait_count!=0)begin
    wait_count<=wait_count-1'b1;
    if(wait_count==1)begin read_active<=1;read_word<=0;end
   end else if(pending)begin
    read_bank<=pending_bank;read_user<=pending_user;read_word<=0;
    pending<=0;
    if(data_complete_delay==0)read_active<=1;
    else wait_count<=data_complete_delay;
   end
   if(I_tvalid)begin
    if(I_tuser)begin write_bank<=0;write_word<=1;line_user<=1;end
    else write_word<=write_word+1'b1;
    if(I_tlast)begin
     pending<=1;pending_bank<=I_tuser?1'b0:write_bank;
     pending_user<=I_tuser||line_user;
     write_bank<=I_tuser?1'b1:!write_bank;
     write_word<=0;line_user<=0;
    end
   end
  end
 end
`ifndef SYNTHESIS
 always @(posedge I_clk)if(I_rst_n&&I_tvalid)begin
  if(I_tlast && (I_tuser?0:write_word)!=WORDS-1)
   $error("zhenghe: input row length mismatch");
  if(I_tlast && pending)$error("zhenghe: row commit queue overrun");
 end
`endif
endmodule
