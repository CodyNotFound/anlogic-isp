`timescale 1ns/1ps
// Interface timing probe; recognition itself is covered by the native suite.
module tb_gimbal_target;
 reg clk=0,rst=0,enabled=1;always #5 clk=~clk;
 reg [3:0] mode=12;wire tv,tf;wire [7:0] tx,ty;
 vision_task_suite #(.RESULT_TTL(4)) dut(
 .clk(clk),.rst_n(rst),.enabled(enabled),.action(1'b0),.mode(mode),
 .source_sof(1'b0),.source_eol(1'b0),.source_de(1'b0),.source_rgb(24'b0),
 .vsync(1'b0),.hsync(1'b0),.de(1'b0),.sof(1'b0),.eol(1'b0),.rgb(24'b0),
 .out_vsync(),.out_hsync(),.out_de(),.out_sof(),.out_eol(),.out_rgb(),
 .target_valid(tv),.target_found(tf),.target_x(tx),.target_y(ty),.manual_mode(1'b0));
 task clock;begin @(posedge clk);#1;end endtask
 initial begin
  force dut.tv=0;force dut.tf=0;repeat(4)clock;rst=1;clock;
  force dut.tv=1;force dut.tf=1;force dut.tx=120;force dut.ty=70;#1;
  if(!tv || !tf || tx!=120 || ty!=70)$fatal(1,"first result suppressed by old TTL age");
  clock;force dut.tv=0;clock;if(!tf)$fatal(1,"fresh result expired early");
  repeat(5)clock;if(tf)$fatal(1,"TTL did not expire");
  force dut.tv=1;#1;if(!tf)$fatal(1,"reacquire first result suppressed");
  mode=14;force dut.rv=0;force dut.rc=0;force dut.rf=0;#1;
  if(tf||tv)$fatal(1,"tracker leaked into REGION");
  force dut.rv=1;force dut.rc=1;force dut.rf=1;force dut.ro=0;force dut.rcx=99;force dut.rcy=65;#1;
  if(!tv||!tf||tx!=99||ty!=65)$fatal(1,"REGION target not connected");
  force dut.ro=1;#1;if(tf)$fatal(1,"overflow REGION drove servo");
  mode=0;#1;if(tv||tf)$fatal(1,"target leaked into effect mode");
  $display("PASS tb_gimbal_target: first acquisition, TTL expiry, reacquisition and mode isolation");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
