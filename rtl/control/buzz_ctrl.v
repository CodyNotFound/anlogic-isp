// buzz_ctrl: 板载蜂鸣器按键反馈+开机音乐 (BUZZER=C12, 板上SW5为物理使能开关)
// 开机: 上电1s后播大疆式三音上行琶音 587/784/988Hz(各90ms)+尾音1175Hz(260ms), 音符间20ms
// 任意按键按下沿 → 2.7kHz方波 ~30ms 哔一声; I_strobe(如MNIST新识别结果) → 短双哔
// 被动/有源蜂鸣器通吃: 有源听到门控长鸣, 被动听到音调
module buzz_ctrl #(
    parameter integer CLK_HZ    = 75_000_000,
    parameter integer TONE_HZ   = 2700,
    parameter integer BEEP_MS   = 30          // 单哔时长
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
    function [22:0] note_len; input [2:0] idx;
        begin
            case (idx)
                3'd1, 3'd3: note_len = MS[22:0] * 23'd220;   // 两个主音各220ms
                3'd2, 3'd4: note_len = MS[22:0] * 23'd70;    // 音符间隔70ms
                default:     note_len = MS[22:0] * 23'd450;  // 尾音450ms
            endcase
        end
    endfunction
    reg [2:0]  boot_st;                        // 0=静默 1/3/5=音符 2/4=间隔 6+=完成
    reg [22:0] boot_cnt;                       // 复用计数: 静默/音符时长/间隔
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
                    if (boot_cnt >= MS[22:0] * 23'd1000) begin
                        boot_cnt <= 23'd0; boot_st <= 3'd1;
                    end
                    else boot_cnt <= boot_cnt + 23'd1;
                end
                3'd1, 3'd2, 3'd3, 3'd4, 3'd5: begin           // 音符/间隔时长
                    if (boot_cnt >= note_len(boot_st)) begin
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
    // ---- 按键按下沿检测(两级同步+边沿) ----
    reg [3:0] k_d1, k_d2;
    wire [3:0] k_press = k_d1 & ~k_d2;

    reg [22:0] tone_cnt;
    reg [22:0] len_cnt;
    reg        tone_ph;
    reg [2:0]  beep_seq;                      // 0=闲 1=第一声 2=间歇 3=第二声
    reg        strobe_d;
    reg        r_double;                      // 1=双哔(strobe来源) 0=单哔(按键)

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            k_d1 <= 4'd0; k_d2 <= 4'd0; strobe_d <= 1'b0; r_double <= 1'b0;
            tone_cnt <= 23'd0; len_cnt <= 23'd0; tone_ph <= 1'b0;
            beep_seq <= 3'd0;
        end
        else begin
            k_d1 <= I_keys; k_d2 <= k_d1; strobe_d <= I_strobe;

            // 音调方波(只在发声期驱动输出)
            if (tone_cnt >= HALF - 1) begin
                tone_cnt <= 23'd0;
                tone_ph  <= ~tone_ph;
            end
            else tone_cnt <= tone_cnt + 23'd1;

            // 状态推进
            case (beep_seq)
                3'd0: begin                                   // 空闲: 等触发
                    if (|k_press) begin beep_seq <= 3'd1; len_cnt <= LEN[22:0]; r_double <= 1'b0; end
                    else if (I_strobe && !strobe_d) begin beep_seq <= 3'd1; len_cnt <= LEN[22:0]; r_double <= 1'b1; end
                end
                3'd1: begin                                   // 第一声
                    if (len_cnt == 23'd1) begin
                        len_cnt  <= 23'd0;
                        beep_seq <= r_double ? 3'd2 : 3'd0;   // 按键单哔, strobe双哔
                    end
                    else len_cnt <= len_cnt - 23'd1;
                end
                3'd2: begin                                   // 40ms间歇→第二声
                    if (len_cnt >= MS[22:0] * 23'd40) begin
                        len_cnt  <= LEN[22:0];
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
    assign O_buzz = boot_active                     ? boot_ph
                  : (((beep_seq == 3'd1) || (beep_seq == 3'd3)) ? tone_ph : 1'b0);

endmodule
