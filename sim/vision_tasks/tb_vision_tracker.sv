`timescale 1ns/1ps
module tb_vision_tracker;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,fs=0,sv=0,fe=0;reg [7:0] gray;
 wire [1:0] unused_lost;wire rv,found,busy;wire [7:0] cx,cy,quality;wire [17:0] best,second;wire [31:0] cycles;
 vision_sad_tracker #(.WIDTH(64),.HEIGHT(48),.ROTATION_ENABLE(0)) dut(clk,rst_n,reseed,fs,sv,fe,gray,rv,found,cx,cy,quality,best,second,busy,cycles,unused_lost);
 reg [7:0] pixels[0:3071];string name;integer f,csv,n,action,er,ef,ex,ey,eb,es,eq,i,waits,checked=0;
 initial begin
  f=$fopen("sim/vision_tasks/tracker_cases.txt","r");csv=$fopen("reports/vision_tasks/tracker_rtl.csv","w");
  $fwrite(csv,"name,result,found,x,y,best,second,quality,cycles\n");
  repeat(4)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   n=$fscanf(f,"%s %d %d %d %d %d %d %d %d\n",name,action,er,ef,ex,ey,eb,es,eq);
   if(n!=9)$fatal(1,"tracker case parse");
   if(action==1)begin rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
   if(action==2)begin reseed=1;@(negedge clk);reseed=0;end
   $readmemh({"sim/vision_tasks/",name,".hex"},pixels);
   @(negedge clk);fs=1;@(negedge clk);fs=0;
   for(i=0;i<3072;i=i+1)begin
    sv=1;gray=pixels[i];fe=i==3071;@(negedge clk);
    if(i%53==0)begin sv=0;fe=0;repeat(2)@(negedge clk);end
   end
   sv=0;fe=0;waits=0;
   if(er)begin
    while(!rv && waits<500000)begin
     @(negedge clk);waits=waits+1;
     // Spurious frame markers while busy must not overwrite this snapshot.
     fs=waits==20;gray=8'hff;
    end
    fs=0;
    if(!rv || found!==ef || cx!==ex || cy!==ey || best!==eb || second!==es || quality!==eq)
     $fatal(1,"tracker %s rv=%b found=%b center=%0d,%0d SAD=%0d/%0d Q=%0d expected %0d %0d,%0d %0d/%0d %0d",name,rv,found,cx,cy,best,second,quality,ef,ex,ey,eb,es,eq);
   end else begin
    repeat(32)@(negedge clk);if(busy||rv||found)$fatal(1,"lost tracker automatically relocked");
   end
   $fwrite(csv,"%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",name,er,found,cx,cy,best,second,quality,cycles);
   $display("PASS tracker %s found=%0d center=%0d,%0d SAD=%0d/%0d cycles=%0d",name,found,cx,cy,best,second,cycles);
   checked=checked+1;repeat(5)@(negedge clk);
  end
  $fclose(csv);if(checked!=12)$fatal(1,"tracker incomplete");
  $display("PASS tb_vision_tracker: 12 stateful translation/light/occlusion/ambiguity/edge/reseed cases");$finish;
 end
 initial begin #50000000;$fatal(1,"tracker timeout");end
endmodule
