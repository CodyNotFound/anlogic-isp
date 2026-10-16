`timescale 1ns/1ps
module tb_mc_command_handshake;
 reg clk=0,rst_n=0;reg arready=0,awready=1;reg user_rd=0;
 wire old_ready,fixed_ready;wire old_app_en,fixed_app_en;wire [2:0] old_cmd,fixed_cmd;
 wire old_user_ready,fixed_user_ready,old_wdf_ready,fixed_wdf_ready;
 assign old_ready=arready||awready;
 assign fixed_ready=(fixed_app_en && fixed_cmd[0]) ? arready : awready;
 mc_to_user_interface_v9_reference dut_old(
  .I_clk(clk),.I_rst_n(rst_n),.I_ddr_user_wr_en(1'b0),.I_ddr_user_rd_en(user_rd),
  .I_ddr_user_addr(25'd1234),.I_ddr_user_wr_data(128'd0),.O_ddr_user_ready(old_user_ready),
  .O_ddr_user_rd_valid(),.O_ddr_user_rd_data(),.O_mc_app_en(old_app_en),.O_mc_app_addr(),
  .O_mc_app_cmd(old_cmd),.I_mc_app_rdy(old_ready),.O_mc_app_wdf_wren(),.O_mc_app_wdf_data(),
  .O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),.I_mc_app_wdf_rdy(awready),.I_mc_app_rd_data_valid(),
  .I_mc_app_rd_data(),.I_mc_app_rd_data_end());
 mc_to_user_interface dut_fixed(
  .I_clk(clk),.I_rst_n(rst_n),.I_ddr_user_wr_en(1'b0),.I_ddr_user_rd_en(user_rd),
  .I_ddr_user_addr(25'd1234),.I_ddr_user_wr_data(128'd0),.O_ddr_user_ready(fixed_user_ready),
  .O_ddr_user_rd_valid(),.O_ddr_user_rd_data(),.O_mc_app_en(fixed_app_en),.O_mc_app_addr(),
  .O_mc_app_cmd(fixed_cmd),.I_mc_app_rdy(fixed_ready),.O_mc_app_wdf_wren(),.O_mc_app_wdf_data(),
  .O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),.I_mc_app_wdf_rdy(awready),.I_mc_app_rd_data_valid(),
  .I_mc_app_rd_data(),.I_mc_app_rd_data_end());
 always #3 clk=~clk;
 integer old_pops=0,fixed_pops=0,i;
 always @(posedge clk)begin
  if(rst_n)begin
   if(old_app_en)old_pops=old_pops+1;
   if(fixed_app_en && fixed_ready)fixed_pops=fixed_pops+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  for(i=0;i<4;i=i+1)begin @(negedge clk);user_rd=1;@(negedge clk);user_rd=0;end
  repeat(5)@(negedge clk);
  $display("PHASE1 arready=%0b awready=%0b old_pops=%0d fixed_pops=%0d",arready,awready,old_pops,fixed_pops);
  if(old_pops!=4)$fatal(1,"old defect not exposed");
  if(fixed_pops!=0)$fatal(1,"fixed read popped without ARREADY");
  arready=1;repeat(8)@(negedge clk);
  $display("PHASE2 old_pops=%0d fixed_pops=%0d",old_pops,fixed_pops);
  if(old_pops!=4)$fatal(1,"old lost commands");
  if(fixed_pops!=4)$fatal(1,"fixed did not queue/process reads");
  $display("PASS tb_mc_command_handshake old_lost=4 fixed_lost=0");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
