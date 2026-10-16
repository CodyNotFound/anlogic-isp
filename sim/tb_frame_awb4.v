`timescale 1ns/1ps
module tb_frame_awb4;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,iv=0,iu=0,il=0,ready=1;
reg [95:0] id=0; wire ir,ov,ou,ol; wire [95:0] od;
frame_awb4 #(.INIT_R_Q8(512),.INIT_B_Q8(410),.MIN_SAMPLES(16)) dut(
.I_bypass(1'b0),
.I_auto_enable(1'b1),.I_clk(clk),.I_rst_n(rst_n),.I_tvalid(iv),.I_tuser(iu),.I_tlast(il),.I_tdata(id),
.I_tready(ir),.O_tready(ready),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(od));
integer gain_r=512,gain_b=410,accepted=0,emitted=0,checks=0;
reg ev1=0,eu1=0,el1=0,ev2=0,eu2=0,el2=0;
reg [95:0] ed1=0,ed2=0;
reg [9:0] old_r=512,old_b=410; reg sof;
localparam [23:0] GRAY={8'd80,8'd160,8'd100},RED={8'd220,8'd20,8'd20};
task fail; input [255:0] message; begin
$display("FAIL %0s t=%0t",message,$time);$fatal(1);$finish;end endtask
function [23:0] pixel_ref;
input [23:0] p;input integer rg,bg;integer r,b;
begin r=(p[23:16]*rg)>>8;b=(p[7:0]*bg)>>8;
if(r>255)r=255;if(b>255)b=255;pixel_ref={r[7:0],p[15:8],b[7:0]};end endfunction
function [95:0] beat_ref;input [95:0] p;input integer rg,bg;
begin beat_ref={pixel_ref(p[95:72],rg,bg),pixel_ref(p[71:48],rg,bg),pixel_ref(p[47:24],rg,bg),pixel_ref(p[23:0],rg,bg)};end endfunction
always @(posedge clk)begin
sof=rst_n&&iv&&ready&&iu;
if(!rst_n)begin ev1=0;eu1=0;el1=0;ed1=0;ev2=0;eu2=0;el2=0;ed2=0;end
else begin
if(ov&&ready)emitted=emitted+1;if(iv&&ready)accepted=accepted+1;
if(ready)begin ev2=ev1;eu2=eu1;el2=el1;ed2=ed1;
ev1=iv;eu1=iu;el1=il;ed1=beat_ref(id,gain_r,gain_b);end end
#1;
if(ir!==ready)fail("ready");
if({ov,ou,ol,od}!=={ev2,eu2,el2,ed2})fail("pipeline or stall");
if(!rst_n)begin if(dut.gain_r_q8!==10'd512||dut.gain_b_q8!==10'd410)fail("reset gains");end
else begin
if((dut.gain_r_q8!==old_r||dut.gain_b_q8!==old_b)&&!sof)fail("gain changed without SOF");
if(dut.gain_r_q8!==gain_r||dut.gain_b_q8!==gain_b)fail("active gains");end
old_r=dut.gain_r_q8;old_b=dut.gain_b_q8;checks=checks+1;end
task wait_cycles;input integer n;integer j;begin for(j=0;j<n;j=j+1)begin @(posedge clk);#2;end end endtask
task beat;input [95:0] p;input u,l;
begin @(negedge clk);iv=1;iu=u;il=l;id=p;@(posedge clk);while(!ir)@(posedge clk);
@(negedge clk);iv=0;iu=0;il=0;end endtask
task frame;input [23:0] p;
begin beat({4{p}},1,0);beat({4{p}},0,1);beat({4{p}},0,0);beat({4{p}},0,1);end endtask
initial begin
wait_cycles(3);@(negedge clk);rst_n=1;
beat({24'hfa641e,24'h405080,24'h102030,24'h50a064},1,1);
@(negedge clk);ready=0;iv=1;iu=1;il=1;id=96'hffeeddccbbaa998877665544;
wait_cycles(5);@(negedge clk);iv=0;iu=0;il=0;ready=1;wait_cycles(3);
frame(GRAY);if(dut.sample_count!==22'd16)fail("gray support");
frame(GRAY);@(negedge clk);ready=0;wait_cycles(110);
if(!dut.pending_valid||dut.pending_r_q8!==10'd512||dut.pending_b_q8!==10'd410)fail("pending ratio");
if(dut.gain_b_q8!==10'd410)fail("early publication");
@(negedge clk);ready=1;wait_cycles(3);gain_b=410;frame(GRAY);wait_cycles(110);
frame(RED);if(dut.sample_count!==22'd0)fail("red candidate accepted");wait_cycles(110);
frame(RED);if(dut.sample_count!==22'd0)fail("red support");wait_cycles(110);
frame(RED);wait_cycles(110);
if(dut.gain_r_q8!==10'd512||dut.gain_b_q8!==10'd410)fail("no-candidate hold");
wait_cycles(5);if(accepted!=emitted)fail("transaction conservation");
$display("PASS tb_frame_awb4 checks=%0d beats=%0d",checks,accepted);$finish;end
initial begin #100000;fail("timeout");end
endmodule
