# PIOLITE-P2 internal 24 MHz PCLK observation; product timing is not qualified.
create_clock -name pclk -period 41.666666667 [get_ports clk_i]
# No blanket false path on reset or GPIO/stream inputs. Report uncharacterized boundaries.
