`timescale 1ns/1ps
module tb_yunet_shift_exact;
 yunet_dot4 #(.MODEL_SHIFT(1)) dut(.clk(1'b0),.rst_n(1'b0),.start(1'b0),.bias(32'sd0),.shift(7'sd1),.relu(1'b0),.ready(),.in_valid(1'b0),.in_ready(),.in_last(1'b0),.activations(36'd0),.weights(32'd0),.out_valid(),.out_ready(1'b0),.accumulator(),.value());
 integer s,i,r,n=0,seed=32'h1255abcd,tmp;reg signed [31:0] a;reg signed [7:0] old_q,new_q;
 task check(input signed [31:0] x,input integer shift,input bit relu);
 begin
  old_q=dut.requant(x,shift,relu);new_q=dut.requant_model(x,shift,relu);
  if(old_q!==new_q)$fatal(1,"requant mismatch a%0d shift%0d relu%0d old%0d new%0d",x,shift,relu,old_q,new_q);
  n=n+1;
 end endtask
 initial begin
  tmp=$urandom(seed);
  for(s=1;s<=31;s=s+1)for(r=0;r<2;r=r+1)begin
   check(32'sh80000000,s,r);check(32'sh7fffffff,s,r);check(0,s,r);check(-1,s,r);
   for(i=0;i<32;i=i+1)begin
    check((32'd1<<i),s,r);check(-(32'd1<<i),s,r);
    check((32'd1<<i)-1,s,r);check(-(32'd1<<i)+1,s,r);
   end
   for(i=0;i<4096;i=i+1)check($urandom,s,r);
  end
  $display("PASS tb_yunet_shift_exact: %0d int32 cases, all positive shifts1..31, both ReLU states, rounding/saturation/extreme values match generic int64",n);$finish;
 end
endmodule
