`timescale 1ns/1ps
module tb_pixel_cartoon_timing;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,sof=0,eol=0;reg[23:0]rgb=0;
 wire[23:0]ap,ae,ash,ab,am,bp,be,bsh,bb,bm;wire ad,af,al,bd,bf,bl;
 pixel_cartoon #(.IMG_WIDTH(16),.IMG_HEIGHT(12),.EXTRA_EFFECTS(1)) dut(.clk(clk),.rst_n(rst),.frame_start(sof),.line_end(eol),.de(de),.pixel_in(rgb),.pixel_out(ap),.out_de(ad),.out_sof(af),.out_eol(al),.edge_out(ae),.sharpen_out(ash),.blur_out(ab),.emboss_out(am));
 pixel_cartoon_timing_ref #(.IMG_WIDTH(16),.IMG_HEIGHT(12),.EXTRA_EFFECTS(1)) reference(.clk(clk),.rst_n(rst),.frame_start(sof),.line_end(eol),.de(de),.pixel_in(rgb),.pixel_out(bp),.out_de(bd),.out_sof(bf),.out_eol(bl),.edge_out(be),.sharpen_out(bsh),.blur_out(bb),.emboss_out(bm));
 integer f,x,y,seed=291022,cycles=0;
 always @(posedge clk)begin #1;if(rst)begin
  if({ad,af,al,ap,ae,ash,ab,am}!=={bd,bf,bl,bp,be,bsh,bb,bm})$fatal(1,"spatial effect mismatch cycle%0d",cycles);
  cycles=cycles+1;
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<100;f=f+1)begin
   for(y=0;y<12;y=y+1)for(x=0;x<16;x=x+1)begin
    de=1;sof=x==0&&y==0;eol=x==15;
    rgb=f%4==0?24'h000000:f%4==1?24'hffffff:$random(seed);
    @(negedge clk);
    if(($random(seed)&3)==0)begin de=0;sof=0;eol=0;@(negedge clk);end
   end
   de=0;sof=0;eol=0;repeat(16)@(negedge clk);
  end
  $display("PASS tb_pixel_cartoon_timing: 100 black/white/random frames, stalls, borders; cartoon edge sharp blur emboss and sync exact");$finish;
 end
endmodule