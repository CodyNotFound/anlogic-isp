`timescale 1ns/1ps
module tb_i2c_clock_enable;
 reg clk=0;always #21 clk=~clk;
 reg rst=0,req=0,ack=1,compare=0;reg [31:0] wr=32'h5634126c;
 wire scl,sclr,busy,busyr,error,errorr;tri1 sda,sdar;
 wire [7:0] rd,rdr;wire dbg,dbgr;
 uii2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(239)) dut(clk,rst,scl,sda,wr,8'd4,rd,8'd0,req,1'b0,busy,error,dbg);
 uii2c_divided_reference #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(239)) refdut(clk,rst,sclr,sdar,wr,8'd4,rdr,8'd0,req,1'b0,busyr,errorr,dbgr);
 assign sda=ack&&dut.IIC_S==3?1'b0:1'bz;
 assign sdar=ack&&refdut.IIC_S==3?1'b0:1'bz;
 integer checked=0,errors=0,timeout;
 always @(negedge clk)if(compare)begin
  checked=checked+1;
  if({scl,sda,busy,error,rd,dbg}!=={sclr,sdar,busyr,errorr,rdr,dbgr})
   $fatal(1,"CE/reference mismatch cycle%0d scl%0b/%0b sda%0b/%0b busy%0b/%0b error%0b/%0b",checked,scl,sclr,sda,sdar,busy,busyr,error,errorr);
  if(error)errors=errors+1;
 end
 task tick;begin @(negedge clk);end endtask
 task transaction;input [31:0] value;begin
  wr=value;req=1;timeout=0;
  while(!busy&&timeout<2000)begin tick;timeout=timeout+1;end
  if(!busy)$fatal(1,"busy timeout");
  req=0;timeout=0;
  while(busy&&timeout<20000)begin tick;timeout=timeout+1;end
  if(busy)$fatal(1,"transaction timeout");
  repeat(500)tick;
 end endtask
 initial begin
  repeat(5)tick;rst=1;repeat(1500)tick;compare=1;
  transaction(32'h5634126c);repeat(17)tick;transaction(32'h1234566c);
  ack=0;transaction(32'h8765436c);
  if(errors==0)$fatal(1,"missing NACK probe");
  ack=1;transaction(32'habcdef6c);
  compare=0;req=1;repeat(3000)tick;rst=0;tick;req=0;repeat(5)tick;
  if(busy||busyr)$fatal(1,"reset did not clear busy");
  rst=1;repeat(1500)tick;compare=1;transaction(32'hffeedd6c);
  $display("PASS tb_i2c_clock_enable %0d parent clocks, writes, NACK and reset",checked);$finish;
 end
 initial begin #30000000;$fatal(1,"watchdog");end
endmodule
