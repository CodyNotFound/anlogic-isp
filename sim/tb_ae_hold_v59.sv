`timescale 1ns/1ps
module tb_ae_hold_v59;
 reg clk=0,rst=1,auto_on=1,valid=0;reg[7:0] y=255;reg[3:0] keys=15;
 wire req;wire[15:0] exposure,gain;integer n,e,g;
 always #5 clk=~clk;
 ae_set dut(clk,rst,keys,1'b1,1'b1,auto_on,y,valid,req,exposure,gain);
 task ticks(input integer count);begin repeat(count)@(negedge clk);end endtask
 initial begin
 ticks(5);rst=0;valid=1;ticks(120);valid=0;ticks(10);
 if(gain>=80)$fatal(1,"AE did not adapt before freeze");
 auto_on=0;e=exposure;g=gain;keys=0;valid=1;y=0;
 for(n=0;n<150;n=n+1)begin ticks(1);if(req||exposure!=e||gain!=g)$fatal(1,"hold changed sensor command");end
 if(dut.r_ae_set!=e||dut.r_ag_set!=g)$fatal(1,"keys altered held settings");
 keys=15;auto_on=1;ticks(20);if(gain<=g)$fatal(1,"AE did not resume");
 $display("PASS tb_ae_hold_v59 adaptation, no baseline reset or key leak during hold, no new requests, resume");$finish;
 end
 initial begin #10000;$fatal(1,"watchdog");end
endmodule
