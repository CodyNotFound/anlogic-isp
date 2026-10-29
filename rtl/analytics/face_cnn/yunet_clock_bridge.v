// One outstanding inference request. Snapshot writes and head reads stay in
// the video domain; only compute start/done and a held cycle bundle cross.
// Assertion of rst_n cancels both sides; core reset release is synchronized.
module yunet_clock_bridge(
 input wire io_clk,core_clk,rst_n,io_start,core_ready,core_done,
 input wire [31:0] core_cycles,
 output wire core_rst_n,output reg core_start,io_done,io_pending,
 output reg [31:0] io_cycles);
 reset_sync u_reset_cnn(.clk(core_clk),.async_rst_n(rst_n),.rst_n(core_rst_n));
 reg request_toggle,start_d,done_seen;
 (* async_reg="true" *) reg request_meta,request_sync,done_meta,done_sync;
 reg request_seen,core_running,done_toggle,publish;
 reg [31:0] held_cycles;
 always @(posedge io_clk or negedge rst_n)begin
  if(!rst_n)begin request_toggle<=0;start_d<=0;done_meta<=0;done_sync<=0;done_seen<=0;io_done<=0;io_pending<=0;io_cycles<=0;end
  else begin
   start_d<=io_start;done_meta<=done_toggle;done_sync<=done_meta;io_done<=0;
   if(io_start&&!start_d&&!io_pending)begin request_toggle<=!request_toggle;io_pending<=1;end
   if(done_sync!=done_seen)begin
    done_seen<=done_sync;
    if(io_pending)begin io_cycles<=held_cycles;io_done<=1;io_pending<=0;end
   end
  end
 end
 always @(posedge core_clk or negedge core_rst_n)begin
  if(!core_rst_n)begin request_meta<=0;request_sync<=0;request_seen<=0;core_running<=0;core_start<=0;done_toggle<=0;held_cycles<=0;publish<=0;end
  else begin
   request_meta<=request_toggle;request_sync<=request_meta;core_start<=0;publish<=0;
   if(request_sync!=request_seen&&core_ready&&!core_running)begin
    request_seen<=request_sync;core_start<=1;core_running<=1;
   end
   if(core_done&&core_running)begin held_cycles<=core_cycles;publish<=1;core_running<=0;end
   // Data is stable BEFORE the event changes and remains held until next done.
   if(publish)done_toggle<=!done_toggle;
  end
 end
endmodule
