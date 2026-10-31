# PPALITE-P2 standalone 24 MHz host/pixel-clock observation only.
create_clock -name pclk -period 41.666666667 [get_ports clk_i]
create_clock -name pixclk -period 41.666666667 [get_ports pixel_clk_i]
set_clock_groups -asynchronous -group {pclk} -group {pixclk}
# No blanket false path on reset, source guards or streams. Report uncharacterized boundaries.
