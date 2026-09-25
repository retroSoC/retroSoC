# Build and Quality Scripts

This directory contains the Python implementation of setup, dependency locking,
build manifests, flow execution, simulation checks, regression orchestration,
quality checks, metrics, packaging, and cleanup.

`apu_mcasm.py`, `apu_isa.py`, `apu_interpreter.py`, and `apu_primitives.py` are
the frozen APU microcode V1 assembler/ABI model, P3/P4/P5 target interpreters, and
bit-accurate P4 primitive model. They accept only the APU instruction language
and deliberately have no C, ELF, RV32, dynamic linking, or runtime
code-generation path.

`setup_apu_reference.py` installs the checksum-pinned libFLAC and official
FLAC corpus as host-only P5 verification inputs and builds libFLAC with Ogg
disabled below the selected build variant. These inputs never enter firmware,
RTL, or shipped APU microcode.
`qualify_apu_p5_corpus.py` enumerates that exact corpus, records source and
decoded-PCM hashes, and classifies each file against the frozen P5 profile.
`run_apu_p5_corpus_rtl.py` then runs every classified file through one shared,
verification-only `apb4_apu` fixture compiled for Icarus and Verilator. It
records exact production result/accounting and PCM hashes in the same manifest;
per-case results are resumable and neither the fixture nor corpus enters a
product filelist.

Scripts are part of the build contract. Prefer existing helpers over ad-hoc
shell behavior, preserve structured JSON results, and keep setup/download
behavior controlled by `dependencies/dependencies.lock.json`.

`generate_apu_kws_rtl_constants.py` also emits the frozen APU-P9 APUC image
and 15-bank layout manifest. `apu_kws_coeff.py` owns the independent APUC 1.0
schema and release validator; generated assets remain below the selected
variant's `apu/coefficients/` directory.
`apu_p9_evidence.py` initializes or assembles the six frozen P9 evidence files;
missing qualifying runs stay explicitly `unrun` rather than becoming passes.
`apu_p9_memory_ab.py` performs the like-for-like inferred-memory, macro-count,
synthesis-time and process-tree peak-RSS comparison from two explicit variant
roots; it never creates or switches Git worktrees itself.

The frozen P9 qualification entry points are explicit and do not turn smoke
runs into release evidence:

```sh
make CONFIG=configs/ci/ihp130.mk setup-apu-kws-reference apu-p9-coefficients apu-p9-evidence
python3 scripts/run_apu_p7_kws_rtl.py \
  --build-dir build/<candidate>/apu/p9/accuracy --profile ihp130-p9
python3 scripts/run_apu_p7_concurrent_rtl.py \
  --build-dir build/<candidate>/apu/p9/concurrent --seconds 60
make CONFIG=configs/ci/ihp130.mk apu-p9-memory-ab \
  APU_P9_BASELINE_ROOT=build/<baseline> APU_P9_CANDIDATE_ROOT=build/<candidate>
```

Both A/B roots must come from clean committed revisions; the baseline is the
frozen pre-P9 revision and both configurations must enable P7 with the same
IHP130 tool, PDK, recipe, and dependency inputs. Assemble the six final reports
with `scripts/apu_p9_evidence.py assemble`; a `passed` input is accepted only
when its report-specific checks and named source artifacts are complete.

`setup_npu_reference.py` prepares the locked KWS/VWW inputs and the existing
TensorFlow/gemmlowp reference sources. `npu_framework_reference.py` builds the
host-only adapter in `tests/cpp/npu_framework_reference.cc`; its integer kernels
consume original tensor constants and quantization, never NPU packed artifacts.
Only raw model parsing is shared with the NPU compiler. Run
`make CONFIG=configs/ci/ihp130.mk npu-p0-qualify` after
`make CONFIG=configs/ci/ihp130.mk setup-npu-reference` to compare both complete
1000-input corpora against the Python graph reference and compiled executor.
The selected variant's `npu/p0/` directory retains oracle build provenance,
per-input golden tensors, three-way hashes, logs and `qualification-p0.json`.
The runner uses at most 16 workers (`JOBS`); missing sources/tools, numerical
differences and incomplete runs cannot pass. A direct `--limit` invocation is
debug-only and returns a nonzero status even when its selected cases match.

`npu_compiler.py` is the P5 production entry point. It accepts one static
batch-one INT8 TFLite v3 subgraph, rejects unsupported placement with an
operator-specific diagnostic, and emits ABI-1 descriptors, packed constants,
`npu.json`, and a model-prefixed freestanding C plan. The generated plan uses
caller-owned aligned descriptor/arena storage, checked physical relocation,
bounded HAL waits, 64-byte Zicbom maintenance when compiled for HP, and the
model-derived terminal integer Softmax. Generated files remain below the
selected build variant. `make CONFIG=configs/ci/ihp130.mk npu-p5-deployments`
builds the locked KWS and VWW packages reproducibly.

`qualify_npu_p5.py` builds one production NPU fixture per simulator and runs
the frozen ten-input sets from both manifests. Every accepted output byte is
checked in actual tile-write order, so later arena reuse cannot hide an
intermediate mismatch. Invoke it through
`make CONFIG=configs/ci/ihp130.mk npu-p5-rtl`; missing tools, inputs, terminal
markers, or any layer write fail the required run.

`npu_p5_report.py` fails closed while assembling P5 evidence. It verifies P0,
compiler/parity and embedded-C/HAL results; exact dual-simulator case counts;
source, trace, log and deployment hashes; LP/HP build manifests and firmware;
cross-profile KWS package identity; and zero skipped/rejected cases. Invoke it
through `npu-p5-report` with the retained LP/HP variant roots and config
digests. The generated report records its fully expanded command.

NPU-P6 qualification is split into auditable drivers. `npu_p6_corpus.py`
builds deterministic CRC-protected 100-case KWS/VWW shards from retained P0
goldens. `run_npu_p6_verilator.py` builds the existing `hp_boot` composition,
runs all shards on one PRODUCT Verilator model, and aggregates architectural
cycles and NPU counters. `run_npu_p6_netlist.py` runs macro-aware isolated
synthesis/STA and four directed synthesized-block transactions covering dense,
depthwise, rejection and accumulation-overflow behavior;
`run_npu_p6_physical.py` invokes the unchanged full PRODUCT Yosys/OpenSTA and
warning/metric gates. `run_npu_p6_regression.py` retains PR/nightly verdicts,
and `npu_p6_report.py` requires current-revision PASS evidence for all of
NPU-V015 through NPU-V018. None of these scripts treats FPGA execution or host
elapsed time as mandatory performance evidence.

`development_environment.py` is the shared Docker, Nix, and manual bootstrap
entry point. It installs only the checksum-verified open-source tool bundles and
hash-pinned Python dependencies; project-local PDK and source setup remains under
the existing Make targets.

`publish_fatfs_artifact.sh` is the manual release helper for the lock-pinned
FatFs R0.16 archive. It verifies the archive, GitHub authentication, release
absence, and the published asset checksum before reporting the checksum-pinned
URL.

`parse_performance_log.py` converts the `APP=benchmark` UART `PERF` records
into `meta/performance.json`. The parser requires the terminal
`PERF_BENCHMARK_PASS` marker. `parse_coremark_log.py` converts the fixed
SRAM CoreMark quick report into `meta/coremark.json`; it requires one valid
`COREMARK_RESULT` record and `COREMARK_PASS`. Both reports complement, rather
than replace, the common `SIM_TEST_PASS` simulation verdict.

`generate_vexiiriscv.py` verifies the locked VexiiRiscv revision and generates
the fixed HP core below `build/`; generated RTL is never tracked.
`setup_hp_linux.py` installs the locked OpenSBI, Linux, and Buildroot revisions
and can resume a checkout left without `HEAD` by an interrupted fetch.
`build_hp_linux.py` builds the RV32 `ilp32d` image set with the repo-owned
external OpenSBI platform. `package_hp_boot.py` creates the v1 LP/HP flash
bundle and its SHA-256/CRC manifest. `check_lp_hp_performance.py` applies the
measured 2.5x CoreMark/MHz gate.

`run_debug_session.py` is the local Hazard3 debug acceptance driver. It starts
the Verilator remote-bitbang endpoint, the lock-pinned OpenOCD binary, and
RISC-V GDB, then records their logs and a structured result. Invoke it through
`make CONFIG=configs/ci/ihp130-debug.mk SIMU=VERILATOR debug-sim`; see
[`../docs/hazard3-debug.md`](../docs/hazard3-debug.md) for its scope and
limitations.

`program_xpi_flash.py` drives the SRAM-resident XPI loader through an existing
OpenOCD GDB endpoint. It validates and splits a BIN at 4 KiB sector boundaries,
generates a reviewable GDB script, and performs erase/program only when
`--execute` is explicit. See [`../docs/ip/xpi.md`](../docs/ip/xpi.md).

`check_rtl_style.py` applies the ownership-aware RTL style rules from
[`../rtl/rtl_style_manifest.json`](../rtl/rtl_style_manifest.json). The CI
target checks changed self-owned RTL for positional module connections, legacy
constructs, and the staged naming contract. `rtl-style-check-all` retains the
historical full-tree structural baseline while naming debt is migrated in
module-sized batches. Existing findings must not be expanded by a new change.

`migrate_rtl_connections.py` is the conservative migration helper for legacy
positional instances. It discovers ANSI-style module declarations in the
production RTL and locked technology/IP trees, rewrites only exact positional
parameter and port lists to named connections, and reports ambiguous instances
without modifying them. Run `make rtl-migrate-connections`, then
`make rtl-format rtl-style-check`; review the generated diff before committing.

`migrate_rtl_names.py` shortens only local identifiers beginning with `s_` or
`r_` (plus local automatic variables such as `read_request`). Public module
ports and interface fields are intentionally unchanged. Run
`make rtl-migrate-names`, then format and lint the resulting diff.

`crypto_constants.py` packs the frozen CRYC1 image from the V1 tables;
`crypto_p0.py` independently checks it against the mathematical oracle in
`tests/crypto_reference.py`. The P0 runner also executes existing V1 tests,
full-width RSA-2048 public/private/recheck vectors, SHA padding boundaries and
a real DMA-to-AES-to-memory test. Missing tools or missing success markers are
errors. It invokes the shared simulation verdict checker; an Icarus `$fatal`
that exits with code zero is still a failed test.

The `crypto-p0-constants`, `crypto-p0-rtl`, `crypto-p0-baseline` and
`crypto-p0-report` Make targets write below `build/<variant>/crypto/p0/`.
Select `CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS` and one BUILD_TIMESTAMP for
all four. P0 preserves production RTL/HAL and records V1 lifecycle limitations;
it does not implement the six-bank V2 refreeze. Block synthesis calls the
unchanged `synth.tcl` and `abc_balanced.script`, adding JSON checkpoints and
standalone interface elaboration only. Each new synthesis attempt uses a fresh
`synth-*` artifact directory recorded in the report, preventing an old netlist
from masking a new failed attempt. Its 20833 ps target is derived from
the PCLK inventory; it is not a full-chip timing result. A timeout/interruption
retains partial checkpoints and cannot pass the aggregate report. See
[`../docs/ip/crypto.md`](../docs/ip/crypto.md).

Update or add tests in [`../tests`](../tests) for script behavior. Run
`ruff check .` and `python3 -m pytest -q`; build-flow changes also require the
relevant dry-run or regression profile from [`AGENTS.md`](../AGENTS.md).
