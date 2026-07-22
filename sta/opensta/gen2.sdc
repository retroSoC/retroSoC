# Mini SoC default external-safe-clock timing mode.
# Dynamic PLL timing modes are enabled only after a PDK backend supplies a
# characterized PLL macro and a glitch-free switch cell.

set clk_ext_freq 72.0
set clk_aud_freq 18.432
set clk_ext_period [expr 1000.0 / $clk_ext_freq]
set clk_aud_period [expr 1000.0 / $clk_aud_freq]

create_clock -name clk_ext -period $clk_ext_period [get_ports extclk_i_pad]
create_clock -name clk_aud -period $clk_aud_period [get_ports audclk_i_pad]
create_generated_clock -name clk_i2s_mclk_o -source [get_pins \u_rcu.u_aud_clk_buf/clk_o] \
  -divide_by 1 [get_ports gpio_10_io_pad]

set_input_transition .1 [all_inputs]
set_clock_uncertainty -setup 0.2 [get_clocks clk_ext]
set_clock_uncertainty -hold 0.1 [get_clocks clk_ext]
set_clock_uncertainty -setup 0.2 [get_clocks clk_aud]
set_clock_uncertainty -hold 0.1 [get_clocks clk_aud]
set_clock_uncertainty -setup 0.2 [get_clocks clk_i2s_mclk_o]
set_clock_uncertainty -hold 0.1 [get_clocks clk_i2s_mclk_o]

set_timing_derate -cell_delay -net_delay -late 1
set_timing_derate -net_delay -clock -early 0.95
set_timing_derate -net_delay -data -early 1
set_timing_derate -cell_delay -clock -early 0.95
set_timing_derate -cell_delay -data -early 1
set_clock_groups -name cgp_async -asynchronous -group [get_clocks clk_ext] \
  -group [get_clocks clk_aud]

set_false_path -from [get_cells \u_rcu.u_ext_rst_sync*]
set_false_path -from [get_cells \u_rcu.u_aud_rst_sync*]
