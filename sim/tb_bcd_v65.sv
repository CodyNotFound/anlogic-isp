`timescale 1ns/1ps
module tb_bcd_v65;
 reg clk=0,rst=0,start=0;always #5 clk=~clk;
 reg[19:0]value=0;wire[23:0]narrow_digits,full;
 vision_bcd #(.BIN_W(14),.DEC_DIGITS(4)) a(clk,rst,start,value,narrow_digits);
 vision_bcd b(clk,rst,start,value,full);
 function[23:0] expected;input integer n;integer j;begin expected=0;for(j=0;j<6;j=j+1)begin expected[j*4+:4]=n%10;n=n/10;end end endfunction
 integer n;
 initial begin repeat(3)@(negedge clk);rst=1;
 for(n=0;n<10000;n=n+1)begin
 value=n;start=1;@(negedge clk);start=0;repeat(22)@(negedge clk);
 if(narrow_digits!==expected(n)||full!==expected(n))$fatal(1,"BCD mismatch %0d %h/%h",n,narrow_digits,full);
 end
 $display("PASS BCD 10000 values: specialized14-bit/4-digit equals default20-bit/6-digit and independent decimal arithmetic");$finish;
 end
endmodule
