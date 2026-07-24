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
committed. OpenSTA timing remains IHP130-only.

The GF180 and SKY130 CI flows synth the digital core and run functional
standard-cell netlist simulation. Physical pad-ring integration remains a
technology-specific signoff task and is not represented by the generic SoC pad
wrappers.
