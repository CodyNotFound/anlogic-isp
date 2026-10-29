`timescale 1ns/1ps
module tb_color_tone_luma;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0,sat=0,tone=0,ready=1;reg[95:0]data=0;
 wire av,au,al,bv,bu,bl;wire[95:0]ad,bd;
 color_tone4 dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_sat_on(sat),.I_tone_on(tone),.I_tdata(data),.I_tready(),.O_tready(ready),.O_tvalid(av),.O_tuser(au),.O_tlast(al),.O_tdata(ad));
 color_tone4_ref reference(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_sat_on(sat),.I_tone_on(tone),.I_tdata(data),.I_tready(),.O_tready(ready),.O_tvalid(bv),.O_tuser(bu),.O_tlast(bl),.O_tdata(bd));
 integer i,j,seed=291026,n=0;
 always @(posedge clk)begin #1;if(rst)begin
  if({av,au,al,ad}!=={bv,bu,bl,bd})$fatal(1,"color pipeline mismatch cycle%0d",n);
  n=n+1;
 end end
 initial begin
  for(i=0;i<256;i=i+1)begin #1;if(dut.tone_value(i)!==reference.tone_value(i))$fatal(1,"gamma mismatch %0d",i);end
  for(i=0;i<16777216;i=i+1)begin
   if(dut.pixel_luma(i)!==reference.pixel_luma(i))$fatal(1,"luma mismatch rgb%h",i);
  end
  $display("PASS luma exhaustive: 16777216 RGB combinations");
  repeat(4)@(negedge clk);rst=1;
  for(i=0;i<50000;i=i+1)begin
   for(j=0;j<3;j=j+1)data[j*32+:32]=$random(seed);
   v=($random(seed)&7)!=0;u=i%128==0;l=i%32==31;
   ready=($random(seed)&3)!=0;sat=i[11];tone=i[12];@(negedge clk);
  end
  $display("PASS tb_color_tone_luma: all RGB luma values, 256 exact gamma levels, 50000 full RGB pipeline random/stall/toggle cycles");$finish;
 end
endmodule
