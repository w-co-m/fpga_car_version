create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


# 保留原三组内的同步关系，只给原跨组路径设置定向例外。
# TD read_sdc 不展开 foreach；全部约束显式列出，避免空读入。
# TD Timing Constraints User Guide 5.3.2：异步 FIFO 双向宽松
# clock-level max_delay + IP 更紧的 Gray 寄存器级 max_delay。
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {sys_clk_50m}]
set_false_path -from [get_clocks {sys_clk_50m}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {pll_clk_100m}]
set_false_path -from [get_clocks {pll_clk_100m}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {pll_clk_24m}]
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {HDMI_SERIAL_CLK}]
set_false_path -from [get_clocks {HDMI_SERIAL_CLK}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {sys_clk_50m}]
set_false_path -from [get_clocks {sys_clk_50m}] -to [get_clocks {MIPI_RX_BYTE_CLK}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {pll_clk_100m}]
set_false_path -from [get_clocks {pll_clk_100m}] -to [get_clocks {MIPI_RX_BYTE_CLK}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {pll_clk_24m}]
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_clocks {MIPI_RX_BYTE_CLK}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {MIPI_RX_BYTE_CLK}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {HDMI_SERIAL_CLK}]
set_false_path -from [get_clocks {HDMI_SERIAL_CLK}] -to [get_clocks {MIPI_RX_BYTE_CLK}]
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {mipi_rx_ck_pad}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {mipi_rx_ck_pad}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {MIPI_RX_BYTE_CLK}]
set_max_delay -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -datapath_only 100
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {MIPI_RX_BYTE_CLK}] -datapath_only 100
set_false_path -from [get_clocks {sys_clk_50m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {sys_clk_50m}]
set_false_path -from [get_clocks {sys_clk_50m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {sys_clk_50m}]
set_false_path -from [get_clocks {pll_clk_100m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {pll_clk_100m}]
set_false_path -from [get_clocks {pll_clk_100m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {pll_clk_100m}]
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {pll_clk_24m}]
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {pll_clk_24m}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_max_delay -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -datapath_only 100
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {HDMI_PIXEL_CLK}] -datapath_only 100
set_false_path -from [get_clocks {HDMI_SERIAL_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] -to [get_clocks {HDMI_SERIAL_CLK}]
set_false_path -from [get_clocks {HDMI_SERIAL_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {HDMI_SERIAL_CLK}]

# Physical buttons and SW1 are asynchronous; time the synchronized internal paths.
set_false_path -from [get_ports {I_button[0] I_button[1] I_threshold_edit}]

# Bundled-data frame mailboxes hold payload until the returned ACK. Destination
# captures after two synchronizer clocks (minimum 26.667 ns at 75 MHz).
# Bound payload routing below one destination cycle, independently of the loose
# 100 ns clock-level CDC bounds above. Do not replace these with false paths.
set_max_delay -from [get_regs -nowarn {*/u_frame_ticket/payload[*]}] -to [get_regs -nowarn {*/u_frame_ticket/dst_data[*]}] -datapath_only 12.000
set_max_delay -from [get_regs -nowarn {*/u_frame_ack/payload[*]}] -to [get_regs -nowarn {*/u_frame_ack/dst_data[*]}] -datapath_only 12.000

# Original v8 actuator keys enter two-stage synchronizers.
set_false_path -from [get_ports {I_motor_key_n[0] I_motor_key_n[1]}]
