`timescale 1ns/1ps
module tb_telemetry_v61;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[3:0] mode=11;reg found=1,cv=1;reg[11:0] x=936,y=404;reg[31:0] cycles=19992365;
 wire[3:0] pm;wire pf,pc,pt;wire[15:0] xd,yd,md;
 vision_telemetry dut(clk,rst,mode,found,cv,x,y,cycles,pm,pf,pc,pt,xd,yd,md);
 function [15:0] decimal(input integer v);begin decimal=((v/1000)%10)*4096+((v/100)%10)*256+((v/10)%10)*16+(v%10);end endfunction
 integer n,expected_ms,waits;reg[63:0] rounded;reg[31:0] random_cycles;
 task packet;begin waits=0;@(negedge clk);while(!pt)begin @(negedge clk);waits=waits+1;if(waits>10200)$fatal(1,"formatter timeout");end end endtask
 initial begin
 repeat(5)@(negedge clk);rst=1;packet;
 if({pm,pf,pc,xd,yd,md}!=={4'd11,1'b1,1'b1,16'h0936,16'h0404,16'h0267})$fatal(1,"first packet");
 for(n=0;n<32;n=n+1)begin
  @(negedge clk);x=(n*73)%1280;y=(n*39)%720;cycles=n==0?32'hffffffff:n==1?32'd37500:n==2?32'd37499:32'd998000*n;found=n%3!=0;cv=n%5!=0;mode=n%2?12:14;
  rounded={32'd0,cycles}+37500;expected_ms=cv?rounded/75000:0;if(expected_ms>9999)expected_ms=9999;
  // The immediately following packet may belong to a transaction already in flight.
  repeat(2)begin packet;@(negedge clk);end
  if(xd!==decimal(x)||yd!==decimal(y)||md!==decimal(expected_ms)||pm!=mode||pf!=found||pc!=cv)$fatal(1,"numeric/atomic packet n%0d X%h Y%h MS%h",n,xd,yd,md);
 end
 x=1280;y=719;found=1;repeat(2)begin packet;@(negedge clk);end;if(pf)$fatal(1,"invalid coordinate accepted");
 $display("PASS tb_telemetry_v61 native coordinates, mode/found packet, exact rounded milliseconds, 9999 saturation, invalid guard, 32 changing snapshots");$finish;
 end
 initial begin #6000000;$fatal(1,"watchdog");end
endmodule
