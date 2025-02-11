create_clock -period 20.000 -waveform {0.000 10.000} [get_ports clk_i]

set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS18} [get_ports clk_i]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS18} [get_ports rst_n_i]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS18} [get_ports uart_rx_i]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS18} [get_ports uart_tx_o]

set_property -dict {PACKAGE_PIN AA8  IOSTANDARD LVCMOS18} [get_ports gpio_io0]
set_property -dict {PACKAGE_PIN A16  IOSTANDARD LVCMOS18} [get_ports gpio_io1]

set_property -dict {PACKAGE_PIN AA9  IOSTANDARD LVCMOS18} [get_ports pwm_pwm_o]

set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS18} [get_ports i2c_scl_io]
set_property -dict {PACKAGE_PIN Y15 IOSTANDARD LVCMOS18} [get_ports i2c_sda_io]

set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS18}  [get_ports cust_uart_tx_o]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS18}  [get_ports cust_uart_rx_i]
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS18}  [get_ports cust_pwm_pwm_o]
set_property -dict {PACKAGE_PIN AB4 IOSTANDARD LVCMOS18}  [get_ports cust_ps2_ps2_clk_i]
set_property -dict {PACKAGE_PIN AB5 IOSTANDARD LVCMOS18}  [get_ports cust_ps2_ps2_dat_i]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS18}  [get_ports cust_spfs_cs_o]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVCMOS18} [get_ports cust_spfs_clk_o]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports cust_spfs_mosi_o]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS18} [get_ports cust_spfs_miso_i]
# tft lcd
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS18} [get_ports gpio_io2]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS18} [get_ports cust_qspi_spi_csn_0_o]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS18} [get_ports cust_qspi_spi_clk_o]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS18} [get_ports cust_qspi_dat_0_io]