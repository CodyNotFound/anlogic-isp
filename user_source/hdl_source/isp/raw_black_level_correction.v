// RAW10 black-level correction hook.
//
// Stream-transparent and combinational so the existing AXI-stream timing and
// top-level interfaces remain unchanged. Correction is disabled by default
// until the actual SC500 black pedestal is measured with the lens covered.
module raw_black_level_correction #(
    parameter integer ENABLE = 0,
    parameter [9:0] OFFSET0 = 10'd0,
    parameter [9:0] OFFSET1 = 10'd0,
    parameter [9:0] OFFSET2 = 10'd0,
    parameter [9:0] OFFSET3 = 10'd0
)(
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [39:0] I_tdata,
    input  wire        I_tvalid,
    input  wire [9:0]  I_tdest,
    output wire        I_tready,
    output wire        O_tlast,
    output wire        O_tuser,
    output wire [39:0] O_tdata,
    output wire        O_tvalid,
    output wire [9:0]  O_tdest,
    input  wire        O_tready
);
    function [9:0] subtract_offset;
        input [9:0] value;
        input [9:0] offset;
        begin
            if (value > offset)
                subtract_offset = value - offset;
            else
                subtract_offset = 10'd0;
        end
    endfunction

    assign O_tdata = ENABLE ? {
        subtract_offset(I_tdata[39:30], OFFSET3),
        subtract_offset(I_tdata[29:20], OFFSET2),
        subtract_offset(I_tdata[19:10], OFFSET1),
        subtract_offset(I_tdata[9:0],   OFFSET0)
    } : I_tdata;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;
    assign O_tvalid = I_tvalid;
    assign O_tdest  = I_tdest;
    assign I_tready = O_tready;
endmodule
