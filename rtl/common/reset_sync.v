// Assert immediately, release only after two active destination clock edges.
// A stopped clock holds reset. Only these synchronizer registers are exempted.
module reset_sync #(parameter NEG_EDGE=0)(input wire clk,async_rst_n,output wire rst_n);
 (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [1:0] release_ff;
 generate if(NEG_EDGE)begin:falling
 always @(negedge clk or negedge async_rst_n)
  if(!async_rst_n) release_ff<=2'b00;
  else release_ff<={release_ff[0],1'b1};
 end else begin:rising
 always @(posedge clk or negedge async_rst_n)
  if(!async_rst_n) release_ff<=2'b00;
  else release_ff<={release_ff[0],1'b1};
 end endgenerate
 assign rst_n=release_ff[1];
endmodule
