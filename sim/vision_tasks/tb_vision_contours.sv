`timescale 1ns/1ps
module tb_vision_contours;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,de=0,sof=0,eol=0;reg [23:0] rgb;
 wire [23:0] edge_out,dir_out,focus_out,sharp_out,bin_out;
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(8)) e(clk,rst_n,4'd7,sof,eol,de,rgb,edge_out);
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(8)) d(clk,rst_n,4'd10,sof,eol,de,rgb,dir_out);
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(8)) f(clk,rst_n,4'd9,sof,eol,de,rgb,focus_out);
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(8)) s(clk,rst_n,4'd5,sof,eol,de,rgb,sharp_out);
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(8)) b(clk,rst_n,4'd3,sof,eol,de,rgb,bin_out);
 integer frame,x,y,value;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(frame=0;frame<4;frame=frame+1)begin
   for(y=0;y<8;y=y+1)begin
    for(x=0;x<16;x=x+1)begin
     @(negedge clk);de=1;sof=x==0&&y==0;eol=x==15;
     case(frame)
      0:value=x>=1?200:32;
      1:value=y>=1?200:32;
      2:value=x==5&&y==3?200:32;
      3:value=32+x*8;
     endcase
     rgb={value[7:0],value[7:0],value[7:0]};
     @(posedge clk);#1;
     if(frame==0&&x==1&&y==0)begin
      if(edge_out==0||dir_out[15:0]!=0||dir_out[23:16]==0)$fatal(1,"dead top/left contour or wrong direction");
      if(focus_out!=24'hff3030)$fatal(1,"focus edge missing");
     end
     if(frame==1&&x==0&&y==1 && (dir_out[23:16]!=0||dir_out[7:0]!=0||dir_out[15:8]==0))$fatal(1,"horizontal contour");
     if(frame==2&&x==6&&y==4 && sharp_out!=24'hffffff)$fatal(1,"sharpen center misaligned %h",sharp_out);
     if(frame==3&&x>2&&bin_out!=24'hffffff)$fatal(1,"local threshold fails smooth illumination ramp");
    end
    @(negedge clk);de=0;sof=0;eol=0;repeat(3)@(negedge clk);
    if(edge_out!=0)$fatal(1,"blanking");
   end
  end
  $display("PASS tb_vision_contours: border contours, orientation, focus, sharpen center, illumination ramp, blanking");$finish;
 end
endmodule
