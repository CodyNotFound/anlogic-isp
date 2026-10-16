`timescale 1ns/1ps
// Exercise the actual CSI/RAW/AXIS entrance; varying frames distinguish stale data.
module tb_csi_isp_frame_integrity #(parameter STOP_CLOCK=0,USE_BRIDGE=0,ALGORITHMS=0,FINISH=1,HEIGHT=6,FRAMES=8,TRAIL=16);
 localparam FRAME_WORDS=HEIGHT*240,RAW_WORDS=HEIGHT*320;
 reg source_done=0;
 reg oscillator=0,clock_enabled=1,rst=0,hs=0;reg[15:0]hd=0;
 always #8.334 oscillator=~oscillator;
 wire clk=oscillator&&clock_enabled;
 reg processing_clk=0;always #10 processing_clk=~processing_clk;
 wire isp_clk=USE_BRIDGE?processing_clk:clk;
 wire cv,fs,fe,rv,rfs,rfe,av,au,al,ov,ou,ol;wire[31:0]cd;
 wire[39:0]rd,ad;wire[127:0]od;
 reg[39:0]vectors[0:1919];reg[23:0]golden[0:7679];
 initial begin $readmemh("boundary_raw.hex",vectors);$readmemh("boundary_rgb.hex",golden);end
 csi_unpacket_2lane csi(clk,rst,hs,hd,fs,fe,cv,,cd);
 raw10_unpacket_2lane raw(clk,rst,fs,fe,cv,cd,10'd0,rfs,rfe,rv,rd);
 wire brv,bfs,bfe;wire[39:0]brd;
 generate if(USE_BRIDGE)begin
  camera_raw_clock_bridge bridge(rst,clk,rv,rfs,rfe,rd,processing_clk,brv,bfs,bfe,brd);
 end else begin assign brv=rv;assign bfs=rfs;assign bfe=rfe;assign brd=rd;end endgenerate
 uial2axis #(.IMG_HEIGHT(HEIGHT),.INPUT_DATA_WIDTH(40)) axis(isp_clk,rst,brd,brv,bfs,bfe,av,ad,au,al);
 isp_top #(.ENABLE_LSC(ALGORITHMS),.ENABLE_AWB(ALGORITHMS),.ENABLE_COLOR(ALGORITHMS),.IMG_HEIGHT(HEIGHT)) isp(
 .I_isp_demo(4'd0),
 .axi4s_video_aclk(isp_clk),.I_rst_n(rst),.I_tlast(al),.I_tuser(au),.I_awb_enable(1'b1),
 .I_tdata(ad),.I_tvalid(av),.I_tdest(10'd0),.O_tready(1'b1),
 .O_tdata(od),.O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.I_tready());
 integer frame=-1,raw_count=0,words=0,bad=0,f,y,i,j,bi,p,channel;reg[127:0]expected;
 reg[23:0]rgb;reg[7:0]value;
 always @(posedge isp_clk)begin #1;if(rst)begin
  if(ou)begin
   if(frame>=0&&words!=FRAME_WORDS)$fatal(1,"frame crossed RAW SOF: frame=%0d words=%0d expected=%0d",frame,words,FRAME_WORDS);
   if(frame>=0&&raw_count!=RAW_WORDS)$fatal(1,"RAW words lost: %0d",raw_count);
   if(frame>=0)$display("FRAME %0d complete RAW=%0d packed=%0d",frame,raw_count,words);
   frame=frame+1;words=0;raw_count=0;
  end
  if(av)raw_count=raw_count+1;
  if(ov)begin
   for(j=0;j<16;j=j+1)begin
    bi=words*16+j;p=bi/3;channel=bi%3;rgb=golden[p%7680];
    case(channel)0:value=rgb[23:16]+frame*2;1:value=rgb[15:8]+frame*2;2:value=rgb[7:0]+frame*2;endcase
    expected[127-j*8-:8]=value;
   end
   if((ALGORITHMS==0&&od!==expected)||(^od===1'bx))begin bad=bad+1;if(bad<4)$display("BAD frame=%0d word=%0d got=%h expected=%h",frame,words,od,expected);end
   words=words+1;
  end
 end end
 function[7:0]payload;input integer n,row,fr;integer base,slot,k;reg[9:0]a[0:3];begin
  base=(n/5);slot=n%5;
  for(k=0;k<4;k=k+1)a[k]=vectors[(row%6)*320+base][k*10+:10]+fr*8;
  case(slot)0:payload=a[0][9:2];1:payload=a[1][9:2];2:payload=a[2][9:2];3:payload=a[3][9:2];4:payload={a[3][1:0],a[2][1:0],a[1][1:0],a[0][1:0]};endcase
 end endfunction
 task drive;input valid;input[15:0]d;begin @(negedge clk);hs=valid;hd=d;end endtask
 task gap;input integer cycles;begin
  repeat(TRAIL)drive(0,0);
  if(STOP_CLOCK)begin clock_enabled=0;repeat(cycles)@(negedge oscillator);clock_enabled=1;end
  else repeat(cycles)drive(0,0);
 end endtask
 initial begin
  repeat(20)drive(0,0);rst=1;repeat(20)drive(0,0);
  for(f=0;f<FRAMES;f=f+1)begin
   drive(1,16'h0000);drive(1,0);gap(20);
   for(y=0;y<HEIGHT;y=y+1)begin
    drive(1,16'h2b40);drive(1,16'h0600);
    for(i=0;i<1600;i=i+2)drive(1,{payload(i,y,f),payload(i+1,y,f)});
    drive(1,0);gap(180+(f%3)*20);
   end
   drive(1,16'h0100);drive(1,0);gap(2000);
  end
  repeat(2000)drive(0,0);
  if(words!=FRAME_WORDS||frame!=FRAMES-1||bad!=0)$fatal(1,"integrity failed frame=%0d words=%0d bad=%0d",frame,words,bad);
  $display("PASS tb_csi_isp_frame_integrity frames=%0d height=%0d varying contents STOP_CLOCK=%0d",FRAMES,HEIGHT,STOP_CLOCK);
  source_done=1;if(FINISH)$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
