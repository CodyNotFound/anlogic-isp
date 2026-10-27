`timescale 1ns/1ps
module tb_panel_atomic_v63;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[11:0] h=1500,v=1500;
 wire[23:0] hd,vd;wire[11:0] dh,dv;wire[3:0] leds;wire[7:0] seg,sel;
 gimbal_panel dut(clk,rst,4'b0,h,v,leds,seg,sel,hd,vd,dh,dv);
 function[23:0] dec;input integer n;integer j;begin dec=0;for(j=0;j<6;j=j+1)begin dec[j*4+:4]=n%10;n=n/10;end end endfunction
 reg[11:0] expected_h=1500,expected_v=1500;
 integer i,published=0;
 always @(negedge clk)if(rst)begin
  if(hd!==dec(dh)||vd!==dec(dv))$fatal(1,"mixed text/position packet");
 end
 initial begin
  repeat(3)@(negedge clk);rst=1;
  for(i=0;i<12000;i=i+1)begin
   @(negedge clk);h=(i*37)%4096;v=(i*71+911)%4096;
   // Snapshot inputs change every clock, including between axis conversions.
   if(dut.convert_count==0)begin expected_h=h;expected_v=v;end
   if(dut.convert_count==46)begin
    @(posedge clk);#1;
    if(dh!==expected_h||dv!==expected_v||hd!==dec(expected_h)||vd!==dec(expected_v))$fatal(1,"snapshot mismatch");
    published=published+1;
   end
  end
  if(published<150)$fatal(1,"insufficient snapshots");
  $display("PASS panel atomic: %0d changing-input snapshots, coherent H/V text and positions",published);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
