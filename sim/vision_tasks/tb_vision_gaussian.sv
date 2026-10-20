`timescale 1ns/1ps
module tb_vision_gaussian;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,de=0,sof=0,eol=0;reg [23:0] rgb;wire [23:0] out;
 reg [7:0] expected_queue[0:255];reg [3:0] de_history=0;
 reg [23:0] image[0:127];integer frame,x,y,i,dx,dy,sum,weight,g,expected,checked=0;
 pixel_algorithm #(.IMG_WIDTH(16),.IMG_HEIGHT(8)) dut(clk,rst_n,4'd6,sof,eol,de,rgb,out);
 always @(posedge clk)begin
  if(!rst_n)de_history=0;
  else begin de_history={de_history[2:0],de};#1;
   if(de_history[3])begin
    if(out!=={expected_queue[checked],expected_queue[checked],expected_queue[checked]})$fatal(1,"Gaussian pipeline pixel%0d got%h expected%0d",checked,out,expected_queue[checked]);
    checked=checked+1;
   end
  end
 end
 function integer gray;input [23:0] p;
  begin gray=(p[23:16]>>2)+(p[15:8]>>1)+(p[7:0]>>2);end
 endfunction
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(frame=0;frame<2;frame=frame+1)begin
   for(y=0;y<8;y=y+1)for(x=0;x<16;x=x+1)
    image[y*16+x]=frame==0?(((x*23+y*51)&255)<<16)|(((x*7+y*19)&255)<<8)|((x*37+y*11)&255):
        (((x+y)%2?255:0)<<16)|((x*17)<<8)|(y*31);
   if(frame==1)begin @(negedge clk);sof=1;de=0;@(negedge clk);sof=0;end
   for(y=0;y<8;y=y+1)begin
    for(x=0;x<16;x=x+1)begin
     @(negedge clk);de=1;sof=frame==0&&x==0&&y==0;eol=x==15;rgb=image[y*16+x];
     expected=gray(rgb);
     if(y>=2&&x>=2)begin
      sum=0;
      for(dy=0;dy<3;dy=dy+1)for(dx=0;dx<3;dx=dx+1)begin
       weight=(dx==1?2:1)*(dy==1?2:1);sum=sum+weight*gray(image[(y-2+dy)*16+x-2+dx]);
      end
      expected=(sum+8)/16;
     end
     expected_queue[frame*128+y*16+x]=expected;
     @(posedge clk);#1;
    end
    @(negedge clk);de=0;sof=0;eol=0;repeat(3)@(negedge clk);
   end
  end
  repeat(6)@(negedge clk);if(checked!=256)$fatal(1,"Gaussian pixel count");
  $display("PASS tb_vision_gaussian: 256 nonuniform RGB pixels, coincident and blank SOF, borders and frame history");$finish;
 end
 initial begin #100000;$fatal(1,"Gaussian timeout");end
endmodule
