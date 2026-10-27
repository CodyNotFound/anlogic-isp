`timescale 1ns/1ps
module tb_servo_range_v71;
 reg clk=0,rst=0,manual=0;reg[3:0]keys=0;always #5 clk=~clk;
 wire h,v;wire[11:0]ph,pv;wire[1:0]state;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) dut(.clk(clk),.rst_n(rst),.enable(1'b0),.result_valid(1'b0),.found(1'b0),.cx(8'd80),.cy(8'd45),.manual_mode(manual),.keys_pressed(keys),.pwm_h(h),.pwm_v(v),.pulse_h_us(ph),.pulse_v_us(pv),.ctl_state(state),.slow_source(1'b0),.capture_valid(1'b0));
 integer n=0,hr=0,vr=0,hp=0,vp=0,last=0;reg hd=0,vd=0;
 always @(negedge clk)if(rst)begin
  n=n+1;if(ph<500||ph>2500||pv<900||pv>2150)$fatal(1,"range violation");
  if(h&&!hd)begin if(hr&&n-hr!=20000)$fatal(1,"PWM period");hr=n;hp=ph;end
  if(v&&!vd)begin vr=n;vp=pv;end
  if(!h&&hd&&n-hr!=hp)$fatal(1,"horizontal PWM width");
  if(!v&&vd&&n-vr!=vp)$fatal(1,"vertical PWM width");hd=h;vd=v;
 end
 task clocks(input integer count);begin repeat(count)@(negedge clk);end endtask
 initial begin
  clocks(5);rst=1;clocks(40000);if(ph!=1500||pv!=1500)$fatal(1,"neutral");
  manual=1;keys=12;clocks(1600000);if(ph!=2500||pv!=2150)$fatal(1,"upper pulse endpoints %d %d",ph,pv);
  keys=3;clocks(1600000);if(ph!=500||pv!=900)$fatal(1,"lower pulse endpoints %d %d",ph,pv);
  keys=0;manual=0;clocks(2100000);if(ph!=500||pv!=900)$fatal(1,"loss unexpectedly homed");
  $display("PASS tb_servo_range_v71: 900..2150 V and 500..2500 H clamps, neutral1500, 50Hz PWM widths and indefinite hold");$finish;
 end
 initial begin #60000000;$fatal(1,"timeout");end
endmodule
