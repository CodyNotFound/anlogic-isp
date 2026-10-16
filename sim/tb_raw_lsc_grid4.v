`timescale 1ns/1ps
module tb_raw_lsc_grid4;
localparam FRAME_BEATS=320*720;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,in_valid=0,in_user=0,in_last=0,out_ready=0;
reg [39:0] in_data=0;reg [9:0] in_dest=0;
wire in_ready,out_valid,out_user,out_last,bypass_ready,bypass_valid,bypass_user,bypass_last;
wire [39:0] out_data,bypass_data;wire [9:0] out_dest,bypass_dest;
raw_lsc_grid4 #(.ENABLE(1),.BLACK_LEVEL(67)) dut(
.I_blc_on(1'b1),.I_lsc_on(1'b1),.I_clk(clk),.I_rst_n(rst_n),.I_tvalid(in_valid),.I_tuser(in_user),.I_tlast(in_last),
.I_tdata(in_data),.I_tdest(in_dest),.O_tready(out_ready),.I_tready(in_ready),
.O_tvalid(out_valid),.O_tuser(out_user),.O_tlast(out_last),.O_tdata(out_data),.O_tdest(out_dest));
raw_lsc_grid4 #(.ENABLE(0),.BLACK_LEVEL(67)) dut_bypass(
.I_blc_on(1'b1),.I_lsc_on(1'b1),.I_clk(clk),.I_rst_n(rst_n),.I_tvalid(in_valid),.I_tuser(in_user),.I_tlast(in_last),
.I_tdata(in_data),.I_tdest(in_dest),.O_tready(out_ready),.I_tready(bypass_ready),
.O_tvalid(bypass_valid),.O_tuser(bypass_user),.O_tlast(bypass_last),.O_tdata(bypass_data),.O_tdest(bypass_dest));
function integer raw_lane;input integer lane;
begin case(lane)0:raw_lane=32;1:raw_lane=211;2:raw_lane=577;default:raw_lane=999;endcase end endfunction
function [39:0] golden_data;input integer beat;
integer x,y,gx,gy,address,fy,fx,lane,shift,a,b,c,d,left_gain,right_gain,gain,sample,value;
reg [47:0] tl,tr,bl,br;reg [39:0] result;
begin
y=beat/320;x=(beat%320)*4;gx=x/80;gy=y/60;address=gy*17+gx;fy=((y%60)*256)/60;
tl=dut.grid_word(address);tr=dut.grid_word(address+1);bl=dut.grid_word(address+17);br=dut.grid_word(address+18);result=0;
for(lane=0;lane<4;lane=lane+1)begin
if((y%2)==0)begin if((lane%2)==0)shift=12;else shift=36;end
else begin if((lane%2)==0)shift=0;else shift=24;end
a=(tl>>shift)&48'hfff;b=(tr>>shift)&48'hfff;c=(bl>>shift)&48'hfff;d=(br>>shift)&48'hfff;
fx=(((x+lane)%80)*256)/80;
left_gain=(a*(256-fy)+c*fy+128)/256;right_gain=(b*(256-fy)+d*fy+128)/256;
gain=(left_gain*(256-fx)+right_gain*fx+128)/256;
sample=raw_lane(lane)-67;if(sample<0)sample=0;
value=(sample*gain+512)/1024;if(value>1023)value=1023;result[lane*10+:10]=value;end
golden_data=result;end endfunction
reg expected_valid[0:3],expected_user[0:3],expected_last[0:3];
reg [9:0] expected_dest[0:3];reg [39:0] expected_data[0:3],expected_bypass[0:3];
reg [52:0] previous_output=0,previous_bypass=0;
integer sent=0,seen=0,cycles=0,stalls=0,errors=0,i,drive_ready;
task fail;input [255:0] message;begin
errors=errors+1;$display("FAIL cycle=%0d sent=%0d seen=%0d: %0s",cycles,sent,seen,message);
if(errors>=10)begin $display("FAIL: stopping after ten errors");$finish;end end endtask
task run_cycle;input valid_value,ready_value;input integer beat;integer stage;
begin
@(negedge clk);out_ready=ready_value;in_valid=valid_value;in_user=valid_value&&(beat==0);
in_last=valid_value&&((beat%320)==319);in_dest=valid_value?(beat%1024):0;
for(stage=0;stage<4;stage=stage+1)in_data[stage*10+:10]=raw_lane(stage);
@(posedge clk);
if(ready_value)begin
for(stage=3;stage>0;stage=stage-1)begin
expected_valid[stage]=expected_valid[stage-1];expected_user[stage]=expected_user[stage-1];
expected_last[stage]=expected_last[stage-1];expected_dest[stage]=expected_dest[stage-1];
expected_data[stage]=expected_data[stage-1];expected_bypass[stage]=expected_bypass[stage-1];end
expected_valid[0]=valid_value;expected_user[0]=in_user;expected_last[0]=in_last;
expected_dest[0]=in_dest;expected_bypass[0]=in_data;
if(valid_value)begin expected_data[0]=golden_data(beat);sent=sent+1;end
end else stalls=stalls+1;
#1;
if(in_ready!==out_ready||bypass_ready!==out_ready)fail("input ready mismatch");
if(out_valid!==expected_valid[3]||bypass_valid!==expected_valid[3])fail("four-enabled-edge valid mismatch");
if(!ready_value)begin
if({out_valid,out_user,out_last,out_data,out_dest}!==previous_output)fail("enabled output changed on stall");
if({bypass_valid,bypass_user,bypass_last,bypass_data,bypass_dest}!==previous_bypass)fail("bypass output changed on stall");end
if(out_valid===1'b1)begin
if(out_data!==expected_data[3])fail("corrected RAW mismatch");
if(out_user!==expected_user[3]||out_last!==expected_last[3]||out_dest!==expected_dest[3])fail("corrected metadata mismatch");
if(bypass_data!==expected_bypass[3])fail("bypass RAW mismatch");
if(bypass_user!==expected_user[3]||bypass_last!==expected_last[3]||bypass_dest!==expected_dest[3])fail("bypass metadata mismatch");
if(ready_value)seen=seen+1;end
previous_output={out_valid,out_user,out_last,out_data,out_dest};
previous_bypass={bypass_valid,bypass_user,bypass_last,bypass_data,bypass_dest};cycles=cycles+1;end endtask
initial begin
for(i=0;i<4;i=i+1)begin expected_valid[i]=0;expected_user[i]=0;expected_last[i]=0;expected_dest[i]=0;expected_data[i]=0;expected_bypass[i]=0;end
repeat(4)@(posedge clk);#1;
if({out_valid,out_user,out_last,out_data,out_dest}!==53'd0)fail("enabled reset mismatch");
if({bypass_valid,bypass_user,bypass_last,bypass_data,bypass_dest}!==53'd0)fail("bypass reset mismatch");
@(negedge clk);rst_n=1;
while(sent<FRAME_BEATS)begin
drive_ready=1;if((cycles%97)==11||(cycles%97)==12||(cycles%251)==40)drive_ready=0;
run_cycle(1'b1,drive_ready!=0,sent);end
repeat(5)run_cycle(1'b0,1'b1,0);
if(sent!=FRAME_BEATS)fail("accepted input count mismatch");if(seen!=FRAME_BEATS)fail("emitted output count mismatch");
if(stalls==0)fail("stall stimulus missing");if(out_valid!==1'b0||bypass_valid!==1'b0)fail("pipeline did not drain");
if(errors==0)$display("PASS raw_lsc_grid4: beats=%0d stalls=%0d cycles=%0d",seen,stalls,cycles);
else $display("FAIL raw_lsc_grid4: errors=%0d",errors);$finish;end
initial begin #10000000;$display("FAIL raw_lsc_grid4: simulation timeout");$finish;end
endmodule
