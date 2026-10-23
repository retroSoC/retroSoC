# SPI-P1 internal PCLK observation. External slave/board timing is NOT qualified.
create_clock -name pclk -period 41.666666667 [get_ports clk_i]
# No blanket false path on reset or raw MISO. Report uncharacterized boundaries.
