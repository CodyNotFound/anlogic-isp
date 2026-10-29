`timescale 1ns/1ps
module tb_yunet_decode_timing;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,fs=0,iv=0,il=0;reg[1:0]lev=0;reg[7:0]gx=0,gy=0,cl=0,ob=0,bx=0,by=0,bw=0,bh=0;
 wire dv,df,rv,rf;wire[13:0]ds,rs;wire[11:0]dx,dy,dz,dcx,dcy,rx,ry,rz,rcx,rcy;
 yunet_decode dut(.clk(clk),.rst_n(rst),.frame_start(fs),.in_valid(iv),.in_last(il),.level(lev),.grid_x(gx),.grid_y(gy),.cls(cl),.obj(ob),.bx(bx),.by(by),.bw(bw),.bh(bh),.result_valid(dv),.found(df),.score_product(ds),.box_x(dx),.box_y(dy),.box_size(dz),.center_x(dcx),.center_y(dcy));
 yunet_decode_timing_ref reference(.clk(clk),.rst_n(rst),.frame_start(fs),.in_valid(iv),.in_last(il),.level(lev),.grid_x(gx),.grid_y(gy),.cls(cl),.obj(ob),.bx(bx),.by(by),.bw(bw),.bh(bh),.result_valid(rv),.found(rf),.score_product(rs),.box_x(rx),.box_y(ry),.box_size(rz),.center_x(rcx),.center_y(rcy));
 reg[74:0]expected;reg pending=0;integer frames=0,seed=291021,t,j,n,waits,positives=0;
 always @(posedge clk)begin #1;if(rst)begin
  if(rv)begin if(pending)$fatal(1,"overlapping reference result");expected={rf,rs,rx,ry,rz,rcx,rcy};pending=1;end
  if(dv)begin
   if(!pending||{df,ds,dx,dy,dz,dcx,dcy}!==expected)$fatal(1,"decoder mismatch frame%0d got%h expected%h",frames,{df,ds,dx,dy,dz,dcx,dcy},expected);
   pending=0;frames=frames+1;if(df)positives=positives+1;
  end
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(t=0;t<1000;t=t+1)begin
   fs=1;iv=0;il=0;@(negedge clk);fs=0;n=1+($random(seed)&127);
   for(j=0;j<n;j=j+1)begin
    iv=j==n-1||($random(seed)&3)!=0;il=j==n-1;
    lev=($random(seed)&127)%3;gx=$random(seed)&31;gy=$random(seed)&31;
    cl=$random(seed);ob=$random(seed);bx=$random(seed);by=$random(seed);bw=$random(seed);bh=$random(seed);
    @(negedge clk);
   end
   iv=0;il=0;waits=0;
   while(!dv&&waits<30)begin @(negedge clk);waits=waits+1;end
   if(!dv)$fatal(1,"decoder result watchdog");
   repeat(2)@(negedge clk);
  end
  if(frames!=1000)$fatal(1,"missing results %0d",frames);
  $display("PASS tb_yunet_decode_timing: 1000 randomized frame results match original, %0d positives, all levels, gaps and border clipping",positives);$finish;
 end
 initial begin #10000000;$fatal(1,"decoder watchdog");end
endmodule