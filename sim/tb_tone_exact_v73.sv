`timescale 1ns/1ps
module tb_tone_exact_v73;
 reg clk=0,rst=0,valid=0,sof=0,eol=0,sat=1,tone=1,ready=1;reg[95:0]rgb=0;always #5 clk=~clk;
 wire vr,vc,sr,sc,er,ec,rr,rc;wire[95:0]pr,pc;
 color_tone4_ref ref0(.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tdata(rgb),.I_tuser(sof),.I_tlast(eol),.I_sat_on(sat),.I_tone_on(tone),.O_tready(ready),.I_tready(rr),.O_tvalid(vr),.O_tuser(sr),.O_tlast(er),.O_tdata(pr));
 color_tone4 opt(.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tdata(rgb),.I_tuser(sof),.I_tlast(eol),.I_sat_on(sat),.I_tone_on(tone),.O_tready(ready),.I_tready(rc),.O_tvalid(vc),.O_tuser(sc),.O_tlast(ec),.O_tdata(pc));
 integer c,y,d,expected,i,n=0;reg advance=1;reg signed[31:0]scaled;
 always @(posedge clk)begin
  advance=ready;#1;if(rst)begin
   if({vr,sr,er,rr}!=={vc,sc,ec,rc}||vr&&pr!==pc)$fatal(1,"stream mismatch at %d",n);
   if(vc&&ready)n=n+4;
  end
 end
 initial begin
  for(c=0;c<256;c=c+1)for(y=0;y<256;y=y+1)begin
   d=c-y;scaled=d*384;expected=y+(scaled>>>8);if(expected<0)expected=0;if(expected>255)expected=255;
   if(opt.sat15(c,y)!==expected[7:0])$fatal(1,"signed arithmetic c%0d y%0d",c,y);
  end
  repeat(5)@(negedge clk);rst=1;
  for(i=0;i<50000;i=i+1)begin
   @(negedge clk);if(advance||!valid)begin valid=1;rgb={$random,$random,$random};sof=i%257==0;eol=i%32==31;sat=(i/257)&1;tone=(i/514)&1;end
   ready=($random&3)!=0;
  end
  @(negedge clk);ready=1;valid=0;repeat(10)@(negedge clk);
  $display("PASS tb_tone_exact_v73: 65536 signed-channel cases and %0d streamed pixels, frame controls and backpressure exact",n);$finish;
 end
endmodule
