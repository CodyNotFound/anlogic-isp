// A command FIFO has one write port. Give a pending camera word precedence;
// the reader sees ready=0 and retains its address/response credit until accepted.
module ddr_user_arbiter (
 input wire I_fifo_ready,
 input wire I_wr_en,input wire [24:0] I_wr_addr,input wire [127:0] I_wr_data,
 input wire I_rd_en,input wire [24:0] I_rd_addr,
 output wire O_wr_ready,O_rd_ready,O_user_wr_en,O_user_rd_en,
 output wire [24:0] O_user_addr,output wire [127:0] O_user_wr_data
);
 assign O_wr_ready=I_fifo_ready;
 assign O_rd_ready=I_fifo_ready&&!I_wr_en;
 assign O_user_wr_en=I_wr_en&&O_wr_ready;
 assign O_user_rd_en=I_rd_en&&O_rd_ready;
 assign O_user_addr=O_user_wr_en?I_wr_addr:I_rd_addr;
 assign O_user_wr_data=I_wr_data;
endmodule
