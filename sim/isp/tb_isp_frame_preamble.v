`timescale 1ns/1ps
// Two frames through actual ISP/RAM models; override LINES_PER_FRAME=720 for full height.
module tb_isp_frame_preamble;
parameter integer LINES_PER_FRAME=6;
localparam integer WORDS_PER_FRAME=LINES_PER_FRAME*240;
reg axi4s_video_aclk=0,I_rst_n,I_tlast,I_tuser,I_tvalid,O_tready;
reg [39:0] I_tdata;reg [9:0] I_tdest;
wire [127:0] O_tdata;wire O_tlast,O_tuser,O_tvalid,I_tready;
integer cycle_count,total_sofs,total_words,total_lasts,frame_words,frame_rows,line_words;
integer sof_cycle,first_output_seen,latency_frame_1,latency_frame_2;
integer frame_index,row_index,beat_index;
isp_top #(.ENABLE_LSC(1),.ENABLE_AWB(1),.ENABLE_COLOR(1),.BLACK_LEVEL(67),.SAT_Q8(614),.IMG_HEIGHT(LINES_PER_FRAME)) dut(
.I_isp_demo(4'd0),
.I_awb_enable(1'b1),.axi4s_video_aclk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
.I_tdata(I_tdata),.I_tvalid(I_tvalid),.I_tdest(I_tdest),.O_tready(O_tready),
.O_tdata(O_tdata),.O_tlast(O_tlast),.O_tuser(O_tuser),.O_tvalid(O_tvalid),.I_tready(I_tready));
always #10.0 axi4s_video_aclk=~axi4s_video_aclk;
task fail;input [1023:0] reason;
begin $display("FAIL tb_isp_frame_preamble time=%0t cycle=%0d: %0s",$time,cycle_count,reason);$fatal(1);end endtask
task drive_cycle;input valid_value,last_value,user_value;input [39:0] data_value;
begin @(negedge axi4s_video_aclk);I_tvalid=valid_value;I_tlast=last_value;I_tuser=user_value;I_tdata=data_value;end endtask
task idle_cycles;input integer count;integer k;
begin for(k=0;k<count;k=k+1)drive_cycle(0,0,0,40'd0);end endtask
always @(posedge axi4s_video_aclk)begin
 if(!I_rst_n)begin
 cycle_count=0;total_sofs=0;total_words=0;total_lasts=0;frame_words=0;frame_rows=0;line_words=0;
 sof_cycle=0;first_output_seen=0;latency_frame_1=-1;latency_frame_2=-1;
 end else begin
 cycle_count=cycle_count+1;
 if(O_tvalid!==1'b0&&O_tvalid!==1'b1)fail("O_tvalid unknown");
 if(O_tuser!==1'b0&&O_tuser!==1'b1)fail("O_tuser unknown");
 if(O_tuser!==(I_tvalid&&I_tuser))fail("external SOF differs from RAW preamble");
 if(O_tuser===1'b1)begin
 if(O_tvalid!==1'b0)fail("SOF overlaps packed output");
 if(total_sofs>=2)fail("more than two SOFs");
 if(total_sofs!=0)begin
 if(frame_words!=WORDS_PER_FRAME)fail("previous frame word count mismatch");
 if(frame_rows!=LINES_PER_FRAME)fail("previous frame line count mismatch");
 if(line_words!=0)fail("previous frame ended inside line");
 if(first_output_seen!=1)fail("previous frame had no first word");
 $display("FRAME %0d complete words=%0d lines=%0d",total_sofs,frame_words,frame_rows);
 end
 total_sofs=total_sofs+1;frame_words=0;frame_rows=0;line_words=0;
 sof_cycle=cycle_count;first_output_seen=0;
 end
 if(O_tvalid===1'b1)begin
 if(total_sofs==0)fail("valid before SOF");
 if((^O_tdata)===1'bx)fail("valid data contains X/Z");
 if(O_tlast!==1'b0&&O_tlast!==1'b1)fail("O_tlast unknown");
 if(first_output_seen==0)begin
 if(cycle_count-sof_cycle<20)fail("SOF advance below 20 cycles");
 first_output_seen=1;
 if(total_sofs==1)latency_frame_1=cycle_count-sof_cycle;else latency_frame_2=cycle_count-sof_cycle;
 $display("FRAME %0d first output SOF advance=%0d camera cycles",total_sofs,cycle_count-sof_cycle);
 end
 frame_words=frame_words+1;total_words=total_words+1;line_words=line_words+1;
 if(frame_words>WORDS_PER_FRAME)fail("frame exceeds expected word count");
 if(line_words>240)fail("line exceeds 240 words");
 if(O_tlast===1'b1)begin
 if(line_words!=240)fail("O_tlast not on word 240");
 frame_rows=frame_rows+1;total_lasts=total_lasts+1;line_words=0;
 if(frame_rows>LINES_PER_FRAME)fail("frame exceeds expected line count");
 end else if(line_words==240)fail("word 240 missing O_tlast");
 end
 end
end
initial begin
 I_rst_n=0;I_tlast=0;I_tuser=0;I_tdata=0;I_tvalid=0;I_tdest=0;O_tready=1;
 repeat(40)@(negedge axi4s_video_aclk);I_rst_n=1;idle_cycles(64);
 for(frame_index=0;frame_index<2;frame_index=frame_index+1)begin
 for(row_index=0;row_index<LINES_PER_FRAME;row_index=row_index+1)begin
 for(beat_index=0;beat_index<320;beat_index=beat_index+1)begin
 drive_cycle(1,beat_index==319,row_index==0&&beat_index==0,{4{10'd320}});
 if(beat_index%4==3)drive_cycle(0,0,0,40'd0);
 end
 idle_cycles(1000);
 end
 idle_cycles(2000);
 end
 idle_cycles(64);@(negedge axi4s_video_aclk);
 if(total_sofs!=2)fail("expected two SOFs");
 if(total_words!=2*WORDS_PER_FRAME)fail("total word count mismatch");
 if(total_lasts!=2*LINES_PER_FRAME)fail("total line count mismatch");
 if(frame_words!=WORDS_PER_FRAME)fail("second frame word count mismatch");
 if(frame_rows!=LINES_PER_FRAME)fail("second frame line count mismatch");
 if(line_words!=0)fail("second frame ended inside line");
 if(first_output_seen!=1)fail("second frame had no first word");
 if(latency_frame_1<20||latency_frame_2<20)fail("SOF advance below 20 cycles");
 $display("PASS tb_isp_frame_preamble frames=2 lines=%0d words=%0d advance1=%0d advance2=%0d",2*LINES_PER_FRAME,2*WORDS_PER_FRAME,latency_frame_1,latency_frame_2);
 $finish;
end
initial begin #100000000;fail("explicit 100ms timeout");end
endmodule
