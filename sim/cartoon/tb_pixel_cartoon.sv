`timescale 1ns/1ps
module tb_pixel_cartoon #(parameter WIDTH=640,HEIGHT=360,SEQUENCE=0);
 wire [23:0] edge_out;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_start=0,line_end=0,de=0;reg [23:0] pixel_in=0;
 wire [23:0] pixel_out;wire out_de,out_sof,out_eol;
 pixel_cartoon #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) dut(.*);
 reg [23:0] image[0:WIDTH*HEIGHT-1],expected[0:WIDTH*HEIGHT-1];
 reg [3:0] dh=0,fh=0,lh=0;
 integer x,y,f,checked=0,index=0,lines=0,frames=0,fd=0,total=0;
 string name,case_name;
 always @(posedge clk)begin
  if(!rst_n)begin dh=0;fh=0;lh=0;end
  else begin
   dh={dh[2:0],de};fh={fh[2:0],frame_start};lh={lh[2:0],line_end};
   #1;
   if(out_de!==dh[3]||out_sof!==fh[3]||out_eol!==lh[3])$fatal(1,"qualifier latency %b/%b/%b",out_de,out_sof,out_eol);
   if(out_sof)begin index=0;frames=frames+1;end
   if(out_de)begin
    if(index>=WIDTH*HEIGHT)$fatal(1,"extra active pixel");
    if(pixel_out!==expected[index])$fatal(1,"reference %s frame%0d x%0d y%0d got%h expected%h",case_name,f,index%WIDTH,index/WIDTH,pixel_out,expected[index]);
    if(fd)$fwrite(fd,"%c%c%c",pixel_out[23:16],pixel_out[15:8],pixel_out[7:0]);
    index=index+1;checked=checked+1;total=total+1;
   end else if(pixel_out!==0)$fatal(1,"blanking output");
   if(out_eol)lines=lines+1;
  end
 end
 initial begin
  if(!$value$plusargs("CASE=%s",name))name="lena";
  repeat(4)@(negedge clk);rst_n=1;
  for(f=0;f<(SEQUENCE?5:1);f=f+1)begin
   if(SEQUENCE)case(f)0:case_name="white";1:case_name="black";2:case_name="isoluma";3:case_name="noise";default:case_name="ramp";endcase
   else case_name=name;
   $readmemh({"sim/cartoon/",case_name,".hex"},image);
   $readmemh({"sim/cartoon/",case_name,".expected"},expected);
   checked=0;lines=0;
   if(!SEQUENCE)begin fd=$fopen({"reports/cartoon_v41/",name,"_rtl.ppm"},"wb");$fwrite(fd,"P6\n%0d %0d\n255\n",WIDTH,HEIGHT);end
   if(f%2)begin @(negedge clk);frame_start=1;de=0;@(negedge clk);frame_start=0;end
   for(y=0;y<HEIGHT;y=y+1)begin
    for(x=0;x<WIDTH;x=x+1)begin
     @(negedge clk);de=1;frame_start=!(f%2)&&x==0&&y==0;line_end=x==WIDTH-1;pixel_in=image[y*WIDTH+x];
     if(SEQUENCE && x%7==3)begin @(negedge clk);de=0;frame_start=0;line_end=0;pixel_in=24'hdeadbe;repeat(2)@(negedge clk);end
    end
    @(negedge clk);de=0;frame_start=0;line_end=0;repeat(4)@(negedge clk);
   end
   repeat(8)@(negedge clk);
   if(checked!=WIDTH*HEIGHT||lines!=HEIGHT)$fatal(1,"frame dimensions %0d/%0d",checked,lines);
   if(fd)begin $fclose(fd);fd=0;end
  end
  if(frames!=(SEQUENCE?5:1))$fatal(1,"frame marker count");
  // Reset while pixels are in flight; no stale valid/marker may escape reset.
  @(negedge clk);de=1;frame_start=1;pixel_in=24'hffffff;
  @(negedge clk);rst_n=0;de=0;frame_start=0;
  repeat(5)@(negedge clk);
  if(out_de||out_sof||out_eol||pixel_out!==0)$fatal(1,"reset output");
  $display("PASS tb_pixel_cartoon %s: %0d exact RGB pixels, synchronous line RAM, four-cycle qualifiers, borders, blanking, reset; sequence=%0d",name,total,SEQUENCE);$finish;
 end
 initial begin #20000000;$fatal(1,"cartoon watchdog");end
endmodule
