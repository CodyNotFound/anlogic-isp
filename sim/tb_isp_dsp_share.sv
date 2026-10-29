`timescale 1ns/1ps
module tb_awb_dsp_share;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0,auto_en=0,bypass=0,ready=1;reg [95:0] data=0;
 wire av,au,al,bv,bu,bl;wire [95:0] ad,bd;
 frame_awb4 #(.MIN_SAMPLES(64)) dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_auto_enable(auto_en),.I_bypass(bypass),.I_tdata(data),.I_tready(),.O_tready(ready),.O_tvalid(av),.O_tuser(au),.O_tlast(al),.O_tdata(ad));
 frame_awb4_throughput_ref #(.MIN_SAMPLES(64)) reference(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_auto_enable(auto_en),.I_bypass(bypass),.I_tdata(data),.I_tready(),.O_tready(ready),.O_tvalid(bv),.O_tuser(bu),.O_tlast(bl),.O_tdata(bd));
 integer seed=20261029,g,p,i,n=0;reg [9:0] gr,gb;
 always @(posedge clk)begin #1;if(rst)begin
  if({av,au,al,ad,dut.beat_sum_r,dut.beat_sum_g,dut.beat_sum_b,dut.beat_count,dut.gain_r_q8,dut.gain_b_q8,dut.sum_r,dut.sum_g,dut.sum_b,dut.sample_count}!=={bv,bu,bl,bd,reference.beat_sum_r,reference.beat_sum_g,reference.beat_sum_b,reference.beat_count,reference.gain_r_q8,reference.gain_b_q8,reference.sum_r,reference.sum_g,reference.sum_b,reference.sample_count})$fatal(1,"AWB mismatch cycle%0d",n);
  n=n+1;
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  force dut.gain_r_q8=gr;force reference.gain_r_q8=gr;force dut.gain_b_q8=gb;force reference.gain_b_q8=gb;
  for(g=0;g<1024;g=g+1)for(p=0;p<256;p=p+1)begin
   gr=g;gb=1023-g;for(i=0;i<12;i=i+1)data[i*8+:8]=p+i*37;
   v=1;u=p==0;l=p==255;ready=p%7!=0;@(negedge clk);
  end
  release dut.gain_r_q8;release reference.gain_r_q8;release dut.gain_b_q8;release reference.gain_b_q8;
  rst=0;repeat(4)@(negedge clk);rst=1;auto_en=1;
  for(p=0;p<40000;p=p+1)begin
   for(i=0;i<3;i=i+1)data[i*32+:32]=$random(seed);
   v=($random(seed)&7)!=0;u=p%128==0;l=p%32==31;ready=($random(seed)&3)!=0;
   auto_en=p%2000<1600;bypass=p[10];@(negedge clk);
  end
  $display("PASS tb_awb_dsp_share: all 1024 gains x 256 input levels, 40000 adaptation/stall/bypass cycles, RGB and statistics exact");$finish;
 end
 initial begin #5000000;$fatal(1,"AWB watchdog");end
endmodule

module tb_lsc_dsp_share;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0,blc=1,lsc=1,ready=1;reg [39:0] data=0;reg [9:0] dest=0;
 wire av,au,al,bv,bu,bl;wire [39:0] ad,bd;wire [9:0] at,bt;
 raw_lsc_grid4 dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_blc_on(blc),.I_lsc_on(lsc),.I_tdata(data),.I_tdest(dest),.I_tready(),.O_tready(ready),.O_tvalid(av),.O_tuser(au),.O_tlast(al),.O_tdata(ad),.O_tdest(at));
 raw_lsc_grid4_throughput_ref reference(.I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_blc_on(blc),.I_lsc_on(lsc),.I_tdata(data),.I_tdest(dest),.I_tready(),.O_tready(ready),.O_tvalid(bv),.O_tuser(bu),.O_tlast(bl),.O_tdata(bd),.O_tdest(bt));
 integer seed=20261030,f,y,x,i,n=0,delta,offset,a,b;reg [7:0] f0,f2;reg [23:0] pair_result;
 always @(posedge clk)begin #1;if(rst)begin
  if({av,au,al,ad,at}!=={bv,bu,bl,bd,bt})$fatal(1,"LSC mismatch cycle%0d",n);
  if(dut.s2_valid&&((dut.s2_x_fraction2-dut.s2_x_fraction0)!=6&&(dut.s2_x_fraction2-dut.s2_x_fraction0)!=7))$fatal(1,"LSC fraction contract violated");
  n=n+1;
 end end
 initial begin
  for(delta=-4095;delta<=4095;delta=delta+1)for(offset=0;offset<80;offset=offset+4)begin
   a=delta<0?-delta:0;b=a+delta;f0=offset*256/80;f2=(offset+2)*256/80;
   pair_result=dut.interp_pair(a,b,f0,f2);
   if(pair_result!=={reference.interp_gain(a,b,f2),reference.interp_gain(a,b,f0)})$fatal(1,"LSC pair mismatch delta%0d offset%0d",delta,offset);
  end
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<3;f=f+1)begin
   blc=f!=1;lsc=f!=1;
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    v=1;u=y==0&&x==0;l=x==319;dest=x;
    for(i=0;i<4;i=i+1)data[i*10+:10]=$random(seed);
    if(($random(seed)&3)==0)begin ready=0;@(negedge clk);end
    ready=1;@(negedge clk);
   end
  end
  v=0;repeat(8)@(negedge clk);
  $display("PASS tb_lsc_dsp_share: all 8191 signed deltas x 20 positions, three complete 720p frames, exact RGB/metadata/stalls/BLC/LSC bypass");$finish;
 end
 initial begin #15000000;$fatal(1,"LSC watchdog");end
endmodule
