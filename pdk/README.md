# Managed Process Design Kits

This directory is the integration root for process design kits, technology
libraries, SRAM/PLL collateral, and related setup scripts. Most child trees
are managed vendor or upstream dependencies rather than ordinary project
source.

Use the dependency lock and PDK setup targets to acquire or update managed
inputs. Do not reformat, patch, or delete vendor content as part of unrelated
work. PDK changes require the affected synthesis, timing, physical-design, or
FPGA validation flow and the ownership review defined by `.github/CODEOWNERS`.
