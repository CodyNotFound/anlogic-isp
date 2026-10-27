`timescale 1ns/1ps
module tb_vision_task_suite;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enabled=1,action=0;reg [3:0] mode=12;
 reg vs=0,hs=0,de=0,sof=0,eol=0;reg [23:0] rgb;
 wire ov,oh,od,os,oe;wire [23:0] op;
 vision_task_suite #(.WIDTH(512),.HEIGHT(384),.RESULT_TTL(3000000)) dut(
  clk,rst_n,enabled,action,mode,sof,eol,de,rgb,vs,hs,de,sof,eol,rgb,ov,oh,od,os,oe,op,,,,,1'b0,1'b1,);
 reg [7:0] track_image[0:3071];reg [23:0] region_image[0:3071];
 reg [23:0] clahe_image[0:196607],clahe_expected[0:196607];
 integer x,y,idx,phase,checked=0,frames=0,track_results=0,region_results=0,prior,waits;
 integer check_mode=0,ex=0,ey=0,ew=0,eh=0,ecx=0,ecy=0;
 reg ef=0,checking=0,within_box,border,crosshair,reticle,panel;reg [23:0] expected,background;
 always @(posedge clk)begin
  #1;
  if(dut.tv)track_results=track_results+1;if(dut.rv)region_results=region_results+1;
  if(rst_n && checking && od)begin
   x=checked%512;y=checked/512;
   if(os!==(checked==0)||oe!==(x==511)||ov!==os||oh!==oe)$fatal(1,"suite qualifier alignment phase %0d pixel %0d",phase,checked);
   if(check_mode==13)expected=clahe_image[checked];
   else if(check_mode==0)expected=clahe_image[checked];
   else begin
    idx=(y/8)*64+x/8;
    background=check_mode==12?{track_image[idx],track_image[idx],track_image[idx]}:region_image[idx];
    within_box=x>=ex && x<ex+ew && y>=ey && y<ey+eh;
    border=ef&&within_box&&(x-ex<2||ex+ew-x<=2||y-ey<2||ey+eh-y<=2);
    crosshair=ef&&((x==ecx&&y+7>=ecy&&y<=ecy+7)||(y==ecy&&x+7>=ecx&&x<=ecx+7));
    reticle=(!ef||check_mode==14)&&((x==256&&y>=180&&y<=204)||(y==192&&x>=244&&x<=268));
    if(check_mode==14 && x>=248&&x<272&&y>=184&&y<208 && (x==248||x==271||y==184||y==207))reticle=1;
    expected=crosshair?24'hff4040:border?24'h00ff40:reticle?24'hffff40:background;
   end
   panel=(check_mode==12||check_mode==14)&&x>=24&&x<408&&y>=48&&y<84;
   if(!panel && op!==expected)$fatal(1,"suite phase %0d x%0d y%0d got %h expected %h",phase,x,y,op,expected);
   checked=checked+1;
  end
 end
 task send_frame;input integer source_kind;
 integer xx,yy,index;
 begin
  checked=0;checking=1;
  for(yy=0;yy<384;yy=yy+1)begin
   for(xx=0;xx<512;xx=xx+1)begin
    @(negedge clk);de=1;sof=xx==0&&yy==0;vs=sof;eol=xx==511;hs=eol;index=(yy/8)*64+xx/8;
    if(source_kind==12)rgb={track_image[index],track_image[index],track_image[index]};
    else if(source_kind==14)rgb=region_image[index];else rgb=clahe_image[yy*512+xx];
   end
   @(negedge clk);de=0;sof=0;vs=0;eol=0;hs=0;repeat(8)@(negedge clk);
  end
  repeat(12)@(negedge clk);checking=0;
  if(checked!=196608)$fatal(1,"suite frame count phase%0d got%0d",phase,checked);
  frames=frames+1;$display("PASS native suite phase %0d mode %0d pixels=%0d",phase,mode,checked);
 end endtask
 task wait_tracker;
 begin waits=0;while(track_results==prior&&waits<2300000)begin @(negedge clk);waits=waits+1;end
  if(track_results==prior)$fatal(1,"suite tracker did not complete");repeat(30)@(negedge clk);end
 endtask
 task wait_region;
 begin waits=0;while(region_results==prior&&waits<200000)begin @(negedge clk);waits=waits+1;end
  if(region_results==prior)$fatal(1,"suite region did not complete");repeat(30)@(negedge clk);end
 endtask
 initial begin
  $readmemh("sim/vision_tasks/suite_clahe_input.hex",clahe_image);$readmemh("sim/vision_tasks/suite_clahe_expected.hex",clahe_expected);
  repeat(4)@(negedge clk);rst_n=1;repeat(600)@(negedge clk);
  $readmemh("sim/vision_tasks/track_seed.hex",track_image);phase=0;check_mode=12;ef=0;prior=track_results;send_frame(12);wait_tracker;
  if(!dut.tf || dut.tx!=32||dut.ty!=24)$fatal(1,"suite acquisition");
  $readmemh("sim/vision_tasks/track_move.hex",track_image);phase=1;ef=1;ex=192;ey=128;ew=128;eh=128;ecx=256;ecy=192;
  prior=track_results;send_frame(12);wait_tracker;
  if(!dut.tf || dut.tx!=37||dut.ty!=21)$fatal(1,"suite translated RGB input");
  phase=2;ex=232;ey=104;ecx=296;ecy=168;prior=track_results;send_frame(12);wait_tracker;
  repeat(3000010)@(negedge clk);if(dut.valid)$fatal(1,"suite stale target TTL without SOF");
  // A user action cancels lock, waits for a new complete frame, rejects flat ROI.
  action=1;@(negedge clk);action=0;$readmemh("sim/vision_tasks/track_flat.hex",track_image);
  phase=3;ef=0;prior=track_results;send_frame(12);wait_tracker;if(dut.tf)$fatal(1,"suite flat patch accepted");
  mode=14;repeat(8)@(negedge clk);$readmemh("sim/vision_tasks/region_pick.hex",region_image);
  phase=4;check_mode=14;ef=0;prior=region_results;send_frame(14);wait_region;
  if(!dut.rc||dut.rf)$fatal(1,"suite color acquisition");
  $readmemh("sim/vision_tasks/region_components.hex",region_image);phase=5;prior=region_results;send_frame(14);wait_region;
  if(!dut.rf||dut.ra!=476||dut.rcx!=31||dut.rcy!=21)$fatal(1,"suite region measurement");
  phase=6;ef=1;ex=160;ey=96;ew=192;eh=160;ecx=248;ecy=168;prior=region_results;send_frame(14);wait_region;
  mode=0;repeat(8)@(negedge clk);phase=7;check_mode=0;send_frame(0);
  if(dut.rf||dut.tf)$fatal(1,"suite mode exit retained analytics");
  mode=13;repeat(600)@(negedge clk);phase=8;check_mode=0;send_frame(0);
  phase=9;check_mode=13;send_frame(0);
  mode=0;repeat(12)@(negedge clk);phase=10;check_mode=0;send_frame(0);
  if(frames!=11)$fatal(1,"suite incomplete");
  $display("PASS tb_vision_task_suite: 2162688 native video pixels, real RGB sampling, rotation TRACK/REGION, retired mode13 bypass, mode exit, K4, TTL");$finish;
 end
 initial begin #160000000;$fatal(1,"suite timeout");end
endmodule
