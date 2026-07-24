# Dynamic PLL timing template.
#
# This file is intentionally not selected by the default OpenSTA flow. It may
# be enabled only after a PDK backend supplies the concrete PLL and
# glitch-free clock-switch cell pin names. Sign off every selector mode with
# its own generated-clock period (24, 48, 72, 96, 120, 144, 168, 192 MHz),
# and declare the external safe clock and PLL clock physically exclusive.
#
# The active core-STA flow generates its external-safe-clock constraints from
# rtl/mini/integration/clock_reset_domains.json. The current IHP130 and ICS55
# wrappers report PLL capability disabled, so this template remains unselected.
