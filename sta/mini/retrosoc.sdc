#120MHz
set clk_period 8.33

create_clock -period $clk_period [get_ports xi_i_pad]
create_clock -period $clk_period [get_ports extclk_i_pad]
 
create_generated_clock -name CLK_sys_peri    -divide_by 1 -source u_xtal_io_pad.u_PXWE1W/XC                  [get_pins  u_sys_mux.u_LVT_CKMUX2HDV4/Z]
create_generated_clock -name CLK_flash_clk_o -divide_by 1 -source u_retrosoc.u_spimemio.xfer.flash_clk_reg/Q [get_ports flash_clk_o_pad]
create_generated_clock -name CLK_cust_qspi_spi_clk_o -divide_by 1 -source u_retrosoc.u_axil_ip_wrapper.u_apb_spi_master.u_spictrl.u_clkgen.spi_clk_reg/Q [get_ports cust_qspi_spi_clk_o_pad]
create_generated_clock -name CLK_cust_psram_sclk_o   -divide_by 2 -source u_retrosoc.u_psram.sclk_reg/Q                                                  [get_ports cust_psram_sclk_o_pad]
create_generated_clock -name CLK_cust_spfs_clk_o     -divide_by 1 -source u_retrosoc.u_axil_ip_wrapper.u_spi_flash.u0_spi_top.clgen.clk_out_reg/Q        [get_ports cust_spfs_clk_o_pad]

set_false_path -from [get_cells s_ext_rst_n_sync_reg]

set clk_period_factor .2
set clk_delay [expr $clk_period * $clk_period_factor]
# set_input_delay $clk_delay -clock clk {req_val reset resp_rdy req_msg[*]}
# set_input_delay $clk_delay -clock xi_i_pad {}
set_output_delay $clk_delay -clock xi_i_pad [all_outputs]
set_input_transition .1 [all_inputs]
