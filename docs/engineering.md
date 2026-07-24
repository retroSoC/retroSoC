# Engineering Workflow

## Supported Profiles

| Tier | Profile | Automated coverage |
| --- | --- | --- |
| Pull request | `configs/ci/hazard3-rv32im-ihp130.mk` | firmware, Verilator, Icarus, Yosys, netlist Icarus, OpenSTA |
| Pull request | `configs/ci/hazard3-rv32im-gf180.mk` | firmware, Verilator, Icarus, Yosys, netlist Icarus |
| Pull request | `configs/ci/hazard3-rv32im-sky130.mk` | firmware, Verilator, Icarus, Yosys, netlist Icarus |
| Pull request | `configs/ci/mdd-rv32im-ihp130.mk` | firmware and Verilator |
| Nightly | `configs/nightly/picorv32-rv32im-ihp130.mk` | firmware, Verilator, and Icarus |
| Cluster | `configs/cluster/hazard3-ics55.mk` | configuration only; run with site PDK/tool access |

OpenSTA timing signoff remains IHP130-only. GF180 and SKY130 use their TT standard-cell libraries
for synthesis and functional netlist simulation, but do not publish an STA result until their
corner, SDC, and frequency policy have been independently qualified.

VCS and ICS55 flows remain cluster-only because public runners do not have the licensed simulator or
the validated site environment. They use the same variant layout, manifests, result JSON, warning
scanner, and cleanup rules.

## Reproducible Inputs

`config/dependencies.lock.json` is the source of truth for external Git repositories, downloaded
archives, and Ubuntu 22.04 toolchain bundles. Git checkouts use full 40-character revisions. Archive
downloads are accepted only after SHA-256 verification. CI actions are pinned to commit IDs.

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
result JSON containing the command, timestamps, duration, exit code, and status. A simulation passes
only when the command succeeds, its log contains the firmware startup marker, and no fatal/failure
marker is present. Icarus regressions use the assembly self-test as `retrosoc_asm`, while the normal
`retrosoc_fw` image remains available for firmware size tracking and Verilator regressions.

`make check-warnings` normalizes tool messages and compares them with
`quality/warnings/<profile>/<tool>.json`. New signatures and increased counts fail; resolved warnings
are reported but do not fail. To refresh one baseline after review:

```sh
python3 scripts/analyze_warnings.py baseline \
  --root . --profile hazard3-rv32im-ihp130 --tool verilator \
  --log build/<variant>/sim/verilator/verilating.log \
  --output quality/warnings/hazard3-rv32im-ihp130/verilator.json
```

## Metrics Promotion

`make check-metrics` currently uses `quality/metrics/policy.json` in `observe` mode. Regression
artifacts retain the metrics from each successful run. After ten successful `main` runs for the same
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
Actions, the dependency lock, and script tests. `regression.yml` runs verified configurations on pull
requests and main branches without repeating the format checks. `nightly.yml` adds PICORV32. Source
dependencies, locked tool archives, and Verilator `ccache` use separate cache keys.

Tags matching `v*` run `release.yml`. The release contains a flattened SystemVerilog export, a source
tarball, build manifest, dependency lock, CycloneDX SBOM, and `SHA256SUMS`. `make package` creates the
same files locally below `dist/<variant>/`.
