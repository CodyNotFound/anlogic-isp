`timescale 1ns/1ps
module osd_font_bram (
 input wire I_clk,input wire [7:0] I_char,input wire [3:0] I_row,
 output wire [15:0] O_row_bits);
 reg [15:0] mem [0:2047];
 reg [6:0] char_idx;
 always @* begin
  if(I_char>=8'h30&&I_char<=8'h39)char_idx=I_char-8'h30;
  else if(I_char>=8'h41&&I_char<=8'h5A)char_idx=I_char-8'h41+7'd10;
  else if(I_char==8'h3A)char_idx=36;
  else if(I_char==8'h2D)char_idx=37;
  else if(I_char==8'h2E)char_idx=38;
  else if(I_char==8'h6D)char_idx=40;
  else if(I_char==8'h73)char_idx=41;
  else if(I_char>=8'h80&&I_char<=8'hD3)char_idx={1'b0,I_char[6:0]}+7'd42;
  else char_idx=39;
 end
 initial $readmemh("osd_font_rom.hex",mem);
 assign O_row_bits=mem[{char_idx,I_row}];
endmodule
module logo_rom_bram(input wire I_clk,input wire [13:0] I_addr,output wire [7:0] O_idx,output wire [23:0] O_rgb);
 assign O_idx=8'd0;assign O_rgb=24'd0;
endmodule

