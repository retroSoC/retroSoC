# Engineering Workflow

## Supported Profiles

| Tier | Profile | Automated coverage |
| --- | --- | --- |
| Smoke | `configs/ci/ihp130.mk` | strict Verilator RTL lint, firmware, Verilator SVA compilation, Icarus assembly self-test |
| Pull request | `configs/ci/ihp130.mk` | strict Verilator RTL lint, firmware, Verilator, Icarus, Yosys, netlist Icarus, OpenSTA |
| Pull request | `configs/ci/ihp130-debug.mk` | Verilator remote-bitbang JTAG DTM, Debug Module, OpenOCD, and GDB acceptance |
| Pull request | `configs/ci/gf180.mk` | strict Verilator RTL lint, firmware, Verilator, Icarus, Yosys, netlist Icarus, OpenSTA |
| Pull request | `configs/ci/ics55.mk` | strict Verilator RTL lint, firmware, Verilator, Icarus, Yosys, netlist Icarus, OpenSTA |
| Pull request | `configs/ci/sky130.mk` | strict Verilator RTL lint, firmware, Verilator, Icarus, Yosys, netlist Icarus, OpenSTA |
| Nightly | `configs/ci/ihp130.mk` | repeated full IHP130 regression |
| Cluster | `configs/cluster/ics55.mk` | compatibility profile for site-specific ICS55 runs |

Regression Verilator firmware simulations override the profiles' manual
`bringup` default with `APP=ci_smoke`. This application verifies UART output,
archinfo APB readback, and test-status completion within the CI time budget;
`bringup` retains the full automatic application-information report for
manual runs.

OpenSTA runs a reproducible core-STA baseline for every CI PDK: IHP130 uses
`slow_1p08V_125C`, GF180 uses `ss_125C_4v50`, ICS55 uses the H7CR
`ss_1p08_125C` view, and SKY130 uses `ss_100C_1v40`.
The SDC is generated from `rtl/mini/integration/clock_reset_domains.json`, applies
the external, audio, and DVP clocks at their technology-buffer observation pins,
and groups unrelated clocks asynchronously. It intentionally excludes package,
board, pad-ring, extraction, and PLL timing, so it is a regression-quality core
analysis rather than physical signoff.

VCS flows remain cluster-only because public runners do not have the licensed
simulator. ICS55 uses the same variant layout, manifests, result JSON, warning
scanner, and cleanup rules as the other open-source CI PDKs.

## Reproducible Inputs

`config/dependencies.lock.json` is the source of truth for external Git repositories, downloaded
archives, OCI container base images, Nix inputs, and Ubuntu 22.04 toolchain bundles. Git checkouts
use full 40-character revisions. Archive downloads are accepted only after SHA-256 verification.
The Docker image uses an immutable OCI digest. The flake lock and dependency lock must agree on
each Nix input revision and NAR hash. CI actions are pinned to commit IDs.

The [development environment guide](development-environment.md) defines the Docker, Nix, and
manual entry points. All three use scripts/development_environment.py to install the same
checksum-verified open-source tools. PDK and managed-source setup deliberately remains a checkout
operation through make setup or make setup-regression, rather than a container or Nix image layer.

To update a dependency:

1. Update its revision, version, URL, and checksum in the lock.
2. Run `python3 scripts/dependency_lock.py`.
3. Run the affected setup target with `--update` directly, then run `make doctor`.
4. Run `python3 -m pytest -q` and the affected regression profile.
5. Review the generated manifest, warning delta, metrics, and SBOM before merging.

Do not reuse an old checksum with a new URL or version. The lock digest is part of every variant ID,
so changing the lock creates a new output directory without contaminating prior results.

For every downloaded archive, calculate the checksum from a fresh download of the exact URL in the
lock; never derive it from an already-installed local tool or a separately cached archive. Before
committing a toolchain lock update, install every affected tool into an empty temporary cache and
check its reported version. For application archives, run the affected setup script with `--update`
against an empty cache. This is the same checksum and safe-extraction path exercised by CI:

```sh
python3 scripts/install_toolchain.py \
  --lock config/dependencies.lock.json --platform ubuntu-22.04 \
  --cache /tmp/retrosoc-toolchain-verify \
  --tool verilator --tool sv2v --tool iverilog \
  --tool yosys --tool opensta --tool riscv_gnu
```

## MISRA Governance

Self-owned `crt/` and `app/` C/header code follows the
[MISRA C:2012 Amendment 2 policy](misra-c-2012.md). The policy defines its
scope, exclusions, Mandatory/Required/Advisory handling, partial automated
enforcement, and required deviation process. The executable exclusion list in
`quality/embedded_c_policy.json` remains authoritative.

This repository does not claim complete MISRA certification from its current
format, policy, compiler-warning, unit-test, or regression gates. Required-rule
deviations must be reviewed and recorded in
[`quality/misra/deviations.md`](../quality/misra/deviations.md) with the
affected implementation change.

## Build Layout

The variant identifier is the profile name, the local creation timestamp, and a hash over effective
hardware/software build settings and the dependency lock. The timestamp has the
`YYYY-MM-DD-HH-MM` format and does not alter the hash. Runtime-only settings such as wave capture
and timeout do not alter the hash either. `BUILD_TIMESTAMP` defaults to the current local minute;
set it explicitly when separate Make commands must share one variant. The regression runner exports
one timestamp to all of its child Make commands.

```text
build/<variant>/
  generated/mpw/<simulator>/
  generated/pin_map/
  sw/
  sim/<simulator>/
  formal/<proof>/
  syn/yosys/
  sta/opensta/
  meta/manifest.json
  meta/warnings.json
  meta/metrics.json
```

Generated filelists and MPW output are flow-local. Make depfiles track expanded RTL sources and
included headers. The shared MPW generator is protected by a file lock. Default tool parallelism is
capped at 16 and can be set with `JOBS=<n>` or `MAX_JOBS=<n>`.

## Result Policy

Every EDA and simulation flow command is run through `scripts/run_flow.py`, which streams a log and writes a
result JSON containing the command, timestamps, duration, exit code, and status. Automated firmware signals a
terminal result by writing SYSCTRL `TEST_STATUS` at offset `0x84`: bit 31 is `VALID`, bit 0 is `PASS`, and
bits 15:8 are an implementation-defined result code. The first valid full-word write after reset is sticky.
The testbench and Verilator harness translate the valid/pass bits into `SIM_TEST_PASS` or `SIM_TEST_FAIL`;
the Verilator harness additionally prints the result code.
A simulation passes only when its command succeeds, the pass marker is present, and no fatal, failure, or
timeout marker is present. UART startup text is diagnostic only; it is not a verdict. The local
`netsim-boot` shortcut remains explicitly scoped to stopping Icarus assembly netlist simulation at
`Hello retroSoC!`; CI uses the terminal software status. Icarus regressions use the assembly self-test as
`retrosoc_asm`, while the normal `retrosoc_fw` image remains available for firmware size tracking and
Verilator regressions.

## Formal Protocol Proofs

`make CONFIG=configs/ci/ihp130.mk formal` proves selected
protocol invariants with SymbiYosys, Yosys, `sv2v`, and Bitwuzla. The current
targets are `bus`, `rib_adapter`, `rib2apb`, `sysctrl`, `pll_rcu`, and
`gpio_user`; each uses
the SBY `prove` task for bounded model checking and k-induction, plus a
`cover` task, at depth 20. `sysctrl` checks register side effects, sticky terminal-test status, PLL request
handling, and fault reporting. `pll_rcu` checks the clock-switch controller
state machine. `gpio_user` checks fixed user-GPIO ownership, lock, handoff,
and mux safety. `rib_adapter` checks both single-word compatibility adapters
under backpressure. Direct Common utility proofs, including `spill_register`,
are maintained in the Common repository.
`FORMAL_DEPTH` and `FORMAL_TIMEOUT` set the proof bound and per-task
wall-clock limit. Use `make CONFIG=<profile> formal-doctor` before a local
proof to verify that the required tools are available.

The locked Bitwuzla 0.9.1 CLI uses `--lang smt2`, while the selected Yosys
version invokes legacy Bitwuzla options. `scripts/bitwuzla_smt2.py` is the
single compatibility adapter used by SBY; it translates only solver startup
arguments and does not modify the generated SMT2 model or proof properties.

Proof environments instantiate the production protocol RTL and the shared
ClusterIP interfaces, registers, and utility cells. The generated conversion,
SBY configuration, SMT2 model, logs, traces, task status, and structured
verdict are stored below
`build/<variant>/formal/<proof>/` and `build/<variant>/meta/formal.json`.
The IHP130 smoke workflow enables this target; the full PDK regressions do not
repeat PDK-independent protocol proofs. The reusable regression workflow runs
the target only when its `formal_checks` input is enabled and its locked
toolset provides SBY and Bitwuzla.

The `pll_rcu` proof uses one formal clock for its system and external-clock
inputs to verify the controller protocol independently of analogue clock
behavior. It is not asynchronous CDC/RDC signoff; implementation timing,
clock-tree checks, and the technology PLL model remain separate signoff work.

`make check-warnings` normalizes tool messages and compares them with
`quality/warnings/<profile>/<tool>.json`. New signatures and increased counts make the standalone
command fail; resolved warnings are reported but do not fail. Regression suites run warning and
metric checks as non-blocking observations so their JSON reports are generated and uploaded even
when a baseline delta is present. Compilation, simulation, synthesis, and STA failures remain
blocking. To refresh one baseline after review:

```sh
python3 scripts/analyze_warnings.py baseline \
  --root . --profile ihp130 --tool verilator \
  --log build/<variant>/sim/verilator/verilating.log \
  --output quality/warnings/ihp130/verilator.json
```

## Metrics Promotion

`make check-metrics` currently uses `quality/metrics/policy.json` in `observe` mode. Regression
artifacts retain the metrics from every completed regression run. After ten successful `main` runs for the same
profile and locked tools, create the median baseline:

```sh
python3 scripts/metrics.py baseline \
  --input run-01/metrics.json --input run-02/metrics.json \
  --input run-03/metrics.json --input run-04/metrics.json \
  --input run-05/metrics.json --input run-06/metrics.json \
  --input run-07/metrics.json --input run-08/metrics.json \
  --input run-09/metrics.json --input run-10/metrics.json \
  --output quality/metrics/baseline.json
```

Review the medians, commit the baseline, then change policy mode to `gate`. The committed future
limits are 5% firmware growth, 3% top area/cell growth, and 0.05 ns WNS regression. TNS is recorded
for diagnosis but is initially non-blocking.

## CI And Releases

`quality.yml` validates C, Makefile, and self-owned RTL formatting as well as Python, YAML, GitHub
Actions, the dependency lock, and script tests. `regression-smoke.yml` provides fast IHP130 feedback;
the four full PDK regression workflows remain required PR coverage and do not repeat the format checks.
`nightly.yml` repeats the fixed IHP130 architecture. Source dependencies, locked tool archives, and Verilator `ccache` use
separate cache keys.

Tags matching `v*` run `release.yml`. The release contains a flattened SystemVerilog export, a source
tarball, build manifest, dependency lock, CycloneDX SBOM, and `SHA256SUMS`. `make package` creates the
same files locally below `dist/<variant>/`.
