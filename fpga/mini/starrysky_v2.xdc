# set W25Q128JWSIQ_tDVCH 2
# set W25Q128JWSIQ_tCHDX 3

# set W25Q128JWSIQ_tCLQV 6
# set W25Q128JWSIQ_tCLQX 1.5

# timing constr
create_clock -period 20.000 -waveform {0.000 10.000} [get_ports clk_i]

# create_generated_clock -name spfs_clk -source [get_pins u_clk_wiz_0/clk_out1] -divide_by 2 [get_ports cust_spfs_clk_o]
# create_generated_clock -name qspi_clk -source [get_pins u_clk_wiz_0/clk_out1] -divide_by 2 [get_ports cust_qspi_spi_clk_o]
# create_generated_clock -name psram_clk -source [get_pins u_clk_wiz_0/clk_out1] -divide_by 2 [get_ports cust_psram_sclk_o]

# set_output_delay -clock [get_clocks spfs_clk] -max [expr 0.5 + $W25Q128JWSIQ_tDVCH] [get_ports cust_spfs_mosi_o]
# set_output_delay -clock [get_clocks spfs_clk] -min [expr -0.5 - $W25Q128JWSIQ_tCHDX] [get_ports cust_spfs_mosi_o]

# set_input_delay -clock [get_clocks spfs_clk] -max [expr 0.5 + $W25Q128JWSIQ_tCLQV] [get_ports cust_spfs_miso_i]
# set_input_delay -clock [get_clocks spfs_clk] -min [expr -0.5 + $W25Q128JWSIQ_tCLQX] [get_ports cust_spfs_miso_i]

set_false_path -from [get_ports rst_n_i]

# physical constr
set_property -dict {PACKAGE_PIN L18  IOSTANDARD LVCMOS18} [get_ports clk_i]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS18} [get_ports rst_n_i]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS18} [get_ports uart_rx_i]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS18} [get_ports uart_tx_o]

set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS18} [get_ports gpio_io0]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS18} [get_ports gpio_io1]

set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS18} [get_ports cust_uart_tx_o]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS18} [get_ports cust_uart_rx_i]
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS18} [get_ports cust_pwm_pwm_o]
set_property -dict {PACKAGE_PIN AB4 IOSTANDARD LVCMOS18} [get_ports cust_ps2_ps2_clk_i]
set_property -dict {PACKAGE_PIN AB5 IOSTANDARD LVCMOS18} [get_ports cust_ps2_ps2_dat_i]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS18} [get_ports cust_i2c_scl_io]
set_property -dict {PACKAGE_PIN Y15 IOSTANDARD LVCMOS18} [get_ports cust_i2c_sda_io]

set_property -dict {PACKAGE_PIN Y14  IOSTANDARD LVCMOS18} [get_ports cust_spfs_cs_o]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVCMOS18} [get_ports cust_spfs_clk_o]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports cust_spfs_mosi_o]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS18} [get_ports cust_spfs_miso_i]
# tft lcd
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS18} [get_ports gpio_io2]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS18} [get_ports cust_qspi_spi_csn_0_o]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS18} [get_ports cust_qspi_spi_clk_o]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS18} [get_ports cust_qspi_dat_0_io]
# psram
# mosi io0
# miso io1
# wp   io2
# hold io3
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS18} [get_ports psram_sclk_o]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS18} [get_ports psram_ce_0_o]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS18} [get_ports psram_sio0_io]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS18} [get_ports psram_sio1_io]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS18} [get_ports psram_sio2_io]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS18} [get_ports psram_sio3_io]
# spisd
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS18} [get_ports spisd_sclk_o]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS18} [get_ports spisd_cs_o]
set_property -dict {PACKAGE_PIN Y19  IOSTANDARD LVCMOS18} [get_ports spisd_mosi_o]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS18} [get_ports spisd_miso_i]