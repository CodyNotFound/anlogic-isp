`timescale 1ns/1ps
// Real ISP output is checked byte-for-byte against an independent BGGR oracle.
module tb_isp_pixel_order;
 reg clk=0,rst=0,v=0,last=0,user=0;reg [39:0] raw=0;
 reg [39:0] vectors[0:1919];reg [23:0] golden[0:7679];
 wire ov,ou,ol;wire [127:0] data;
 integer f,y,b,k,words=0,bad=0,idx,pi,byte_idx;reg [127:0] expected;
 always #8.334 clk=~clk;
 isp_top #(.ENABLE_LSC(0),.ENABLE_AWB(0),.ENABLE_COLOR(0),.IMG_HEIGHT(6)) dut(
 .I_isp_demo(4'd0),
 .axi4s_video_aclk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_awb_enable(1'b0),
 .I_tdata(raw),.I_tvalid(v),.I_tdest(10'd0),.O_tready(1'b1),.O_tdata(data),
 .O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.I_tready());
 always @(posedge clk)begin #1;if(rst&&ov)begin
  expected=0;
  for(k=0;k<16;k=k+1)begin
   byte_idx=(words%1440)*16+k;pi=byte_idx/3;
   case(byte_idx%3)
    0:expected[127-k*8-:8]=golden[pi][23:16];
    1:expected[127-k*8-:8]=golden[pi][15:8];
    2:expected[127-k*8-:8]=golden[pi][7:0];
   endcase
  end
  if(data!==expected)begin bad=bad+1;if(bad<=4)$display("BAD word=%0d got=%h expected=%h",words,data,expected);end
  words=words+1;
 end end
 task drive;input vv,ll,uu;input [39:0] rr;
 begin @(negedge clk);v=vv;last=ll;user=uu;raw=rr;end endtask
 initial begin
  $readmemh("boundary_raw.hex",vectors);$readmemh("boundary_rgb.hex",golden);
  repeat(20)@(negedge clk);rst=1;repeat(40)drive(0,0,0,0);
  for(f=0;f<3;f=f+1)begin
   for(y=0;y<6;y=y+1)begin
    for(b=0;b<320;b=b+1)begin
     drive(1,b==319,y==0&&b==0,vectors[y*320+b]);
     // Alternate full-frame valid cadence without changing any RAW samples.
     if(f!=1)drive(0,0,0,0);
     if(b%4==3)begin drive(0,0,0,0);if(f!=1)drive(0,0,0,0);end
    end
    repeat(200)drive(0,0,0,0);
   end
   repeat(2000)drive(0,0,0,0);
  end
  if(words!=4320||bad!=0)$fatal(1,"ISP pixel order/count: words=%0d expected=4320 bad=%0d",words,bad);
  $display("PASS tb_isp_pixel_order cold+cadence changes frames=3 pixels=23040");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
