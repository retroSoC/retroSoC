create_clock -period 20.000 -waveform {0.000 10.000} [get_ports clk_i]

set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS18} [get_ports clk_i]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS18} [get_ports rst_n_i]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS18} [get_ports uart_rx_i]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS18} [get_ports uart_tx_o]

set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS18} [get_ports flash_csb_o]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVCMOS18} [get_ports flash_clk_o]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports flash_io0_io]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS18} [get_ports flash_io1_io]

