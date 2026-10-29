`timescale 1ns/1ps
module tb_yunet_dual_arena;
 reg clk=0,io_clk=0;always #3.333 clk=~clk;initial begin #1.1;forever #6.667 io_clk=~io_clk;end
 reg rst=0,load=0;reg [16:0] la=0,ra=0;reg [7:0] ld=0;wire [7:0] rd;wire [31:0] word;
 yunet_network #(.DUAL_CLOCK(1)) dut(.clk(clk),.io_clk(io_clk),.rst_n(rst),.start(1'b0),.load_valid(load),.load_address(la),.load_data(ld),.read_address(ra),.read_data(rd),.read_word(word),.busy(),.done(),.operation_done(),.operation_index(),.cycles());
 reg [7:0] expected[0:65535];reg [16:0] wa;reg [7:0] wd;integer i,j,addr;
 initial begin
  repeat(5)@(negedge io_clk);rst=1;
  for(i=0;i<65536;i=i+1)begin load=1;la=i;ld=(i*29)^(i>>8);expected[i]=ld;@(negedge io_clk);end
  load=0;
  force dut.write_pending=1;force dut.write_address=wa;force dut.write_we=4'b0001<<wa[1:0];force dut.write_data0=wd;force dut.write_data1=wd;force dut.write_data2=wd;force dut.write_data3=wd;
  for(i=0;i<1024;i=i+1)begin @(negedge clk);wa=(i*61)%65536;wd=i^8'hb7;expected[wa]=wd;force dut.write_we=4'b0001<<wa[1:0];end
  @(negedge clk);release dut.write_pending;release dut.write_address;release dut.write_we;release dut.write_data0;release dut.write_data1;release dut.write_data2;release dut.write_data3;
  for(i=0;i<65536;i=i+1)begin
   @(negedge io_clk);ra=i;@(negedge io_clk);
   if(rd!==expected[i])$fatal(1,"dual arena byte mismatch %0d got%h want%h",i,rd,expected[i]);
   for(j=0;j<4;j=j+1)if(word[j*8+:8]!==expected[(i&65532)+j])$fatal(1,"dual arena word mismatch %0d lane%0d",i,j);
  end
  $display("PASS tb_yunet_dual_arena: 65536 IO writes, 1024 compute writes, all byte and word reads, nonaligned 75/150 clocks");$finish;
 end
 initial begin #4000000;$fatal(1,"arena watchdog");end
endmodule
