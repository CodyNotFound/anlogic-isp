// Source holds data until the next frame and announces it one source cycle later.
// Data: two stages; event: three stages. The event therefore gives the bundled
// byte an additional destination cycle to settle before it is consumed.
module frame_stat_cdc(input wire clk,rst_n,input wire [7:0] data_async,
 input wire toggle_async,output reg [7:0] data,output reg valid);
 (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [7:0] data_meta,data_sync;
 (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [2:0] event_sync;
 reg seen;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin data_meta<=0;data_sync<=0;event_sync<=0;seen<=0;data<=0;valid<=0;end
  else begin
   data_meta<=data_async;data_sync<=data_meta;
   event_sync<={event_sync[1:0],toggle_async};valid<=0;
   if(event_sync[2]!=seen)begin seen<=event_sync[2];data<=data_sync;valid<=1;end
  end
 end
endmodule
