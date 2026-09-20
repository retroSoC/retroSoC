# GA2D block core-STA constraints, hand-written for the isolated apb4_ga2d
# block flow (physical/smoke/syn/yosys/ga2d_block.mk, target sta-ga2d-block).
# The clock period is the "pclk" domain value from
# rtl/mini/integration/clock_reset_domains.json (20.833333333 ns, 48 MHz);
# do not weaken it. Conventions mirror the SoC core-STA profile produced by
# physical/smoke/sta/opensta/generate_sdc.py.

proc require_ports {label name} {
  set objects [get_ports -quiet $name]
  if {$objects eq ""} {
    error "required SDC object is missing: $label ($name)"
  }
  return $objects
}

set clk_pclk_port [require_ports "clock pclk" {clk_i}]
create_clock -name clk_pclk -period 20.833333333 $clk_pclk_port

set_clock_uncertainty -setup 0.2 [get_clocks {clk_pclk}]
set_clock_uncertainty -hold 0.1 [get_clocks {clk_pclk}]

set_clock_transition 0.1 [get_clocks {clk_pclk}]

set reset_rst_n_i [require_ports "reset rst_n_i" {rst_n_i}]
set_false_path -from $reset_rst_n_i

# Same scope as the SoC core-STA baseline: sequential block paths only.
# Integration (APB/AXI boundary) timing is supplied by the owning SoC SDC.
set_false_path -from [all_inputs]
set_false_path -to [all_outputs]
