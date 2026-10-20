// K1-K4 mode controller. Buttons are active-low.
// K1/K2: modes 0..14. K4: reacquire/pick in TRACK/REGION; otherwise ISP back.
// 演示模式(ISP分步): K3 进入(step=0)并前进步进(5到顶再按回0), K4 后退(到0不动),
//                    K1/K2 退出演示回到原模式(模式值不变)。
// isp 分步语义由上层 isp_sel={demo_active,demo_step} 解码, 正常模式恒走全链。
module algorithm_mode_ctrl #(
    parameter integer DEBOUNCE_CYCLES = 750000,
    parameter [2:0] DEMO_STEP_LAST = 3'd5,
    parameter integer ENABLE_ISP_DEMO = 1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] buttons_n,     // [0]=K1 [1]=K2 [2]=K3 [3]=K4, 低有效
    output reg  [3:0] mode,
    output reg        demo_active,
    output reg  [2:0] demo_step,
    output reg        action_pulse
);
    localparam integer CW = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam [3:0] MODE_LAST = 4'd14;

    reg [3:0] sync1, sync2, stable, stable_d;
    reg [CW-1:0] count0, count1, count2, count3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 4'b1111; sync2 <= 4'b1111;
            stable <= 4'b1111; stable_d <= 4'b1111;
            count0 <= {CW{1'b0}}; count1 <= {CW{1'b0}};
            count2 <= {CW{1'b0}}; count3 <= {CW{1'b0}};
            mode <= 4'd0;
            demo_active <= 1'b0;
            demo_step <= 3'd0;
            action_pulse <= 1'b0;
        end else begin
            action_pulse <= 1'b0;
            sync1 <= buttons_n;
            sync2 <= sync1;
            stable_d <= stable;
            if (sync2[0] != stable[0]) begin
                if (count0 == DEBOUNCE_CYCLES-1) begin stable[0] <= sync2[0]; count0 <= 0; end
                else count0 <= count0 + 1'b1;
            end else count0 <= 0;
            if (sync2[1] != stable[1]) begin
                if (count1 == DEBOUNCE_CYCLES-1) begin stable[1] <= sync2[1]; count1 <= 0; end
                else count1 <= count1 + 1'b1;
            end else count1 <= 0;
            if (sync2[2] != stable[2]) begin
                if (count2 == DEBOUNCE_CYCLES-1) begin stable[2] <= sync2[2]; count2 <= 0; end
                else count2 <= count2 + 1'b1;
            end else count2 <= 0;
            if (sync2[3] != stable[3]) begin
                if (count3 == DEBOUNCE_CYCLES-1) begin stable[3] <= sync2[3]; count3 <= 0; end
                else count3 <= count3 + 1'b1;
            end else count3 <= 0;

            // K1/K2: 演示模式下仅退出; 正常模式下加减模式
            if (stable_d[0] && !stable[0]) begin
                if (demo_active) demo_active <= 1'b0;
                else if (mode == MODE_LAST) mode <= 4'd0;
                else if(mode==12)mode<=14; // retired local histogram mode 13
                else mode <= mode + 1'b1;
            end
            if (stable_d[1] && !stable[1]) begin
                if (demo_active) demo_active <= 1'b0;
                else if (mode == 4'd0) mode <= MODE_LAST;
                else if(mode==14)mode<=12;
                else mode <= mode - 1'b1;
            end
            // K3: 进入演示/下一步(到顶循环回0)
            if (ENABLE_ISP_DEMO && stable_d[2] && !stable[2]) begin
                if (!demo_active) begin demo_active <= 1'b1; demo_step <= 3'd0; end
                else if (demo_step == DEMO_STEP_LAST) demo_step <= 3'd0;
                else demo_step <= demo_step + 1'b1;
            end
            // K4: 上一步(到0不动), 非演示状态无动作
            if (stable_d[3] && !stable[3]) begin
                if (demo_active && demo_step != 3'd0) demo_step <= demo_step - 1'b1;
                else if(!demo_active && (mode==12 || mode==14))action_pulse<=1'b1;
            end
        end
    end
endmodule
