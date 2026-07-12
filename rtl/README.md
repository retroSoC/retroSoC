# RTL Design and Simulation

This directory contains retroSoC SystemVerilog RTL, CPU/IP integration,
peripheral and technology wrappers, filelists, testbench support, and the Mini
SoC build entry points.

`mini/` is the active SoC integration flow. `clusterip/` and `ip/` contain
managed or generated integration inputs; `filelist/` selects PDK-specific RTL
sources; `tech/` contains technology wrappers. Respect managed upstream
boundaries and use setup helpers rather than editing generated MPW output.

RTL changes require an affected firmware build and simulation. Use
`make regress-pr` or `make regress-nightly` for supported regression coverage;
see [Engineering Workflow](../docs/engineering.md) for results and artifacts.
