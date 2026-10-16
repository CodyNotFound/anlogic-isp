// MIPI receive clocks may stop between packets. Only capture belongs in that
// domain: the ISP must be able to finish buffered rows and its synthetic tail
// while the sensor is idle. Carry native frame events with data in one FIFO.
module camera_raw_clock_bridge (
 input wire I_rst_n,I_rx_clk,I_raw_valid,I_frame_start,I_frame_end,
 input wire [39:0] I_raw_data,input wire I_processing_clk,
 output wire O_raw_valid,O_frame_start,O_frame_end,
 output wire [39:0] O_raw_data
);
 wire [127:0] event_data;
 wire event_valid,event_empty,event_full;
 wire write_event=I_rst_n&&(I_raw_valid||I_frame_start||I_frame_end);
 w128_d512_fifo events(
 .rst(!I_rst_n),.clkw(I_rx_clk),.clkr(I_processing_clk),
 .we(write_event),
 .di({85'd0,I_raw_valid,I_frame_start,I_frame_end,I_raw_data}),
 .re(I_rst_n&&!event_empty),.dout(event_data),.valid(event_valid),
 .full_flag(event_full),.empty_flag(event_empty),.afull(),.aempty(),.wrusedw(),.rdusedw());
 assign O_raw_valid=event_valid&&event_data[42];
 assign O_frame_start=event_valid&&event_data[41];
 assign O_frame_end=event_valid&&event_data[40];
 assign O_raw_data=event_data[39:0];
`ifndef SYNTHESIS
 always @(posedge I_rx_clk)if(write_event&&event_full)
  $error("camera_raw_clock_bridge: event FIFO overflow");
`endif
endmodule
