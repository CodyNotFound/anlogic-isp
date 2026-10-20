`timescale 1ns/1ps
module tb_vision_sampler;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enable=1,sof=0,eol=0,de=0;
 reg [23:0] rgb;wire fs,sv,fe,err;wire [7:0] sx,sy,gray;wire [23:0] srgb;
 reg [23:0] pixels[0:3071],expected[0:47];
 integer x,y,checked=0,errors=0,starts=0;reg checking=1;integer gy;
 vision_rgb_sampler #(.WIDTH(64),.HEIGHT(48),.STALL_CYCLES(32)) dut(clk,rst_n,enable,sof,eol,de,rgb,fs,sv,fe,err,sx,sy,srgb,gray);
 always @(posedge clk)begin
  #1;
  if(rst_n)begin
   if(err)errors=errors+1;if(fs)starts=starts+1;
   if(sv && checking)begin
    if(checked>=48 || srgb!==expected[checked] || sx!==checked%8 || sy!==checked/8 || fe!==(checked==47))$fatal(1,"sampler index %0d got %h at %0d,%0d",checked,srgb,sx,sy);
    gy=(expected[checked][23:16]+2*expected[checked][15:8]+expected[checked][7:0])/4;
    if(gray!==gy)$fatal(1,"sample luma");checked=checked+1;
   end
  end
 end
 initial begin
  $readmemh("sim/vision_tasks/sampler_rgb.hex",pixels);$readmemh("sim/vision_tasks/sampler_expected.hex",expected);
  repeat(4)@(negedge clk);rst_n=1;
  for(y=0;y<48;y=y+1)begin
   for(x=0;x<64;x=x+1)begin
    @(negedge clk);de=1;sof=x==0&&y==0;eol=x==63;rgb=pixels[y*64+x];
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(3+y%4)@(negedge clk);
  end
  repeat(4)@(negedge clk);if(checked!=48 || starts!=1 || errors!=0)$fatal(1,"sampler complete counts");checking=0;
  // Short row; a bad frame must not publish any partial-frame completion.
  @(negedge clk);sof=1;de=1;eol=0;@(negedge clk);sof=0;eol=1;
  @(negedge clk);de=0;eol=0;repeat(3)@(negedge clk);if(errors!=1)$fatal(1,"short row not rejected");
  // Premature SOF and a stopped source are independent abort cases.
  @(negedge clk);sof=1;@(negedge clk);sof=0;@(negedge clk);sof=1;
  @(negedge clk);sof=0;repeat(3)@(negedge clk);if(errors!=2)$fatal(1,"premature SOF not rejected");
  @(negedge clk);sof=1;@(negedge clk);sof=0;repeat(36)@(negedge clk);
  if(errors!=3)$fatal(1,"stopped source not rejected");
  enable=0;repeat(4)@(negedge clk);if(sv||fs||fe)$fatal(1,"sampler disabled");
  $display("PASS tb_vision_sampler: 3072 native RGB pixels, 48 rounded RGB/luma blocks, 3 abort cases");$finish;
 end
 initial begin #1000000;$fatal(1,"sampler timeout");end
endmodule
