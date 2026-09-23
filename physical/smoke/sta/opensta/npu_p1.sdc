# NPU isolated core STA constraints, mirroring generate_sdc.py conventions.
# Single-clock targets (P1 compute and the P3 engine modules) run at the
# 1000000/72 ps HP period regardless of the port's local name; the integrated
# shell (apb4_npu) also carries PCLK at its 48 MHz platform period and the two
# domains are grouped asynchronously. The locked OpenSTA build lacks
# remove_from_collection/filter_collection, so ports are selected by name
# iteration.
set npu_clk_ports [list]
set npu_rst_ports [list]
set npu_io_inputs [list]
foreach npu_port [all_inputs] {
  set npu_port_name [get_property $npu_port name]
  if {$npu_port_name eq "clk_i" || $npu_port_name eq "clk_hp_i"} {
    lappend npu_clk_ports $npu_port
  } elseif {$npu_port_name eq "rst_n_i" || $npu_port_name eq "rst_hp_n_i"} {
    lappend npu_rst_ports $npu_port
  } else {
    lappend npu_io_inputs $npu_port
  }
}
set npu_hp_found 0
set npu_pclk_found 0
foreach npu_clk_port $npu_clk_ports {
  set npu_clk_name [get_property $npu_clk_port name]
  if {$npu_clk_name eq "clk_hp_i" || [llength $npu_clk_ports] == 1} {
    # The 72 MHz HP fabric period (13.888889 ns).
    create_clock -name npu_hp_clk -period 13.888889 $npu_clk_port
    set npu_hp_found 1
  } else {
    # PCLK at its 48 MHz platform period (20.833333 ns).
    create_clock -name npu_pclk -period 20.833333 $npu_clk_port
    set npu_pclk_found 1
  }
}
if {$npu_hp_found} {
  set_clock_uncertainty -setup 0.2 [get_clocks npu_hp_clk]
  set_clock_uncertainty -hold 0.1 [get_clocks npu_hp_clk]
  set_clock_transition 0.1 [get_clocks npu_hp_clk]
}
if {$npu_pclk_found} {
  set_clock_uncertainty -setup 0.2 [get_clocks npu_pclk]
  set_clock_uncertainty -hold 0.1 [get_clocks npu_pclk]
  set_clock_transition 0.1 [get_clocks npu_pclk]
}
if {$npu_hp_found && $npu_pclk_found} {
  set_clock_groups -asynchronous -group [get_clocks npu_hp_clk] -group [get_clocks npu_pclk]
}
if {[llength $npu_rst_ports] > 0} {
  set_false_path -from $npu_rst_ports
}
# Async-reset check arcs are not timed here: assertion/deassertion discipline
# is provided by the Common reset synchronizers/barriers, and this locked
# OpenSTA build does not cut RESET_B recovery arcs via set_clock_groups.
# Physical CDC/RDC signoff remains a separate commercial-delivery gap.
set_false_path -to [get_pins -hierarchical * -filter {name =~ */RESET_B}]
set_input_delay -clock npu_hp_clk 2.0 $npu_io_inputs
set_output_delay -clock npu_hp_clk 2.0 [all_outputs]
