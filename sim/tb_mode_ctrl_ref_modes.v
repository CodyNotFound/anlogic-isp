`timescale 1ns/1ps
module tb_mode_ctrl_ref_modes;
 reg clk=0,rst_n=0;reg [3:0] buttons=4'b1111;wire [3:0] mode;
 wire demo_active;wire [2:0] demo_step;wire action_pulse;integer actions=0;
 algorithm_mode_ctrl #(.DEBOUNCE_CYCLES(3)) dut(.clk(clk),.rst_n(rst_n),
   .buttons_n(buttons),.mode(mode),.demo_active(demo_active),.demo_step(demo_step),.action_pulse(action_pulse));
 always @(posedge clk)if(action_pulse)actions=actions+1;
 integer i;
 always #3.333 clk=~clk;
 task pulse;input integer which;
 begin @(negedge clk);buttons[which]=0;repeat(5)@(negedge clk);buttons[which]=1;repeat(5)@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
  if(mode!==4'd0||demo_active!==1'b0)$fatal(1,"reset state");

  // C1: K1 循环 0..11, FACE included.
  for(i=0;i<13;i=i+1)begin pulse(0);if(mode!==(i==12?14:i+1))$fatal(1,"K1 mode step%0d got %0d",i+1,mode);end
  pulse(0);if(mode!==4'd0)$fatal(1,"K1 wrap");
  pulse(1);if(mode!==4'd14)$fatal(1,"K2 wrap");
  pulse(3);if(actions!=1 || mode!=14)$fatal(1,"K4 REGION action");
  pulse(1);pulse(3);if(actions!=2 || mode!=12)$fatal(1,"K4 TRACK action / skip13");
  for(i=12;i>0;i=i-1)begin pulse(1);if(mode!==i-1)$fatal(1,"K2 mode %0d got %0d",i-1,mode);end
  $display("** C1 PASS: K1/K2 cycle 0..14, K4 task action");

  // C2: K3 进入演示(step0), 连按到6再回0
  pulse(2);
  if(demo_active!==1'b1||demo_step!==3'd0)$fatal(1,"K3 enter demo");
  for(i=1;i<=5;i=i+1)begin pulse(2);if(demo_step!==i)$fatal(1,"K3 step %0d got %0d",i,demo_step);end
  pulse(2);if(demo_step!==3'd0)$fatal(1,"K3 wrap to 0");
  $display("** C2 PASS: K3 enter/advance/wrap");

  // C3: K4 后退, 到0不动
  pulse(2);if(demo_step!==3'd1)$fatal(1,"K3 step1");
  pulse(3);if(demo_step!==3'd0)$fatal(1,"K4 back to 0");
  pulse(3);if(demo_step!==3'd0)$fatal(1,"K4 hold at 0");
  $display("** C3 PASS: K4 retreat/floor");

  // C4: 演示中 K1/K2 退出, 模式值保持; 退出后恢复正常循环
  pulse(2);pulse(2);pulse(2); // step 3
  if(demo_step!==3'd3)$fatal(1,"step3");
  pulse(1); // K2 退出
  if(demo_active!==1'b0)$fatal(1,"K2 exit demo");
  if(mode!==4'd0)$fatal(1,"mode preserved after exit");
  pulse(0);if(mode!==4'd1||demo_active!==1'b0)$fatal(1,"K1 normal after exit");
  pulse(2);if(demo_active!==1'b1)$fatal(1,"reenter");
  pulse(0);if(demo_active!==1'b0||mode!==4'd1)$fatal(1,"K1 exit, mode preserved");
  $display("** C4 PASS: K1/K2 exit demo, mode preserved");

  // C5: 非演示状态 K4 无动作
  pulse(3);if(demo_active!==1'b0||mode!==4'd1)$fatal(1,"K4 no-op outside demo");
  $display("** C5 PASS: K4 no-op outside demo");

  $display("PASS tb_mode_ctrl_ref_modes");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
