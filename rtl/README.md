# RTL Design and Simulation

This directory contains retroSoC SystemVerilog RTL, CPU/IP integration,
peripheral and technology wrappers, filelists, testbench support, and the Mini
SoC build entry points.

`mini/` is the active SoC integration flow. `managed/` contains locked or
vendored integration inputs, while `ip/` contains self-owned IP and
experiments. `filelist/` selects PDK-specific RTL sources; `tech/` contains
technology wrappers. Respect managed upstream boundaries and use setup helpers
rather than editing generated MPW output.

RTL changes require an affected firmware build and simulation. Use
`make regress-pr` or `make regress-nightly` for supported regression coverage;
see [Engineering Workflow](../docs/engineering.md) for results and artifacts.

The Verilator harness uses a zero-delay SDRAM protocol model because Verilator
does not elaborate the tri-state delays in the Micron model. The Icarus
testbench retains that Micron timing model, so it is the reference for SDRAM
command timing while Verilator provides fast functional coverage.
