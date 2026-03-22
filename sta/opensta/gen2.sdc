# mini gen2 plus
# set_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm

# unit: MHz
set clk_xtal_freq 24.0
set clk_ext_freq  72.0
set clk_aud_freq  18.432

set clk_xtal_period [expr 1000.0 / $clk_xtal_freq]
set clk_ext_period  [expr 1000.0 / $clk_ext_freq]
set clk_aud_period  [expr 1000.0 / $clk_aud_freq]

set clk_period_factor .2



# set_operating_conditions -analysis_type on_chip_variation -library [get_libs {ETSCA_N55_H7BH_DSS_PRCMAX_V1P0_T125.db:ETSCA_N55_H7BH_DSS_PRCMAX_V1P0_T125}]
###############################################################################
# Clock Related Information
###############################################################################
create_clock -name clk_ext -period $clk_ext_period [get_pins \u_extclk_i_pad.u_sg13g2_IOPadInOut4mA/p2c]
create_clock -name clk_aud -period $clk_aud_period [get_pins \u_audclk_i_pad.u_sg13g2_IOPadInOut4mA/p2c]
###############################################################################
# Derived Clock related information
###############################################################################
# create_generated_clock -name CLK_sys_clk_buf -source [get_pins {u_rcu.u_ext_clk_buf.u_BUFX0P7H7L/Y}]  -divide_by 1  -add -master_clock [get_clocks {clk_ext}] [get_pins {u_rcu.u_sys_clk_buf.u_BUFX0P7H7L/Y}] 
# set_clock_uncertainty -setup  0.2 [get_clocks {CLK_sys_clk_buf}]
# set_clock_uncertainty -hold  0.1 [get_clocks {CLK_sys_clk_buf}]
# create_generated_clock -name CLK_cust_qspi_spi_clk_o -source [get_pins {u_rcu.u_sys_clk_buf.u_BUFX0P7H7L/Y}]  -divide_by 2 [get_ports {cust_qspi_spi_clk_o_pad}] 
# set_clock_uncertainty -setup  0.2 [get_clocks {CLK_cust_qspi_spi_clk_o}]
# set_clock_uncertainty -hold  0.1 [get_clocks {CLK_cust_qspi_spi_clk_o}]
# create_generated_clock -name CLK_cust_spfs_clk_o -source [get_pins {u_rcu.u_sys_clk_buf.u_BUFX0P7H7L/Y}]  -divide_by 2 [get_ports {cust_spfs_clk_o_pad}] 
# set_clock_uncertainty -setup  0.2 [get_clocks {CLK_cust_spfs_clk_o}]
# set_clock_uncertainty -hold  0.1 [get_clocks {CLK_cust_spfs_clk_o}]
# create_generated_clock -name CLK_cust_psram_sclk_o -source [get_pins {u_rcu.u_sys_clk_buf.u_BUFX0P7H7L/Y}]  -divide_by 2 [get_ports {cust_psram_sclk_o_pad}] 
# set_clock_uncertainty -setup  0.2 [get_clocks {CLK_cust_psram_sclk_o}]
# set_clock_uncertainty -hold  0.1 [get_clocks {CLK_cust_psram_sclk_o}]
# set_clock_groups -asynchronous -name CLK_u_xtal_io_pad_u_P65_1233_PWE_XC_1 -group [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}] -group [get_clocks {clk_ext CLK_sys_clk_buf CLK_cust_qspi_spi_clk_o CLK_cust_psram_sclk_o CLK_cust_spfs_clk_o}] -group [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}]
###############################################################################
# Point to Point exceptions
###############################################################################
# group_path -name CLK_u_xtal_io_pad_u_P65_1233_PWE_XC_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}]
# group_path -name CLK_u_xtal_io_pad_u_P65_1233_PWE_XC_reg2out -from [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name CLK_u_extclk_i_pad_u_P65_1233_PBMUX_C_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {clk_ext}]
# group_path -name CLK_u_extclk_i_pad_u_P65_1233_PBMUX_C_reg2out -from [get_clocks {clk_ext}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}]
# group_path -name CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y_reg2out -from [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name CLK_sys_clk_buf_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {CLK_sys_clk_buf}]
# group_path -name CLK_sys_clk_buf_reg2out -from [get_clocks {CLK_sys_clk_buf}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name CLK_cust_qspi_spi_clk_o_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {CLK_cust_qspi_spi_clk_o}]
# group_path -name CLK_cust_qspi_spi_clk_o_reg2out -from [get_clocks {CLK_cust_qspi_spi_clk_o}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name CLK_cust_psram_sclk_o_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {CLK_cust_psram_sclk_o}]
# group_path -name CLK_cust_psram_sclk_o_reg2out -from [get_clocks {CLK_cust_psram_sclk_o}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name CLK_cust_spfs_clk_o_in2reg -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_clocks {CLK_cust_spfs_clk_o}]
# group_path -name CLK_cust_spfs_clk_o_reg2out -from [get_clocks {CLK_cust_spfs_clk_o}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# group_path -name all_in2out -from [get_ports {xi_i_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_rx_i_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_miso_i_pad}] -to [get_ports {xo_o_pad extclk_i_pad pll_cfg_0_i_pad pll_cfg_1_i_pad pll_cfg_2_i_pad clk_bypass_i_pad ext_rst_n_i_pad sys_clkdiv4_o_pad uart_tx_o_pad uart_rx_i_pad gpio_0_io_pad gpio_1_io_pad gpio_2_io_pad gpio_3_io_pad gpio_4_io_pad gpio_5_io_pad gpio_6_io_pad gpio_7_io_pad gpio_8_io_pad gpio_9_io_pad gpio_10_io_pad gpio_11_io_pad gpio_12_io_pad gpio_13_io_pad gpio_14_io_pad gpio_15_io_pad irq_pin_i_pad cust_uart_tx_o_pad cust_uart_rx_i_pad cust_pwm_pwm_0_o_pad cust_pwm_pwm_1_o_pad cust_pwm_pwm_2_o_pad cust_pwm_pwm_3_o_pad cust_ps2_ps2_clk_i_pad cust_ps2_ps2_dat_i_pad cust_i2c_scl_io_pad cust_i2c_sda_io_pad cust_qspi_spi_clk_o_pad cust_qspi_spi_csn_0_o_pad cust_qspi_spi_csn_1_o_pad cust_qspi_spi_csn_2_o_pad cust_qspi_spi_csn_3_o_pad cust_qspi_dat_0_io_pad cust_qspi_dat_1_io_pad cust_qspi_dat_2_io_pad cust_qspi_dat_3_io_pad cust_psram_sclk_o_pad cust_psram_ce_o_pad cust_psram_sio0_io_pad cust_psram_sio1_io_pad cust_psram_sio2_io_pad cust_psram_sio3_io_pad cust_spfs_clk_o_pad cust_spfs_cs_o_pad cust_spfs_mosi_o_pad cust_spfs_miso_i_pad}]
# set_case_analysis 1 [get_pins {u_rcu.u_sys_mux.u_MUX2X0P5H7L/S0}]

set_input_transition .1 [all_inputs]
set_clock_uncertainty -setup 0.2 [get_clocks clk_ext]
set_clock_uncertainty -hold  0.1 [get_clocks clk_ext]
set_clock_uncertainty -setup 0.2 [get_clocks clk_aud]
set_clock_uncertainty -hold  0.1 [get_clocks clk_aud]

set_timing_derate -cell_delay -net_delay -late 1
set_timing_derate -net_delay -clock -early 0.95
set_timing_derate -net_delay -data -early 1
set_timing_derate -net_delay -clock -early 0.95
set_timing_derate -net_delay -data -early 1
set_timing_derate -cell_delay -clock -early 0.95
set_timing_derate -cell_delay -data -early 1
# Clock Group
###############################################################################
set_clock_groups -name cgp_async -asynchronous -group [get_clocks clk_ext] -group [get_clocks clk_aud]
###############################################################################
# Input/Output Delay
###############################################################################

###############################################################################
# Pin drive/load
###############################################################################
# set_load -pin_load  8 [get_ports extclk_i_pad]
# set_load -pin_load  8 [get_ports audclk_i_pad]
# set_load -pin_load  8 [get_ports ext_rst_n_i_pad]
# set_load -pin_load  8 [get_ports gpio_0_io_pad]
# set_load -pin_load  8 [get_ports gpio_1_io_pad]
# set_load -pin_load  8 [get_ports gpio_2_io_pad]
# set_load -pin_load  8 [get_ports gpio_3_io_pad]
# set_load -pin_load  8 [get_ports gpio_4_io_pad]
# set_load -pin_load  8 [get_ports gpio_5_io_pad]
# set_load -pin_load  8 [get_ports gpio_6_io_pad]
# set_load -pin_load  8 [get_ports gpio_7_io_pad]
# set_load -pin_load  8 [get_ports gpio_8_io_pad]
# set_load -pin_load  8 [get_ports gpio_9_io_pad]
# set_load -pin_load  8 [get_ports gpio_10_io_pad]
# set_load -pin_load  8 [get_ports gpio_11_io_pad]
# set_load -pin_load  8 [get_ports gpio_12_io_pad]
# set_load -pin_load  8 [get_ports gpio_13_io_pad]
# set_load -pin_load  8 [get_ports gpio_14_io_pad]
# set_load -pin_load  8 [get_ports gpio_15_io_pad]
# set_load -pin_load  8 [get_ports gpio_16_io_pad]
# set_load -pin_load  8 [get_ports gpio_17_io_pad]
# set_load -pin_load  8 [get_ports gpio_18_io_pad]
# set_load -pin_load  8 [get_ports gpio_19_io_pad]
# set_load -pin_load  8 [get_ports gpio_20_io_pad]
# set_load -pin_load  8 [get_ports gpio_21_io_pad]
# set_load -pin_load  8 [get_ports gpio_22_io_pad]
# set_load -pin_load  8 [get_ports gpio_23_io_pad]
# set_load -pin_load  8 [get_ports gpio_24_io_pad]
# set_load -pin_load  8 [get_ports gpio_25_io_pad]
# set_load -pin_load  8 [get_ports gpio_26_io_pad]
# set_load -pin_load  8 [get_ports gpio_27_io_pad]
# set_load -pin_load  8 [get_ports gpio_28_io_pad]
# set_load -pin_load  8 [get_ports gpio_29_io_pad]
# set_load -pin_load  8 [get_ports gpio_30_io_pad]
# set_load -pin_load  8 [get_ports gpio_31_io_pad]
# set_load -pin_load  8 [get_ports uart0_tx_o_pad]
# set_load -pin_load  8 [get_ports uart0_rx_i_pad]
# set_load -pin_load  8 [get_ports xpi_sck_o_pad]
# set_load -pin_load  8 [get_ports xpi_nss0_o_pad]
# set_load -pin_load  8 [get_ports xpi_nss1_o_pad]
# set_load -pin_load  8 [get_ports xpi_nss2_o_pad]
# set_load -pin_load  8 [get_ports xpi_nss3_o_pad]
# set_load -pin_load  8 [get_ports xpi_dat0_io_pad]
# set_load -pin_load  8 [get_ports xpi_dat1_io_pad]
# set_load -pin_load  8 [get_ports xpi_dat2_io_pad]
# set_load -pin_load  8 [get_ports xpi_dat3_io_pad]
# set_load -pin_load  8 [get_ports sdram_clk_o_pad]
# set_load -pin_load  8 [get_ports sdram_cke_o_pad]
# set_load -pin_load  8 [get_ports sdram_cs_n_o_pad]
# set_load -pin_load  8 [get_ports sdram_ras_n_o_pad]
# set_load -pin_load  8 [get_ports sdram_cas_n_o_pad]
# set_load -pin_load  8 [get_ports sdram_we_n_o_pad]
# set_load -pin_load  8 [get_ports sdram_ba0_o_pad]
# set_load -pin_load  8 [get_ports sdram_ba1_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr0_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr1_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr2_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr3_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr4_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr5_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr6_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr7_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr8_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr9_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr10_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr11_o_pad]
# set_load -pin_load  8 [get_ports sdram_addr12_o_pad]
# set_load -pin_load  8 [get_ports sdram_dqm0_o_pad]
# set_load -pin_load  8 [get_ports sdram_dqm1_o_pad]
# set_load -pin_load  8 [get_ports sdram_dq0_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq1_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq2_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq3_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq4_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq5_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq6_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq7_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq8_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq9_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq10_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq11_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq12_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq13_io_pad]
# set_load -pin_load  8 [get_ports sdram_dq14_io_pad]
###############################################################################
# False Path
###############################################################################
set_false_path -from [get_cells \u_rcu.u_ext_rst_sync*]
set_false_path -from [get_cells s_sys_rst_n_reg]
set_false_path -from [get_cells \u_rcu.u_aud_rst_sync*]
set_false_path -from [get_cells s_aud_rst_n_reg]

###############################################################################

# set_wire_load_mode top
# set_max_fanout  32 [current_design]
# set_max_transition  1.7 [get_clocks {CLK_sys_clk_buf}] -clock_path  -rise 
# set_max_transition  1.7 [get_clocks {CLK_sys_clk_buf}] -clock_path  -fall 
# set_max_transition  3.4 [get_clocks {CLK_sys_clk_buf}] -data_path  -rise 
# set_max_transition  3.4 [get_clocks {CLK_sys_clk_buf}] -data_path  -fall 
# set_max_transition  7.083333 [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}] -clock_path  -rise 
# set_max_transition  7.083333 [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}] -clock_path  -fall 
# set_max_transition  14.166667 [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}] -data_path  -rise 
# set_max_transition  14.166667 [get_clocks {CLK_u_xtal_io_pad_u_P65_1233_PWE_XC}] -data_path  -fall 
# set_max_transition  1.7 [get_clocks {clk_ext}] -clock_path  -rise 
# set_max_transition  1.7 [get_clocks {clk_ext}] -clock_path  -fall 
# set_max_transition  3.4 [get_clocks {clk_ext}] -data_path  -rise 
# set_max_transition  3.4 [get_clocks {clk_ext}] -data_path  -fall 
# set_max_transition  7.083333 [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}] -clock_path  -rise 
# set_max_transition  7.083333 [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}] -clock_path  -fall 
# set_max_transition  14.166667 [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}] -data_path  -rise 
# set_max_transition  14.166667 [get_clocks {CLK_u_rcu_u_pll_clk_buf_u_BUFX0P7H7L_Y}] -data_path  -fall 
# ###############################################################################
# # POCV Information
# ###############################################################################
