# Physical Design

This directory owns physical-design integration, managed technology inputs,
smoke implementation-flow sources, and the self-developed commercial-flow
drivers.

- `pdk/` contains the locked PDK setup helpers and managed PDK checkouts.
- `smoke/syn/` contains Yosys synthesis and source-export integration.
- `smoke/sta/` contains OpenSTA constraints and timing integration.
- `commercial/` contains licensed-tool orchestration and flow logic. PDKs,
  foundry decks, commercial libraries, site configuration, and results remain
  outside Git.
- `sdf/`, when supplied by an implementation flow, contains post-layout
  netlist and SDF collateral consumed by post-layout simulation.

The local Makefile is reserved for implementation flows that require the
selected PDK, technology collateral, and often site-specific tools.

Generated layout, report, and database outputs must remain outside tracked
source paths. Treat PDK-dependent physical-design results as toolchain-specific
evidence and record the selected profile, PDK, and validation command when
handing off a change. See [Engineering Workflow](../docs/engineering.md).
