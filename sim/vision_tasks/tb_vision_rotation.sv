`timescale 1ns/1ps
module tb_vision_rotation #(parameter CASE_FILE="sim/vision_tasks/rotation/cases.txt",CSV_FILE="reports/vision_tasks/rotation/rtl.csv",EXPECTED_FRAMES=76,WIDTH=64,HEIGHT=48,RADIUS=4);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,reseed=0,fs=0,sv=0,fe=0;reg [7:0] gray;
 wire rv,found,busy;wire [7:0] cx,cy,quality;wire [17:0] best,second;wire [31:0] cycles;wire [1:0] lost;
 vision_sad_tracker #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.RADIUS(RADIUS)) dut(clk,rst_n,reseed,fs,sv,fe,gray,rv,found,cx,cy,quality,best,second,busy,cycles,lost);
 reg [7:0] image[0:WIDTH*HEIGHT-1];reg [8:0] templates[0:1791];
 string name;integer f,csv,n,reset_case,ef,ex,ey,eb,es,eq,i,j,waits,count=0,previous_state=0;
 function [8:0] template_at;input integer addr;
 begin case(addr/256)
  0:template_at=dut.g_template[0].mem[addr%256];
  1:template_at=dut.g_template[1].mem[addr%256];
  2:template_at=dut.g_template[2].mem[addr%256];
  3:template_at=dut.g_template[3].mem[addr%256];
  4:template_at=dut.g_template[4].mem[addr%256];
  5:template_at=dut.g_template[5].mem[addr%256];
  6:template_at=dut.g_template[6].mem[addr%256];
 endcase end endfunction
 always @(posedge clk)begin
  #1;
  if(rst_n && previous_state==12 && dut.state!=0)$fatal(1,"DECIDE did not return IDLE");
  previous_state=dut.state;
  if(rst_n && busy && dut.read_addr>=WIDTH*HEIGHT)$fatal(1,"frame read out of range");
 end
 initial begin
  f=$fopen(CASE_FILE,"r");csv=$fopen(CSV_FILE,"w");
  if(!f||!csv)$fatal(1,"rotation fixtures/output missing");
  $fwrite(csv,"name,found,x,y,best,second,quality,cycles,bank\n");
  repeat(4)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   n=$fscanf(f,"%s %d %d %d %d %d %d %d\n",name,reset_case,ef,ex,ey,eb,es,eq);
   if(n!=8)$fatal(1,"rotation case parse");
   if(reset_case)begin rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
   $readmemh({"sim/vision_tasks/rotation/",name,".hex"},image);
   @(negedge clk);fs=1;@(negedge clk);fs=0;
   for(i=0;i<WIDTH*HEIGHT;i=i+1)begin sv=1;gray=image[i];fe=i==WIDTH*HEIGHT-1;@(negedge clk);end
   sv=0;fe=0;waits=0;
   while(!rv&&waits<800000)begin @(negedge clk);waits=waits+1;fs=waits==20;end fs=0;
   if(!rv||found!==ef||cx!==ex||cy!==ey||best!==eb||second!==es||quality!==eq)
    $fatal(1,"rotation %s rv%b found%b center%0d,%0d score%0d/%0d Q%0d expected %0d %0d,%0d %0d/%0d %0d state%0d",name,rv,found,cx,cy,best,second,quality,ef,ex,ey,eb,es,eq,dut.state);
   if(reset_case)begin
    $readmemh({"sim/vision_tasks/rotation/",name,"_templates.hex"},templates);
    for(j=0;j<1792;j=j+1)if(template_at(j)!==templates[j])$fatal(1,"rotation template %s bank%0d index%0d got%h expected%h",name,j/256,j%256,template_at(j),templates[j]);
   end
   $fwrite(csv,"%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",name,found,cx,cy,best,second,quality,cycles,dut.best_bank);
   $display("PASS rotation %s found%0d center%0d,%0d SAD%0d/%0d cycles%0d",name,found,cx,cy,best,second,cycles);
   count=count+1;repeat(5)@(negedge clk);
  end
  $fclose(csv);if(count!=EXPECTED_FRAMES)$fatal(1,"incomplete rotation test %0d",count);
  $display("PASS tb_vision_rotation: %0d frames, all bank values and SAD, bounded FSM completion",count);$finish;
 end
 initial begin #600000000;$fatal(1,"rotation timeout");end
endmodule
