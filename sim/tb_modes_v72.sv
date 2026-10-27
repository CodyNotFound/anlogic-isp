`timescale 1ns/1ps
module tb_modes_v72;
 reg clk=0,rst=0;always #5 clk=~clk;reg[3:0]keys=15,remote=0;reg set=0,action=0;
 wire[3:0]mode;wire demo,pick;wire[2:0]step;integer seen=0,k;
 algorithm_mode_ctrl #(.BUTTONS_DEBOUNCED(1),.ENABLE_REMOTE(1),.ENABLE_ISP_DEMO(0),.LAST_MODE(14)) dut(.clk(clk),.rst_n(rst),.buttons_n(keys),.mode(mode),.demo_active(demo),.demo_step(step),.action_pulse(pick),.remote_set(set),.remote_action(action),.remote_mode(remote));
 always @(posedge clk)if(pick)seen=seen+1;
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task press(input[3:0]mask);begin keys=mask;clocks(10);keys=15;clocks(10);end endtask
 initial begin clocks(5);rst=1;clocks(10);
  for(k=1;k<=15;k=k+1)begin press(14);if(mode!=k%15)$fatal(1,"next skipped %0d",k);end
  for(k=1;k<=15;k=k+1)begin press(13);if(mode!=(15-k)%15)$fatal(1,"previous skipped %0d",k);end
  remote=13;set=1;clocks(1);set=0;clocks(5);press(7);if(mode!=13||seen!=1)$fatal(1,"color selection at13");
  remote=14;set=1;clocks(1);set=0;clocks(5);press(7);if(mode!=14||seen!=2)$fatal(1,"motion reset at14");
  remote=15;set=1;clocks(1);set=0;clocks(5);if(mode!=14)$fatal(1,"illegal15 accepted");
  $display("PASS tb_modes_v72: local forward/back all15 modes, wrap, remote and actions13/14");$finish;
 end
endmodule
