// =============================================================================
// 模块名 : logo_rom_bram
// 用途   : OSD logo 双级 ERAM 查表（索引 ERAM + 调色板 ERAM），替换
//          hdmi_mixer.v 中 6396 行组合 case-ROM（anlogic_logo_rom），
//          把 LUT 消耗转移到安路 PH1P35 片上 ERAM。
// 数据来源:
//   osd_logo_idx.mif : WIDTH=8,  DEPTH=16384, 前 13724 项有效 = 146x94 逐行
//                      调色板索引, 0 = 透明;
//   osd_logo_pal.mif : WIDTH=24, DEPTH=256,   RGB888 调色板,
//                      条目 0 = 24'h000000 为透明哨兵。
// 两级流水（无复位, 逐拍语义）:
//   拍 0 : I_clk 上升沿采样 I_addr（裁剪窗线性地址 = 行*146 + 列, 0..13723）;
//   拍 1 : O_idx 有效 —— 索引 ERAM 同步读输出直连（REGMODE="NOREG"）,
//          同拍该 8bit 值在模块内部直连调色板 ERAM 的 addra（不经过任何
//          寄存器, ERAM 自身的输出寄存就是这一拍）;
//   拍 2 : O_rgb 有效 —— 该索引对应的 RGB888。索引 0 时 O_rgb 无意义,
//          透明判定（hit 门控）由上层完成, 本模块不做任何比较。
// 集成路径: 本工程 RTL 集成路径为 rtl/hardware/hdl_source/（TD .al 按此
//   目录编译）, 且 INIT_FILE 用裸文件名时 TD 按 .v 同目录解析 mif
//   （先例: ph1p_ddrphy_init.v 的 "ddrphy_cfg_rom.txt"）, 因此本模块与
//   两份 mif 必须同目录 —— 这是对通用 rtl/ 目录约定的显式例外。
// ERAM 模板: PH1P_LOGIC_ERAM 例化写法逐字抄自本工程 vendor 生成网表
//   ram_c36c2ca3b3a7.v（板上验证过）, 仅改参数值。两个实例均为 A 口只读
//   （wea=1'b0）, B 口闲置（web=1'b0, addrb=0, dob 悬空）, 两口同用 I_clk。
// =============================================================================

module logo_rom_bram (
    input  wire        I_clk,    // 像素时钟, 上升沿采样
    input  wire [13:0] I_addr,   // 裁剪窗线性地址 = (行)*146+(列), 0..13723
    output wire [7:0]  O_idx,    // 1拍后: 该像素调色板索引(0=透明)
    output wire [23:0] O_rgb     // 2拍后: 该索引的RGB(索引0时无意义, 由上层hit门控)
);

    // -------------------------------------------------------------------------
    // 实例 1: 索引 ERAM —— 16384 x 8bit, 初始化自 osd_logo_idx.mif。
    // doa 直连 O_idx（wire, 无中间寄存器）, 同步读 1 拍延迟即流水第 1 拍。
    // -------------------------------------------------------------------------
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8),
        .DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(14),
        .ADDR_WIDTH_B(14),
        .DATA_DEPTH_A(16384),
        .DATA_DEPTH_B(16384),
        .MODE("DP"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("READBEFOREWRITE"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),
        .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),
        .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("osd_logo_idx.mif"),
        .FILL_ALL("NONE")
    ) logo_idx_eram_inst (
        .dia(8'd0), .dib(8'd0),
        .addra(I_addr), .addrb(14'd0),
        .cea(1'b1), .ceb(1'b1),
        .ocea(1'b0), .oceb(1'b0),
        .clka(I_clk), .clkb(I_clk),
        .wea(1'b0), .web(1'b0),
        .bea({32{1'b0}}), .beb({32{1'b0}}),
        .rsta(1'b0), .rstb(1'b0),
        .doa(O_idx), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0),
        .dob()
    );

    // -------------------------------------------------------------------------
    // 实例 2: 调色板 ERAM —— 256 x 24bit, 初始化自 osd_logo_pal.mif。
    // addra 直连 O_idx（8bit 索引即 8bit 地址, 不经过寄存器）, doa 直连
    // O_rgb。两级 ERAM 各贡献 1 拍, I_addr 采样沿后第 2 拍 O_rgb 有效。
    // -------------------------------------------------------------------------
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(24),
        .DATA_WIDTH_B(24),
        .ADDR_WIDTH_A(8),
        .ADDR_WIDTH_B(8),
        .DATA_DEPTH_A(256),
        .DATA_DEPTH_B(256),
        .MODE("DP"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("READBEFOREWRITE"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),
        .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),
        .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("osd_logo_pal.mif"),
        .FILL_ALL("NONE")
    ) logo_pal_eram_inst (
        .dia(24'd0), .dib(24'd0),
        .addra(O_idx), .addrb(8'd0),
        .cea(1'b1), .ceb(1'b1),
        .ocea(1'b0), .oceb(1'b0),
        .clka(I_clk), .clkb(I_clk),
        .wea(1'b0), .web(1'b0),
        .bea({32{1'b0}}), .beb({32{1'b0}}),
        .rsta(1'b0), .rstb(1'b0),
        .doa(O_rgb), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0),
        .dob()
    );

endmodule
