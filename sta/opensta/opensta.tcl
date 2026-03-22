# report_timing
read_liberty pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib
read_liberty pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
read_verilog syn/yosys/.synth_build/out/retrosoc_asic_yosys.v
link_design retrosoc_asic
read_sdc sta/opensta/gen2.sdc

report_checks -path_delay min_max -path_group {clk_ext clk_aud } -sort_by_slack -slack_max 0.0 -group_path_count 1000 -endpoint_path_count 1000 > sta/opensta/retrosoc_sta.log

# set_propagated_clock clk
# read_spef gcd_sky130hd.spef
# set_power_activity -input -activity .1
# set_power_activity -input_port reset -activity 0
# report_power
