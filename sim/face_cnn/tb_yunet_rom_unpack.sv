`timescale 1ns/1ps
module tb_yunet_rom_unpack;
 `include "yunet_rom_unpack.vh"
 reg [31:0] canonical_bias[0:1523];
 reg [6:0] canonical_shift[0:1523];
 reg [15:0] packed_bias[0:1523];
 reg [2:0] packed_shift[0:1523];
 integer i;
 initial begin
  $readmemh("rtl/analytics/face_cnn/bias.hex",canonical_bias);
  $readmemh("rtl/analytics/face_cnn/shift.hex",canonical_shift);
  $readmemh("rtl/analytics/face_cnn/bias.hex.lo16",packed_bias);
  $readmemh("rtl/analytics/face_cnn/shift.hex.code3",packed_shift);
  for(i=0;i<1524;i=i+1)begin
   if(unpack_model_bias(i,packed_bias[i])!==canonical_bias[i])$fatal(1,"bias mismatch at %0d",i);
   if(unpack_model_shift(i,packed_shift[i])!==canonical_shift[i])$fatal(1,"shift mismatch at %0d",i);
  end
  $display("PASS tb_yunet_rom_unpack: all 1524 bias/shift pairs reconstructed bit exactly");
  $finish;
 end
endmodule
