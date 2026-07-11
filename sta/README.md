# Static Timing Analysis

This directory contains OpenSTA constraints, Tcl setup, and Make integration
for retroSoC timing analysis. The selected profile and synthesized netlist
define the actual timing context.

Run synthesis before timing analysis, then invoke the supported OpenSTA flow:

```sh
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk STA=OPENSTA sta
```

Review WNS/TNS and warning changes through the generated reports and quality
checks. Timing results are PDK/tool/profile dependent; do not compare unrelated
variants as a gate.
