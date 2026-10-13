// Camera/algorithm adaptive brightness, before OSD composition.
// This module changes image RGB values, leaving OSD colors untouched. It does not
// modify camera exposure, ISP processing, DDR contents, or algorithm data.
module adaptive_brightness #(
    parameter integer TARGET_LOW  = 80,
    parameter integer TARGET_HIGH = 176
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    input  wire        de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    // Extra headroom for frame sums; 1280x720x255 needs 28 unsigned bits.
    reg [39:0] luma_sum;
    reg [21:0] pixel_count;
    reg [8:0] gain_q8;
    // BT.601 full-range Y, implemented as shift/add coefficients.
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

    wire [7:0] luma = rgb_to_y(pixel_in);
    wire [39:0] count_wide = {18'd0,pixel_count};
    wire [39:0] low_threshold = (TARGET_LOW == 80) ? ((count_wide << 6) + (count_wide << 4)) : count_wide * TARGET_LOW;
    wire [39:0] high_threshold = (TARGET_HIGH == 176) ? ((count_wide << 7) + (count_wide << 5) + (count_wide << 4)) : count_wide * TARGET_HIGH;

    function [7:0] scale_channel;
        input [7:0] value;
        input [8:0] gain;
        reg [16:0] product;
        begin
            product = value * gain;
            if (product > 17'd65280) scale_channel = 8'hff;
            else scale_channel = product[15:8];
        end
    endfunction

    always @* begin
        if (!de) pixel_out = 24'd0;
        else if (!enable) pixel_out = pixel_in;
        else pixel_out = {scale_channel(pixel_in[23:16], gain_q8),
                          scale_channel(pixel_in[15:8], gain_q8),
                          scale_channel(pixel_in[7:0], gain_q8)};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            luma_sum <= 0;
            pixel_count <= 22'd0;
            gain_q8 <= 9'd256;
        end else if (frame_start) begin
            if (enable && (luma_sum != 0) && (pixel_count != 0)) begin
                if (luma_sum < low_threshold) begin
                    if (gain_q8 < 9'd368) gain_q8 <= gain_q8 + 8;
                end else if (luma_sum > high_threshold) begin
                    if (gain_q8 > 9'd144) gain_q8 <= gain_q8 - 8;
                end
            end else if (!enable) gain_q8 <= 9'd256;
            luma_sum <= {{32{1'b0}},luma};
            pixel_count <= 22'd1;
        end else if (de) begin
            luma_sum <= luma_sum + luma;
            if (pixel_count != 22'h3fffff) pixel_count <= pixel_count + 1'b1;
        end
    end
endmodule
