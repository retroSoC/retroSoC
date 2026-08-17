# Synthesis Flows

This directory contains Yosys synthesis integration, configuration, and source
export tooling. `yosys/` owns the supported open-source synthesis flow;
`tools/` exports flattened source sets.

Use a committed profile and run the supported flow:

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
```

`SYNTH_RECIPE` selects the ABC mapping recipe without changing the variant hash:

- `balanced` (default) writes `build/<variant>/syn/yosys/`
- `area` writes `build/<variant>/syn/yosys-area/`
- `speed` writes `build/<variant>/syn/yosys-speed/`

STA, netlist simulation, warning analysis, and metrics consume the default
`syn/yosys/` slot. Nightly IHP130 regression also runs the `area` and `speed`
recipes as synth-only extra jobs.

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=area synth
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=speed synth
```

The default ABC target period is derived from the `external` STA period in
`rtl/mini/integration/clock_reset_domains.json`. Override it with
`YOSYS_TARGET_PERIOD_PS=<ps>` when needed.

Synthesis outputs are generated below `build/` and must not be committed.
Review warning and metric changes with `make check-warnings check-metrics` for
the affected profile.
