# Canonical SoC Pin Map

`pin_map.json` is the single source for the Mini SoC logical pad ABI and its
ASIC, FPGA, Verilator, and RTL-testbench bindings. The generator emits
temporary SystemVerilog include files below the selected build variant; do not
edit generated files.

The map intentionally does not contain FPGA package locations. Board-level
locations remain owned by the FPGA constraint file. Validate changes with
`make check-pin-map` and the pin-map tests before running a regression.
