# NPU-P1 isolated core STA constraints: single 72 MHz HP clock at the
# 1000000/72 ps target period, mirroring generate_sdc.py conventions.
# NOTE: the locked OpenSTA build has no remove_from_collection/filter_collection,
# so the input-delay exclusion of clock/reset ports is done by name iteration.
create_clock -name clk_i -period 13.888889 [get_ports clk_i]
set_clock_uncertainty -setup 0.2 [get_clocks clk_i]
set_clock_uncertainty -hold 0.1 [get_clocks clk_i]
set_clock_transition 0.1 [get_clocks clk_i]
set_false_path -from [get_ports rst_n_i]
set npu_io_inputs [list]
foreach npu_port [all_inputs] {
  set npu_port_name [get_property $npu_port name]
  if {$npu_port_name ne "clk_i" && $npu_port_name ne "rst_n_i"} {
    lappend npu_io_inputs $npu_port
  }
}
set_input_delay -clock clk_i 2.0 $npu_io_inputs
set_output_delay -clock clk_i 2.0 [all_outputs]
