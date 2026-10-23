// buzz_ctrl: 板载蜂鸣器按键反馈+开机音乐 (BUZZER=C12, 板上SW5为物理使能开关)
// 开机: 上电1s后播大疆式三音上行琶音 587/784/988Hz(各90ms)+尾音1175Hz(260ms), 音符间20ms
// 任意按键按下沿 → 2.7kHz方波 ~30ms 哔一声; I_strobe(如MNIST新识别结果) → 短双哔
// 被动/有源蜂鸣器通吃: 有源听到门控长鸣, 被动听到音调
module buzz_ctrl #(
    parameter integer CLK_HZ    = 75_000_000,
    parameter integer TONE_HZ   = 2700,
    parameter integer BEEP_MS   = 30,         // 单哔时长
    parameter integer DEBOUNCE_MS = 20       // 连续稳定后才确认按下/松开
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_keys,                 // 按键(高=按下, 内部做按下沿)
    input  wire       I_strobe,               // 事件脉冲(识别新结果等): 双哔
    output wire       O_buzz
);
    localparam integer HALF = CLK_HZ / (2 * TONE_HZ);   // 13888 tick
    localparam integer LEN  = CLK_HZ / 1000 * BEEP_MS;  // 2_250_000
    localparam integer MS   = CLK_HZ / 1000;            // 75_000

    // ================= 开机旋律状态机 =================
    // 状态: 0=上电静默1s 1=D5(587Hz,220ms) 2=间隔70ms 3=A5(880Hz,220ms)
    //       4=间隔70ms 5=D6(1175Hz,450ms)尾音 6+=完成
    function [22:0] note_half; input [2:0] idx;
        begin
            case (idx)
                3'd1: note_half = CLK_HZ / (2 * 587);
                3'd3: note_half = CLK_HZ / (2 * 880);
                default: note_half = CLK_HZ / (2 * 1175);
            endcase
        end
    endfunction
    function [31:0] note_len; input [2:0] idx;
        begin
            case (idx)
                3'd1, 3'd3: note_len = MS * 220;
                3'd2, 3'd4: note_len = MS * 70;
                default:     note_len = MS * 450;
            endcase
        end
    endfunction
    reg [2:0]  boot_st;                        // 0=静默 1/3/5=音符 2/4=间隔 6+=完成
    reg [31:0] boot_cnt;                       // 75MHz的1秒需要27位，不能用23位
    reg [22:0] boot_tone_cnt;
    reg        boot_ph;
    wire       boot_active = (boot_st == 3'd1) || (boot_st == 3'd3) || (boot_st == 3'd5);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            boot_st <= 3'd0; boot_cnt <= 23'd0; boot_tone_cnt <= 23'd0; boot_ph <= 1'b0;
        end
        else begin
            // 方波发生(仅音符期推进)
            if (boot_active) begin
                if (boot_tone_cnt >= note_half(boot_st) - 23'd1) begin
                    boot_tone_cnt <= 23'd0;
                    boot_ph <= ~boot_ph;
                end
                else boot_tone_cnt <= boot_tone_cnt + 23'd1;
            end
            else begin boot_tone_cnt <= 23'd0; boot_ph <= 1'b0; end

            case (boot_st)
                3'd0: begin                                   // 上电静默1s
                    if (boot_cnt >= MS * 1000 - 1) begin
                        boot_cnt <= 23'd0; boot_st <= 3'd1;
                    end
                    else boot_cnt <= boot_cnt + 23'd1;
                end
                3'd1, 3'd2, 3'd3, 3'd4, 3'd5: begin           // 音符/间隔时长
                    if (boot_cnt >= note_len(boot_st) - 1) begin
                        boot_cnt <= 23'd0;
                        boot_st <= boot_st + 3'd1;            // 5→6=完成
                    end
                    else boot_cnt <= boot_cnt + 23'd1;
                end
                default: ;                                    // 6,7: 旋律完成, 终态静止
            endcase
        end
    end

    // ================= 按键哔 =================
    // 同步不等于防抖。每路独立确认按下和松开，释放抖动不能重新武装。
    localparam integer DB_CYCLES = (MS * DEBOUNCE_MS < 1) ? 1 : MS * DEBOUNCE_MS;
    localparam integer DB_W = (DB_CYCLES < 2) ? 1 : $clog2(DB_CYCLES);
    reg [3:0] k_meta, k_sync, k_stable, k_previous;
    wire [3:0] k_press = k_stable & ~k_previous;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            k_meta <= 0; k_sync <= 0; k_previous <= 0;
        end else begin
            k_meta <= I_keys; k_sync <= k_meta; k_previous <= k_stable;
        end
    end
    genvar key_index;
    generate for (key_index=0; key_index<4; key_index=key_index+1) begin: g_debounce
        reg [DB_W-1:0] count;
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                count <= 0; k_stable[key_index] <= 0;
            end else if (k_sync[key_index] == k_stable[key_index]) count <= 0;
            else if (count == DB_CYCLES-1) begin
                count <= 0; k_stable[key_index] <= k_sync[key_index];
            end else count <= count + 1'b1;
        end
    end endgenerate

    reg [22:0] tone_cnt;
    reg [31:0] len_cnt;
    reg        tone_ph;
    reg [2:0]  beep_seq;                      // 0=闲 1=第一声 2=间歇 3=第二声
    reg        strobe_d;
    reg        r_double;                      // 1=双哔(strobe来源) 0=单哔(按键)

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            strobe_d <= 1'b0; r_double <= 1'b0;
            tone_cnt <= 23'd0; len_cnt <= 23'd0; tone_ph <= 1'b0;
            beep_seq <= 3'd0;
        end
        else begin
            strobe_d <= I_strobe;

            // 音调方波(只在发声期驱动输出)
            if (tone_cnt >= HALF - 1) begin
                tone_cnt <= 23'd0;
                tone_ph  <= ~tone_ph;
            end
            else tone_cnt <= tone_cnt + 23'd1;

            // 状态推进
            case (beep_seq)
                3'd0: begin                                   // 空闲: 等触发
                    if (|k_press) begin beep_seq <= 3'd1; len_cnt <= LEN; r_double <= 1'b0; end
                    else if (I_strobe && !strobe_d) begin beep_seq <= 3'd1; len_cnt <= LEN; r_double <= 1'b1; end
                end
                3'd1: begin                                   // 第一声
                    if (len_cnt == 23'd1) begin
                        len_cnt  <= 23'd0;
                        beep_seq <= r_double ? 3'd2 : 3'd0;   // 按键单哔, strobe双哔
                    end
                    else len_cnt <= len_cnt - 23'd1;
                end
                3'd2: begin                                   // 40ms间歇→第二声
                    if (len_cnt >= MS * 40 - 1) begin
                        len_cnt  <= LEN;
                        beep_seq <= 3'd3;
                    end
                    else len_cnt <= len_cnt + 23'd1;
                end
                default: begin                                // 第二声→回空闲
                    if (len_cnt == 23'd1) begin
                        len_cnt  <= 23'd0;
                        beep_seq <= 3'd0;
                    end
                    else len_cnt <= len_cnt - 23'd1;
                end
            endcase
        end
    end

    // 输出仲裁: 开机旋律期间旋律优先, 之后按键哔
    // 板上PNP驱动低有效，空闲必须输出1，不能持续给蜂鸣器通电。
    assign O_buzz = boot_active                     ? ~boot_ph
                  : (((beep_seq == 3'd1) || (beep_seq == 3'd3)) ? ~tone_ph : 1'b1);

endmodule
