`timescale 1ns/1ps
module tb_csi_raw10_order;
 reg clk=0,rst=0,hs=0;reg [15:0] hd=0;
 wire cv,fs,fe,rv,rfs,rfe;wire [31:0] cd;wire [39:0] rd;
 integer f,y,i,k,received=0,bad=0,lines=0,csi_words=0;
 reg [39:0] expected;
 always #8.334 clk=~clk;
 csi_unpacket_2lane csi(.I_clk(clk),.I_rst_n(rst),.I_hs_valid(hs),.I_hs_data(hd),
 .O_csi_frame_start(fs),.O_csi_frame_end(fe),.O_csi_valid(cv),.O_csi_hs(),.O_csi_data(cd));
 raw10_unpacket_2lane raw(.I_clk(clk),.I_rst_n(rst),.I_csi_frame_start(fs),.I_csi_frame_end(fe),
 .I_csi_valid(cv),.I_csi_data(cd),.I_camera_black_level(10'd0),.O_raw10_frame_start(rfs),
 .O_raw10_frame_end(rfe),.O_raw10_valid(rv),.O_raw10_data(rd));
 function [9:0] pixel;input integer idx;begin pixel=(idx*19+37)&1023;end endfunction
 function [7:0] payload_byte;input integer n;integer base,slot;reg [9:0] p0,p1,p2,p3;begin
  base=(n/5)*4;slot=n%5;p0=pixel(base);p1=pixel(base+1);p2=pixel(base+2);p3=pixel(base+3);
  case(slot)0:payload_byte=p0[9:2];1:payload_byte=p1[9:2];2:payload_byte=p2[9:2];
  3:payload_byte=p3[9:2];4:payload_byte={p3[1:0],p2[1:0],p1[1:0],p0[1:0]};endcase
 end endfunction
 always @(posedge clk)begin #1;if(rst)begin
  if(cv)csi_words=csi_words+1;
  if(rv)begin
   for(k=0;k<4;k=k+1)expected[k*10+:10]=pixel((received%320)*4+k);
   if(rd!==expected)begin bad=bad+1;if(bad<5)$display("BAD raw=%0d got=%h exp=%h",received,rd,expected);end
   received=received+1;
  end
 end end
 task drive;input hv;input [15:0] d;begin @(negedge clk);hs=hv;hd=d;end endtask
 initial begin
  repeat(20)drive(0,0);rst=1;repeat(20)drive(0,0);
  for(f=0;f<2;f=f+1)begin
   drive(1,16'h0000);drive(1,16'h0000);repeat(20)drive(0,0);
   for(y=0;y<6;y=y+1)begin
    drive(1,16'h2b40);drive(1,16'h0600);
    for(i=0;i<1600;i=i+2)drive(1,{payload_byte(i),payload_byte(i+1)});
    drive(1,16'h0000);repeat(200)drive(0,0);
   end
   drive(1,16'h0100);drive(1,16'h0000);repeat(100)drive(0,0);
  end
  if(received!=3840||csi_words!=4800||bad!=0)$fatal(1,"counts raw=%0d CSI=%0d bad=%0d",received,csi_words,bad);
  $display("PASS tb_csi_raw10_order frames=2 rows=12 RAW10 beats=3840 pixels=15360");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
