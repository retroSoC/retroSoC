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
The dedicated SDIO1 pads are intentionally left unbound by the FPGA profile
until a board package location and 3.3 V I/O-bank assignment are approved;
the existing LVCMOS18 constraints do not establish SDIO electrical support.
The new UART1 HP-console ports are likewise left unbound until two StarrySky
package pins and their I/O voltage are reviewed. The ASIC profile still owns
dedicated UART1 pads; this FPGA constraint gap is intentional and must be
resolved before generating an HP board bitstream.

FPGA constraints are board-specific implementation inputs, not generic ASIC
RTL. Validate changes with the relevant FPGA tool flow and hardware target; do
not reuse them as ASIC timing constraints. Follow the RTL and hardware-facing
validation requirements in [`AGENTS.md`](../AGENTS.md).
