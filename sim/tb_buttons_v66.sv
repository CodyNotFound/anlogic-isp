`timescale 1ns/1ps
module tb_buttons_v66;
 reg clk=0,rst=0,manual_mode=0;reg[3:0]buttons=15,sw=15;always #5 clk=~clk;
 wire[3:0]features,pressed,normal,mode;wire action;reg remote_set=0,remote_action=0;reg[3:0]remote_mode=0;
 vision_switch_ctrl #(.DEBOUNCE_CYCLES(100),.SAMPLE_CYCLES(10)) switches(clk,rst,sw,features);
 gimbal_button_router #(.DEBOUNCE_CYCLES(100),.SAMPLE_CYCLES(10)) router(clk,rst,manual_mode,buttons,pressed,normal);
 algorithm_mode_ctrl #(.ENABLE_ISP_DEMO(0),.LAST_MODE(15),.BUTTONS_DEBOUNCED(1),.ENABLE_REMOTE(1)) modes(
 .clk(clk),.rst_n(rst),.buttons_n(normal),.mode(mode),.demo_active(),.demo_step(),.action_pulse(action),
 .remote_set(remote_set),.remote_action(remote_action),.remote_mode(remote_mode));
 integer events=0;reg[3:0]previous=0;
 always @(posedge clk)begin if(mode!=previous)events=events+1;previous<=mode;end
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
  clocks(5);rst=1;clocks(5);
  sw=14;buttons=14;clocks(50);if(features||pressed||mode)$fatal(1,"bounce accepted");sw=15;buttons=15;clocks(20);
  sw=14;buttons=14;clocks(100);if(features||pressed||mode)$fatal(1,"early sample acceptance");clocks(20);if(features!=1||pressed!=1||mode!=1)$fatal(1,"stable press");
  clocks(250);if(mode!=1)$fatal(1,"held key repeated event");
  // Release channel zero while the other channel repeatedly bounces.
  buttons[0]=1;sw[0]=1;
  repeat(24)begin buttons[1]=~buttons[1];sw[1]=~sw[1];clocks(5);end
  if(pressed[0]||features[0]||mode!=1)$fatal(1,"independent release");buttons=15;sw=15;clocks(120);
  manual_mode=1;buttons=7;clocks(120);if(pressed!=8||normal!=15)$fatal(1,"manual routing");
  manual_mode=0;clocks(20);if(normal!=15||mode!=1)$fatal(1,"release interlock");buttons=15;clocks(120);
  remote_mode=12;remote_set=1;clocks(1);remote_set=0;clocks(3);if(mode!=12)$fatal(1,"remote mode");
  remote_action=1;clocks(1);if(!action)$fatal(1,"remote selection");remote_action=0;clocks(2);
  buttons=14;clocks(120);if(mode!=14)$fatal(1,"retired mode skip");buttons=15;clocks(120);
  $display("PASS tb_buttons_v66 short bounce rejection, independent release, no held repeats, manual interlock, remote mode/pick");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule
