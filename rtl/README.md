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

## Self-Owned RTL Naming

Self-owned SystemVerilog follows these signal and register naming rules. New
RTL and local changes to existing RTL must preserve them:

- Declare synthesizable data, state, and interconnect signals as `logic`.
  Reserve explicit net types for signals that require net resolution semantics.
- Use `_i` and `_o` for module ports, `s_` for internal signals, and `u_` for
  module instances.
- Name state owned by the current module `s_<name>_d` for next state and
  `s_<name>_q` for registered current state. Keep the pair adjacent in the
  declaration and connect it through a reusable register component from
  ClusterIP Common.
- Name a register write enable `s_<name>_en`. Do not add `_d` or `_q` to an
  ordinary combinational signal or to a parent-module connection simply
  because its source is registered inside a child module.
- Use `s_req`, `s_write`, `s_req_accept`, and `s_access_error` for a RIBP slave
  transaction. Name its registered response signals `s_ribp_ready_d/q`,
  `s_ribp_rdata_d/q`, and `s_ribp_resp_err_d/q`.
- Name register offsets `RIBP_<IP>_<REGISTER>` and field bit positions
  `<IP>_<REGISTER>_<FIELD>`. Do not add redundant `_OFFSET`, `_LSB`, `_MASK`,
  or `_VALUE` suffixes; keep implementation-only masks and constant values as
  typed `localparam` declarations in the owning module.

Run `verible-verilog-format --flagfile=.verible-format` on changed RTL. Where
the formatter cannot preserve required macro or port-column alignment, use a
narrow `// verilog_format: off/on` region and align the enclosed declarations
manually.

The Verilator harness uses a zero-delay SDRAM protocol model because Verilator
does not elaborate the tri-state delays in the Micron model. The Icarus
testbench retains that Micron timing model, so it is the reference for SDRAM
command timing while Verilator provides fast functional coverage.
