# Synthesis Flows

This directory contains Yosys synthesis integration, configuration, and source
export tooling. `yosys/` owns the supported open-source synthesis flow;
`tools/` exports flattened source sets; `demo/` contains examples only.

Use a committed profile and run the supported flow:

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
```

Synthesis outputs are generated below `build/` and must not be committed.
Review warning and metric changes with `make check-warnings check-metrics` for
the affected profile.
