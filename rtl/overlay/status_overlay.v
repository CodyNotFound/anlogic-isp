// Compact feature status overlay for board bring-up.
// The overlay is placed before the HDMI mixer so its pixel coordinates and
// timing are delayed together with the video stream.
module status_overlay #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire        line_end,
    input  wire        de,
    input  wire [3:0]  feature_enable,
    input  wire [11:0] latency_cycles,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    localparam integer PANEL_X = (IMG_WIDTH > 132) ? IMG_WIDTH - 120 : 0;
    localparam integer PANEL_Y = 12;
    localparam integer PANEL_W = 112;
    localparam integer PANEL_H = 80;
    localparam integer TEXT_X  = 6;
    localparam integer CELL_W  = 12;
    localparam integer CELL_H  = 16;

    reg [11:0] x;
    reg [11:0] y;
    wire in_panel = de && (x >= PANEL_X) && (x < PANEL_X + PANEL_W) &&
                    (y >= PANEL_Y) && (y < PANEL_Y + PANEL_H);
    wire [11:0] panel_x = x - PANEL_X;
    wire [11:0] panel_y = y - PANEL_Y;
    // Eight cells are required for the latency string: "LAT 005C".
    // All rows reserve the same state column so ON and OFF align vertically.
    wire text_area = in_panel && (panel_x >= TEXT_X) &&
                     (panel_x < TEXT_X + 8 * CELL_W);
    wire [2:0] row_index = (panel_y / CELL_H);
    wire [2:0] char_index = ((panel_x - TEXT_X) / CELL_W);
    wire [3:0] char_x = ((panel_x - TEXT_X) % CELL_W);
    wire [3:0] char_y = (panel_y % CELL_H);
    wire [2:0] glyph_row_index = char_y / 2;
    wire [2:0] glyph_col_index = char_x / 2;
    wire [7:0] status_char;
    wire [4:0] glyph_bits;
    wire glyph_on;
    // Avoid an out-of-range dynamic bit-select on the fifth (latency) row.
    wire row_enabled = (row_index == 0) ? feature_enable[0] :
                       (row_index == 1) ? feature_enable[1] :
                       (row_index == 2) ? feature_enable[2] :
                       (row_index == 3) ? feature_enable[3] : 1'b1;

    function [7:0] hex_char;
        input [3:0] value;
        begin
            if (value < 10) hex_char = 8'h30 + value;
            else hex_char = 8'h41 + value - 10;
        end
    endfunction

    function [7:0] get_char;
        input [2:0] row;
        input [2:0] index;
        input       enabled;
        input [11:0] latency;
        begin
            get_char = 8'h20;
            case (row)
                3'd0: begin
                    case (index)
                        3'd0: get_char = 8'h41; // A
                        3'd1: get_char = 8'h45; // E
                        3'd4: get_char = 8'h4f; // O
                        3'd5: get_char = enabled ? 8'h4e : 8'h46; // N/F
                        3'd6: get_char = enabled ? 8'h20 : 8'h46; // F
                        default: get_char = 8'h20;
                    endcase
                end
                3'd1: begin
                    case (index)
                        3'd0: get_char = 8'h41; // A
                        3'd1: get_char = 8'h57; // W
                        3'd2: get_char = 8'h42; // B
                        3'd4: get_char = 8'h4f; // O
                        3'd5: get_char = enabled ? 8'h4e : 8'h46; // N/F
                        3'd6: get_char = enabled ? 8'h20 : 8'h46; // F
                        default: get_char = 8'h20;
                    endcase
                end
                3'd2: begin
                    case (index)
                        3'd0: get_char = 8'h48; // H
                        3'd1: get_char = 8'h45; // E
                        3'd4: get_char = 8'h4f; // O
                        3'd5: get_char = enabled ? 8'h4e : 8'h46; // N/F
                        3'd6: get_char = enabled ? 8'h20 : 8'h46; // F
                        default: get_char = 8'h20;
                    endcase
                end
                3'd4: begin
                    case (index)
                        3'd0: get_char = 8'h4c; // L
                        3'd1: get_char = 8'h41; // A
                        3'd2: get_char = 8'h54; // T
                        3'd4: get_char = hex_char(latency[11:8]);
                        3'd5: get_char = hex_char(latency[7:4]);
                        3'd6: get_char = hex_char(latency[3:0]);
                        3'd7: get_char = 8'h43; // C: pixel-clock cycles
                        default: get_char = 8'h20;
                    endcase
                end
                default: begin
                    case (index)
                        3'd0: get_char = 8'h41; // A
                        3'd1: get_char = 8'h42; // B
                        3'd4: get_char = 8'h4f; // O
                        3'd5: get_char = enabled ? 8'h4e : 8'h46; // N/F
                        3'd6: get_char = enabled ? 8'h20 : 8'h46; // F
                        default: get_char = 8'h20;
                    endcase
                end
            endcase
        end
    endfunction

    // 5x7 glyphs, doubled in both axes for reliable visibility at 720p.
    function [4:0] glyph;
        input [7:0] ch;
        input [2:0] row;
        begin
            glyph = 5'b00000;
            case (ch)
                8'h41: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b11111;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b10001; default: glyph = 5'b00000;
                endcase
                8'h42: case (row)
                    0: glyph = 5'b11110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b11110;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b11110; default: glyph = 5'b00000;
                endcase
                8'h45: case (row)
                    0: glyph = 5'b11111; 1: glyph = 5'b10000;
                    2: glyph = 5'b10000; 3: glyph = 5'b11110;
                    4: glyph = 5'b10000; 5: glyph = 5'b10000;
                    6: glyph = 5'b11111; default: glyph = 5'b00000;
                endcase
                8'h46: case (row)
                    0: glyph = 5'b11111; 1: glyph = 5'b10000;
                    2: glyph = 5'b10000; 3: glyph = 5'b11110;
                    4: glyph = 5'b10000; 5: glyph = 5'b10000;
                    6: glyph = 5'b10000; default: glyph = 5'b00000;
                endcase
                8'h48: case (row)
                    0: glyph = 5'b10001; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b11111;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b10001; default: glyph = 5'b00000;
                endcase
                8'h4e: case (row)
                    0: glyph = 5'b10001; 1: glyph = 5'b11001;
                    2: glyph = 5'b10101; 3: glyph = 5'b10011;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b10001; default: glyph = 5'b00000;
                endcase
                8'h4f: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b10001;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h57: case (row)
                    0: glyph = 5'b10001; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b10101;
                    4: glyph = 5'b10101; 5: glyph = 5'b11011;
                    6: glyph = 5'b10001; default: glyph = 5'b00000;
                endcase
                8'h30: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10011; 3: glyph = 5'b10101;
                    4: glyph = 5'b11001; 5: glyph = 5'b10001;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h31: case (row)
                    0: glyph = 5'b00100; 1: glyph = 5'b01100;
                    2: glyph = 5'b00100; 3: glyph = 5'b00100;
                    4: glyph = 5'b00100; 5: glyph = 5'b00100;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h32: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b00001; 3: glyph = 5'b00010;
                    4: glyph = 5'b00100; 5: glyph = 5'b01000;
                    6: glyph = 5'b11111; default: glyph = 5'b00000;
                endcase
                8'h33: case (row)
                    0: glyph = 5'b11110; 1: glyph = 5'b00001;
                    2: glyph = 5'b00001; 3: glyph = 5'b01110;
                    4: glyph = 5'b00001; 5: glyph = 5'b00001;
                    6: glyph = 5'b11110; default: glyph = 5'b00000;
                endcase
                8'h34: case (row)
                    0: glyph = 5'b00010; 1: glyph = 5'b00110;
                    2: glyph = 5'b01010; 3: glyph = 5'b10010;
                    4: glyph = 5'b11111; 5: glyph = 5'b00010;
                    6: glyph = 5'b00010; default: glyph = 5'b00000;
                endcase
                8'h35: case (row)
                    0: glyph = 5'b11111; 1: glyph = 5'b10000;
                    2: glyph = 5'b10000; 3: glyph = 5'b11110;
                    4: glyph = 5'b00001; 5: glyph = 5'b00001;
                    6: glyph = 5'b11110; default: glyph = 5'b00000;
                endcase
                8'h36: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10000;
                    2: glyph = 5'b10000; 3: glyph = 5'b11110;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h37: case (row)
                    0: glyph = 5'b11111; 1: glyph = 5'b00001;
                    2: glyph = 5'b00010; 3: glyph = 5'b00100;
                    4: glyph = 5'b01000; 5: glyph = 5'b01000;
                    6: glyph = 5'b01000; default: glyph = 5'b00000;
                endcase
                8'h38: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b01110;
                    4: glyph = 5'b10001; 5: glyph = 5'b10001;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h39: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10001; 3: glyph = 5'b01111;
                    4: glyph = 5'b00001; 5: glyph = 5'b00001;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h43: case (row)
                    0: glyph = 5'b01110; 1: glyph = 5'b10001;
                    2: glyph = 5'b10000; 3: glyph = 5'b10000;
                    4: glyph = 5'b10000; 5: glyph = 5'b10001;
                    6: glyph = 5'b01110; default: glyph = 5'b00000;
                endcase
                8'h4c: case (row)
                    0: glyph = 5'b10000; 1: glyph = 5'b10000;
                    2: glyph = 5'b10000; 3: glyph = 5'b10000;
                    4: glyph = 5'b10000; 5: glyph = 5'b10000;
                    6: glyph = 5'b11111; default: glyph = 5'b00000;
                endcase
                8'h54: case (row)
                    0: glyph = 5'b11111; 1: glyph = 5'b00100;
                    2: glyph = 5'b00100; 3: glyph = 5'b00100;
                    4: glyph = 5'b00100; 5: glyph = 5'b00100;
                    6: glyph = 5'b00100; default: glyph = 5'b00000;
                endcase
                default: glyph = 5'b00000;
            endcase
        end
    endfunction

    assign status_char = get_char(row_index, char_index, row_enabled,
                                  latency_cycles);
    assign glyph_bits = glyph(status_char, glyph_row_index);
    assign glyph_on = text_area && (glyph_col_index < 5) &&
                      glyph_bits[4 - glyph_col_index];

    reg [23:0] pixel_next;

    // Register the completed OSD pixel. The previous implementation left the
    // glyph/decode network combinational all the way into hdmi_mixer, making
    // the Sobel-to-HDMI path unnecessarily long. vision_pipeline delays the
    // matching video qualifiers by one pixel clock.
    always @* begin
        if (!de) pixel_next = 24'd0;
        else if (in_panel) begin
            if (glyph_on) begin
                if ((row_index < 4) && (char_index >= 3) && row_enabled)
                    pixel_next = 24'h20ff60;
                else if ((row_index < 4) && (char_index >= 3) && !row_enabled)
                    pixel_next = 24'hff5040;
                else
                    pixel_next = 24'hffffff;
            end else pixel_next = 24'h080808;
        end else pixel_next = pixel_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out <= 24'd0;
            x <= 0;
            y <= 0;
        end else if (frame_start) begin
            pixel_out <= 24'd0;
            x <= 0;
            y <= 0;
        end else begin
            pixel_out <= pixel_next;
            if (de) begin
                if (line_end) begin
                    x <= 0;
                    if (y == IMG_HEIGHT-1) y <= 0;
                    else y <= y + 1'b1;
                end else if (x == IMG_WIDTH-1) x <= 0;
                else x <= x + 1'b1;
            end
        end
    end
endmodule
