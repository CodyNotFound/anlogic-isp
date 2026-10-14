# CSI 域 103.5MHz 时序收敛改造记录（2026-10-04）

## 背景

闪屏（偶发整屏黑一下）根因分析定位：`td_project/camera_to_dsi_display.sdc` 曾将 MIPI RX
时钟约束从 2.415ns（414MHz pad / 103.5MHz byte clock）误放宽至 4.167ns（240MHz），导致整条
CSI/ISP 域按 60MHz 约束、62.9MHz 实现、实际运行 103.5MHz（placed db 实测 SWNS -6.243ns /
STNS -1762ns / 1490 违例端点）。本次改造将约束恢复为 2.415ns，并对 CSI 域内新增算法逻辑
做流水化重构，使其在真实频率下收敛。

## 约束与工程配置修复

| 项 | 修复前 | 修复后 |
|---|---|---|
| `camera_to_dsi_display.sdc:2` mipi_rx_ck_pad | period 4.167 (waveform 2.083) | period 2.415 (waveform 1.208)，与 lab_ex3_osd / sc520_base 原厂一致 |
| `.al` Default_PhysicalDesign_Strategy | speedup_effort=5, hfn_opt_effort=low, opt_timing=low（降级） | 移除降级，恢复 bitgen compress=on |
| `.al` Configurations | 空 | mclk_freq=33MHz, boot_mode=mspix4（恢复，SPI 固化依赖） |
| `.al` "foo" 空 Synthesis Run | 存在（probe.tcl 试验残留） | 移除 |
| `design_top_wrapper.v` car_ctrl 例化 | CLK_HZ=60_000_000（与实际 103.5MHz 时钟不符，UART 实际 ~198.7kbps） | CLK_HZ=103_500_000（实际波特率 115.25k，误差 0.09%） |
| 上电默认模式 | S_video_mode=4'd7 (SCHARR) + isp_top r_mode_sync=M_SCHARR | 4'd0 / M_BYPASS（原图直通） |

## RTL 流水化重构（四个模块，接口与算法语义不变）

违例分布（placed db，103.5MHz）：blob_detect_96 1220 端点(worst -6.243ns)、track_assoc
227(-3.351)、fx_window_96 18(-2.230)、car_ctrl 7(-3.364)、mnist_engine 12(-0.594，交布线
吸收)、awb 1(-3.475，单端点 O_tlast，交布线吸收)。

### blob_detect_96.v（消费 FSM 拆级）
- 旧 ST_EV 同拍"FIFO 异步读+行比较+FSM 分支"（742 端点）→ ST_EV 纯取数，行判断移至
  ST_CHK 用寄存后的 evr。
- 旧 ST_DO 同拍"搜索→按 mid 读表→绝对差→F_step→26bit 加→写回"→ ST_CHK/ST_SRCH(搜索
  寄存) → ST_APP1(读表保持 h_*) → ST_APP2(算术+写回)。
- 旧 ST_SC/ST_FS 定稿"补底边→P²乘→4πA乘→阈值乘×2→比较→输出"单拍双 DSP 链(-6.24ns)
  → ST_S0(锁存 fa/fp/dim_ok/清 T_v) → ST_S1(pr2=fp², lhs=51472·fa) → ST_S2(thr_c/thr_s)
  → ST_S3(比较+O_det_* 输出) 四级流水。
- run 提取组合块 ev_d[0..5] 全量默认赋值，消除 SYN-5015 的 10 个锁存器。
- 行为差异（有意接受）：事件消费 2→4~5 拍/事件，每行事件上限 ~160→~80（FIFO 16 深 +
  warn_ovf 计数兜底，实际彩色目标场景 << 上限）；输出序列逐项等价。

### track_assoc.v（两级→三级流水）
- v2 遗留：r2 拍"未寄存绝对差门控→3 层 12bit min 树→sel_i→表写回/有符号减"~14 级。
- v3：r1 拍把各槽绝对差/曼哈顿距离/半径判定/完整门控快照 gm_s 一并入寄存；r2 拍仅掩码
  mux + min 树 + 空位搜索，选择结果(best/free/alloc)寄存；r3 拍表写回与 O_* 输出。
- 延迟 2→3 拍；门控采样由 r2 提前到 r1（上游 blob 定稿流水保证 O_det_valid 间隔 ≥4 拍，
  写回边沿早于下一检测采样边沿 ≥1 拍，v2 的"背靠背读旧质心"容差说明作废）。

### fx_window_96.v（对外 1 拍契约不变，逐像素等价）
- 行缓存异步 LUTRAM 读（PHY-5079 告警源）→ 同步预取读：rd_addr=写地址 FSM 下一状态，
  beat N-1 末沿把 mem[x_grp[N]] 采入 top_word_r/mid_word_r，逐拍数值与异步读等价
  （归纳论证见 fpga-rtl-build fork note）。
- F_scharr_mag 10 项串行移位加减(~13 级)→平衡树（3 个 9bit 减→3x/10x 缩放→3 项 13bit
  和→绝对值→14bit 幅值→饱和，≤7 级）；F_window sum9 改三行先行求和。

### car_ctrl.v
- 主目标选择"乘法+22bit 比较+写回"单拍 → 两拍流水（SEL-1 寄存载荷与 a_area_r，SEL-2
  比较更新；frame_done 同拍清零优先）。
- UART TX 位节拍 `tx_ph==BIT_CYC-1` 组合高扇出使能 → bit_tick_r 寄存（比较取 BIT_CYC-2
  补偿打拍延迟，每位仍精确 BIT_CYC 拍，波特率零漂移）；下一位电平节拍当拍预载 O_uart_tx，
  消除 LUTRAM 异步读+XOR 树直通输出链。

## 验证

- **最终结果（2026-10-04 12:01，phy_2 全流程重建）**：真实 2.415ns/103.5MHz 约束下
  **SWNS 0.000ns / STNS 0.000ns / 0 违例端点（setup 与 hold 双清零）**；bit 与压缩 bit
  均产出并同步 best_result；`export_bitgen_param` 成功（RUN-8001 消失，Configurations
  恢复生效）。迭代轨迹：旧网表+真实约束（placed db STA）SWNS -6.243/1490 端点 →
  第 1 轮（blob/track/fx 1 拍版/car 重构）布线后 -1.543/202 端点（全部在 fx_window
  O_tdata 输入侧链）→ 第 2 轮（fx_window 2 拍化 + isp_top 4 支路 +1 拍对齐）全清零。
- 行为回归（待跑）：`sim/tb_blob_dbg.v`、`sim/tb_detect.v`、`sim/tb_track.v`、
  `tb/tb_fx_window.v`（期望延迟改 2 拍）、`sim/tb_car.v`、`tb/tb_isp_modes.v`（支路
  总延迟 4 拍）。
- 已知前提契约：blob O_det_valid 脉冲间隔 ≥4 拍（track/car_ctrl 流水时序假设依赖它）；
  fx_window_96 的 2 拍契约与 isp_top 的 *_d1 对齐必须同批生效（单改其一会引入 1 拍
  支路失配 → 模式切换丢帧头）。

## 画质修复追加（2026-10-04 第 3 轮，同批重建验证）

- **gamma 提亮**：`axis_gamma_rgb96`（16 段折线 y=255·(x/255)^0.7，取自 sc520_base）
  例化于 AWB 之后、显示支路分发之前（isp_top.v）；五条显示支路统一 +1 拍（4→5 拍，
  支路对齐保持），detect/mnist 保持原始 awb 输入不受影响。
- **BLC**：`design_top_wrapper.v` 的 `I_camera_black_level` 由 0 改为 10'd64
  （SmartSens 10bit 黑电平惯例；sensor 侧 0x5780 BLC 模块已启用，输出带 pedestal。
  板上验证：遮镜头应近全黑；若暗部细节丢失则回退此常量）。
  `raw10_unpacket_2lane.v` 减法改为饱和式，黑电平高于实际 pedestal 时暗部噪声钳 0
  而非无符号下溢回绕成白点。
- 第 3 轮重建：**SWNS +0.101ns / HWNS +0.020ns，0 违例端点**；bit 12:22 产出并同步
  best_result。
- 待办（画质#2）：静态白平衡（对角增益）标定流程——bypass 模式对白纸，ChipWatcher 抓
  `u_isp_top/u_awb/sum_red/sum_green/sum_blue` 帧统计值，得 R̄/Ḡ/B̄ 后以 Ḡ 为基准算
  kR/kB 烘焙为静态增益；完整 3×3 CCM 需色卡标定。

## 相关文件

- `user_source/hdl_source/detect/blob_detect_96.v`（重写）
- `user_source/hdl_source/detect/track_assoc.v`（重写）
- `user_source/hdl_source/isp/fx_window_96.v`（重构）
- `user_source/hdl_source/car_ctrl.v`（重构）
- `user_source/hdl_source/design_top_wrapper.v`（CLK_HZ 参数 + 上电默认模式两处小改）
- `user_source/hdl_source/isp/isp_top.v`（上电默认 M_BYPASS 一处小改）
- `td_project/camera_to_dsi_display.sdc`、`td_project/camera_to_dsi_display.al`（恢复）
- STA 证据：`td_project/camera_to_dsi_display_Runs/sta_scratch/sta_real_constraint.timing`
  （1490 端点违例普查）与 `viol_mipi_full.rpt`（按模块聚类）
