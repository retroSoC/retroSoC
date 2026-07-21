# FPGA Integration

This directory contains FPGA-facing top-level integration for the Mini SoC.
`mini/retrosoc_top.sv` is the FPGA top wrapper and
`mini/starrysky_v2.xdc` contains board timing and pin constraints.

The wrapper consumes the generated `retrosoc_asic_fpga_mini_bindings.svh`
include. Before invoking an FPGA tool, generate the selected profile with
`make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk pin-map` and add
`build/<variant>/generated/pin_map/rtl` to the tool include path. Logical pad
names and wrapper bindings are owned by `rtl/mini/pin_map/pin_map.json`;
package locations remain in the board `.xdc` file.

FPGA constraints are board-specific implementation inputs, not generic ASIC
RTL. Validate changes with the relevant FPGA tool flow and hardware target; do
not reuse them as ASIC timing constraints. Follow the RTL and hardware-facing
validation requirements in [`AGENTS.md`](../AGENTS.md).
