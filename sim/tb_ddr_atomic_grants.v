`timescale 1ns/1ps
module tb_ddr_atomic_grants;
 reg clk=0,ready=0,wr=0,rd=0;
 always #5 clk=~clk;
 wire wg,rg,we,re;wire [24:0] addr;wire [127:0] data;
 ddr_user_arbiter dut(ready,wr,25'd80,128'h12345678,rd,25'd160,wg,rg,we,re,addr,data);
 integer writes=0,reads=0,n;
 always @(posedge clk)begin
  if(we&&re)$fatal(1,"dual command");
  if(we)begin if(addr!=80||data!=128'h12345678)$fatal(1,"write payload");writes=writes+1;end
  if(re)begin if(addr!=160)$fatal(1,"read address");reads=reads+1;end
 end
 initial begin
  for(n=0;n<100;n=n+1)begin
   @(negedge clk);ready=0;wr=1;rd=1;
   repeat(3)@(negedge clk);
   if(we||re||wg||rg)$fatal(1,"accepted while blocked");
   ready=1;
   @(negedge clk);if(!wg||rg)$fatal(1,"write priority");wr=0;
   @(negedge clk);if(!rg)$fatal(1,"reader did not resume");rd=0;
  end
  if(writes!=100||reads!=100)$fatal(1,"lost request");
  $display("PASS tb_ddr_atomic_grants writes=%0d reads=%0d",writes,reads);$finish;
 end
endmodule
