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

set_clock_groups -name cgp_async -asynchronous -group [get_clocks -include_generated_clocks clk_out1_clk_wiz_0] -group [get_clocks -include_generated_clocks clk_out2_clk_wiz_0]
set_false_path -from [get_ports rst_n_i]

# physical constr
set_property -dict {PACKAGE_PIN L18  IOSTANDARD LVCMOS18} [get_ports clk_i]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS18} [get_ports rst_n_i]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS18} [get_ports uart0_rx_i]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS18} [get_ports uart0_tx_o]

set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS18} [get_ports gpio_io0]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS18} [get_ports gpio_io1]

set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS18} [get_ports uart1_tx_o]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS18} [get_ports uart1_rx_i]
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS18} [get_ports pwm_0_o]
set_property -dict {PACKAGE_PIN AB4 IOSTANDARD LVCMOS18} [get_ports ps2_clk_i]
set_property -dict {PACKAGE_PIN AB5 IOSTANDARD LVCMOS18} [get_ports ps2_dat_i]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS18} [get_ports i2c_scl_io]
set_property -dict {PACKAGE_PIN Y15 IOSTANDARD LVCMOS18} [get_ports i2c_sda_io]

set_property -dict {PACKAGE_PIN Y14  IOSTANDARD LVCMOS18} [get_ports spfs_nss_o]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVCMOS18} [get_ports spfs_sck_o]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports spfs_mosi_o]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS18} [get_ports spfs_miso_i]
# tft lcd
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS18} [get_ports gpio_io2]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS18} [get_ports qspi_nss0_o]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS18} [get_ports qspi_sck_o]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS18} [get_ports qspi_dat0_io]
# psram
# mosi io0
# miso io1
# wp   io2
# hold io3
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS18} [get_ports psram_sck_o]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS18} [get_ports psram_nss0_o]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS18} [get_ports psram_dat0_io]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS18} [get_ports psram_dat1_io]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS18} [get_ports psram_dat2_io]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS18} [get_ports psram_dat3_io]
# spisd
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS18} [get_ports spisd_sck_o]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS18} [get_ports spisd_nss_o]
set_property -dict {PACKAGE_PIN Y19  IOSTANDARD LVCMOS18} [get_ports spisd_mosi_o]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS18} [get_ports spisd_miso_i]
#i2s
set_property -dict {PACKAGE_PIN Y10 IOSTANDARD LVCMOS18} [get_ports i2s_mclk_o]
set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS18} [get_ports i2s_sclk_o]
set_property -dict {PACKAGE_PIN AB12 IOSTANDARD LVCMOS18} [get_ports i2s_lrck_o]
set_property -dict {PACKAGE_PIN AA12 IOSTANDARD LVCMOS18} [get_ports i2s_dacdat_o]
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS18} [get_ports i2s_adcdat_i]
#onewire
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS18} [get_ports onewire_dat_o]