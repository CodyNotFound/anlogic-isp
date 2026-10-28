`timescale 1ns/1ps
module tb_region_reticle;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;reg[3:0]mode=13;reg found=0,vs=0,hs=0,de=0,sof=0,eol=0;
 wire ovs,ohs,ode,osof,oeol;wire[23:0]rgb;
 vision_task_hud #(.WIDTH(64),.HEIGHT(48),.TEXT_ENABLE(0)) dut(
 .clk(clk),.rst_n(rst),.mode(mode),.enable(1'b1),.result_valid(1'b0),.found(found),.calibrated(1'b1),.overflow(1'b0),.lost(2'd0),
 .box_x(12'd4),.box_y(12'd4),.box_w(12'd12),.box_h(12'd12),.center_x(12'd10),.center_y(12'd10),.metric(20'd0),
 .vsync(vs),.hsync(hs),.de(de),.sof(sof),.eol(eol),.rgb(24'h123456),
 .out_vsync(ovs),.out_hsync(ohs),.out_de(ode),.out_sof(osof),.out_eol(oeol),.out_rgb(rgb),.pick_pending(1'b0),.manual_mode(1'b0));
 integer f,x,y,n=0,ox,oy,yellow=0;reg checking=0;reg[23:0]want;
 always @(posedge clk)begin
  #1;
  if(checking&&ode)begin
   ox=n%64;oy=n/64;want=24'h123456;
   if((ox==32&&oy>=12&&oy<=36)||(oy==24&&ox>=20&&ox<=44))want=24'hffff40;
   if(found)begin
    if(ox>=4&&ox<16&&oy>=4&&oy<16&&(ox<7||ox>=13||oy<7||oy>=13))want=24'h00ff40;
    if((ox>=9&&ox<=11&&oy>=3&&oy<=17)||(oy>=9&&oy<=11&&ox>=3&&ox<=17))want=24'hff4040;
   end
   if(rgb!==want)$fatal(1,"frame%0d pixel(%0d,%0d) got%h want%h",f,ox,oy,rgb,want);
   if(osof!==(n==0)||oeol!==(ox==63)||ovs!==osof||ohs!==oeol)$fatal(1,"qualifier mismatch");
   if(rgb==24'hffff40)yellow=yellow+1;
   n=n+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<3;f=f+1)begin
   found=f==1;mode=f==2?12:13;n=0;yellow=0;checking=1;
   for(y=0;y<48;y=y+1)begin
    for(x=0;x<64;x=x+1)begin de=1;sof=x==0&&y==0;vs=sof;eol=x==63;hs=eol;@(negedge clk);end
    de=0;sof=0;eol=0;vs=0;hs=0;repeat(4)@(negedge clk);
   end
   repeat(4)@(negedge clk);checking=0;
   if(n!=3072||yellow!=49)$fatal(1,"unexpected pixel count %0d or cross pixels %0d",n,yellow);
  end
  $display("PASS tb_region_reticle: centered cross only; detected target border and timing preserved; 9216 exact pixels");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
