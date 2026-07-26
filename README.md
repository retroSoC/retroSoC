# retroSoC

[![quality](https://github.com/retroSoC/retroSoC/actions/workflows/quality.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/quality.yml)
[![IHP130 regression](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ihp130.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ihp130.yml)
[![GF180 regression](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml)
[![SKY130 regression](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml)
[![nightly](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml)

retroSoC is a fully open-source RISC-V SoC project. The repository brings together
SystemVerilog RTL, a freestanding embedded C SDK and applications, simulation, synthesis,
static timing analysis, reproducible dependencies, and release packaging. It is licensed
under the [Mulan Permissive Software License, Version 2](LICENSE).

## Highlights

- A fixed architecture with a Hazard3 management core by default (PicoRV32 is
  an explicit build option) and software-selected
  user-core and user-IP extension slots.
- Configurable GF180, SKY130, IHP130, and ICS55 implementation targets. GF180, SKY130,
  and IHP130 have open-source CI coverage; ICS55 remains a configured cluster target.
- A memory-mapped peripheral subsystem with GPIO, UART, timers, PWM, I2C, I2S, PS2,
  1-Wire, SPI/QSPI, SDIO, PSRAM/OPI-PSRAM, SDRAM, DMA, LCD, RTC, watchdog, RNG, and CRC
  support. Available interfaces depend on the selected SoC configuration.
- A standalone RISC-V runtime, HAL, board support, middleware, and `bringup` and `shell`
  applications.
- Open-source behavioral simulation with Icarus Verilog and Verilator, synthesis with
  Yosys, netlist simulation with Icarus Verilog, and timing analysis with OpenSTA.
- Checksum-verified dependency and toolchain locks, structured flow results, warning
  baselines, metrics collection, SBOM generation, and checksummed release packages.

## Repository Layout

| Path | Contents |
| --- | --- |
| [`rtl/`](rtl) | SoC RTL, CPU integration, peripherals, interfaces, testbenches, and technology wrappers. |
| [`crt/`](crt) | Freestanding RISC-V startup code, linker scripts, runtime library, core services, and HAL headers. |
| [`app/`](app) | Applications, board support, media, middleware, networking, ports, and benchmarks. |
| [`configs/`](configs) | Versioned build profiles for CI, nightly, and cluster flows. |
| [`pdk/`](pdk) | PDK setup entry points and technology-specific integration. |
| [`syn/`](syn) and [`sta/`](sta) | Synthesis and static timing analysis flows. |
| [`scripts/`](scripts) and [`quality/`](quality) | Build helpers, regression orchestration, checks, warning baselines, and metric policy. |
| [`.github/`](.github) | GitHub automation, Dependabot configuration, and CI/release workflows; see [`GUIDE.md`](.github/GUIDE.md). |
| [`docs/`](docs) | Engineering workflow and release-process documentation. |

## Supported Configurations

The committed profiles are the supported starting points. They select an ISA,
PDK, application, linker layout, and optional features as one reproducible
configuration. The user-extension fabric is fixed; `CORE` selects the management
core and defaults to `HAZARD3`.

| Profile | ISA | Application | Coverage |
| --- | --- | --- | --- |
| [`configs/ci/ihp130.mk`](configs/ci/ihp130.mk) | RV32IM | `bringup` | Pull-request open-source regression: firmware, Verilator, Icarus, Yosys, Icarus netlist simulation, and OpenSTA. |
| [`configs/ci/gf180.mk`](configs/ci/gf180.mk) | RV32IM | `bringup` | Pull-request firmware, RTL simulation, Yosys, and Icarus netlist coverage. |
| [`configs/ci/sky130.mk`](configs/ci/sky130.mk) | RV32IM | `bringup` | Pull-request firmware, RTL simulation, Yosys, and Icarus netlist coverage. |
| [`configs/ci/ihp130-shell.mk`](configs/ci/ihp130-shell.mk) | RV32IM | `shell` | Pull-request firmware build with CSR support enabled. |
| [`configs/cluster/ics55.mk`](configs/cluster/ics55.mk) | RV32IM | `bringup` | Cluster-only configuration; requires the site PDK and licensed-tool environment. |

## Prerequisites

The prebuilt, locked toolchain bundles target Ubuntu 22.04. Install Python 3, GNU Make, a host
C compiler, `clang-format-14`, a RISC-V bare-metal GNU toolchain, and the tools required by the
flow you intend to run: Icarus Verilog, Verilator, sv2v, Yosys, and OpenSTA. Source formatting
also requires `mbake` 1.4.6 and the locked Verible formatter. The CI environment installs the
exact versions from [`config/dependencies.lock.json`](config/dependencies.lock.json). Local flow
tools must be available on `PATH` before running `make doctor`; the three formatters must be
available before running `make format-check`.

Install the Python build dependencies once per environment:

```sh
python3 -m pip install --requirement requirements/build.txt
```

The lock file also pins external RTL, PDK, benchmark, and application sources. Their setup
scripts verify full Git revisions or SHA-256 checksums before use. See the
[engineering workflow](docs/engineering.md#reproducible-inputs) for the locked-tool installer
and dependency update procedure.

## Quick Start

Start with the CI-verified IHP130 `bringup` profile. `setup` retrieves the pinned
source dependencies, and `doctor` reports any missing local executables or setup inputs.

```sh
make CONFIG=configs/ci/ihp130.mk setup
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG doctor
make CONFIG=configs/ci/ihp130.mk firmware
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG sim
```

Select the interactive shell application without editing source files:

```sh
make CONFIG=configs/ci/ihp130-shell.mk firmware
```

## Common Flows

All commands use a committed profile. `make config` prints the effective configuration and
variant identifier; `make help` lists all available targets. Netlist simulation and timing
analysis consume the Yosys netlist, so run the synthesis command first. The CI-proven netlist
regression uses the assembly self-test image:

Verilator simulations run for 180 seconds by default. Set `SOC_SIM_TIME` explicitly only when
an exploratory local run needs a different limit.

```sh
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG RTL_SIM_TIMEOUT=5200000 sim-asm
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG \
  SIM_FIRMWARE_NAME=retrosoc_asm \
  SIM_SUCCESS_MARKER='Mem wr/rd test success' \
  RTL_SIM_TIMEOUT=5200000 netsim
```

| Goal | Command |
| --- | --- |
| Icarus behavioral simulation | `make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG sim` |
| Verilator behavioral simulation | `make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR sim` |
| Assembly self-test with Icarus | `make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG RTL_SIM_TIMEOUT=5200000 sim-asm` |
| Yosys synthesis | `make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth` |
| Icarus netlist simulation after synthesis | `make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG netsim` |
| OpenSTA core timing analysis after synthesis | `make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta` |
| Strict Verilator RTL lint | `make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR HAVE_SVA=YES check-rtl-lint` |
| IHP130 fast smoke suite | `make regress-smoke` |
| Pull-request regression suite | `make regress-pr` |
| Nightly regression suite | `make regress-nightly` |
| Format C, Makefile, and RTL sources | `make format` |
| Check C, Makefile, and RTL formatting | `make format-check` |
| Script and policy checks | `make sw-policy-check sw-host-test` |

`make regress-smoke` builds the IHP130 firmware, compiles the Verilator SVA
configuration, and runs the Icarus assembly self-test. It runs strict RTL lint
before those flows and omits synthesis,
timing, and netlist simulation for fast feedback. `make regress-pr` runs the
supported IHP130, GF180, and SKY130 PR matrices in sequence, including
slow-corner OpenSTA core timing analysis for each PDK.

Build outputs are isolated below `build/<profile>-<YYYY-MM-DD-HH-MM>-<config-hash>/`. Each variant keeps its
firmware, generated sources, simulator output, synthesis and timing reports, manifest, warning
analysis, and metrics separate from other configurations. Use `make clean` to remove the
selected backend, `make clean-all` to remove all build output, and `make purge-cache` to remove
download and compiler caches.

`BUILD_TIMESTAMP` defaults to the local build-start time. Set it explicitly when separate Make
commands must reuse one variant:

```sh
export BUILD_TIMESTAMP=2026-07-21-10-39
make CONFIG=configs/ci/ihp130.mk firmware
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG sim
```

## Reproducibility And CI

[`config/dependencies.lock.json`](config/dependencies.lock.json) is the source of truth for
external repositories, application archives, and Ubuntu 22.04 toolchain bundles. The lock digest
is part of each build variant, and every download is checksum verified. GitHub Actions pins its
actions by commit, validates the lock and engineering scripts, and runs pull-request and nightly
regression matrices.

Every EDA command is recorded with a log and a machine-readable result JSON. The regression
policy checks warning deltas against committed baselines and collects metrics for later gate
promotion. Tags matching `v*` produce a flattened SystemVerilog export, source archive, build
manifest, dependency lock, CycloneDX SBOM, and `SHA256SUMS`. Run `make package` to create the
same local deliverables under `dist/<variant>/`.

See [`docs/engineering.md`](docs/engineering.md) for supported-flow details, artifact layout,
warning and metric policy, CI behavior, and release contents.

## Contributing And Security

- Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before submitting changes.
- Report vulnerabilities according to [`Security.md`](Security.md).
- Review retained third-party notices in [`NOTICE`](NOTICE) and
  [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md).
- The project is distributed under [Mulan PSL v2](LICENSE).
