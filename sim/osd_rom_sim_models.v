`timescale 1ns/1ps
module osd_font_bram #(parameter FONT_FILE="osd_font_rom.hex") (
 input wire I_clk,input wire [7:0] I_char,input wire [3:0] I_row,
 output reg [15:0] O_row_bits);
 reg [15:0] mem [0:2047];
 reg [6:0] char_idx;
 always @* begin
  case(I_char)
   8'h30:char_idx=7'd0;
   8'h31:char_idx=7'd1;
   8'h32:char_idx=7'd2;
   8'h33:char_idx=7'd3;
   8'h34:char_idx=7'd4;
   8'h35:char_idx=7'd5;
   8'h36:char_idx=7'd6;
   8'h37:char_idx=7'd7;
   8'h38:char_idx=7'd8;
   8'h39:char_idx=7'd9;
   8'h41:char_idx=7'd10;
   8'h42:char_idx=7'd11;
   8'h43:char_idx=7'd12;
   8'h44:char_idx=7'd13;
   8'h45:char_idx=7'd14;
   8'h46:char_idx=7'd15;
   8'h47:char_idx=7'd16;
   8'h48:char_idx=7'd17;
   8'h49:char_idx=7'd18;
   8'h4D:char_idx=7'd19;
   8'h4E:char_idx=7'd20;
   8'h4F:char_idx=7'd21;
   8'h50:char_idx=7'd22;
   8'h52:char_idx=7'd23;
   8'h53:char_idx=7'd24;
   8'h54:char_idx=7'd25;
   8'h56:char_idx=7'd26;
   8'h57:char_idx=7'd27;
   8'h58:char_idx=7'd28;
   8'h59:char_idx=7'd29;
   8'h3A:char_idx=7'd30;
   8'h2D:char_idx=7'd31;
   8'h2E:char_idx=7'd32;
   8'h20:char_idx=7'd33;
   8'h6D:char_idx=7'd34;
   8'h73:char_idx=7'd35;
   default:if(I_char>=8'h80&&I_char<=8'hDB)char_idx={1'b0,I_char[6:0]}+7'd36;else char_idx=7'd33;
  endcase
 end
 initial $readmemh(FONT_FILE,mem);
 always @(posedge I_clk)O_row_bits<=mem[{char_idx,I_row}];
endmodule
module logo_rom_bram(input wire I_clk,input wire [13:0] I_addr,output wire [7:0] O_idx,output wire [23:0] O_rgb);
 assign O_idx=8'd0;assign O_rgb=24'd0;
endmodule

