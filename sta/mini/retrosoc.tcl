# report_timing
read_liberty ../S110/S011HD1P_X256Y4D32_BW_TT_1.2_25.lib
read_liberty ../S110/scc011ums_hd_lvt_tt_v1p2_25c_basic.lib
read_liberty ../S110/SP013D3WP_V1p7_typ.lib
read_liberty ../S110/S013PLLFN_v1.5.1_typ.lib
read_verilog ../yosys/out/retrosoc_asic_yosys.v
link_design retrosoc_asic
# 
read_sdc retrosoc_pll.sdc

report_checks -path_delay min_max -path_group {CLK_src_xtal CLK_src_ext CLK_xtal_buf CLK_ext_buf CLK_pll CLK_pll_buf CLK_sys_mux_pll CLK_sys_mux_ext CLK_sys_clk_buf CLK_flash_clk_o CLK_cust_qspi_spi_clk_o CLK_cust_psram_sclk_o CLK_cust_spfs_clk_o} -sort_by_slack -slack_max 0.0 -group_path_count 50000 -endpoint_path_count 50000 > retrosoc_sta.log

# set_propagated_clock clk
# read_spef gcd_sky130hd.spef
# set_power_activity -input -activity .1
# set_power_activity -input_port reset -activity 0
# report_power
