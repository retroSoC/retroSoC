# Managed Process Design Kits

This directory is the integration root for process design kits, technology
libraries, SRAM/PLL collateral, and related setup scripts. Most child trees
are managed vendor or upstream dependencies rather than ordinary project
source.

Use the dependency lock and PDK setup targets to acquire or update managed
inputs. Do not reformat, patch, or delete vendor content as part of unrelated
work. PDK changes require the affected synthesis, timing, physical-design, or
FPGA validation flow and the ownership review defined by
[`../../.github/CODEOWNERS`](../../.github/CODEOWNERS).

The supported CI PDKs are IHP130, GF180, ICS55, and SKY130. ICS55 obtains its
locked H7CR standard-cell Liberty archive through
`dependencies/dependencies.lock.json` and materializes normalized TT and SS views
below `.cache/retrosoc/pdk/ics55/`; its IO Liberty is part of the locked
source checkout. PDK setup also generates a cached copy of the H7CR
functional standard-cell model that corrects the seven upstream `MUXI2`
self-feedback models without modifying the vendor checkout. GF180 assembles its
locked `gf180mcu_fd_sc_mcu7t5v0` Liberty fragments and the two SoC-used IO
cells (`in_c` and `bi_t`) at both its TT and core-STA slow corners. SKY130
generates its `sky130_fd_sc_hd` Liberty model from locked upstream JSON files
at TT and slow corners. Derived Liberty files are stored below
`.cache/retrosoc/pdk/` and are not committed. SKY130 setup initializes only
the locked HD library submodule; the remaining upstream libraries are outside
the SoC integration boundary.

The IHP130 dependency is also the technology source for the single-level
`physical/librelane/` full-chip flow. The locked checkout includes the upstream
`libs.tech/librelane` standard-cell, pad, extraction, DRC, LVS, filler, bondpad,
and seal-ring configuration; LibreLane consumes it directly in manual-PDK mode.
The other three open PDKs do not yet have project-owned LibreLane adapters.

All four PDK profiles run slow-corner OpenSTA core timing in CI. The analysis
uses the PDK standard-cell Liberty plus the linked IO-cell model required to
read the synthesized top-level wrapper. It excludes board, pad-ring,
extraction, and PLL timing and is therefore not a physical signoff result.

The GF180, ICS55, and SKY130 CI flows synth the digital core and run functional
standard-cell netlist simulation. Their generic SoC wrappers explicitly use
the locked PDK GPIO and clock cells for RTL and netlist simulation: GF180 uses
`gf180mcu_fd_io__in_c`/`gf180mcu_fd_io__bi_t` and MCU7T5V0 clock cells, while
SKY130 uses `sky130_fd_io__top_gpiov2` and HD clock cells. This integration
does not add supply, corner, filler, placement, or physical verification
collateral; physical pad-ring integration remains a technology-specific
signoff task. GF180/SKY130 PLL configurations are rejected because no
qualified crystal-pad implementation is selected. SKY130 maps the generic
Schmitt-control input to its threshold-select control and therefore does not
provide hysteresis. ICS55 uses its cached corrected standard-cell functional
model with timing blocks disabled and a pin-compatible local PBMUX/PWE model
only for Verilator, because the upstream IO model uses unsupported gate
strengths and transmission primitives. Verilator uses a pin-compatible local functional model
for the GF180 IO cells because the upstream model contains unsupported `rnmos`
primitives. SKY130 uses the same approach because its upstream IO model uses
unsupported switch primitives and drive strengths. Synthesis still preserves
the original PDK cell instances. GF180 netlist simulation also substitutes
pin-compatible sequential-cell models because the upstream functional models
propagate an unconnected synthesized notifier as an unknown value.
