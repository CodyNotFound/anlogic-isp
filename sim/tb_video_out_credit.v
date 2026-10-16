`timescale 1ns/1ps
// Small fault-focused test: delayed read responses, stale frame returns, AB order.
module tb_video_out_credit;
 reg ddr_clk=0,pixel_clk=0,rst_n=0,vsync=0,de=0;
 reg [1:0] rp=0;
 always #7.5 ddr_clk=~ddr_clk;
 always #6.6665 pixel_clk=~pixel_clk;
 wire [1:0] request,busy;
 wire [24:0] address[0:1];
 reg [1:0] response_valid=0;
 reg [127:0] response_data[0:1];
 wire [23:0] pixel[0:1];
 video_out_v9_reference old_dut(
 .I_rst_n(rst_n),.I_ddr_clk(ddr_clk),.O_video_out_rd_busy(busy[0]),
 .I_video_in_wr_busy(1'b0),.I_video_out_rp(rp),.O_ddr_user_rd_en(request[0]),
 .O_ddr_user_addr(address[0]),.I_ddr_user_ready(1'b1),
 .I_ddr_user_rd_valid(response_valid[0]),.I_ddr_user_rd_data(response_data[0]),
 .I_dsi_clk(pixel_clk),.I_video_vsync(vsync),.I_video_rd_en(de),.O_vdieo_data(pixel[0]));
 video_out dut(
 .I_rst_n(rst_n),.I_ddr_clk(ddr_clk),.O_video_out_rd_busy(busy[1]),
 .I_video_in_wr_busy(1'b0),.I_video_out_rp(rp),.O_ddr_user_rd_en(request[1]),
 .O_ddr_user_addr(address[1]),.I_ddr_user_ready(1'b1),
 .I_ddr_user_rd_valid(response_valid[1]),.I_ddr_user_rd_data(response_data[1]),
 .I_dsi_clk(pixel_clk),.I_video_vsync(vsync),.I_video_rd_en(de),.O_vdieo_data(pixel[1]));
 integer cycle=0,phase=0,model,i,after_switch=0;
 integer head[0:1],tail[0:1],due[0:1][0:8191];
 reg [127:0] queue_data[0:1][0:8191];
 integer drops[0:1],stale[0:1],good_new[0:1],peak_reserved[0:1];
 integer new_reserved,old_reserved;
 function [23:0] expected_pixel;input integer x;
 begin expected_pixel=(x%1280<640)?24'h204080:24'hd03010;end endfunction
 function [127:0] memory_word;input [24:0] addr;
 integer byte_no,byte_index,pixel_index;reg [23:0] rgb;reg [127:0] result;
 begin
  if(phase<3)result={4{{7'd0,addr}}};
  else begin
   result=0;
   for(byte_no=0;byte_no<16;byte_no=byte_no+1)begin
    byte_index=(addr/8)*16+byte_no;pixel_index=byte_index/3;
    rgb=expected_pixel(pixel_index);
    case(byte_index%3)
     0:result[127-byte_no*8-:8]=rgb[23:16];
     1:result[127-byte_no*8-:8]=rgb[15:8];
     2:result[127-byte_no*8-:8]=rgb[7:0];
    endcase
   end
  end
  memory_word=result;
 end endfunction
 always @(posedge ddr_clk)begin
  if(!rst_n)begin
   cycle=0;
   for(model=0;model<2;model=model+1)begin
    head[model]=0;tail[model]=0;drops[model]=0;stale[model]=0;
    good_new[model]=0;peak_reserved[model]=0;
   end
  end else begin
   cycle=cycle+1;
   for(model=0;model<2;model=model+1)begin
    if(request[model])begin
     due[model][tail[model]]=cycle+400;
     queue_data[model][tail[model]]=memory_word(address[model]);
     tail[model]=tail[model]+1;
    end
   end
   if(old_dut.U_w128_d512_fifo.we&&!old_dut.U_w128_d512_fifo.soft_fifo_al_4057d6b76aa6_Inst.wr_rst)begin
    if(old_dut.U_w128_d512_fifo.full_flag)drops[0]=drops[0]+1;
    if(phase==2&&after_switch&&response_data[0][24:0]<7000000)stale[0]=stale[0]+1;
   end
   if(dut.U_w128_d512_fifo.we&&!dut.U_w128_d512_fifo.soft_fifo_al_4057d6b76aa6_Inst.wr_rst)begin
    if(dut.U_w128_d512_fifo.full_flag)drops[1]=drops[1]+1;
    if(phase==2&&after_switch)begin
     if(response_data[1][24:0]<7000000)stale[1]=stale[1]+1;
     else good_new[1]=good_new[1]+1;
    end
   end
   old_reserved=old_dut.S_fifo_wr_num+(tail[0]-head[0])+response_valid[0];
   new_reserved=dut.reserved_read_words;
   if(old_reserved>peak_reserved[0])peak_reserved[0]=old_reserved;
   if(new_reserved>peak_reserved[1])peak_reserved[1]=new_reserved;
   if(new_reserved>511)$fatal(1,"New reader over-reserved FIFO: %0d",new_reserved);
  end
 end
 always @(negedge ddr_clk)begin
  response_valid=0;
  if(rst_n)for(i=0;i<2;i=i+1)begin
   if(head[i]<tail[i]&&due[i][head[i]]<=cycle)begin
    response_valid[i]=1;response_data[i]=queue_data[i][head[i]];head[i]=head[i]+1;
   end
  end
 end
 task reset_case;input integer new_phase;
 begin
  @(negedge ddr_clk);rst_n=0;vsync=0;de=0;rp=0;after_switch=0;phase=new_phase;
  repeat(8)@(negedge ddr_clk);rst_n=1;vsync=1;
  repeat(12)@(negedge ddr_clk);vsync=0;
 end endtask
 integer source_pixels=0,checked_pixels=0,x,line;
 reg ref_valid1=0,ref_valid2=0;
 reg [23:0] ref_pixel1=0,ref_pixel2=0;
 always @(posedge pixel_clk)begin
  if(!rst_n||phase!=3)begin
   source_pixels=0;checked_pixels=0;ref_valid1=0;ref_valid2=0;
  end else begin
   ref_valid2=ref_valid1;ref_pixel2=ref_pixel1;
   ref_valid1=de;
   if(de)begin ref_pixel1=expected_pixel(source_pixels);source_pixels=source_pixels+1;end
   #1;
   if(ref_valid2)begin
    if(pixel[1]!==ref_pixel2)$fatal(1,"AB/RGB order pixel=%0d expected=%h got=%h",checked_pixels,ref_pixel2,pixel[1]);
    checked_pixels=checked_pixels+1;
   end
  end
 end
 initial begin
  response_data[0]=0;response_data[1]=0;
  reset_case(1);repeat(1600)@(negedge ddr_clk);
  $display("CREDIT old_drops=%0d new_drops=%0d old_peak=%0d new_peak=%0d",drops[0],drops[1],peak_reserved[0],peak_reserved[1]);
  if(drops[0]==0||peak_reserved[0]<=511)$fatal(1,"Old overflow was not reproduced");
  if(drops[1]!=0)$fatal(1,"New reader overflow");
  reset_case(2);repeat(280)@(negedge ddr_clk);
  after_switch=1;rp=1;vsync=1;repeat(12)@(negedge ddr_clk);vsync=0;
  repeat(1500)@(negedge ddr_clk);
  $display("FRAME old_stale=%0d new_stale=%0d new_correct_returns=%0d",stale[0],stale[1],good_new[1]);
  if(stale[0]==0)$fatal(1,"Old stale-return defect was not reproduced");
  if(stale[1]!=0||good_new[1]==0)$fatal(1,"New frame switch failed");
  reset_case(3);repeat(700)@(negedge ddr_clk);
  for(line=0;line<2;line=line+1)begin
   for(x=0;x<1280;x=x+1)begin @(negedge pixel_clk);de=1;end
   @(negedge pixel_clk);de=0;repeat(370)@(negedge pixel_clk);
  end
  repeat(8)@(negedge pixel_clk);
  if(checked_pixels!=2560||dut.read_underflow_latched)$fatal(1,"Pixel count or underflow failure");
  $display("PIXELS AB/RGB order checked=%0d",checked_pixels);
  // Force a real underrun, then check clean recovery at the next frame.
  reset_case(4);repeat(40)@(negedge ddr_clk);
  @(negedge pixel_clk);de=1;
  repeat(1000)@(negedge ddr_clk);
  if(!dut.read_underflow_latched||pixel[1]!==24'd0)$fatal(1,"Underrun must blank, not cycle RGB phase");
  @(negedge pixel_clk);de=0;
  @(negedge ddr_clk);vsync=1;repeat(12)@(negedge ddr_clk);vsync=0;
  repeat(900)@(negedge ddr_clk);
  if(dut.read_underflow_latched)$fatal(1,"Underrun did not clear on frame reset");
  phase=3;
  for(x=0;x<16;x=x+1)begin @(negedge pixel_clk);de=1;end
  @(negedge pixel_clk);de=0;repeat(8)@(negedge pixel_clk);
  if(checked_pixels!=16)$fatal(1,"Recovery pixel count mismatch");
  $display("PASS tb_video_out_credit: overflow, stale returns, AB/RGB order, underrun recovery");$finish;
 end
 initial begin #200000;$fatal(1,"Timeout");end
endmodule
