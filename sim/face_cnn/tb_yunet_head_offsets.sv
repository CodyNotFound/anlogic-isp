`timescale 1ns/1ps
module tb_yunet_head_offsets;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;wire result,found;wire [11:0] x,y,sz,cx,cy;wire [13:0] score;
 yunet_position_snapshot dut(.clk(clk),.core_clk(clk),.rst_n(rst),.start(1'b0),.load_valid(1'b0),.load_address(17'd0),.load_data(8'd0),.ready(),.busy(),.result_valid(result),.found(found),.box_x(x),.box_y(y),.box_size(sz),.center_x(cx),.center_y(cy),.score_product(score),.cycles(),.external_read_enable(1'b0),.external_read_address(17'd0),.external_read_data(),.external_read_word());
 reg [7:0] mem[0:65535];integer i,fd,n,ef,es,ex,ey,ez,ecx,ecy;
 initial begin
  $readmemh("build/head_offsets/memory.hex",mem);
  fd=$fopen("build/head_offsets/expected.txt","r");n=$fscanf(fd,"%d %d %d %d %d %d %d",ef,es,ex,ey,ez,ecx,ecy);
  if(n!=7)$fatal(1,"missing scanner fixture");
  repeat(5)@(negedge clk);rst=1;
  for(i=0;i<16384;i=i+1)begin dut.network.fm0[i]=mem[4*i];dut.network.fm1[i]=mem[4*i+1];dut.network.fm2[i]=mem[4*i+2];dut.network.fm3[i]=mem[4*i+3];end
  // Bypass CNN computation only: start the REAL head scanner on golden memory.
  @(negedge clk);dut.state=1;force dut.nn_done=1;
  @(negedge clk);release dut.nn_done;
  wait(result);@(negedge clk);
  if(found!==ef[0]||score!==es[13:0]||x!==ex[11:0]||y!==ey[11:0]||sz!==ez[11:0]||cx!==ecx[11:0]||cy!==ecy[11:0])$fatal(1,"scanner mismatch found=%d score=%d box=%d,%d,%d center=%d,%d",found,score,x,y,sz,cx,cy);
  $display("PASS tb_yunet_head_offsets: actual head scanner plus decoder match golden reference found=%d score=%d",found,score);$finish;
 end
 initial begin #1000000;$fatal(1,"scanner watchdog");end
endmodule
