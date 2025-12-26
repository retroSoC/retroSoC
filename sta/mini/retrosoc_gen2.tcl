# read lib
read_liberty /nfs/share/home/zhuangchunan/proj/Flow_CX55/lib_data/ccslib/ics55_LLSC_H7CH_ss_rcworst_1p08_125_nldm.lib
read_liberty /nfs/share/home/zhuangchunan/proj/Flow_CX55/lib_data/ccslib/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib
read_liberty /nfs/share/home/zhuangchunan/proj/Flow_CX55/lib_data/ccslib/ics55_LLSC_H7CR_ss_rcworst_1p08_125_nldm.lib
read_liberty /nfs/share/home/zhuangchunan/proj/Flow_CX55/lib_data/ccslib/ICSIOA_N55_3P3_ss_1p08_2p97_125c.lib
read_verilog /nfs/share/home/zhaoxueyan/dataset_gj_test26/retrosoc_asic-cx55/retrosoc_asic_yosys.v
link_design retrosoc_asic
# read sdc
read_sdc retrosoc_gen2.sdc

report_checks -path_delay min_max -path_group {CLK_src_xtal CLK_src_ext CLK_xtal_buf CLK_ext_buf CLK_pll CLK_pll_buf CLK_sys_mux_pll CLK_sys_mux_ext CLK_sys_clk_buf CLK_flash_clk_o CLK_cust_qspi_spi_clk_o CLK_cust_psram_sclk_o CLK_cust_spfs_clk_o} -sort_by_slack -slack_max 0.0 -group_path_count 50000 -endpoint_path_count 50000 > retrosoc_sta.log

# set_propagated_clock clk
# read_spef gcd_sky130hd.spef
# set_power_activity -input -activity .1
# set_power_activity -input_port reset -activity 0
# report_power
