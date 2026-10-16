`timescale 1ns/1ps
module tb_awb_bypass;
 reg clk=0,rst=0,valid=0,user=0,last=0,ready=1,bypass=1;
 reg [95:0] data=0;wire ir,ov,ou,ol;wire[95:0]od;
 frame_awb4 #(.INIT_R_Q8(512),.INIT_B_Q8(410),.MIN_SAMPLES(16)) dut(.I_bypass(bypass),.I_auto_enable(1),.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),.I_tready(ir),.O_tready(ready),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(od));
 integer n,frame,raw_words;reg stats_seen;
 always #5 clk=~clk;
 task beat;input integer index;begin @(negedge clk);valid=1;user=index==0;last=index==15;data={4{24'h285032}};@(posedge clk);#1;if(ov&&frame>0)begin if(od!==data)$fatal(1,"bypass altered RGB got=%h",od);raw_words=raw_words+1;end end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(frame=0;frame<3;frame=frame+1)begin for(n=0;n<16;n=n+1)beat(n);@(negedge clk);valid=0;user=0;last=0;repeat(95)@(negedge clk);if(dut.sample_count===64)stats_seen=1;else $fatal(1,"statistics did not accumulate frame=%0d samples=%0d",frame,dut.sample_count);end
  if(raw_words!=32)$fatal(1,"raw word count=%0d",raw_words);
  if(!stats_seen)$fatal(1,"statistics never accumulated in bypass");
  $display("PASS tb_awb_bypass RGB raw while statistics continue");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
