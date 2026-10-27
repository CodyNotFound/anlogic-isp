`timescale 1ns/1ps
module tb_gimbal_panel;
 reg clk=0,rst=0,manual=0;reg [3:0] keys=15,features=0;
 wire [3:0] pressed,normal,leds;wire [7:0] seg,sel;wire [23:0] hd,vd;wire [11:0] dh,dv;
 reg [11:0] ph=1500,pv=1500;
 gimbal_button_router #(.DEBOUNCE_CYCLES(4)) router(clk,rst,manual,keys,pressed,normal);
 gimbal_panel #(.CLK_HZ(1000000)) panel(clk,rst,features,ph,pv,leds,seg,sel,hd,vd,dh,dv);
 always #5 clk=~clk;
 task waitc;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
 function [7:0] encode;input integer d;begin case(d)
 0:encode='hc0;1:encode='hf9;2:encode='ha4;3:encode='hb0;4:encode='h99;
 5:encode='h92;6:encode='h82;7:encode='hf8;8:encode='h80;9:encode='h90;
 default:encode='hff;endcase end endfunction
 integer i,j,count=0;reg [7:0] last_sel=255,last_seg=255;reg scanning=0;
 always @(negedge clk)if(rst)begin
  if(sel!=255 && ((~sel & 8'hff) & ((~sel & 8'hff)-1))!=0)$fatal(1,"multiple digits selected");
  if(sel!=255 && last_sel!=255 && seg!=last_seg)$fatal(1,"segment changed without blank");
  if(scanning && sel!=255 && sel!=last_sel)begin
   for(j=0;j<8;j=j+1)if(sel==((~(1<<j)) & 8'hff))begin
    if(seg!==encode(j<4?((32'h2150>>((3-j)*4))&15):((32'h1050>>((7-j)*4))&15)))
     $fatal(1,"digit order/value %0d seg=%h",j,seg);
   end
   count=count+1;
  end
  last_sel=sel;last_seg=seg;
 end
 initial begin
  waitc(5);rst=1;waitc(12);
  keys=14;waitc(2);keys=15;waitc(12);if(pressed!=0)$fatal(1,"bounce");
  manual=1;keys=7;waitc(12);if(pressed!=8||normal!=15)$fatal(1,"manual routing");
  manual=0;waitc(12);if(normal!=15)$fatal(1,"held key leaked at exit");
  keys=15;waitc(12);keys=7;waitc(12);if(normal!=7)$fatal(1,"release rearm");
  ph=2150;pv=1050;features=4'b1011;waitc(17000);
  if(hd!=24'h002150||vd!=24'h001050||dh!=2150||dv!=1050||leds!=4'b1011)$fatal(1,"BCD/LED states");
  scanning=1;waitc(9000);if(count<8)$fatal(1,"scan did not cover digits");
  $display("PASS tb_gimbal_panel: debounce, manual interlock, BCD, digit order, blanking, LEDs");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
