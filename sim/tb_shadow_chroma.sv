`timescale 1ns/1ps
module tb_shadow_chroma;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0;reg [95:0] data=0;wire ov;wire [95:0] out;
 color_tone4 #(.DEFRINGE_ENABLE(0),.TONE_ENABLE(0)) dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tdata(data),
 .I_tuser(1'b0),.I_tlast(1'b0),.I_sat_on(1'b1),.I_tone_on(1'b1),.I_tready(),.O_tvalid(ov),.O_tready(1'b1),.O_tuser(),.O_tlast(),.O_tdata(out));
 integer seen=0;
 always @(posedge clk)begin #1;if(ov)begin
  case(seen)
   0:if(out!=={24'h040404,24'h040c04,24'h081009,24'h101010})$fatal(1,"shadow vector %h",out);
   1:if(out!=={24'hf2b600,24'h000000,24'h002000,24'h080808})$fatal(1,"normal/black/neutral vector %h",out);
   default:$fatal(1,"extra output");
  endcase
  seen=seen+1;
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  @(negedge clk);valid=1;data={24'h000800,24'h001000,24'h041406,24'h101010};
  @(negedge clk);data={24'hdcb428,24'h000000,24'h002000,24'h080808};
  @(negedge clk);valid=0;repeat(8)@(negedge clk);
  if(seen!=2)$fatal(1,"missing vectors");
  $display("PASS tb_shadow_chroma: dark green suppressed, four RGB lanes, normal yellow unchanged, exact black and neutrals");$finish;
 end
 initial begin #10000;$fatal(1,"shadow watchdog");end
endmodule
