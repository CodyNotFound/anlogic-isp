`timescale 1ns/1ps
// Exhaust all signed input pairs for the narrowed Add contract. Expected values
// use algebraic per-case identities, independent of the hardware alignment sum.
module tb_yunet_misc_exact;
 reg clk=0,rst=0;reg signed [7:0] av,bv;reg signed [6:0] s1,s2;
 wire [7:0] rd;wire busy,done,od;wire [5:0] oi;wire [31:0] cycles;
 yunet_network dut(clk,rst,1'b0,1'b0,17'd0,8'd0,17'd0,rd,busy,done,od,oi,cycles);
 integer a,b,u,v,expected,actual,n=0;
 initial begin
  #1;
  force dut.a_bank_q=0;force dut.aq0=bv;force dut.misc_temp=av;force dut.shift1=s1;force dut.shift2=s2;
  for(u=0;u<2;u=u+1)for(v=0;v<2;v=v+1)begin
   s1=u;s2=v;
   for(a=-128;a<128;a=a+1)for(b=-128;b<128;b=b+1)begin
    av=a;bv=b;#1;
    case({u[0],v[0]})
     0:expected=a+b;1:expected=a+((b+1)>>>1);
     2:expected=b+((a+1)>>>1);3:expected=(a+b+1)>>>1;
    endcase
    if(expected>127)expected=127;if(expected< -128)expected=-128;
    actual=$signed(dut.quantize_misc(dut.aligned_a+dut.aligned_b,dut.align_half));
    if(actual!=expected)$fatal(1,"Add exactness a%0d b%0d shifts%0d/%0d got%0d expected%0d",a,b,u,v,actual,expected);
    n=n+1;
   end
  end
  $display("PASS tb_yunet_misc_exact: %0d exhaustive signed Add input/scale combinations, rounding ties and saturation",n);$finish;
 end
endmodule
