create_clock -period 10 [get_ports xi_i_pad]
create_clock -period 10 [get_ports extclk_i_pad]

 
create_generated_clock -name CLK_sys_peri            -div 1 -source u_xtal_io_pad/clk                                                               u_retrosoc_asic/u_sys_mux/clk_o
create_generated_clock -name CLK_spi_mst_sck_o       -div 2 -source u_retrosoc/u_simple_spi_master/isck_reg/Q                                       u_retrosoc_asic/spi_mst_sck_o_pad
create_generated_clock -name CLK_flash_clk_o         -div 1 -source u_retrosoc/u_spimemio/xfer/flash_clk_reg/Q                                      u_retrosoc_asic/flash_clk_o_pad
create_generated_clock -name CLK_cust_qspi_spi_clk_o -div 1 -source u_retrosoc/u_axil_ip_wrapper/u_apb_spi_master/u_spictrl/u_clkgen/spi_clk_reg/Q  u_retrosoc_asic/cust_qspi_spi_clk_o_pad
create_generated_clock -name CLK_cust_psram_sclk_o   -div 2 -source u_retrosoc/u_psram/sclk_reg/Q                                                   u_retrosoc_asic/cust_psram_sclk_o_pad
create_generated_clock -name CLK_cust_spfs_clk_o     -div 1 -source u_retrosoc/u_axil_ip_wrapper/u_spi_flash/u0_spi_top/clgen/clk_out_reg/Q         u_retrosoc_asic/cust_spfs_clk_o_pad
