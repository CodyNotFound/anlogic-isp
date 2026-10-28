// Streaming frame histogram equalizer.
// A double-buffered histogram lets the current frame accumulate while the
// previous frame builds a 256-entry LUT during horizontal blanking. This is
// deliberately frame-to-frame adaptive because a same-frame equalizer would
// require a second frame read or an additional frame buffer.
module histogram_equalizer #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    input  wire        de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    localparam integer PIXEL_COUNT = IMG_WIDTH * IMG_HEIGHT;

    reg [19:0] hist_a [0:255];
    reg [19:0] hist_b [0:255];
    reg [7:0]  lut [0:255];
    reg [8:0] init_index;
    reg       init_done;
    reg       active_hist_sel;
    reg       source_hist_sel;
    reg       build_pending;
    reg       clear_pending;
    reg [8:0] build_index;
    reg [8:0] clear_index;
    reg [20:0] cdf;

    // Use the same BT.601 Y component as the other video algorithms.
    // Shift/add coefficient decomposition avoids RGB multipliers.
    function [7:0] rgb_to_y;
        input [23:0] rgb;
        reg [16:0] y_r;
        reg [16:0] y_g;
        reg [16:0] y_b;
        reg [16:0] y_sum;
        begin
            y_r   = ({9'd0,rgb[23:16]} << 6) +
                    ({9'd0,rgb[23:16]} << 3) +
                    ({9'd0,rgb[23:16]} << 2) + rgb[23:16];
            y_g   = ({9'd0,rgb[15:8]}  << 7) +
                    ({9'd0,rgb[15:8]}  << 4) +
                    ({9'd0,rgb[15:8]}  << 2) +
                    ({9'd0,rgb[15:8]}  << 1);
            y_b   = ({9'd0,rgb[7:0]}   << 4) +
                    ({9'd0,rgb[7:0]}   << 3) +
                    ({9'd0,rgb[7:0]}   << 2) + rgb[7:0];
            y_sum = y_r + y_g + y_b;
            rgb_to_y = y_sum[15:8];
        end
    endfunction

    wire [7:0] gray = rgb_to_y(pixel_in);
    wire [20:0] source_hist_value = source_hist_sel ?
                                     {1'b0,hist_b[build_index]} :
                                     {1'b0,hist_a[build_index]};
    wire [20:0] cdf_next = cdf + source_hist_value;
    // 255 / 921600 is approximately 291 / 2^20. This Q20 normalization
    // replaces a large combinational divider while keeping the LUT within
    // one output code of the exact full-frame result.
    wire [29:0] cdf_wide = {9'd0,cdf_next};
    wire [29:0] lut_product = (cdf_wide << 8) + (cdf_wide << 5) + (cdf_wide << 1) + cdf_wide;
    wire [9:0] lut_scaled = lut_product[29:20];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out      <= 24'd0;
            init_index      <= 0;
            init_done       <= 1'b0;
            active_hist_sel <= 1'b0;
            source_hist_sel <= 1'b0;
            build_pending   <= 1'b0;
            clear_pending   <= 1'b0;
            build_index     <= 0;
            clear_index     <= 0;
            cdf             <= 0;
        end else if (!init_done) begin
            pixel_out <= 24'd0;
            hist_a[init_index] <= 0;
            hist_b[init_index] <= 0;
            lut[init_index] <= init_index[7:0];
            if (init_index == 9'd255) init_done <= 1'b1;
            else init_index <= init_index + 1'b1;
        end else begin
            // Register the LUT read and normalization result before the
            // spatial algorithm stage.
            if (!de) pixel_out <= 24'd0;
            else if (!enable) pixel_out <= pixel_in;
            else pixel_out <= {lut[gray], lut[gray], lut[gray]};

            if (frame_start) begin
                source_hist_sel <= active_hist_sel;
                active_hist_sel <= ~active_hist_sel;
                build_pending   <= 1'b1;
                clear_pending   <= 1'b0;
                build_index     <= 0;
                clear_index     <= 0;
                cdf             <= 0;
                if (de) begin
                    if (active_hist_sel) hist_a[gray] <= 20'd1;
                    else hist_b[gray] <= 20'd1;
                end
            end else if (de) begin
                if (active_hist_sel) hist_b[gray] <= hist_b[gray] + 1'b1;
                else hist_a[gray] <= hist_a[gray] + 1'b1;
            end

            if (!de && build_pending) begin
                if (lut_scaled > 10'd255) lut[build_index] <= 8'hff;
                else lut[build_index] <= lut_scaled[7:0];
                cdf <= cdf_next;
                if (build_index == 9'd255) begin
                    build_pending <= 1'b0;
                    clear_pending <= 1'b1;
                    clear_index <= 0;
                end else build_index <= build_index + 1'b1;
            end else if (!de && clear_pending) begin
                if (source_hist_sel) hist_b[clear_index] <= 0;
                else hist_a[clear_index] <= 0;
                if (clear_index == 9'd255) clear_pending <= 1'b0;
                else clear_index <= clear_index + 1'b1;
            end
        end
    end
endmodule
