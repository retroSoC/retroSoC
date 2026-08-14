# Smoke Implementation Flows

This directory contains the reproducible synthesis and static-timing source
flows used by smoke and regression coverage. `syn/` owns Yosys synthesis and
source export; `sta/` owns OpenSTA constraints and timing integration.

Generated netlists, reports, and timing artifacts remain below the selected
`build/<variant>/` directory. Run the flows through the root Makefile with a
committed profile; do not write generated output into this source tree.
