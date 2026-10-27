`timescale 1ns/1ps
module osd_font_bram (
 input wire I_clk,input wire [7:0] I_char,input wire [3:0] I_row,
 output wire [15:0] O_row_bits);
 reg [15:0] mem [0:2047];reg [6:0] char_idx;
 always @* begin
  if(I_char>=8'h30&&I_char<=8'h39)char_idx={3'b000,I_char[3:0]};
  else if(I_char>=8'h41&&I_char<=8'h5A)char_idx={2'b00,I_char[4:0]}+7'd9;
  else if(I_char==8'h3a)char_idx=7'd36;else if(I_char==8'h2d)char_idx=7'd37;
  else if(I_char==8'h2e)char_idx=7'd38;else if(I_char>=8'h80&&I_char<=8'hce)char_idx={1'b0,I_char[6:0]}+7'd40;
  else char_idx=7'd39;
 end
 initial $readmemh("osd_font_rom.hex",mem);
 assign O_row_bits=mem[{char_idx,I_row}];
endmodule
module logo_rom_bram (
 input wire I_clk,input wire [13:0] I_addr,output reg [7:0] O_idx,output reg [23:0] O_rgb);
 reg [7:0] idx_mem[0:16383];reg [23:0] pal_mem[0:255];
 initial begin $readmemh("logo_idx.hex",idx_mem);$readmemh("logo_pal.hex",pal_mem);end
 always @(posedge I_clk) begin O_idx<=idx_mem[I_addr];O_rgb<=pal_mem[O_idx];end
endmodule

