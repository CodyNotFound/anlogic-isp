`timescale 1ns/1ps
module tb_gimbal_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enable=0,result_valid=0,found=0,manual_mode=0,slow_source=0,capture_valid=0;
 reg[7:0] cx=0,cy=0;reg[3:0] keys_pressed=0;
 wire ah,av,bh,bv;wire[11:0] ap_h,ap_v,bp_h,bp_v;wire[1:0] as_,bs_;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) candidate(
 .clk(clk),.rst_n(rst_n),.enable(enable),.result_valid(result_valid),.found(found),.cx(cx),.cy(cy),
 .manual_mode(manual_mode),.keys_pressed(keys_pressed),.slow_source(slow_source),.capture_valid(capture_valid),
 .pwm_h(ah),.pwm_v(av),.pulse_h_us(ap_h),.pulse_v_us(ap_v),.ctl_state(as_));
 servo_gimbal_reference #(.CLK_HZ(1000000)) reference(
 .clk(clk),.rst_n(rst_n),.enable(enable),.result_valid(result_valid),.found(found),.cx(cx),.cy(cy),
 .manual_mode(manual_mode),.keys_pressed(keys_pressed),.slow_source(slow_source),.capture_valid(capture_valid),
 .pwm_h(bh),.pwm_v(bv),.pulse_h_us(bp_h),.pulse_v_us(bp_v),.ctl_state(bs_));
 integer cycles=0,updates=0,k;reg[31:0] rng=32'h183b764a;
 always @(posedge clk)begin #1;
  if(rst_n)begin
   cycles=cycles+1;
   if({ah,av,ap_h,ap_v,as_}!=={bh,bv,bp_h,bp_v,bs_})
    $fatal(1,"Mismatch at cycle %0d mode%0d xy%0d,%0d pulse %0d,%0d reference %0d,%0d",cycles,slow_source,cx,cy,ap_h,ap_v,bp_h,bp_v);
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  // Prove the narrow signed interval decoder over every representable input.
  for(k=-256;k<256;k=k+1)
   if(candidate.within_short_plan(k)!=(k>=-64&&k<=64))$fatal(1,"short interval %0d",k);
  for(k=0;k<420000;k=k+1)begin
   @(negedge clk);
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   capture_valid=0;result_valid=0;
   if(k%30000==0)begin enable=1;manual_mode=0;keys_pressed=0;found=1;slow_source=~slow_source;end
   if(k%1000==10)capture_valid=1;
   if(k%1000==20||k%30000==19999||k%30000==20000)begin
    result_valid=1;
    cx=(k%4000<3000)?rng[7:0]%160:rng[7:0];
    cy=(k%4000<3000)?rng[15:8]%90:rng[15:8];updates=updates+1;
   end
   if(k%30000==19000)begin manual_mode=1;keys_pressed=rng[3:0];end
   if(k%30000==25000)begin manual_mode=0;keys_pressed=0;end
   if(k%30000==27000)found=0;
   if(k%30000==29000)enable=0;
  end
  $display("PASS tb_gimbal_equivalence: %0d clocks, %0d result events, all PWM pulses/positions/states exact",cycles,updates);
  $finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
