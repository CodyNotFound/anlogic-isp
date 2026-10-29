`timescale 1ns/1ps
module tb_yunet_clock_bridge;
 reg io_clk=0,core_clk=0,rst=0,start=0,done=0;reg [31:0] cycles=0;
 initial begin #1.17;forever #6.667 io_clk=~io_clk;end
 always #3.333 core_clk=~core_clk;
 wire crst,cs,idone,pending;wire [31:0] result;
 reg running=0;integer tag=0,ctag=0,count=0,starts=0,finishes=0,t;
 yunet_clock_bridge dut(.io_clk(io_clk),.core_clk(core_clk),.rst_n(rst),.io_start(start),.core_ready(!running),.core_done(done),.core_cycles(cycles),.core_rst_n(crst),.core_start(cs),.io_done(idone),.io_pending(pending),.io_cycles(result));
 reg last_start=0;
 always @(posedge core_clk or negedge crst)begin
  if(!crst)begin running<=0;done<=0;count<=0;cycles<=0;last_start<=0;ctag<=0;end
  else begin
   done<=0;cycles<=cycles+32'h12345;last_start<=cs;
   if(cs)begin
    if(last_start||running)$fatal(1,"duplicate compute request");
    running<=1;ctag<=tag;count<=0;starts=starts+1;
   end else if(running)begin
    count<=count+1;
    if(count==40+(ctag%17))begin cycles<={ctag[15:0],count[15:0]};done<=1;running<=0;end
   end
  end
 end
 initial begin
  repeat(5)@(negedge io_clk);rst=1;repeat(5)@(negedge io_clk);
  for(t=0;t<100;t=t+1)begin
   tag=t;start=1;repeat(2)@(negedge io_clk);start=0;
   if(t%10==3)begin
    repeat(3)@(negedge io_clk);#1;rst=0;#17;rst=1;
    repeat(8)@(negedge io_clk);if(idone||pending)$fatal(1,"stale completion after cancel");
   end else begin
    wait(idone);@(negedge io_clk);
    if(result[31:16]!==t[15:0]||result[15:0]!==16'(40+t%17))$fatal(1,"cycle bundle mismatch t%0d got%h",t,result);
    finishes=finishes+1;repeat(2)@(negedge io_clk);
   end
  end
  if(starts!=100||finishes!=90)$fatal(1,"event count starts%0d finishes%0d",starts,finishes);
  $display("PASS tb_yunet_clock_bridge: 100 requests, 90 completions, 10 cancellations, held bundles and nonaligned clocks");$finish;
 end
 initial begin #1000000;$fatal(1,"bridge watchdog");end
endmodule
