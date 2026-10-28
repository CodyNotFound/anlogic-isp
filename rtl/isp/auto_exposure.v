// Digital fine exposure control and frame-luma statistics in the HDMI pixel
// domain.  The sensor-domain controller consumes the stable frame statistics
// to adjust SC500 exposure time and analogue gain; this block is deliberately
// kept as a small digital trim stage.
module auto_exposure #(
    parameter integer IMG_WIDTH   = 1280,
    parameter integer IMG_HEIGHT  = 720,
    parameter integer TARGET_LOW  = 96,
    parameter integer TARGET_HIGH = 128,
    parameter integer GAIN_MIN    = 224,
    parameter integer GAIN_MAX    = 288,
    parameter integer GAIN_STEP   = 4
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       frame_start,
    input  wire       de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out,
    output reg  [7:0]  frame_stat_y,
    output reg         frame_stat_toggle
);
    // 1280x720x255 is larger than 32 bits. Keep the frame accumulator wide
    // enough that the average remains valid for every camera frame.
    reg [39:0] luma_sum;
    reg [21:0] pixel_count;
    reg [8:0]  gain_q8;
    reg frame_stat_pending;

    // BT.601 full-range Y=(77R+150G+29B)>>8, using shift/add terms.
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
    // 1280x720 has 921600 active pixels.  146/2^27 is its reciprocal to
    // better than 0.2%, and 146=128+16+2 keeps the frame-average path as
    // shift/add logic instead of inferring a large divider.
    wire [47:0] frame_avg_product =
                         ({8'd0,luma_sum} << 7) +
                         ({8'd0,luma_sum} << 4) +
                         ({8'd0,luma_sum} << 1);
    wire [8:0] frame_avg_calc = frame_avg_product[35:27];

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
            luma_sum <= 40'd0;
            pixel_count <= 22'd0;
            gain_q8  <= 9'd256;
            frame_stat_y <= 8'd0;
            frame_stat_toggle <= 1'b0;
            frame_stat_pending <= 1'b0;
        end else begin
            frame_stat_pending <= 1'b0;
            if(frame_stat_pending) frame_stat_toggle <= ~frame_stat_toggle;
            // Register the pixel result to isolate the frame-control gain
            // and channel multipliers from the next ISP stage.
            if (!de) pixel_out <= 24'd0;
            else if (!enable) pixel_out <= pixel_in;
            else pixel_out <= {scale_channel(pixel_in[23:16], gain_q8),
                               scale_channel(pixel_in[15:8],  gain_q8),
                               scale_channel(pixel_in[7:0],   gain_q8)};

            if (frame_start) begin
                if (pixel_count != 0) begin
                    // The result is exported on a toggle protocol and remains
                    // stable until the next frame, making the CDC safe.
                    frame_stat_y <= (frame_avg_calc > 9'd255) ?
                                    8'hff : frame_avg_calc[7:0];
                    frame_stat_pending <= 1'b1;
                end
                if (enable && (pixel_count != 0)) begin
                    if (luma_sum < (pixel_count * TARGET_LOW)) begin
                        if (gain_q8 < GAIN_MAX - GAIN_STEP) gain_q8 <= gain_q8 + GAIN_STEP;
                        else gain_q8 <= GAIN_MAX;
                    end else if (luma_sum > (pixel_count * TARGET_HIGH)) begin
                        if (gain_q8 > GAIN_MIN + GAIN_STEP) gain_q8 <= gain_q8 - GAIN_STEP;
                        else gain_q8 <= GAIN_MIN;
                    end
                end else if (!enable) begin
                    gain_q8 <= 9'd256;
                end
                luma_sum <= de ? {{32{1'b0}},luma} : 40'd0;
                pixel_count <= de ? 22'd1 : 22'd0;
            end else if (de) begin
                luma_sum <= luma_sum + luma;
                if (pixel_count != 22'h3fffff) pixel_count <= pixel_count + 1'b1;
            end
        end
    end
endmodule
