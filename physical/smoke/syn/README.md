# Synthesis Flows

This directory contains Yosys synthesis integration, configuration, and source
export tooling. `yosys/` owns the supported open-source synthesis flow;
`tools/` exports flattened source sets.

Use a committed profile and run the supported flow:

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
```

`SYNTH_RECIPE` selects the ABC mapping recipe without changing the variant hash.
The recipe also selects the synthesis-derived output roots so timing, netlist
simulation, and metrics cannot accidentally consume the `balanced` netlist:

- `balanced` (default): `syn/yosys/`, `sta/opensta/`, `sim/<tool>/netl/`, and `meta/metrics.json`
- `area`: `syn/yosys-area/`, `sta/opensta-area/`, `sim/<tool>/netl-area/`, and `meta/metrics-area.json`
- `speed`: `syn/yosys-speed/`, `sta/opensta-speed/`, `sim/<tool>/netl-speed/`, and `meta/metrics-speed.json`

`balanced` remains the PR and default CI recipe. Nightly IHP130 runs `area`
and `speed` through synthesis, OpenSTA, and metrics; their long netlist
simulation is available on demand but is not part of nightly-extra.

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=area synth
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=speed synth

make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=area STA=OPENSTA sta
make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=area metrics
make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=area SIMU=IVERILOG netsim
```

Replace `area` with `speed` for the corresponding recipe. Run all three
recipes with the same commit, PDK, `BUILD_TIMESTAMP`, and
`YOSYS_TARGET_PERIOD_PS` when collecting a comparable QoR baseline.

Compare top area, cell count, WNS/TNS, synthesis and STA duration, warning
signatures, and the netlist simulation verdict. Area is an area-first mapping
recipe and speed is a timing-first exploration recipe; neither is promoted to
the default solely from one area or timing result. Metrics remain in observe
mode until the documented baseline review is complete.

The default ABC target period is derived from the `external` STA period in
`rtl/mini/integration/clock_reset_domains.json`. Override it with
`YOSYS_TARGET_PERIOD_PS=<ps>` when needed.

Synthesis outputs are generated below `build/` and must not be committed.
Review warning and metric changes with `make check-warnings check-metrics` for
the affected profile. `make metrics` writes the recipe-specific file listed
above; `make check-metrics` checks that same file.
