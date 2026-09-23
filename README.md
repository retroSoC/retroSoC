# retroSoC

An open-source RISC-V SoC platform, from SystemVerilog RTL and firmware to reproducible verification and release artifacts.

[![License](https://img.shields.io/badge/License-Mulan%20PSL%20v2-d4a72c?style=flat-square&labelColor=3b301a&logo=github&logoColor=f6d365)](LICENSE)
[![RTL](https://img.shields.io/badge/RTL-SystemVerilog-d4a72c?style=flat-square&labelColor=3b301a&logo=devbox&logoColor=f6d365)](rtl)
[![ISA](https://img.shields.io/badge/ISA-RV32IMAC+RV32GC-d4a72c?style=flat-square&labelColor=3b301a&logo=riscv&logoColor=f6d365)](configs/ci/ihp130.mk)
[![RISC-V GCC](https://img.shields.io/badge/RISC--V%20GCC-2025.05.01-d4a72c?style=flat-square&labelColor=3b301a&logo=c&logoColor=f6d365)](dependencies/dependencies.lock.json)<br>
[![IHP130 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-ihp130.yml?branch=main&style=flat-square&label=IHP130&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ihp130.yml)
[![GF180 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-gf180.yml?branch=main&style=flat-square&label=GF180&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml)
[![ICS55 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-ics55.yml?branch=main&style=flat-square&label=ICS55&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ics55.yml)
[![SKY130 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-sky130.yml?branch=main&style=flat-square&label=SKY130&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml)<br>
[![Quality](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/quality.yml?branch=main&style=flat-square&label=Quality&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/quality.yml)
[![Nightly](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/nightly.yml?branch=main&style=flat-square&label=Nightly&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml)
[![Nix/Docker](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/development-environment.yml?branch=main&style=flat-square&label=Nix%20Docker&labelColor=3b301a&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/development-environment.yml?query=branch%3Amain)



[Overview](#platform-overview) · [Quick start](#quick-start) · [Configurations](#configurations-and-common-flows) · [Documentation](#documentation-and-repository) · [Validation](#validation-and-reproducibility) · [Contributing](#contributing)

## Platform overview

**Mini is the active implementation.** The product configuration combines a
low-power (LP) management hart and a high-performance (HP) application hart.
The separate Mini MPW profile retains the legacy selectable-core integration.
[Tiny, Std, and Pro](docs/soc-family-positioning.md) are product-roadmap targets,
not additional supported build profiles.

| Area | Mini platform |
| --- | --- |
| Compute | Hazard3 LP management hart; generated dual-issue VexiiRiscv HP application hart. Baseline profiles compile LP firmware for RV32IM and select an RV32IMAFDC HP core with Zicbom cache maintenance. |
| Memory and interconnect | Native AXI4 data plane, APB4 control, configurable on-chip SRAM, SDRAM, PSRAM/OPI-PSRAM, and XPI flash integration. |
| Control and I/O | GPIO, timers, UART, I2C, I2S, PWM, RTC, watchdog, storage interfaces, DMA, interrupt routing, and fixed EXT-L/EXT-H extension slots. |
| Software | Freestanding C runtime and HAL, board support, diagnostic and shell applications, CoreMark, and HP boot/bundle tooling. |
| Development | Locked toolchains and dependencies; Icarus Verilog and Verilator simulation, Yosys synthesis, OpenSTA timing analysis, and structured verification artifacts. |

The accelerator integrations include:

- **[APU](docs/ip/apu.md)** — LP-loaded audio microcode, WAV/PCM and native FLAC
  decoding, I2S streaming, and optional keyword spotting (KWS). MP3 decoding
  is deferred.
- **[NPU](docs/ip/npu.md)** — an INT8 inference engine with 64 dense MAC lanes,
  64 KiB of private banked SRAM, offline compilation, and bare-metal deployment.
- **[GA2D](docs/ip/ga2d.md)** — 2D fill, copy, pixel conversion, and alpha
  blending with opaque output and A8 foreground masks; no scaler or Linux driver.
- **[JPEG](docs/ip/jpeg.md) and [crypto](docs/ip/crypto.md)** — dedicated image
  and cryptographic blocks with their own interface and verification contracts.

Capabilities depend on the selected profile and each IP's implementation and
qualification status. Linux boot and performance qualification remain separate
from baseline CI coverage. The integrated RNG uses an unqualified deterministic
source for diagnostics; it does not provide production entropy. See the
[architecture](docs/lp-hp-architecture.md) and [engineering guide](docs/engineering.md)
for these boundaries.

## Quick start

### 1. Prepare the development environment

Use the [development environment guide](docs/development-environment.md) to
prepare the locked tools before building. The native environment targets
Linux x86_64. Docker supports a Linux/amd64 environment, including emulation
on Apple Silicon; Nix support is Linux x86_64 only.

| Environment | Setup instructions |
| --- | --- |
| Docker | [Build and enter the development image](docs/development-environment.md#docker). |
| Nix | [Open the repository development shell](docs/development-environment.md#nix). |
| Manual Ubuntu 22.04 | [Bootstrap and activate the locked tools](docs/development-environment.md#shared-bootstrap). |

For manual Ubuntu installs, first install the host packages from the
`apt-get install` list in [docker/Dockerfile](docker/Dockerfile), including
Java 17. The bootstrap checks these tools but does not install OS packages.

Tools and checkout inputs are separate: the environment provides compilers and
EDA tools, while `make setup` retrieves the profile's managed sources, PDK,
and application inputs. Tool versions come from the
[dependency lock](dependencies/dependencies.lock.json).

### 2. Build and simulate Mini

From the repository root, inside the prepared environment:

```sh
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG setup
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG doctor
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG firmware sim
```

This runs the IHP130 profile's manual `bringup` application. It is not the
exact PR regression: automated Verilator runs select `ci_smoke`, while Icarus
regressions use the assembly self-test. See
[supported flows](docs/engineering.md#supported-profiles) for the overrides.

Keep `firmware sim` in the same Make invocation so both use one build variant.
Outputs live under `build/<profile>-<YYYY-MM-DD-HH-MM>-<config-hash>/`.
Check the flow logs and result JSON; UART startup text alone is not a pass.

## Configurations and common flows

Start from a [committed profile](configs/README.md). These are selected entry
points, not the complete profile or application inventory.

| Profile | Purpose |
| --- | --- |
| [IHP130 Mini](configs/ci/ihp130.mk) | Manual bring-up with 32 KiB macro-backed SRAM. |
| [GF180](configs/ci/gf180.mk) / [SKY130](configs/ci/sky130.mk) | Alternative PDK profiles with 32 KiB macro-backed SRAM. |
| [ICS55](configs/ci/ics55.mk) | Regression-compatible profile with SRAM and PLL disabled. |
| [Interactive shell](configs/ci/ihp130-shell.mk) | Shell firmware with CSR support enabled. |
| [Hazard3 debug](configs/ci/ihp130-debug.mk) | JTAG acceptance using Verilator, OpenOCD, and GDB. |
| [HP Linux](configs/ci/ihp130-hp.mk) | HP image/bundle flow; outside the supported PR matrix. |
| [APU LP/HP](configs/ci/ihp130-apu.mk) | Audio and KWS evidence flow with ownership handoff to HP. |
| [CoreMark](configs/benchmark/ihp130-hazard3-coremark.mk) | Fixed LP SRAM benchmark with the product HP core present. |
| [Mini MPW](configs/cluster/mini-mpw.mk) | Legacy C0-C3/user-IP compatibility, separate from the product ABI. |

After the corresponding setup, use these common commands:

```sh
# Build the interactive shell firmware
make CONFIG=configs/ci/ihp130-shell.mk firmware

# Inspect the effective configuration and available targets
make CONFIG=configs/ci/ihp130.mk config
make help

# Check source formatting and embedded C policy/host tests
make format-check
make sw-policy-check sw-host-test
```

| Validation flow | Command |
| --- | --- |
| IHP130 smoke: RTL lint, firmware, SVA compilation, Icarus self-test | `make regress-smoke` |
| IHP130 behavioral flows, including debug acceptance | `make regress-rtl` |
| Full local PR matrix across four PDKs | `make regress-pr` |
| Extended local regression | `make regress-nightly` |

Prepare the multi-PDK inputs with `make setup-regression` before the full PR
matrix. Profile setup does not install every optional reference corpus; follow
any additional prerequisites in the affected IP or test guide. For debugging,
benchmarks, and HP software, use the dedicated guides linked below.

<details>
<summary>Advanced local flows: netlist simulation and licensed VCS</summary>

These flows require the relevant synthesis/timing tools and PDK inputs, or a
licensed VCS environment. Keep one timestamp across dependent commands:

```sh
export BUILD_TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG RTL_SIM_TIMEOUT=5200000 sim-asm
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG \
  SIM_FIRMWARE_NAME=retrosoc_asm RTL_SIM_TIMEOUT=5200000 netsim
make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta
```

VCS defaults to `bsub -Is` for licensed cluster runs. Disable LSF for a licensed
local run, or set `VCS_RUNNER` to the site's wrapper:

```sh
make CONFIG=configs/ci/ihp130.mk SIMU=VCS VCS_USE_LSF=NO firmware sim
```

After this sequence, `unset BUILD_TIMESTAMP` to restore automatic timestamps.
See [build layout](docs/engineering.md#build-layout) and
[result policy](docs/engineering.md#result-policy) for artifacts and verdicts.

</details>

## Documentation and repository

| Start here | Guides |
| --- | --- |
| Understand the platform | [LP/HP architecture](docs/lp-hp-architecture.md), [IP specifications](docs/ip/README.md), [datasheet workflow](publications/README.md). |
| Develop firmware | [SDK](crt/README.md), [applications](app/README.md), [HP software](app/ports/linux/README.md). |
| Debug and measure | [Hazard3 debug](docs/hazard3-debug.md), [CoreMark](docs/coremark.md), [engineering workflow](docs/engineering.md). |
| Change RTL or tooling | [RTL conventions](docs/rtl-coding-style.md), [MISRA policy](docs/misra-c-2012.md), [agent contract](AGENTS.md). |
| Explore further | [Documentation index](docs/README.md), [build profiles](configs/README.md), [contribution process](CONTRIBUTING.md). |

| Directory | Contents |
| --- | --- |
| [rtl/](rtl/README.md) | SoC integration, IP, interfaces, simulation, and technology wrappers. |
| [crt/](crt/README.md) / [app/](app/README.md) | Freestanding SDK, firmware applications, and software integrations. |
| [configs/](configs/README.md) / [dependencies/](dependencies/README.md) | Reproducible profiles and locked external inputs. |
| [tests/](tests/README.md) / [scripts/](scripts/README.md) / [quality/](quality/README.md) | Verification, build helpers, and executable quality policy. |
| [physical/](physical/README.md) / [fpga/](fpga/README.md) | Physical-design flows and FPGA integration. |
| [docs/](docs/README.md) / [publications/](publications/README.md) | Engineering specifications and manually built datasheets. |
| [.github/](.github/GUIDE.md) / [docker/](docker/README.md) | Automation and the container development environment. |

## Validation and reproducibility

The status badges above track **`main`**, not the current checkout. Other runs:
[GF180](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml),
[ICS55](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ics55.yml),
[SKY130](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml),
and [nightly](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml).

The quality gate checks source policy and runs script/RTL fixture tests.
Hosted SoC regression and development-environment workflows use
`--behavioral-only`: they do not run the full SoC synthesis, netlist simulation,
or OpenSTA stages. Local full-flow commands retain those stages. Neither CI
status nor core timing analysis establishes physical or silicon signoff.

Dependencies and tool archives are pinned by revision or checksum. Each build
variant records its configuration and lock digest, and EDA flows produce logs
and structured results. Warning and metric policies remain defined by the
[engineering guide](docs/engineering.md); no performance claim is implied by
a badge. Maintainer-published `v*` tags trigger
[release packaging](docs/engineering.md#ci-and-releases), including the source
archive, manifest, dependency lock, SBOM, and checksums.

## Contributing

Start with the [contribution guide](CONTRIBUTING.md), follow the
[Git workflow](docs/git-workflow.md), and use the
[PR template](.github/pull_request_template.md). Ordinary contributions target
`dev` and preserve meaningful commits through merge-commit integration.
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

retroSoC is licensed under [Mulan PSL v2](LICENSE). Third-party terms are
recorded in [NOTICE](NOTICE), [ATTRIBUTIONS](ATTRIBUTIONS.md), and
[licenses/](licenses/README.md). See the existing [security policy](Security.md)
for its current reporting information.

Thanks to everyone contributing to retroSoC.

[![retroSoC contributors](https://contrib.rocks/image?repo=retroSoC/retroSoC)](https://github.com/retroSoC/retroSoC/graphs/contributors)
