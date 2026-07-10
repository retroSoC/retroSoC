# retroSoC

[![quality](https://github.com/retroSoC/retroSoC/actions/workflows/quality.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/quality.yml)
[![regression](https://github.com/retroSoC/retroSoC/actions/workflows/regression.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/regression.yml)
[![nightly](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml)

## Build Automation

The build uses committed configuration profiles and a single dependency lock. Start with the
verified HAZARD3 profile:

```sh
python3 -m pip install --requirement requirements/build.txt
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk setup
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk SIMU=IVERILOG doctor
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk firmware
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk SIMU=IVERILOG RTL_SIM_TIMEOUT=5200000 sim-asm
```

Other open-source flows use the same profile:

```sh
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk SIMU=VERILATOR sim
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk STA=OPENSTA sta
```

`make help` lists targets, while `make config` prints the effective configuration and its variant
identifier. Outputs live below `build/<profile>-<config-hash>/`; firmware, simulator, synthesis,
STA, reports, and manifests are isolated inside that directory. `make clean` removes the selected
backend, `make clean-all` removes all build outputs, and `make purge-cache` explicitly removes
download and compiler caches.

Dependency sources and binary tool archives are pinned in
[`config/dependencies.lock.json`](config/dependencies.lock.json). Downloads are checksum verified,
and every flow writes a machine-readable manifest and result records. See
[`docs/engineering.md`](docs/engineering.md) for CI coverage, warning baselines, metrics promotion,
release packaging, and cluster-only flows.
