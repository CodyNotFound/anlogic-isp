`timescale 1ns/1ps
module tb_mc_axi_backpressure;
 reg clk=0,rst=0,wr=0,rd=0,ar=0,aw=0,w=0;
 reg [24:0] addr=0; reg [127:0] data=0;
 wire en,we,ready; wire [2:0] cmd; wire [24:0] a; wire [127:0] d;
 wire rdy=(en && cmd[0])?ar:aw;
 integer nr=0,na=0,nw=0,submitted_writes=0,i,j;
 always #5 clk=~clk;
 mc_to_user_interface dut(.I_clk(clk),.I_rst_n(rst),.I_ddr_user_wr_en(wr),
 .I_ddr_user_rd_en(rd),.I_ddr_user_addr(addr),.I_ddr_user_wr_data(data),
 .O_ddr_user_ready(ready),.O_ddr_user_rd_valid(),.O_ddr_user_rd_data(),
 .O_mc_app_en(en),.O_mc_app_addr(a),.O_mc_app_cmd(cmd),.I_mc_app_rdy(rdy),
 .O_mc_app_wdf_wren(we),.O_mc_app_wdf_data(d),.O_mc_app_wdf_end(),
 .O_mc_app_wdf_mask(),.I_mc_app_wdf_rdy(w),.I_mc_app_rd_data(128'd0),
 .I_mc_app_rd_data_end(1'b0),.I_mc_app_rd_data_valid(1'b0));
 always @(posedge clk) if(rst) begin
  if(en && rdy) begin
   if(cmd[0]) begin if(a!==25'd100) $fatal(1,"read address"); nr=nr+1; end
   else begin if(a!==(25'd200+na)) $fatal(1,"write address/order"); na=na+1; end
  end
  if(we && w) begin if(d!==(128'h123456789abcdef+nw)) $fatal(1,"write data/order"); nw=nw+1; end
 end
 task push;input is_read;begin
  @(negedge clk);rd=is_read;wr=!is_read;addr=is_read?100:200+submitted_writes;
  data=128'h123456789abcdef+submitted_writes;
  if(!is_read)submitted_writes=submitted_writes+1;
  @(negedge clk);rd=0;wr=0;
 end endtask
 initial begin
  repeat(5) @(negedge clk);rst=1;repeat(8) @(negedge clk);
  aw=1;push(1);repeat(12) @(negedge clk);
  if(nr!=0 || !en || cmd!==3'd1) $fatal(1,"read blocked by AW or VALID depends on READY");
  ar=1;repeat(8) @(negedge clk);if(nr!=1) $fatal(1,"read recovery");
  // AW before W, then W before AW. Neither channel may be duplicated.
  push(0);repeat(12) @(negedge clk);if(na!=1 || nw!=0) $fatal(1,"AW-first");
  w=1;repeat(8) @(negedge clk);if(na!=1 || nw!=1) $fatal(1,"AW-first completion");
  aw=0;push(0);repeat(12) @(negedge clk);if(na!=1 || nw!=2) $fatal(1,"W-first");
  aw=1;repeat(8) @(negedge clk);if(na!=2 || nw!=2) $fatal(1,"W-first completion");
  push(1);repeat(8) @(negedge clk);if(nr!=2) $fatal(1,"read after writes");
  fork
   begin for(i=0;i<32;i=i+1)begin push(0);push(1);end end
   begin for(j=0;j<400;j=j+1)begin
    @(negedge clk);ar=(j%7)>1;aw=(j%11)>3;w=(j%5)>1;
   end end
  join
  @(negedge clk);ar=1;aw=1;w=1;repeat(80) @(negedge clk);
  if(nr!=34 || na!=34 || nw!=34) $fatal(1,"mixed queue lost or duplicated beats");
  if(en || we) $fatal(1,"queue did not drain");
  $display("PASS tb_mc_axi_backpressure reads=34 AW=34 W=34 independent stalls and ordered data");$finish;
 end
 initial begin #20000;$fatal(1,"timeout");end
endmodule
