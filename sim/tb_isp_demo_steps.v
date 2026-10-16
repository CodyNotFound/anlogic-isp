`timescale 1ns/1ps
// ISP 分步演示链路 TB (6步: 0原图彩色/1BLC/2LSC/3AWB/4GAMMA/5饱和全链):
//  C1 step5(全链) == normal 逐字一致 —— 演示终点与模式00等价
//  C2 step0(原图) != step5 —— 旁路生效(彩色偏色, 无任何矫正)
//  C3 step0 与 step1(BLC) 输出不同 —— BLC 步可见生效
// AWB 冻结(I_awb_enable=0, 增益恒INIT) 保证逐字节比对确定性。
module tb_isp_demo_steps;
parameter integer LINES_PER_FRAME=6;
parameter integer WORDS_PER_FRAME=LINES_PER_FRAME*240;
reg axi4s_video_aclk=0,I_rst_n,I_tlast,I_tuser,I_tvalid,O_tready;
reg [3:0] I_isp_demo;
reg [39:0] I_tdata;reg [9:0] I_tdest;
wire [127:0] O_tdata;wire O_tlast,O_tuser,O_tvalid,I_tready;
integer frame_words[0:3];
reg [127:0] frame_data[0:3][0:WORDS_PER_FRAME-1];
integer f,w,row,beat,errors,diff05,diff01;
isp_top #(.ENABLE_LSC(1),.ENABLE_AWB(1),.ENABLE_COLOR(1),.BLACK_LEVEL(67),.SAT_Q8(384),.IMG_HEIGHT(LINES_PER_FRAME)) dut(
.I_isp_demo(I_isp_demo),
.I_awb_enable(1'b0),.axi4s_video_aclk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
.I_tdata(I_tdata),.I_tvalid(I_tvalid),.I_tdest(I_tdest),.O_tready(O_tready),
.O_tdata(O_tdata),.O_tlast(O_tlast),.O_tuser(O_tuser),.O_tvalid(O_tvalid),.I_tready(I_tready));
always #8.334 axi4s_video_aclk=~axi4s_video_aclk;
function [9:0] sample_at;input integer r;input integer c;
begin sample_at=200+((r+c)%2)*400;end endfunction
task drive_cycle;input valid_value,last_value,user_value;input [39:0] data_value;
begin @(negedge axi4s_video_aclk);I_tvalid=valid_value;I_tlast=last_value;I_tuser=user_value;I_tdata=data_value;end endtask
task idle_cycles;input integer count;integer k;
begin for(k=0;k<count;k=k+1)drive_cycle(0,0,0,40'd0);end endtask
always @(posedge axi4s_video_aclk)begin
 if(I_rst_n&&O_tvalid&&O_tready)begin
  if(f>=0&&f<4&&frame_words[f]<WORDS_PER_FRAME)begin
   frame_data[f][frame_words[f]]<=O_tdata;
   frame_words[f]<=frame_words[f]+1;
  end
 end
end
task send_frame;input integer frame_id;input [3:0] demo_val;
begin
 f=frame_id;I_isp_demo=demo_val;
 idle_cycles(64);
 for(row=0;row<LINES_PER_FRAME;row=row+1)begin
  for(beat=0;beat<320;beat=beat+1)begin
   drive_cycle(1,beat==319,row==0&&beat==0,
    {sample_at(row,beat*4+3),sample_at(row,beat*4+2),sample_at(row,beat*4+1),sample_at(row,beat*4)});
   if(beat%4==3)drive_cycle(0,0,0,40'd0);
  end
  idle_cycles(200);
 end
 idle_cycles(800);
end endtask
initial begin
 I_rst_n=0;I_tlast=0;I_tuser=0;I_tdata=0;I_tvalid=0;I_tdest=0;O_tready=1;I_isp_demo=4'd0;f=-1;
 for(w=0;w<4;w=w+1)frame_words[w]=0;
 repeat(40)@(negedge axi4s_video_aclk);I_rst_n=1;idle_cycles(64);
 send_frame(0,4'd0);      // normal 基线(全链)
 send_frame(1,4'b1101);   // step5 全链
 send_frame(2,4'b1000);   // step0 原图(彩色, 全矫正关)
 send_frame(3,4'b1001);   // step1 +BLC
 f=4;
 // C1: step5 == normal 逐字一致
 errors=0;
 for(w=0;w<WORDS_PER_FRAME;w=w+1)
  if(frame_data[1][w]!==frame_data[0][w])errors=errors+1;
 if(errors!=0)begin $display("** FAIL C1: step5 vs normal diff words=%0d",errors);$fatal(1); end
 $display("** C1 PASS: step5 == normal");
 // C2: step0 != step5 (旁路生效, 大量差异)
 diff05=0;
 for(w=64;w<WORDS_PER_FRAME;w=w+1)
  if(frame_data[2][w]!==frame_data[1][w])diff05=diff05+1;
 if(diff05<100)begin $display("** FAIL C2: step0 vs step5 diff=%0d (旁路未生效?)",diff05);$fatal(1); end
 $display("** C2 PASS: step0 vs step5 diff=%0d (彩色原图生效)",diff05);
 // C3: step0 != step1 (BLC 步生效)
 diff01=0;
 for(w=64;w<WORDS_PER_FRAME;w=w+1)
  if(frame_data[2][w]!==frame_data[3][w])diff01=diff01+1;
 if(diff01<10)begin $display("** FAIL C3: step0 vs step1 diff=%0d (BLC未生效?)",diff01);$fatal(1); end
 $display("** C3 PASS: step0 vs step1 diff=%0d (BLC生效)",diff01);
 $display("** TB_ISP_DEMO_STEPS PASS **");$finish;
end
initial begin #200000000;$fatal(1,"timeout");end
endmodule
