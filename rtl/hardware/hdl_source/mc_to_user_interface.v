

module mc_to_user_interface (
    input wire          I_clk,
    input wire          I_rst_n,

    /*
        ddr user interface
        当I_ddr_user_ready拉低时，还能写入8个长度数据
    */
    input wire          I_ddr_user_wr_en,
    input wire          I_ddr_user_rd_en,  //synthesis keep
    input wire[24:0]    I_ddr_user_addr,
    input wire[127:0]   I_ddr_user_wr_data,
    output wire         O_ddr_user_ready,
    output wire         O_ddr_user_rd_valid,
    output wire[127:0]  O_ddr_user_rd_data,

    /*
        ddr memory controller interface
    */
    output  wire        O_mc_app_en,
    output  wire [24:0] O_mc_app_addr,
    output  wire [2:0]  O_mc_app_cmd,
    input  wire         I_mc_app_rdy,
    output wire         O_mc_app_wdf_wren,
    output wire [127:0] O_mc_app_wdf_data,
    output wire         O_mc_app_wdf_end,
    output wire [31:0]  O_mc_app_wdf_mask,
    input wire          I_mc_app_wdf_rdy,
    input wire [127:0]  I_mc_app_rd_data,
    input wire          I_mc_app_rd_data_end,
    input wire          I_mc_app_rd_data_valid
);

    wire        S_fifo_wr_en;    
    wire[154:0] S_fifo_wr_data;
    wire        S_fifio_pro_full;
    wire        S_fifo_rd_en;    
    wire[154:0] S_fifo_rd_data;
    wire        S_fifo_rd_valid;
    wire        S_fifo_empty;   

    assign S_fifo_wr_en = I_ddr_user_wr_en | I_ddr_user_rd_en;

    assign S_fifo_wr_data = {I_ddr_user_wr_en,I_ddr_user_rd_en,I_ddr_user_addr,I_ddr_user_wr_data};


    // A read command must not depend on the AXI write-data ready signal.
    // SHOW_AHEAD FIFO presents the command before pop, so select readiness by command type.
    wire       next_cmd_is_read = S_fifo_rd_data[153];
    reg address_sent, data_sent;
    wire command_valid = !S_fifo_empty && I_rst_n;
    wire address_accept = O_mc_app_en && I_mc_app_rdy;
    wire data_accept = O_mc_app_wdf_wren && I_mc_app_wdf_rdy;
    assign S_fifo_rd_en = command_valid && (next_cmd_is_read ? address_accept :
                         ((address_sent || address_accept) && (data_sent || data_accept)));
    // AXI AW and W may complete on different cycles. Hold the FIFO head until
    // both have completed, and never send either half of a write twice.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin address_sent<=0; data_sent<=0; end
        else if(S_fifo_rd_en) begin address_sent<=0; data_sent<=0; end
        else begin
            if(address_accept) address_sent<=1;
            if(data_accept) data_sent<=1;
        end
    end

    assign O_ddr_user_ready = ~S_fifio_pro_full;

    assign O_mc_app_en = command_valid && !address_sent;

    assign O_mc_app_addr = command_valid ? S_fifo_rd_data[152:128] : 'd0;

    assign O_mc_app_cmd = command_valid && next_cmd_is_read ? 3'd1 : 3'd0;

    assign O_mc_app_wdf_wren = command_valid && !next_cmd_is_read && !data_sent;

    assign O_mc_app_wdf_end = O_mc_app_wdf_wren;

    assign O_mc_app_wdf_mask = 'd0;

    assign O_mc_app_wdf_data = O_mc_app_wdf_wren ? S_fifo_rd_data[127:0] : 'd0;

    assign O_ddr_user_rd_valid = I_mc_app_rd_data_valid;

    assign O_ddr_user_rd_data = I_mc_app_rd_data;

    w155_d512_fifo U_w155_d512_fifo(
        .clk        ( I_clk            ),     
        .rst        ( ~I_rst_n         ),     

        .we         ( S_fifo_wr_en     ),
        .di         ( S_fifo_wr_data   ),
        .afull      ( S_fifio_pro_full ),
        .full_flag  (),
        .wrusedw    (),

        .re         ( S_fifo_rd_en     ), 
        .valid      ( S_fifo_rd_valid  ), 
        .dout       ( S_fifo_rd_data   ),  
        .empty_flag ( S_fifo_empty     ),
        .aempty     (),
        .rdusedw    ()
    );

endmodule
