# Static Timing Analysis

This directory contains OpenSTA constraints, Tcl setup, and Make integration
for retroSoC timing analysis. The selected profile and synthesized netlist
define the actual timing context.

Run synthesis before timing analysis, then invoke the supported OpenSTA flow.
All CI PDK profiles are supported:

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta
make CONFIG=configs/ci/gf180.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/gf180.mk STA=OPENSTA sta
make CONFIG=configs/ci/sky130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/sky130.mk STA=OPENSTA sta
```

The generated SDC derives clock and reset objects from
`rtl/mini/integration/clock_reset_domains.json`. It analyzes internal core
paths at the PDK slow corner and treats the external, audio, and DVP clocks as
separate asynchronous groups. Review WNS/TNS and warning changes through the
generated reports and quality checks. This flow excludes board, pad-ring,
extraction, and PLL timing; it is not a physical signoff constraint set.
