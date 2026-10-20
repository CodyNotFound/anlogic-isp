`timescale 1ns/1ps
module tb_vision_clahe;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enable=1,cancel=0,fs=0,sv=0,fe=0,vs=0,hs=0,de=0,sof=0,eol=0;
 reg [7:0] sx,sy,gray;reg [23:0] rgb;
 wire ov,oh,od,os,oe,mv;wire [23:0] op;wire [31:0] built;
 vision_clahe dut(clk,rst_n,enable,cancel,fs,sv,fe,sx,sy,gray,vs,hs,de,sof,eol,rgb,ov,oh,od,os,oe,op,mv,built);
 reg [7:0] sample_data[0:14399],maps[0:479],next_maps[0:479];
 reg [23:0] input_rgb[0:921599],expected[0:921599],next_expected[0:31];
 integer i,x,y,j,waits,bank,checking=0,checked=0,ppm;reg [23:0] want;
 always @(posedge clk)begin
  #1;
  if(rst_n && checking && od)begin
   want=checking==1?expected[checked]:checking==2?next_expected[checked]:24'h243648;
   if(op!==want)$fatal(1,"CLAHE pixel %0d mode=%0d got %h expected %h",checked,checking,op,want);
   if(checking==1)begin
    if(os!==(checked==0)||oe!==(checked%1280==1279)||ov!==os||oh!==oe)$fatal(1,"CLAHE native qualifier alignment");
    $fwrite(ppm,"%c%c%c",op[23:16],op[15:8],op[7:0]);
   end
   if(dut.active_bank!==bank && checking!=3)$fatal(1,"CLAHE bank switched inside frame");
   checked=checked+1;
  end
 end
 task feed_statistics;input integer invert;
 begin
  @(negedge clk);fs=1;@(negedge clk);fs=0;
  for(j=0;j<14400;j=j+1)begin
   sv=1;sx=j%160;sy=j/160;gray=invert?255-sample_data[j]:sample_data[j];fe=j==14399;
   @(negedge clk);sv=0;fe=0;repeat(7)@(negedge clk);
  end
 end endtask
 task verify_map;input integer which;
 begin
  bank=dut.pending_bank;
  for(i=0;i<480;i=i+1)begin
   if(dut.map00[bank*512+i] !== (which?next_maps[i]:maps[i]) ||
      dut.map10[bank*512+i] !== (which?next_maps[i]:maps[i]) ||
      dut.map01[bank*512+i] !== (which?next_maps[i]:maps[i]) ||
      dut.map11[bank*512+i] !== (which?next_maps[i]:maps[i]) ||
      dut.low00[bank*512+i] !== (which?next_maps[i]:maps[i]) || dut.low10[bank*512+i] !== (which?next_maps[i]:maps[i]) ||
      dut.low01[bank*512+i] !== (which?next_maps[i]:maps[i]) || dut.low11[bank*512+i] !== (which?next_maps[i]:maps[i]))$fatal(1,"CLAHE CDF map %0d tile%0d bin%0d",which,i/32,i%32);
  end
 end endtask
 initial begin
  $readmemh("sim/vision_tasks/clahe_input.hex",input_rgb);$readmemh("sim/vision_tasks/clahe_expected.hex",expected);
  $readmemh("sim/vision_tasks/clahe_small.hex",sample_data);$readmemh("sim/vision_tasks/clahe_maps.hex",maps);
  $readmemh("sim/vision_tasks/clahe_next_maps.hex",next_maps);$readmemh("sim/vision_tasks/clahe_next_probe.hex",next_expected);
  ppm=$fopen("reports/vision_tasks/clahe_rtl.ppm","wb");$fwrite(ppm,"P6\n1280 720\n255\n");
  repeat(4)@(negedge clk);rst_n=1;repeat(600)@(negedge clk);
  feed_statistics(0);waits=0;while(built!=1 && waits<30000)begin @(negedge clk);waits=waits+1;end
  if(built!=1||mv)$fatal(1,"CLAHE build did not finish / committed without SOF");verify_map(0);
  $display("PASS CLAHE first histogram/CDF: 480 bins x 8 map replicas");
  checking=1;checked=0;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin
    @(negedge clk);rgb=input_rgb[y*1280+x];de=1;sof=x==0&&y==0;vs=sof;eol=x==1279;hs=eol;
   end
   @(negedge clk);de=0;sof=0;vs=0;eol=0;hs=0;repeat(8)@(negedge clk);
  end
  repeat(12)@(negedge clk);checking=0;$fclose(ppm);if(checked!=921600)$fatal(1,"CLAHE native pixel count %0d",checked);
  if(!mv)$fatal(1,"CLAHE missing active map");
  $display("PASS CLAHE 921600 native RGB pixels + qualifiers");
  feed_statistics(1);waits=0;while(built!=2 && waits<30000)begin @(negedge clk);waits=waits+1;end
  if(built!=2 || dut.active_bank!==bank)$fatal(1,"CLAHE map changed before SOF");verify_map(1);
  checking=2;checked=0;
  for(x=0;x<32;x=x+1)begin @(negedge clk);de=1;sof=x==0;rgb=input_rgb[x];end
  @(negedge clk);de=0;sof=0;repeat(12)@(negedge clk);checking=0;
  if(checked!=32)$fatal(1,"CLAHE next-bank probe incomplete");
  enable=0;repeat(8)@(negedge clk);if(mv)$fatal(1,"CLAHE old map survived disable");checking=3;checked=0;
  for(x=0;x<32;x=x+1)begin @(negedge clk);de=1;sof=x==0;rgb=24'h243648;end
  @(negedge clk);de=0;sof=0;repeat(12)@(negedge clk);checking=0;
  if(checked!=32)$fatal(1,"CLAHE bypass probe incomplete");
  $display("PASS tb_vision_clahe: 2 map banks, 921600 image pixels, atomic SOF update, 32 next-map and 32 bypass pixels");$finish;
 end
 initial begin #30000000;$fatal(1,"CLAHE timeout");end
endmodule
