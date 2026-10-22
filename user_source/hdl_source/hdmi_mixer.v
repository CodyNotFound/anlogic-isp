module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0,
    parameter integer ENABLE_OSD = 1,
    parameter integer ENABLE_SWITCH_OSD = 1
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,
    input wire        I_cam_frame_tog,   //摄像头帧脉冲toggle电平（csi时钟域）
    input wire[7:0]   I_latency_frames,  //兼容接口；延迟显示已移除
    input wire[3:0]   I_mode,            //0=色彩还原,1..10=效果,11=FACE人脸定位
    input wire[3:0]   I_isp_demo,        //{active, step[2:0]} ISP分步演示状态, 底栏切"ISP:N 名称"
    input wire[3:0]   I_feature_enable,  //AE/AWB/HE/AB, HDMI像素域

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data,
    output reg        O_hdmi_sof
);

    reg        S_video_user_1d;
    reg        S_video_user_2d;
    reg        S_video_user_3d;
    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;

    reg        S_osd_hit;
    wire [7:0]  S_logo_idx;    // logo索引ERAM输出(级B有效, 0=透明)
    wire [23:0] S_logo_rgb;    // logo调色板ERAM输出(级C有效, 随r2_hit直混)
    reg [31:0] S_frame_cnt;
    reg [3:0]  S_cnt_d0;
    reg [3:0]  S_cnt_d1;
    reg [3:0]  S_cnt_d2;
    reg [3:0]  S_cnt_d3;
    reg [3:0]  S_cnt_d4;
    reg [3:0]  S_cnt_d5;
    wire [15:0] S_pf_row_bits;

    // FPS测量
    reg        S_cam_tog_1d;
    reg        S_cam_tog_2d;
    reg [26:0] S_fps_win_cnt;
    reg [6:0]  S_cam_frame_cnt;
    reg [6:0]  S_fps;
    reg [3:0]  S_fps_d1;
    reg [3:0]  S_fps_d0;

    reg [3:0]  S_mode_1d;
    reg [3:0]  S_mode_2d;
    reg [3:0]  S_isp_demo_1d;
    reg [3:0]  S_isp_demo_2d;
    reg [3:0]  S_ban_d1;
    reg [3:0]  S_ban_d0;
    reg [3:0]  S_feature_1d;
    reg [3:0]  S_feature_2d;


    // ---- 渲染三级流水: 把"地址/字符选择->ROM->命中颜色->优先混合"拆到三个周期 ----
    // 级A(位置S_x_1d/S_y_1d): 区域判定 + 字符/行列选择 + Logo地址(乘加离最终输出两级)
    reg [2:0]  r1_region;    // 0=无前景 1=logo 2=CNT行 3=FPS行 4=保留 5=模式栏 6=SW状态
    reg [3:0]  r1_sw_idx;
    reg [14:0] r1_addr;      // logo ROM地址
    reg [7:0]  r1_char;      // 字库字符码
    reg [3:0]  r1_row;       // 字库行
    reg [3:0]  r1_col;       // 字库列(已完成放大映射)
    reg        r1_blend;     // HUD/模式栏半透明背景区域
    // 级B: ROM组合读出 + 命中/颜色
    reg        r2_hit;
    reg        r2_is_logo;   // logo像素标记: 颜色由调色板ERAM第2拍在级C直混
    reg [23:0] r2_color;
    reg        r2_blend;
    // 级C前的图像/时序第三拍
    reg        S_video_de_3d;
    reg        S_video_vsync_3d;
    reg        S_video_hsync_3d;
    reg [23:0] S_video_data_3d;
    // 级A组合中间量
    reg [2:0]  v_region;
    reg [14:0] v_addr;
    reg [7:0]  v_char;
    reg [3:0]  v_row;
    reg [3:0]  v_col;
    reg [11:0] v_lx;
    reg [11:0] v_ly;
    reg [3:0]  v_idx;

    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;
    // logo实际墨迹裁剪窗(146x94@(7,34)), 与logo_rom_bram的mif布局一致;
    // 160x160窗内裁剪窗之外无墨迹, 不读BRAM
    localparam LOGO_EX = 12'd24;
    localparam LOGO_EY = 12'd24;   // 侧栏卡片: 图形(146x94)与状态行统一24px边距
    localparam LOGO_EW = 12'd146;
    localparam LOGO_EH = 12'd94;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    // 文字排版: 原生16px高, 中文16px宽/ASCII 8px宽, 无缩放(像素字非整数倍拉伸粗细不匀)
    localparam DYN_OSD_X         = 12'd24;
    localparam DYN_OSD_Y         = 12'd134;  // logo下方: CNT@134 FPS@154
    localparam DYN_OSD_W         = 12'd120;  // 安路(32)+gap(8)+CNT:(32)+6数字(48)
    localparam DYN_OSD_H         = 12'd16;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;
    localparam ST_OSD_X      = 12'd24;
    localparam ST_OSD_Y      = 12'd154;  // 行距20: CNT@134 FPS@154
    localparam ST_OSD_W      = 12'd48;   // FPS:xx 6字符x8
    localparam ST_OSD_H      = 12'd16;
    localparam COLOR_FPS_TEXT = 24'h00ff6a;
`ifdef SIM_SHORT_FPS
    localparam ONE_SEC_TICKS = 27'd6000 - 27'd1;   // 仿真用: 缩短FPS统计窗口
`else
    localparam ONE_SEC_TICKS = 27'd74999999;  // 75MHz像素钟 x 1s
`endif

    // 底部模式栏 OSD: 半透明暗底 + 模式编号/名称
    localparam BAN_X        = 12'd24;
    localparam BAN_Y        = 12'd686;
    localparam BAN_H        = 12'd28;
    localparam BAN_TEXT_DY  = 12'd6;      // 28高栏内16高文字居中
    localparam BAN_CELL_W   = 12'd8;      // ASCII原生半宽单元
    localparam BAN_TXT_W    = 12'd128;    // 模式:dd_名称 段宽(名称4字)
    // [二轮] MNIST识别框/标签几何与配色已随 full-modes 分支撤下
    localparam COLOR_BAN_TEXT = 24'hffffff;
    localparam COLOR_SW_ON     = 24'h20ff50;
    localparam COLOR_SW_OFF    = 24'h707070;
    localparam SW_OSD_X        = 12'd1152;
    localparam SW_OSD_W        = 12'd96;
    localparam HUD_X        = 12'd16;
    localparam HUD_Y        = 12'd16;
    localparam HUD_W        = 12'd162;  // 侧栏卡片: 8px内边距包住logo(24..170)与状态行(24..144)
    localparam HUD_H        = 12'd158;  // 16..174 覆盖logo(24..118)+CNT/FPS两行状态(134..170)

    assign O_video_rd_en = I_video_de;

    // logo/字库双BRAM: 地址取级A组合信号(v_addr/v_char/v_row), ERAM在r1_*打拍
    // 的同一时钟沿采样, 输出在级B周期有效 —— 与旧组合ROM(输入r1_*)等效零改拍
    logo_rom_bram u_logo_rom_bram(
        .I_clk  ( I_clk        ),
        .I_addr ( v_addr[13:0] ),
        .O_idx  ( S_logo_idx   ),
        .O_rgb  ( S_logo_rgb   )
    );

    osd_font_bram u_osd_font_bram(
        .I_clk      ( I_clk         ),
        .I_char     ( v_char        ),
        .I_row      ( v_row         ),
        .O_row_bits ( S_pf_row_bits )
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end
        else if(I_video_user) begin
            S_frame_cnt <= S_frame_cnt + 32'd1;
            if(S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if(S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if(S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if(S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if(S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if(S_cnt_d5 == 4'd9)
                                    S_cnt_d5 <= 4'd0;
                                else
                                    S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end
                            else
                                S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end
                        else
                            S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end
                    else
                        S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end
                else
                    S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end
            else
                S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    // 摄像头帧toggle电平两拍同步，边沿检测出帧脉冲
    wire S_cam_frame_pulse = S_cam_tog_1d ^ S_cam_tog_2d;
    function [3:0] F_tens_99;
        input [7:0] value;
        begin
            if(value>=8'd90)F_tens_99=4'd9;
            else if(value>=8'd80)F_tens_99=4'd8;
            else if(value>=8'd70)F_tens_99=4'd7;
            else if(value>=8'd60)F_tens_99=4'd6;
            else if(value>=8'd50)F_tens_99=4'd5;
            else if(value>=8'd40)F_tens_99=4'd4;
            else if(value>=8'd30)F_tens_99=4'd3;
            else if(value>=8'd20)F_tens_99=4'd2;
            else if(value>=8'd10)F_tens_99=4'd1;
            else F_tens_99=4'd0;
        end
    endfunction

    wire [7:0] S_fps_final = {1'b0, S_cam_frame_cnt} + (S_cam_frame_pulse ? 8'd1 : 8'd0);
    wire [7:0] S_fps_cap   = (S_fps_final > 8'd99) ? 8'd99 : S_fps_final;
    wire [3:0] S_fps_tens = F_tens_99(S_fps_cap);
    wire [7:0] S_fps_sub_tens = S_fps_cap-((({4'd0,S_fps_tens})<<3)+({4'd0,S_fps_tens}<<1));
    wire [3:0] S_fps_ones = S_fps_sub_tens[3:0];
    // 1秒窗口统计摄像头帧数 -> FPS
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_cam_tog_1d    <= 1'b0;
            S_cam_tog_2d    <= 1'b0;
            S_fps_win_cnt   <= 27'd0;
            S_cam_frame_cnt <= 7'd0;
            S_fps           <= 7'd0;
            S_fps_d1        <= 4'd0;
            S_fps_d0        <= 4'd0;
        end
        else begin
            S_cam_tog_1d <= I_cam_frame_tog;
            S_cam_tog_2d <= S_cam_tog_1d;
            if(S_cam_frame_pulse)
                S_cam_frame_cnt <= S_cam_frame_cnt + 7'd1;
            if(S_fps_win_cnt == ONE_SEC_TICKS) begin
                S_fps           <= S_fps_cap[6:0];
                S_fps_d1        <= S_fps_tens;
                S_fps_d0        <= S_fps_ones;
                S_fps_win_cnt   <= 27'd0;
                S_cam_frame_cnt <= S_cam_frame_pulse ? 7'd1 : 7'd0;
            end
            else
                S_fps_win_cnt <= S_fps_win_cnt + 27'd1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
        end
        else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
        end
    end

    // 模式号两拍同步到像素时钟域, 并拆出十/个位
    always @(posedge I_clk) begin
        S_mode_1d <= I_mode;
        S_mode_2d <= S_mode_1d;
        S_isp_demo_1d <= I_isp_demo;
        S_isp_demo_2d <= S_isp_demo_1d;
        S_feature_1d <= I_feature_enable;
        S_feature_2d <= S_feature_1d;
        S_ban_d1  <= (S_mode_2d > 4'd9) ? 4'd1 : 4'd0;
        S_ban_d0  <= (S_mode_2d > 4'd9) ? (S_mode_2d - 4'd10) : S_mode_2d;
    end

    // 模式名称字符表, idx 超出名称长度返回 0(空白)
    // 模式名(中文两字, 0x80系字库码; 超出返回空白)
    function [7:0] F_mode_name_char;
        input [3:0] I_m;
        input [3:0] I_idx;
        begin
            case (I_m)
                4'd0: case (I_idx) 4'd0: F_mode_name_char=8'h9c; 4'd1: F_mode_name_char=8'hcc; 4'd2: F_mode_name_char=8'hcd; 4'd3: F_mode_name_char=8'h97; default: F_mode_name_char=8'h00; endcase // 色彩还原(ISP链直通)
                4'd1: case (I_idx) 4'd0: F_mode_name_char=8'h99; 4'd1: F_mode_name_char=8'h9a; default: F_mode_name_char=8'h00; endcase // 灰度
                4'd2: case (I_idx) 4'd0: F_mode_name_char=8'h9b; 4'd1: F_mode_name_char=8'h9c; default: F_mode_name_char=8'h00; endcase // 反色
                4'd3: case (I_idx) 4'd0: F_mode_name_char=8'h9d; 4'd1: F_mode_name_char=8'h9e; default: F_mode_name_char=8'h00; endcase // 二值
                4'd4: case (I_idx) 4'd0: F_mode_name_char=8'h9f; 4'd1: F_mode_name_char=8'ha0; default: F_mode_name_char=8'h00; endcase // 增亮
                4'd5: case (I_idx) 4'd0: F_mode_name_char=8'ha1; 4'd1: F_mode_name_char=8'ha2; default: F_mode_name_char=8'h00; endcase // 锐化
                4'd6: case (I_idx) 4'd0: F_mode_name_char=8'h82; 4'd1: F_mode_name_char=8'ha3; default: F_mode_name_char=8'h00; endcase // 模糊
                4'd7: case (I_idx) 4'd0: F_mode_name_char=8'ha4; 4'd1: F_mode_name_char=8'ha5; default: F_mode_name_char=8'h00; endcase // 边缘
                4'd8: case (I_idx) 4'd0: F_mode_name_char=8'ha6; 4'd1: F_mode_name_char=8'ha7; default: F_mode_name_char=8'h00; endcase // 浮雕
                4'd9: case (I_idx) 4'd0: F_mode_name_char="T"; 4'd1: F_mode_name_char="O"; 4'd2: F_mode_name_char="O"; 4'd3: F_mode_name_char="N"; default: F_mode_name_char=8'h00; endcase // Cel cartoon
                4'd10: case (I_idx) 4'd0: F_mode_name_char=8'haa; 4'd1: F_mode_name_char=8'h9c; default: F_mode_name_char=8'h00; endcase // 换色
                4'd11: case (I_idx) 4'd0: F_mode_name_char="F"; 4'd1: F_mode_name_char="A"; 4'd2: F_mode_name_char="C"; 4'd3: F_mode_name_char="E"; default: F_mode_name_char=8'h00; endcase // 人脸
                4'd12: case (I_idx) 4'd0: F_mode_name_char=8'h8c; 4'd1: F_mode_name_char=8'h8d; default: F_mode_name_char=8'h00; endcase // 跟踪
                4'd13: case (I_idx) 4'd0: F_mode_name_char=8'h88; 4'd1: F_mode_name_char=8'h89; default: F_mode_name_char=8'h00; endcase // 均衡
                4'd14: case (I_idx) 4'd0: F_mode_name_char=8'h9c; 4'd1: F_mode_name_char=8'hce; default: F_mode_name_char=8'h00; endcase // 色区
                default: case (I_idx) 4'd0: F_mode_name_char=8'h00; 4'd1: F_mode_name_char=8'h00; default: F_mode_name_char=8'h00; endcase // 空白
            endcase
        end
    endfunction

    // [2026-10-14 还原] 车牌识别串(cls2char+7字符锁存)已随plate-demo分支撤下

    // ISP分步演示名称: 名称区64px按8px槽取字符(0=空白); CJK字符占两槽(左右半字)
    // 步0原图 1黑电平 2白平衡 3镜头阴影 4色调 5色彩还原(=模式00)
    function [7:0] F_isp_name_char;
        input [2:0] I_step;
        input [2:0] I_slot;
        begin
            case (I_step)
                3'd0: case (I_slot) 3'd0,3'd1: F_isp_name_char=8'h97; 3'd2,3'd3: F_isp_name_char=8'h98; default: F_isp_name_char=8'h00; endcase // 原图
                3'd1: case (I_slot) 3'd0:F_isp_name_char=8'h42; 3'd1:F_isp_name_char=8'h4c; 3'd2:F_isp_name_char=8'h43; default:F_isp_name_char=8'h00; endcase // BLC
                3'd2: case (I_slot) 3'd0:F_isp_name_char=8'h41; 3'd1:F_isp_name_char=8'h57; 3'd2:F_isp_name_char=8'h42; default:F_isp_name_char=8'h00; endcase // AWB
                3'd3: case (I_slot) 3'd0:F_isp_name_char=8'h4c; 3'd1:F_isp_name_char=8'h53; 3'd2:F_isp_name_char=8'h43; default:F_isp_name_char=8'h00; endcase // LSC
                3'd4: case (I_slot) 3'd0:F_isp_name_char=8'h47; 3'd1:F_isp_name_char=8'h41; 3'd2:F_isp_name_char=8'h4d; 3'd3:F_isp_name_char=8'h4d; 3'd4:F_isp_name_char=8'h41; default:F_isp_name_char=8'h00; endcase // GAMMA
                default: case (I_slot) 3'd0,3'd1: F_isp_name_char=8'h9c; 3'd2,3'd3: F_isp_name_char=8'hcc; 3'd4,3'd5: F_isp_name_char=8'hcd; 3'd6,3'd7: F_isp_name_char=8'h97; default: F_isp_name_char=8'h00; endcase // 色彩还原
            endcase
        end
    endfunction
    // 1=该步名称为CJK(列号=槽内16px位置v_lx[3:0]), 0=ASCII(列号=8px位置)
    function F_isp_name_cjk;
        input [2:0] I_step;
        begin F_isp_name_cjk = (I_step == 3'd0) || (I_step >= 3'd5); end
    endfunction

    // ================= 级A: 区域判定与字符选择 (像素位置在 S_x_1d/S_y_1d) =================
    // 纯位置判定, 各区域显式互斥, 不存在旧实现的 S_osd_hit 反馈(组合环)
    always @(*) begin
        v_region = 3'd0; v_addr = 15'd0; v_char = 8'd0;
        v_row = 4'd0; v_col = 4'd0;
        v_lx = 12'd0; v_ly = 12'd0; v_idx = 4'd0;

        if (S_video_de_1d) begin
            if ((S_x_1d >= LOGO_X + LOGO_EX) && (S_x_1d < (LOGO_X + LOGO_EX + LOGO_EW)) &&
                (S_y_1d >= LOGO_Y + LOGO_EY) && (S_y_1d < (LOGO_Y + LOGO_EY + LOGO_EH))) begin
                v_region = 3'd1;
                v_addr   = ({{3{1'b0}},(S_y_1d-LOGO_Y-LOGO_EY)}<<7)+({{3{1'b0}},(S_y_1d-LOGO_Y-LOGO_EY)}<<4)+({{3{1'b0}},(S_y_1d-LOGO_Y-LOGO_EY)}<<1)+{{3{1'b0}},(S_x_1d-LOGO_X-LOGO_EX)};
            end
            else if ((S_x_1d >= DYN_OSD_X) && (S_x_1d < (DYN_OSD_X + DYN_OSD_W)) &&
                     (S_y_1d >= DYN_OSD_Y) && (S_y_1d < (DYN_OSD_Y + DYN_OSD_H))) begin
                // 安路 CNT:xxxxxx (原生16px: 中文16宽/ASCII 8宽)
                v_region = 3'd2;
                v_lx = S_x_1d - DYN_OSD_X;
                v_ly = S_y_1d - DYN_OSD_Y;
                v_row = v_ly[3:0];
                if (v_lx < 12'd16) begin
                    v_char = CHAR_AN;  v_col = v_lx[3:0];
                end
                else if (v_lx < 12'd32) begin
                    v_char = CHAR_LU;  v_col = (v_lx - 12'd16);
                end
                else if (v_lx < 12'd40) begin
                    v_region = 3'd0;                            // 中西文间8px间隙
                end
                else if (v_lx < 12'd72) begin
                    case ((v_lx - 12'd40) >> 3)
                        3'd0: v_char = CHAR_C;
                        3'd1: v_char = CHAR_N;
                        3'd2: v_char = CHAR_T;
                        default: v_char = CHAR_COLON;
                    endcase
                    v_col = {1'b0, v_lx[2:0]};                 // ASCII字模在16bit字左半
                end
                else begin
                    v_idx = (v_lx - 12'd72) >> 3;
                    v_col = {1'b0, v_lx[2:0]};
                    case (v_idx)
                        4'd0: v_char = {4'h3, S_cnt_d5};
                        4'd1: v_char = {4'h3, S_cnt_d4};
                        4'd2: v_char = {4'h3, S_cnt_d3};
                        4'd3: v_char = {4'h3, S_cnt_d2};
                        4'd4: v_char = {4'h3, S_cnt_d1};
                        default: v_char = {4'h3, S_cnt_d0};
                    endcase
                end
            end
            else if ((S_x_1d >= ST_OSD_X) && (S_x_1d < (ST_OSD_X + ST_OSD_W)) &&
                     (S_y_1d >= ST_OSD_Y) && (S_y_1d < (ST_OSD_Y + ST_OSD_H))) begin
                // FPS:xx, ASCII 8px原生
                v_lx = S_x_1d - ST_OSD_X;
                v_ly = S_y_1d - ST_OSD_Y;
                v_idx = v_lx >> 3;
                v_col = {1'b0, v_lx[2:0]};
                if (v_ly < 12'd16) begin
                    v_row = v_ly[3:0];
                    v_region = 3'd3;
                    case (v_idx)
                        4'd0: v_char = 8'h46;  // F
                        4'd1: v_char = 8'h50;  // P
                        4'd2: v_char = 8'h53;  // S
                        4'd3: v_char = 8'h3a;  // :
                        4'd4: v_char = {4'h3, S_fps_d1};
                        4'd5: v_char = {4'h3, S_fps_d0};
                        default: v_region = 3'd0;          // FPS行仅6格, 余量空白
                    endcase
                end
            end
            else if ((S_x_1d >= BAN_X) && (S_x_1d < (BAN_X + BAN_TXT_W)) &&
                     (S_y_1d >= BAN_Y + BAN_TEXT_DY) && (S_y_1d < (BAN_Y + BAN_TEXT_DY + 12'd16))) begin
                // 底部模式栏 正常: 模式:dd_名称 | 演示: ISP:d_名称
                v_lx = S_x_1d - BAN_X;
                v_row = (S_y_1d - BAN_Y - BAN_TEXT_DY);
                if (S_isp_demo_2d[3]) begin
                    // ISP分步演示: [I8|S8|P8|:8|空8|d8|空16|名称64]
                    v_region = 3'd5;
                    if (v_lx < 12'd8)       begin v_char = 8'h49; v_col = {1'b0, v_lx[2:0]}; end      // I
                    else if (v_lx < 12'd16) begin v_char = 8'h53; v_col = {1'b0, v_lx[2:0]}; end      // S
                    else if (v_lx < 12'd24) begin v_char = 8'h50; v_col = {1'b0, v_lx[2:0]}; end      // P
                    else if (v_lx < 12'd32) begin v_char = 8'h3a; v_col = {1'b0, v_lx[2:0]}; end      // :
                    else if (v_lx < 12'd40) v_region = 3'd0;
                    else if (v_lx < 12'd48) begin v_char = {4'h3, S_isp_demo_2d[2:0]}; v_col = {1'b0, v_lx[2:0]}; end // 步号0-6
                    else if (v_lx < 12'd64) v_region = 3'd0;                     // 间隙
                    else begin
                        // 名称区起点v_lx=64(低6位为0), 槽号=(v_lx-64)>>3=v_lx[5:3]
                        v_char = F_isp_name_char(S_isp_demo_2d[2:0], v_lx[5:3]);
                        if (v_char == 8'd0) v_region = 3'd0;
                        else v_col = F_isp_name_cjk(S_isp_demo_2d[2:0]) ? v_lx[3:0] : {1'b0, v_lx[2:0]};
                    end
                end
                else begin
                    // 正常模式: [模16|式16|:8|d8|d8|gap8|名16×4]
                    v_region = 3'd5;
                    if (v_lx < 12'd16) begin
                        v_char = 8'h82;  v_col = v_lx[3:0];          // 模
                    end
                    else if (v_lx < 12'd32) begin
                        v_char = 8'h83;  v_col = (v_lx - 12'd16);    // 式
                    end
                    else if (v_lx < 12'd40) begin
                        v_char = CHAR_COLON;  v_col = {1'b0, v_lx[2:0]};
                    end
                    else if (v_lx < 12'd56) begin
                        v_col = {1'b0, v_lx[2:0]};
                        v_char = (v_lx < 12'd48) ? {4'h3, S_ban_d1} : {4'h3, S_ban_d0};
                    end
                    else if (v_lx < 12'd64) begin
                        v_region = 3'd0;                             // 间隙
                    end
                    else if (v_lx < 12'd80) begin
                        v_char = F_mode_name_char(S_mode_2d, 4'd0);  v_col = (v_lx - 12'd64);
                    end
                    else if (v_lx < 12'd96) begin
                        v_char = F_mode_name_char(S_mode_2d, 4'd1);  v_col = (v_lx - 12'd80);
                    end
                    else if (v_lx < 12'd112) begin
                        v_char = F_mode_name_char(S_mode_2d, 4'd2);  v_col = (v_lx - 12'd96);
                    end
                    else begin
                        v_char = F_mode_name_char(S_mode_2d, 4'd3);  v_col = (v_lx - 12'd112);
                    end
                end
            end
            else if (ENABLE_SWITCH_OSD && (S_x_1d >= SW_OSD_X) && (S_x_1d < (SW_OSD_X + SW_OSD_W)) &&
                     (S_y_1d >= BAN_Y + BAN_TEXT_DY) && (S_y_1d < (BAN_Y + BAN_TEXT_DY + 12'd16))) begin
                // Right-bottom compact switch state: AE AWB HE AB.
                v_region = 3'd6;
                v_row = (S_y_1d - BAN_Y - BAN_TEXT_DY);
                v_lx = S_x_1d - SW_OSD_X;
                v_idx = v_lx >> 3;
                v_col = {1'b0, v_lx[2:0]};
                case (v_idx)
                    4'd0: v_char = 8'h41; // A
                    4'd1: v_char = 8'h45; // E
                    4'd3: v_char = 8'h41; // A
                    4'd4: v_char = 8'h57; // W
                    4'd5: v_char = 8'h42; // B
                    4'd7: v_char = 8'h48; // H
                    4'd8: v_char = 8'h45; // E
                    4'd10: v_char = 8'h41; // A
                    4'd11: v_char = 8'h42; // B
                    default: v_char = 8'd0; // spaces
                endcase
            end
            // [二轮] 模式14识别框/标签已随 full-modes 分支撤下; 车牌串见 plate-demo 分支
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r1_region <= 3'd0;  r1_char <= 8'd0;
            r1_row <= 4'd0;  r1_col <= 4'd0;  r1_blend <= 1'b0;
            r1_sw_idx <= 4'd0;
        end
        else begin
            r1_region <= v_region;
            r1_char    <= v_char;
            r1_row     <= v_row;
            r1_col     <= v_col;
            r1_sw_idx  <= v_idx;
            // 半透明背景: HUD侧栏(Logo+CNT/FPS两行状态)、底部模式栏整条
            r1_blend   <= S_video_de_1d &&
                          (((S_x_1d >= HUD_X) && (S_x_1d < (HUD_X + HUD_W)) &&
                            (S_y_1d >= HUD_Y) && (S_y_1d < (HUD_Y + HUD_H))) ||
                           ((S_y_1d >= BAN_Y) && (S_y_1d < (BAN_Y + BAN_H))));
        end
    end

    // ================= 级B: BRAM命中与颜色 (ERAM同步读出, 打拍) =================
    wire v2_text_bit = S_pf_row_bits[4'd15 - r1_col];   // 字库ERAM(地址已提前到级A组合, 本拍有效)
    reg  v2_hit;
    reg  v2_is_logo;      // logo像素: 颜色不走r2_color, 由调色板ERAM在级C直混
    reg  [23:0] v2_color;

    always @(*) begin
        v2_hit = 1'b0;
        v2_is_logo = 1'b0;
        v2_color = 24'd0;
        if (r1_region == 3'd1) begin
            if (S_logo_idx != 8'd0) begin       // 索引0=透明; RGB两级BRAM延迟到级C
                v2_hit = 1'b1;
                v2_is_logo = 1'b1;
            end
        end
        else if (r1_region != 3'd0) begin
            if ((r1_char != 8'd0) && v2_text_bit) begin
                v2_hit = 1'b1;
                case (r1_region)
                    3'd2:    v2_color = COLOR_DYN_TEXT;
                    3'd3:    v2_color = COLOR_FPS_TEXT;
                    3'd6: begin
                        case (r1_sw_idx)
                            4'd0,4'd1: v2_color = S_feature_2d[0] ? COLOR_SW_ON : COLOR_SW_OFF;
                            4'd3,4'd4,4'd5: v2_color = S_feature_2d[1] ? COLOR_SW_ON : COLOR_SW_OFF;
                            4'd7,4'd8: v2_color = S_feature_2d[2] ? COLOR_SW_ON : COLOR_SW_OFF;
                            default: v2_color = S_feature_2d[3] ? COLOR_SW_ON : COLOR_SW_OFF;
                        endcase
                    end
                    default: v2_color = COLOR_BAN_TEXT;
                endcase
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r2_hit <= 1'b0;  r2_is_logo <= 1'b0;  r2_color <= 24'd0;  r2_blend <= 1'b0;
        end
        else begin
            r2_hit   <= v2_hit;
            r2_is_logo <= v2_is_logo;
            r2_color <= v2_color;
            r2_blend <= r1_blend;
        end
    end

    // ================= 级C: 一级优先混合 + 输出 =================
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_vsync_3d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_hsync_3d <= 1'b0;
            S_video_user_1d  <= 1'b0;
            S_video_user_2d  <= 1'b0;
            S_video_user_3d  <= 1'b0;
            O_hdmi_sof       <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            S_video_de_3d    <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_vsync_3d <= S_video_vsync_2d;
            O_hdmi_vsync     <= S_video_vsync_3d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            S_video_hsync_3d <= S_video_hsync_2d;
            O_hdmi_hsync     <= S_video_hsync_3d;

            S_video_user_1d  <= I_video_user;
            S_video_user_2d  <= S_video_user_1d;
            S_video_user_3d  <= S_video_user_2d;
            O_hdmi_sof       <= S_video_user_3d;
            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            S_video_de_3d    <= S_video_de_2d;
            O_hdmi_de        <= S_video_de_3d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;
            S_video_data_3d  <= S_video_data_2d;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_3d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_3d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_3d) begin
                    if(S_x < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if (ENABLE_OSD == 0) begin
                // 保持原图像流水延迟，允许综合裁剪未使用的 OSD 逻辑。
                O_hdmi_data <= S_video_data_3d;
            end
            else begin
                // 最终只有一级优先选择: 前景命中 > 半透明压暗 > 原图像
                // logo颜色走调色板ERAM第2拍输出(本拍直混), 文字颜色走r2_color
                if(r2_hit)
                    O_hdmi_data <= r2_is_logo ? S_logo_rgb : r2_color;
                else if(r2_blend)
                    O_hdmi_data <= {1'b0, S_video_data_3d[23:17],
                                    1'b0, S_video_data_3d[15:9],
                                    1'b0, S_video_data_3d[7:1]};
                else
                    O_hdmi_data <= S_video_data_3d;
            end
        end
    end

endmodule

