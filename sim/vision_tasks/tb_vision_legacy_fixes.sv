`timescale 1ns/1ps
module tb_vision_legacy_fixes;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,de=0,sof=0,eol=0;reg [23:0] rgb;wire [23:0] adaptive,fixed_binary,blur;
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(4),.ADAPTIVE_BINARY(1)) a(clk,rst_n,4'd3,sof,eol,de,rgb,adaptive);
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(4),.ADAPTIVE_BINARY(0)) f(clk,rst_n,4'd3,sof,eol,de,rgb,fixed_binary);
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(4)) b(clk,rst_n,4'd6,sof,eol,de,rgb,blur);
 integer x,y,frame;reg [23:0] ao,fo,bo;
 task send_frame;input [7:0] gray;
 begin
  for(y=0;y<4;y=y+1)begin
   for(x=0;x<16;x=x+1)begin
    @(negedge clk);de=1;sof=x==0&&y==0;eol=x==15;rgb={gray,gray,gray};
    @(posedge clk);#1;if(x==10&&y==3)begin ao=adaptive;fo=fixed_binary;bo=blur;end
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(3)@(negedge clk);
  end
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  send_frame(100);if(ao!==24'hffffff||fo!==24'hffffff)$fatal(1,"binary initial threshold");
  send_frame(100);if(ao!==24'h000000||fo!==24'hffffff)$fatal(1,"adaptive threshold not applied to pixels");
  send_frame(200);if(bo!==24'hc8c8c8)$fatal(1,"blur changes uniform bright signal %h",bo);
  send_frame(32);if(bo!==24'h202020)$fatal(1,"blur changes uniform dark signal %h",bo);
  $display("PASS tb_vision_legacy_fixes: adaptive-vs-fixed behavior and dark/bright DC preservation");$finish;
 end
 initial begin #100000;$fatal(1,"legacy fixes timeout");end
endmodule
