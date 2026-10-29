`timescale 1ns/1ps
module tb_reset_ae_cdc;
 reg src=0,dst=0,run_dst=0,arst=0,frame_start=0;
 always #7 src=~src;
 always #19.5 if(run_dst)dst=~dst;
 wire srst,drst,nrst;
 reset_sync #(.NEG_EDGE(1)) neg_reset(.clk(dst),.async_rst_n(arst),.rst_n(nrst));
 integer neg_edges=0;
 always @(negedge dst or negedge arst)begin
  if(!arst)neg_edges=0;else neg_edges=neg_edges+1;
  #1;if(nrst&&neg_edges<2)$fatal(1,"falling-edge reset released early");
 end
 reset_sync a(.clk(src),.async_rst_n(arst),.rst_n(srst));
 reset_sync b(.clk(dst),.async_rst_n(arst),.rst_n(drst));
 wire[7:0] stat,delayed_stat,received;wire toggle,valid;wire[23:0]pixel;
 auto_exposure ae(.clk(src),.rst_n(srst),.enable(1'b0),.frame_start(frame_start),.de(1'b0),.pixel_in(24'd0),.pixel_out(pixel),.frame_stat_y(stat),.frame_stat_toggle(toggle));
 genvar bitnum;generate for(bitnum=0;bitnum<8;bitnum=bitnum+1)begin:skew
  assign #(bitnum*3+1) delayed_stat[bitnum]=stat[bitnum];
 end endgenerate
 frame_stat_cdc c(.clk(dst),.rst_n(drst),.data_async(delayed_stat),.toggle_async(toggle),.data(received),.valid(valid));
 reg pending=0;reg[7:0]want;integer events=0,edges=0,i,prior;reg prev_toggle;
 always @(posedge dst or negedge arst)begin
  if(!arst)edges=0;else edges=edges+1;
  #1;if(drst&&edges<2)$fatal(1,"reset released before two destination edges");
  if(valid)begin
   if(!pending||received!==want)$fatal(1,"torn or unexpected statistic got%h want%h pending%b",received,want,pending);
   pending=0;events=events+1;
  end
 end
 task emit(input[7:0]mean);
  begin
   #(3+(mean%17));@(negedge src);
   // Focus the test on frame-boundary publication, not 921600 accumulation beats.
   ae.luma_sum=40'd921600*mean;ae.pixel_count=22'd921600;
   #1;want=ae.frame_avg_calc>255?255:ae.frame_avg_calc[7:0];pending=1;prior=events;
   prev_toggle=toggle;frame_start=1;
   @(posedge src);#1;if(toggle!==prev_toggle||stat!==want)$fatal(1,"data must publish before event");
   @(negedge src);frame_start=0;
   @(posedge src);#1;if(toggle===prev_toggle)$fatal(1,"event not published one source cycle later");
   wait(events==prior+1);repeat(4)@(posedge dst);#2;
  end
 endtask
 initial begin
  #3;arst=1;#150;if(drst!==0||nrst!==0)$fatal(1,"stopped destination clock released reset");
  run_dst=1;wait(srst&&drst);
  for(i=0;i<32;i=i+1)emit(i%2?8'haa+i:8'h55-i);
  #3;arst=0;#1;if(srst!==0||drst!==0||nrst!==0)$fatal(1,"reset assertion not asynchronous");
  #2;arst=1;wait(srst&&drst);emit(8'hfe);emit(8'h01);
  if(events!=34)$fatal(1,"event count %0d",events);
  $display("PASS tb_reset_ae_cdc: stopped clock, async reassertion, two-edge release, 34 coherent AE events with bit skew");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule

module tb_model_shift;
 reg clk=0,rst=0,start=0,inv=0;reg signed[31:0]bias=0;reg signed[6:0]shift=0;
 wire ready,inready,ov;wire signed[31:0]acc;wire signed[7:0]value;
 always #5 clk=~clk;
 yunet_dot4 #(.MODEL_SHIFT(1)) dut(.clk(clk),.rst_n(rst),.start(start),.bias(bias),.shift(shift),.relu(1'b0),.ready(ready),
 .in_valid(inv),.in_ready(inready),.in_last(1'b1),.activations(36'd0),.weights(32'd0),.out_valid(ov),.out_ready(1'b1),.accumulator(acc),.value(value),.dw_mode(1'b0),.dw_stop(1'b0),.dw_p_valid(),.dw_p0(),.dw_p1(),.dw_p2(),.dw_p3());
 integer s,i,r,checks=0;reg signed[31:0]v;reg signed[7:0]want;
 initial begin
  for(s=0;s<32;s=s+1)for(r=0;r<2;r=r+1)for(i=0;i<1030;i=i+1)begin
   case(i)
    0:v=32'sh80000000;1:v=32'sh7fffffff;2:v=0;3:v=-1;4:v=127;5:v=-128;
    default:v=$random;
   endcase
   if(dut.requant_model(v,s,r)!==dut.requant(v,s,r))$fatal(1,"shift%0d input%0d relu%0d",s,v,r);
   checks=checks+1;
  end
  repeat(3)@(negedge clk);rst=1;
  for(i=-256;i<=256;i=i+32)begin
   @(negedge clk);bias=i;shift=0;start=1;
   @(negedge clk);start=0;inv=1;
   @(negedge clk);inv=0;
   wait(ov);#1;want=i>127?127:i< -128?-128:i;
   if(value!==want||acc!==i)$fatal(1,"zero shift pipeline input%0d output%0d accumulator%0d",i,value,acc);
   wait(ready);
  end
  $display("PASS tb_model_shift: %0d function comparisons for shifts0..31 plus 17 zero-shift pipeline transactions",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
