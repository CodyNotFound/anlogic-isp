// Frame-adaptive RGB white-balance trim.
// The platform ISP remains unchanged; this optional application-stage trim
// tracks the previous frame and converges R/B toward the green reference.
module auto_white_balance #(
    parameter integer GAIN_MIN = 128,
    parameter integer GAIN_MAX = 384,
    // Ignore clipped/near-black pixels when estimating the gray-world point.
    // These pixels carry little reliable chromatic information and were the
    // main weakness of the original whole-frame accumulator.
    parameter integer MIN_VALID_Y = 12,
    parameter integer MAX_VALID_Y = 240,
    // Do not update gains when a scene contains too few usable samples.
    parameter integer MIN_SAMPLES = 1024
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    input  wire        de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    // 1280x720x255 exceeds 32 bits for each color channel.
    reg [39:0] sum_r;
    reg [39:0] sum_g;
    reg [39:0] sum_b;
    reg [21:0] sample_count;
    reg [8:0] gain_r_q8;
    reg [8:0] gain_b_q8;

    // BT.601 full-range luma, implemented with shift/add coefficients.  This
    // is intentionally the same luma definition used by AE/HE and the gray
    // mode, so all application-stage statistics use one brightness metric.
    function [7:0] rgb_to_y;
        input [23:0] rgb;
        reg [16:0] y_r;
        reg [16:0] y_g;
        reg [16:0] y_b;
        reg [16:0] y_sum;
        begin
            y_r = ({9'd0,rgb[23:16]} << 6) +
                  ({9'd0,rgb[23:16]} << 3) +
                  ({9'd0,rgb[23:16]} << 2) + rgb[23:16];
            y_g = ({9'd0,rgb[15:8]} << 7) +
                  ({9'd0,rgb[15:8]} << 4) +
                  ({9'd0,rgb[15:8]} << 2) +
                  ({9'd0,rgb[15:8]} << 1);
            y_b = ({9'd0,rgb[7:0]} << 4) +
                  ({9'd0,rgb[7:0]} << 3) +
                  ({9'd0,rgb[7:0]} << 2) + rgb[7:0];
            y_sum = y_r + y_g + y_b;
            rgb_to_y = y_sum[15:8];
        end
    endfunction

    wire [7:0] pixel_y = rgb_to_y(pixel_in);
    wire       sample_valid = de &&
                               (pixel_y >= MIN_VALID_Y) &&
                               (pixel_y <= MAX_VALID_Y);

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out <= 24'd0;
            sum_r    <= 32'd0;
            sum_g    <= 32'd0;
            sum_b    <= 32'd0;
            sample_count <= 22'd0;
            gain_r_q8 <= 9'd256;
            gain_b_q8 <= 9'd256;
        end else begin
            // Keep the channel multipliers out of the following HE path.
            if (!de) pixel_out <= 24'd0;
            else if (!enable) pixel_out <= pixel_in;
            else pixel_out <= {scale_channel(pixel_in[23:16], gain_r_q8),
                               pixel_in[15:8],
                               scale_channel(pixel_in[7:0], gain_b_q8)};

            if (frame_start) begin
                // Update only from a sufficiently populated previous frame.
                // The gain therefore remains stable during a frame and does
                // not react to a mostly-black/mostly-clipped image.
                if (enable && (sum_g != 0) &&
                    (sample_count >= MIN_SAMPLES)) begin
                    if (sum_r + (sum_r >> 3) < sum_g) begin
                        if (gain_r_q8 < GAIN_MAX - 8) gain_r_q8 <= gain_r_q8 + 8;
                    end else if (sum_r > sum_g + (sum_g >> 3)) begin
                        if (gain_r_q8 > GAIN_MIN + 8) gain_r_q8 <= gain_r_q8 - 8;
                    end
                    if (sum_b + (sum_b >> 3) < sum_g) begin
                        if (gain_b_q8 < GAIN_MAX - 8) gain_b_q8 <= gain_b_q8 + 8;
                    end else if (sum_b > sum_g + (sum_g >> 3)) begin
                        if (gain_b_q8 > GAIN_MIN + 8) gain_b_q8 <= gain_b_q8 - 8;
                    end
                end else if (!enable) begin
                    gain_r_q8 <= 9'd256;
                    gain_b_q8 <= 9'd256;
                end
                // The first pixel belongs to the new frame. Include it only
                // when it passes the same validity test as all later pixels.
                sum_r <= sample_valid ? {{32{1'b0}},pixel_in[23:16]} : 40'd0;
                sum_g <= sample_valid ? {{32{1'b0}},pixel_in[15:8]}  : 40'd0;
                sum_b <= sample_valid ? {{32{1'b0}},pixel_in[7:0]}   : 40'd0;
                sample_count <= sample_valid ? 22'd1 : 22'd0;
            end else if (sample_valid) begin
                sum_r <= sum_r + pixel_in[23:16];
                sum_g <= sum_g + pixel_in[15:8];
                sum_b <= sum_b + pixel_in[7:0];
                if (sample_count != 22'h3fffff)
                    sample_count <= sample_count + 1'b1;
            end
        end
    end
endmodule
