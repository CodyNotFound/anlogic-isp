create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_vendor_pipeline/u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_vendor_pipeline/u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_vendor_pipeline/u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_vendor_pipeline/u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_vendor_pipeline/u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]
# Keep MIPI<->sys50, sys50<->DDR and DDR<->HDMI ungrouped so async-FIFO
# Gray pointers retain their datapath-only max-delay checks. The buffered
# ISP and video_in producer now run on the continuous sys50 clock.

set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {pll_clk_100m pll_clk_24m}]

set_clock_groups -asynchronous \
    -group [get_clocks {pll_clk_100m pll_clk_24m}] \
    -group [get_clocks {u_vendor_pipeline/u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_vendor_pipeline/u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {HDMI_PIXEL_CLK HDMI_SERIAL_CLK}]

# Stable frame statistic bus/toggle protocol.
set_clock_groups -asynchronous \
    -group [get_clocks {HDMI_PIXEL_CLK}] \
    -group [get_clocks {pll_clk_24m}]

# Single-bit level synchronizers. These signals are either held across many
# destination cycles or are reset-synchronizer async inputs; hold relationships
# are not meaningful. Do not apply these exceptions to FIFO Gray pointer buses.
set_false_path -setup -to [get_regs -nowarn {*u_video_in/S_camera_frame_start_extend_*}]
set_false_path -hold   -to [get_regs -nowarn {*u_video_in/S_camera_frame_start_extend_*}]
set_false_path -setup -to [get_regs -nowarn {*u_video_out/S_video_vsync_*}]
set_false_path -hold   -to [get_regs -nowarn {*u_video_out/S_video_vsync_*}]

# v37 application fixes ISP demo select to zero (K3 is a manual down key).
# There is no runtime HDMI-to-sys50 demo bus. Remove its former first-stage
# exception and keep ordinary timing checks on any remaining destination logic.

# Async reset assertion/deassertion into each domain's reset synchronizer.
set_false_path -to [get_regs -nowarn {*u_video_out/pixel_reset_sync*}]
set_false_path -to [get_regs -nowarn {*u_video_in/U_w128_d512_fifo/*/asy_w_rst1*}]
set_false_path -to [get_regs -nowarn {*u_video_out/U_w128_d512_fifo/*/asy_r_rst0*}]
