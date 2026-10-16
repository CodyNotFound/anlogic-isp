`timescale 1ns/1ps
module tb_buzz_ctrl;
 reg clk=0,rst_n=0;reg [3:0] keys=4'b0000;wire buzz;
 integer ticks=0, flips=0;
 // boot_st 转移时刻(拍): 0静默1s 1=D5 2=gap 3=A5 4=gap 5=D6尾音 6=完成
 integer t_st[0:6];reg [2:0] last_st=0;
 integer t_expect;
 buzz_ctrl #(.CLK_HZ(75000)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_keys(keys),.I_strobe(1'b0),.O_buzz(buzz));
 always #6666 clk=~clk;  // 1拍=1等效ms (CLK_HZ缩频1000x自洽)
 always @(posedge clk)begin
  ticks=ticks+1;
  if(rst_n)begin
   if(buzz)flips=flips+1;
   if(dut.boot_st!=last_st)begin t_st[dut.boot_st]=ticks;last_st=dut.boot_st;end
  end
 end
 initial begin
  repeat(10)@(negedge clk);rst_n=1;
  repeat(115000)@(negedge clk);   // 静默75000 + 旋律~37000拍 + 余量
  // C1: 转移时刻 (静默1000ms, D5 220ms, gap 70ms, A5 220ms, gap 70ms, D6 450ms)
  t_expect=75000;
  if(t_st[1]>t_expect+300||t_st[1]<t_expect-300)$fatal(1,"D5=%0d exp~%0d",t_st[1],t_expect);
  t_expect=t_expect+16500;
  if(t_st[2]>t_expect+200||t_st[2]<t_expect-200)$fatal(1,"gap1=%0d exp~%0d",t_st[2],t_expect);
  t_expect=t_expect+5250;
  if(t_st[3]>t_expect+200||t_st[3]<t_expect-200)$fatal(1,"A5=%0d exp~%0d",t_st[3],t_expect);
  t_expect=t_expect+16500;
  if(t_st[4]>t_expect+200||t_st[4]<t_expect-200)$fatal(1,"gap2=%0d exp~%0d",t_st[4],t_expect);
  t_expect=t_expect+5250;
  if(t_st[5]>t_expect+200||t_st[5]<t_expect-200)$fatal(1,"D6=%0d exp~%0d",t_st[5],t_expect);
  t_expect=t_expect+33750;
  if(t_st[6]>t_expect+500||t_st[6]<t_expect-300)$fatal(1,"done=%0d exp~%0d",t_st[6],t_expect);
  $display("** C1 PASS: boot melody D5(220ms)-gap(70)-A5(220ms)-gap(70)-D6(450ms)");
  // C2: 旋律期间有方波, 完成后静止
  if(flips<200)$fatal(1,"melody flips=%0d",flips);
  flips=0;
  repeat(3000)@(negedge clk);
  if(flips!=0)$fatal(1,"flips after done=%0d",flips);
  $display("** C2 PASS: square wave + silent after");
  // C3: 按键哔
  keys=4'b0100;repeat(4)@(negedge clk);keys=4'b0000;
  repeat(3000)@(negedge clk);
  if(dut.beep_seq!=3'd0)$fatal(1,"key beep not finished");
  $display("** C3 PASS: key beep");
  $display("** TB_BUZZ PASS **");$finish;
 end
 initial begin #2000000000;$fatal(1,"timeout");end
endmodule
