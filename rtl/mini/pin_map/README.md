# Canonical SoC Pin Map

`pin_map.json` is the single source for the Mini SoC logical pad ABI and its
ASIC, FPGA, Verilator, and RTL-testbench bindings. The generator emits
temporary SystemVerilog include files below the selected build variant; do not
edit generated files.

The map intentionally does not contain FPGA package locations. Board-level
locations remain owned by the FPGA constraint file. Dedicated SDIO1 pads are
therefore emitted but intentionally unbound in the FPGA profile until a
package pin and 3.3 V I/O-bank contract exists. The generic
`peripheral_bidir` kind requires explicit input, output, and output-enable
signals and is reusable for any peripheral, not just SDIO. Validate changes
with `make check-pin-map` and the pin-map tests before running a regression.
