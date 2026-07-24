# Managed Process Design Kits

This directory is the integration root for process design kits, technology
libraries, SRAM/PLL collateral, and related setup scripts. Most child trees
are managed vendor or upstream dependencies rather than ordinary project
source.

Use the dependency lock and PDK setup targets to acquire or update managed
inputs. Do not reformat, patch, or delete vendor content as part of unrelated
work. PDK changes require the affected synthesis, timing, physical-design, or
FPGA validation flow and the ownership review defined by `.github/CODEOWNERS`.

The supported CI PDKs are IHP130, GF180, and SKY130. GF180 assembles its
locked `gf180mcu_fd_sc_mcu7t5v0` TT 5.0 V cell fragments, and SKY130 generates
its `sky130_fd_sc_hd` TT 1.8 V Liberty model from locked upstream JSON files.
Both derived Liberty files are stored below `.cache/retrosoc/pdk/` and are not
committed. SKY130 setup initializes only the locked HD library submodule;
the remaining upstream libraries are outside the SoC integration boundary.
OpenSTA timing remains IHP130-only.

The GF180 and SKY130 CI flows synth the digital core and run functional
standard-cell netlist simulation. Their generic SoC wrappers explicitly use
the locked PDK GPIO and clock cells for RTL and netlist simulation: GF180 uses
`gf180mcu_fd_io__in_c`/`gf180mcu_fd_io__bi_t` and MCU7T5V0 clock cells, while
SKY130 uses `sky130_fd_io__top_gpiov2` and HD clock cells. This integration
does not add supply, corner, filler, placement, or physical verification
collateral; physical pad-ring integration remains a technology-specific
signoff task. GF180/SKY130 PLL configurations are rejected because no
qualified crystal-pad implementation is selected. SKY130 maps the generic
Schmitt-control input to its threshold-select control and therefore does not
provide hysteresis. Verilator uses a pin-compatible local functional model
for the GF180 IO cells because the upstream model contains unsupported `rnmos`
primitives. SKY130 uses the same approach because its upstream IO model uses
unsupported switch primitives and drive strengths. Synthesis still preserves
the original PDK cell instances. GF180 netlist simulation also substitutes
pin-compatible sequential-cell models because the upstream functional models
propagate an unconnected synthesized notifier as an unknown value.
