# FPGA Integration

This directory contains FPGA-facing top-level integration for the Mini SoC.
`mini/retrosoc_top.sv` is the FPGA top wrapper and
`mini/starrysky_v2.xdc` contains board timing and pin constraints.

FPGA constraints are board-specific implementation inputs, not generic ASIC
RTL. Validate changes with the relevant FPGA tool flow and hardware target; do
not reuse them as ASIC timing constraints. Follow the RTL and hardware-facing
validation requirements in [`AGENTS.md`](../AGENTS.md).
