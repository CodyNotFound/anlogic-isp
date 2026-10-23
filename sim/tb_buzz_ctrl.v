`timescale 1ns/1ps
module tb_buzz_ctrl;
 reg clk=0,rst_n=0; reg [3:0] keys=0; reg strobe=0; wire buzz;
 integer cycle=0, last_boot=0, last_beep=0, tones=0, starts=0;
 integer entered[0:6]; integer n, keyno, before_count;
 buzz_ctrl #(.CLK_HZ(75000)) dut(clk,rst_n,keys,strobe,buzz);
 always #5 clk=~clk;
 always @(negedge clk) if(rst_n) begin
  cycle=cycle+1;
  if(dut.boot_st!=last_boot)begin entered[dut.boot_st]=cycle;last_boot=dut.boot_st;end
  if(dut.beep_seq!=last_beep)begin
   if(dut.beep_seq==1 || dut.beep_seq==3)tones=tones+1;
   if(dut.beep_seq==1)starts=starts+1;
   last_beep=dut.beep_seq;
  end
  if(dut.boot_st==6 && dut.beep_seq==0 && buzz!==1'b1)
   $fatal(1,"active-low buzzer must idle high");
 end
 task wait_cycles; input integer count;
 begin repeat(count)@(posedge clk);#1;end endtask
 task key_bounce; input integer idx;
 begin
  // 8ms press chatter, stable press, 8ms release chatter; includes >30ms hold.
  for(n=0;n<8;n=n+1)begin keys[idx]=~keys[idx];wait_cycles(75);end
  keys[idx]=1;wait_cycles(9000);
  for(n=0;n<8;n=n+1)begin keys[idx]=~keys[idx];wait_cycles(75);end
  keys[idx]=0;wait_cycles(6000);
 end endtask
 initial begin
  for(n=0;n<7;n=n+1)entered[n]=-1;
  wait_cycles(5);rst_n=1;
  wait_cycles(160000);
  if(dut.boot_st!==6)$fatal(1,"boot did not complete");
  if(entered[1]<74999 || entered[1]>75002)$fatal(1,"boot silence %0d",entered[1]);
  if(entered[2]-entered[1]!=16500 || entered[3]-entered[2]!=5250 ||
     entered[4]-entered[3]!=16500 || entered[5]-entered[4]!=5250 ||
     entered[6]-entered[5]!=33750)$fatal(1,"wrong note/gap lengths");
  $display("PASS boot silence 1000ms, notes 220/220/450ms, gaps 70ms");
  // Narrow spikes are ignored, and not just swallowed while a beep is busy.
  keys=1;wait_cycles(1400);keys=0;wait_cycles(6000);
  if(starts!=0)$fatal(1,"short glitch beeped");
  for(keyno=0;keyno<4;keyno=keyno+1) begin
   before_count=starts;key_bounce(keyno);
   if(starts!=before_count+1)$fatal(1,"key %0d bounce generated %0d beeps",keyno,starts-before_count);
  end
  $display("PASS four keys: press/release chatter produces one beep each");
  before_count=starts;keys=15;wait_cycles(15000);
  if(starts!=before_count+1)$fatal(1,"simultaneous keys/long hold repeated");
  keys=0;wait_cycles(6000);
  keys=1;wait_cycles(3000);keys=0;wait_cycles(3000);
  keys=1;wait_cycles(3000);keys=0;wait_cycles(6000);
  if(starts!=before_count+3)$fatal(1,"separate deliberate presses lost");
  $display("PASS simultaneous press, long hold, release rearm, repeated deliberate presses");
  before_count=tones;strobe=1;wait_cycles(12000);strobe=0;wait_cycles(3000);
  if(tones!=before_count+2)$fatal(1,"event must generate exactly two tones, got %0d",tones-before_count);
  if(dut.beep_seq!==0 || buzz!==1)$fatal(1,"must end silent");
  $display("PASS strobe still gives exactly two tones; idle output high");
  $display("TB_BUZZ_PASS");$finish;
 end
 initial begin #4000000;$fatal(1,"timeout");end
endmodule

// Production-clock arithmetic boundary checks, without simulating 150M clocks.
module tb_buzz_production;
 reg clk=0,rst_n=0;wire buzz;
 buzz_ctrl dut(clk,rst_n,4'b0,1'b0,buzz);
 always #5 clk=~clk;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  @(negedge clk);
  if(dut.note_len(1)!==32'd16500000 || dut.note_len(5)!==32'd33750000)
   $fatal(1,"75MHz note arithmetic truncated");
  if(dut.DB_CYCLES!=1500000)$fatal(1,"20ms debounce at 75MHz");
  dut.boot_cnt=74999998;
  @(negedge clk);
  if(dut.boot_st!==0 || dut.boot_cnt!==74999999)$fatal(1,"1s count truncated");
  @(negedge clk);
  if(dut.boot_st!==1 || dut.boot_cnt!==0)$fatal(1,"1s boundary");
  dut.boot_cnt=16499999;
  @(negedge clk);
  if(dut.boot_st!==2)$fatal(1,"220ms boundary");
  $display("TB_BUZZ_PRODUCTION_PASS: 75MHz counter boundaries and debounce");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
