`timescale 1ns/1ps
module tb_face_motion_photos;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=1,seed=0,fs=0,fe=0,err=0,sv=0,adaptive=0;
 reg [7:0] seed_x,seed_y,sx,sy,g;
 wire valid,found,busy;wire [7:0] x,y;wire [31:0] cycles;wire [15:0] sad;
 face_patch_motion dut(clk,rst,en,seed,fs,fe,err,sv,seed_x,seed_y,sx,sy,g,valid,found,x,y,busy,cycles,sad,adaptive);
 reg [7:0] frames[0:863999];string dir;
 integer fd,rc,cases,nframes,c,f,i,j,cursor=0,ex,ey,ef,es,ix,iy,ad,seen=0,before_seen;
 reg got_found;reg [7:0] got_x,got_y;reg [15:0] got_sad;
 always @(posedge clk)begin #1;if(valid)begin seen=seen+1;got_found=found;got_x=x;got_y=y;got_sad=sad;end end
 task tick;begin @(negedge clk);end endtask
 initial begin
  if(!$value$plusargs("DATA_DIR=%s",dir))$fatal(1,"DATA_DIR required");
  $readmemh({dir,"/frames.hex"},frames);
  fd=$fopen({dir,"/expected.txt"},"r");if(!fd)$fatal(1,"missing expected");
  rc=$fscanf(fd,"%d\n",cases);if(rc!=1||cases!=30)$fatal(1,"case count");
  for(c=0;c<cases;c=c+1)begin
   rst=0;seed=0;sv=0;fe=0;fs=0;repeat(5)tick;
   rc=$fscanf(fd,"%d %d %d %d\n",ix,iy,ad,nframes);if(rc!=4)$fatal(1,"bad case header");
   rst=1;seed_x=ix;seed_y=iy;adaptive=ad;tick;seed=1;tick;seed=0;
   for(f=0;f<nframes;f=f+1)begin
    before_seen=seen;tick;fs=1;tick;fs=0;
    for(j=0;j<90;j=j+1)for(i=0;i<160;i=i+1)begin
     sx=i;sy=j;g=frames[cursor];cursor=cursor+1;sv=1;fe=i==159&&j==89;tick;
    end
    sv=0;fe=0;repeat(65000)tick;
    rc=$fscanf(fd,"%d %d %d %d\n",ex,ey,ef,es);
    if(rc!=4||seen!=before_seen+1)$fatal(1,"missing result case%0d frame%0d",c,f);
    if({got_x,got_y,got_found,got_sad}!=={8'(ex),8'(ey),1'(ef),16'(es)})
     $fatal(1,"photo case%0d frame%0d got=%0d,%0d found%0d SAD%0d expected=%0d,%0d found%0d SAD%0d",c,f,got_x,got_y,got_found,got_sad,ex,ey,ef,es);
   end
  end
  $display("PASS tb_face_motion_photos: 21 transformed photo pairs + 9 negative pairs, exact coordinates/reject/gradient SAD");$finish;
 end
 initial begin #100000000;$fatal(1,"photo watchdog");end
endmodule
