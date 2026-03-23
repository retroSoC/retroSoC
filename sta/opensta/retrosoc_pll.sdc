#24MHz
set clk_xtal_period 41.67
#120MHz
set clk_ext_period 8.33
set clk_period_factor .2
# clk src
create_clock -name CLK_src_xtal -period $clk_xtal_period xi_i_pad
create_clock -name CLK_src_ext  -period $clk_ext_period  extclk_i_pad
# clk buf
create_generated_clock -name CLK_xtal_buf -source \u_rcu.u_xtal_buf.i_buf/I    -master_clock CLK_src_xtal -divide_by   1 \u_rcu.u_xtal_buf.i_buf/Z
create_generated_clock -name CLK_ext_buf  -source \u_rcu.u_ext_clk_buf.i_buf/I -master_clock CLK_src_ext  -divide_by   1 \u_rcu.u_ext_clk_buf.i_buf/Z
create_generated_clock -name CLK_pll      -source \u_rcu.u_tc_pll.u0_pll/XIN   -master_clock CLK_xtal_buf -multiply_by 4 \u_rcu.u_tc_pll.u0_pll/CLK_OUT
create_generated_clock -name CLK_pll_buf  -source \u_rcu.u_pll_clk_buf.i_buf/I -master_clock CLK_pll      -divide_by   1 \u_rcu.u_pll_clk_buf.i_buf/Z
set_clock_groups -logically_exclusive -group {CLK_pll_buf} -group {CLK_ext_buf}
set_clock_groups -asynchronous        -group {CLK_pll_buf} -group {CLK_ext_buf}
# clk mux
create_generated_clock -name CLK_sys_mux_pll -source \u_rcu.u_sys_mux.u_LVT_CKMUX2HDV4/I0 -master_clock CLK_pll_buf -divide_by 1 \u_rcu.u_sys_mux.u_LVT_CKMUX2HDV4/Z -add
create_generated_clock -name CLK_sys_mux_ext -source \u_rcu.u_sys_mux.u_LVT_CKMUX2HDV4/I1 -master_clock CLK_ext_buf -divide_by 1 \u_rcu.u_sys_mux.u_LVT_CKMUX2HDV4/Z -add
create_generated_clock -name CLK_sys_clk_buf -source \u_rcu.u_sys_clk_buf.i_buf/I         -master_clock CLK_src_ext -divide_by 1 \u_rcu.u_sys_clk_buf.i_buf/Z
set_clock_groups -physically_exclusive -group {CLK_sys_mux_pll} -group {CLK_sys_mux_ext}
# set bypass mode
set_case_analysis 0 \u_rcu.u_sys_mux.u_LVT_CKMUX2HDV4/S
# when bypass xtal_buf 
# set_clock_groups -asynchronous -group {CLK_xtal_buf} -group {CLK_sys_clk_buf}
# ip
create_generated_clock -name CLK_flash_clk_o         -source \u_retrosoc.u_spimemio.xfer.flash_clk_reg/Q -master_clock CLK_sys_clk_buf -divide_by 2 flash_clk_o_pad
create_generated_clock -name CLK_cust_qspi_spi_clk_o -source s_cust_qspi_spi_clk_o_reg/Q                 -master_clock CLK_sys_clk_buf -divide_by 2 cust_qspi_spi_clk_o_pad
create_generated_clock -name CLK_cust_psram_sclk_o   -source s_cust_psram_sclk_o_reg/Q                   -master_clock CLK_sys_clk_buf -divide_by 2 cust_psram_sclk_o_pad
create_generated_clock -name CLK_cust_spfs_clk_o     -source s_cust_spfs_clk_o_reg/Q                     -master_clock CLK_sys_clk_buf -divide_by 2 cust_spfs_clk_o_pad
# async rst
set_false_path -from \u_rcu.s_ext_rst_n_sync_reg
set_false_path -from [get_cells \u_rcu.u_tc_pll.s_lock_cnt_*__reg]
# in/out
# set clk_delay [expr $clk_ext_period * $clk_period_factor]
# set_input_delay $clk_delay -clock clk {req_val reset resp_rdy req_msg[*]}
# set_input_delay $clk_delay -clock xi_i_pad {}
# set_output_delay $clk_delay -clock xi_i_pad [all_outputs]
set_input_transition .1 [all_inputs]
set_clock_uncertainty -setup .1 [all_clocks]
set_clock_uncertainty -hold .1 [all_clocks]