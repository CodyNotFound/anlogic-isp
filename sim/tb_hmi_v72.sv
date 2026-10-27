`timescale 1ns/1ps
module tb_hmi_v72;
 reg local_takeover=0;reg clk=0,rst=0,rx=1;always #5 clk=~clk;
 reg[3:0]physical=0,mode=11;wire[3:0]features,keys,selected;wire tx,mode_set,action;
 hmi_control_link #(.CLK_HZ(1000000),.BAUD(100000)) dut(.clk(clk),.rst_n(rst),.rx(rx),.tx(tx),
 .physical_features(physical),.mode(mode),.target_found(1'b1),.compute_valid(1'b1),.task_status(4'd0),.ctl_state(2'd1),
 .x_digits(16'h0936),.y_digits(16'h0404),.h_digits(16'h1539),.v_digits(16'h1476),.ms_digits(16'h0267),.fps_digits(8'h60),
 .local_takeover(local_takeover),.manual_active(1'b0),.connected(),.features(features),.mode_set(mode_set),.mode_value(selected),.action(action),.keys(keys));
 wire valid,error;wire[7:0]data;
 vision_uart_8n1 #(.CLK_HZ(1000000),.BAUD(100000)) monitor(.clk(clk),.rst_n(rst),.rx(tx),.tx_valid(1'b0),.tx_data(8'd0),.tx_ready(),.tx(),.rx_valid(valid),.rx_error(error),.rx_data(data));
 integer tick_count=0,last_start=-1000000;
 integer bytes=0,packets=0,sets=0,picks=0,idx=0,field=0,value=0,last_seq=-1;reg[127:0] golden;integer first[0:13];
 always @(posedge clk)begin
  tick_count=tick_count+1;
  if(mode_set)begin mode<=selected;sets=sets+1;end
  if(action)picks=picks+1;
  if(error)$fatal(1,"UART TX framing error");
  if(valid)begin
   if(idx==0&&field==0)begin if(tick_count-last_start<99000)$fatal(1,"query bypassed atomic snapshot interval");last_start=tick_count;end
   golden="main.vA.val=0000";golden[79:72]=field==12?"N":field==13?"M":"A"+field;
   if(idx<12 && data!==((golden>>(8*(15-idx)))&255))$fatal(1,"header index%0d field%0d got%x expected%x",idx,field,data,(golden>>(8*(15-idx)))&255);
   if(idx>=12&&idx<=15)begin
    if(data<"0"||data>"9")$fatal(1,"invalid decimal");value=value*10+data-"0";
   end
   if(idx>=16 && data!==8'hff)$fatal(1,"missing native command terminator");
   if(idx==18)begin
    if(packets==0 && value!=first[field])$fatal(1,"first snapshot field%0d got%0d expected%0d",field,value,first[field]);
    if(field==13)begin
     if(last_seq>=0 && value!=(last_seq==99?0:last_seq+1))$fatal(1,"sequence");last_seq=value;packets=packets+1;field=0;
    end else field=field+1;
    idx=0;value=0;
   end else idx=idx+1;
   bytes=bytes+1;
  end
 end
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task send(input[7:0]b);integer j;begin rx=0;clocks(10);for(j=0;j<8;j=j+1)begin rx=b[j];clocks(10);end rx=1;clocks(10);end endtask
 task command(input[7:0]o,a);begin send(8'ha5);send(8'h5a);send(o);send(a);send(8'hff^o^a);send(8'h0d);clocks(5);end endtask
 initial begin
  first[0]=11;first[1]=0;first[2]=5;first[3]=936;first[4]=404;first[5]=1539;first[6]=1476;first[7]=267;first[8]=1;first[9]=1;first[10]=60;first[11]=0;first[12]=0;first[13]=0;
  clocks(5);rst=1;clocks(30000);if(packets!=1)$fatal(1,"initial telemetry packet");
  command(8'h01,0);if(!dut.connected||features!=physical)$fatal(1,"initial query");
  command(8'h11,1);command(8'h12,1);command(8'h13,1);command(8'h14,1);command(8'h16,8);
  if(features!=15||keys!=8)$fatal(1,"remote direction");
  clocks(251000);if(keys!=0||!dut.connected||features!=15)$fatal(1,"direction timeout affected ownership");
  clocks(1100000);if(!dut.connected||features!=15)$fatal(1,"idle dropped screen ownership");
  physical=8;clocks(5);if(dut.connected||features!=8)$fatal(1,"switch takeover");
  command(8'h01,0);command(8'h02,0);if(dut.connected||features!=8)$fatal(1,"poll stole local ownership");
  command(8'h14,0);if(!dut.connected||features!=0)$fatal(1,"explicit remote retake");
  physical=0;clocks(5);
  for(integer k=0;k<15;k=k+1)begin command(8'h10,k);if(mode!=k)$fatal(1,"contiguous mode %0d",k);end
  command(8'h10,15);command(8'h10,16);if(mode!=14)$fatal(1,"invalid mode");
  command(8'h15,0);command(8'h10,13);command(8'h15,0);if(picks!=2)$fatal(1,"renumbered pick/reset");
  command(8'h11,1);local_takeover=1;clocks(1);local_takeover=0;clocks(3);
  if(dut.connected||features!=physical||keys!=0)$fatal(1,"button takeover");
  command(8'h02,0);command(8'h01,0);if(dut.connected)$fatal(1,"poll undid physical button");
  command(8'h13,1);if(!dut.connected||features!=4)$fatal(1,"screen action failed retake");
  send(8'ha5);send(8'h5a);send(8'h13);send(0);send(0);send(8'h0d);clocks(5);if(features!=4)$fatal(1,"bad checksum");
  clocks(110000);if(packets<4)$fatal(1,"periodic telemetry");
  $display("PASS tb_hmi_v72 %0d bytes %0d atomic snapshots, persistent ownership, direction timeout, local takeover, contiguous modes and atomic snapshots",bytes,packets);$finish;
 end
 initial begin #40000000;$fatal(1,"watchdog");end
endmodule
