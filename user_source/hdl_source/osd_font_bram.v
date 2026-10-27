//=============================================================================
// 模块名   : osd_font_bram
// 所属工程 : hdmi_mixer（安路 PH1P35，TD 6.x 工具链）
// 用途     : OSD 16x16 点阵字库 BRAM ROM（ERAM 同步读版）。
//            用于替换 osd_char_lib 中的 873 行组合 case-ROM：把字库存储从
//            大量组合 LUT 搬进 1 个 20K ERAM，综合后显著节省 LUT 资源。
// 数据来源 : user_source/hdl_source/osd_font_rom.mif
//            WIDTH=16, DEPTH=2048；前 1888 字有效（118 字符 x 16 行，
//            ASCII 40 + 中文 79），每字符 16 行、每行 1 个 16bit 字，
//            bit15 = 字模最左像素。索引 0~118（地址 0~1903），其余填充。
// 时序     : 纯 1 拍同步读 —— I_clk 上升沿采样 I_char/I_row，
//            O_row_bits 在下一时钟周期稳定有效（REGMODE="NOREG"）。
//            无复位：ROM 无状态，配置加载 mif 后输出即有效。
// 放置要求 : 本文件必须与 osd_font_rom.mif 同目录（TD 按 .v 同目录解析
//            INIT_FILE 裸文件名，先例：本工程 ph1p_ddrphy_init.v 的
//            "ddrphy_cfg_rom.txt"）。本工程 RTL 集成路径为
//            user_source/hdl_source/（TD .al 工程按此路径编译），
//            这是对通用 rtl/ 目录约定的显式例外，理由详见
//            doc/spec/behavior_spec.md 的 osd_font_bram 章节。
// 例化模板 : PH1P_LOGIC_ERAM 例化写法逐字抄自本工程 vendor 生成网表
//            ram_c36c2ca3b3a7.v（板上验证过），仅改参数值与实例名。
//=============================================================================
module osd_font_bram (
    input  wire        I_clk,        // 采样时钟，上升沿采样地址
    input  wire [7:0]  I_char,       // 字符码（ASCII 0x20~0x5A / 中文 0x80~0xCD）
    input  wire [3:0]  I_row,        // 字模行号 0~15
    output wire [15:0] O_row_bits    // 行像数据，bit15=最左像素，滞后地址 1 拍
);

    //-------------------------------------------------------------------------
    // ERAM 参数取值（参数名沿用 vendor 网表模板，便于逐字对照）
    //-------------------------------------------------------------------------
    localparam integer DATA_WIDTH_A  = 16;
    localparam integer DATA_WIDTH_B  = 16;
    localparam integer ADDR_WIDTH_A  = 11;
    localparam integer ADDR_WIDTH_B  = 11;
    localparam integer DATA_DEPTH_A  = 2048;
    localparam integer DATA_DEPTH_B  = 2048;
    localparam REGMODE_A   = "NOREG";            // 无输出寄存器级 -> 1 拍同步读
    localparam REGMODE_B   = "NOREG";
    localparam WRITEMODE_A = "NORMAL";           // A 口只读，写模式无实际作用
    localparam WRITEMODE_B = "READBEFOREWRITE";  // B 口闲置，维持模板取值
    localparam RESETMODE_A = "ASYNC";
    localparam RESETMODE_B = "ASYNC";
    localparam INIT_FILE   = "osd_font_rom.mif"; // 裸文件名，与 .v 同目录解析
    localparam FILL_ALL    = "NONE";             // 填充区不初始化，正常不寻址

    //-------------------------------------------------------------------------
    // 字符码 -> ROM 索引映射（索引 0~117，组合逻辑）
    // 未列出的字符码（含空格 0x20）一律落到索引 39：空格字模全 0，天然兜底。
    //-------------------------------------------------------------------------
    reg [6:0] char_idx;

    always @* begin
  case(I_char)
   8'h30:char_idx=7'd0;
   8'h31:char_idx=7'd1;
   8'h32:char_idx=7'd2;
   8'h33:char_idx=7'd3;
   8'h34:char_idx=7'd4;
   8'h35:char_idx=7'd5;
   8'h36:char_idx=7'd6;
   8'h37:char_idx=7'd7;
   8'h38:char_idx=7'd8;
   8'h39:char_idx=7'd9;
   8'h41:char_idx=7'd10;
   8'h42:char_idx=7'd11;
   8'h43:char_idx=7'd12;
   8'h44:char_idx=7'd13;
   8'h45:char_idx=7'd14;
   8'h46:char_idx=7'd15;
   8'h47:char_idx=7'd16;
   8'h48:char_idx=7'd17;
   8'h49:char_idx=7'd18;
   8'h4D:char_idx=7'd19;
   8'h4E:char_idx=7'd20;
   8'h4F:char_idx=7'd21;
   8'h50:char_idx=7'd22;
   8'h52:char_idx=7'd23;
   8'h53:char_idx=7'd24;
   8'h54:char_idx=7'd25;
   8'h56:char_idx=7'd26;
   8'h57:char_idx=7'd27;
   8'h58:char_idx=7'd28;
   8'h59:char_idx=7'd29;
   8'h3A:char_idx=7'd30;
   8'h2D:char_idx=7'd31;
   8'h2E:char_idx=7'd32;
   8'h20:char_idx=7'd33;
   8'h6D:char_idx=7'd34;
   8'h73:char_idx=7'd35;
   default:if(I_char>=8'h80&&I_char<=8'hDB)char_idx={1'b0,I_char[6:0]}+7'd36;else char_idx=7'd33;
  endcase
 end

    // ROM 读地址 = 索引*16 + 行号，即 7bit 索引拼接 4bit 行号（11bit，最大 1887）
    wire [10:0] rom_addr = {char_idx, I_row};   // 索引*16+行, 最大118*16+15=1903

    //-------------------------------------------------------------------------
    // ERAM 例化连线（信号名沿用 vendor 网表模板，便于与模板逐字对照）
    //-------------------------------------------------------------------------
    wire [15:0] dia   = 16'd0;       // A 口写数据恒 0（ROM 只读）
    wire [15:0] dib   = 16'd0;       // B 口写数据恒 0（B 口闲置）
    wire [10:0] addra = rom_addr;    // A 口读地址 = {字符索引, 行号}
    wire [10:0] addrb = 11'd0;       // B 口地址固定 0（闲置）
    wire        wea   = 1'b0;        // A 口禁止写
    wire        web   = 1'b0;        // B 口禁止写
    wire        clka  = I_clk;       // A 口时钟
    wire        clkb  = I_clk;       // B 口时钟
    wire [15:0] doa;                 // A 口同步读数据 -> 模块输出
    wire [15:0] dob;                 // B 口读数据悬空不用，综合时被优化

    //-------------------------------------------------------------------------
    // ERAM 例化（模板逐字抄自 ram_c36c2ca3b3a7.v 板上验证网表，
    // 仅改参数值与实例名；下方块保持 vendor 网表原始缩进，勿随意重排）
    //-------------------------------------------------------------------------
	PH1P_LOGIC_ERAM #(
		.DATA_WIDTH_A(DATA_WIDTH_A),
		.DATA_WIDTH_B(DATA_WIDTH_B),
		.ADDR_WIDTH_A(ADDR_WIDTH_A),
		.ADDR_WIDTH_B(ADDR_WIDTH_B),
		.DATA_DEPTH_A(DATA_DEPTH_A),
		.DATA_DEPTH_B(DATA_DEPTH_B),
		.MODE("DP"),
		.REGMODE_A(REGMODE_A),
		.REGMODE_B(REGMODE_B),
		.WRITEMODE_A(WRITEMODE_A),
		.WRITEMODE_B(WRITEMODE_B),
		.IMPLEMENT("20K(FAST)"),
		.ECC_ENCODE("DISABLE"),
		.ECC_DECODE("DISABLE"),
		.CLKMODE("ASYNC"),
		.SSROVERCE("DISABLE"),
		.OREGSET_A("RESET"),
		.OREGSET_B("RESET"),
		.RESETMODE_A(RESETMODE_A),
		.RESETMODE_B(RESETMODE_B),
		.ASYNC_RESET_RELEASE_A("ASYNC"),
		.ASYNC_RESET_RELEASE_B("ASYNC"),
		.INIT_FILE(INIT_FILE),
		.FILL_ALL(FILL_ALL)
	) osd_font_rom_inst(
		.dia(dia), .dib(dib), .addra(addra), .addrb(addrb),
		.cea(1'b1), .ceb(1'b1),
		.ocea(1'b0), .oceb(1'b0),
		.clka(clka), .clkb(clkb),
		.wea(wea), .web(web),
		.bea({32{1'b0}}), .beb({32{1'b0}}),
		.rsta(1'b0), .rstb(1'b0),
		.doa(doa), .ecc_sbiterr(), .ecc_dbiterr(),
		.ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0),
		.dob(dob)
	);

    // A 口同步读数据直接作为行像输出（1 拍延迟由 ERAM NOREG 模式提供）
    assign O_row_bits = doa;

endmodule
