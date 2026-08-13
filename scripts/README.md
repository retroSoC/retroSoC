# Build and Quality Scripts

This directory contains the Python implementation of setup, dependency locking,
build manifests, flow execution, simulation checks, regression orchestration,
quality checks, metrics, packaging, and cleanup.

Scripts are part of the build contract. Prefer existing helpers over ad-hoc
shell behavior, preserve structured JSON results, and keep setup/download
behavior controlled by `dependencies/dependencies.lock.json`.

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

`run_debug_session.py` is the local Hazard3 debug acceptance driver. It starts
the Verilator remote-bitbang endpoint, the lock-pinned OpenOCD binary, and
RISC-V GDB, then records their logs and a structured result. Invoke it through
`make CONFIG=configs/ci/ihp130-debug.mk SIMU=VERILATOR debug-sim`; see
[`../docs/hazard3-debug.md`](../docs/hazard3-debug.md) for its scope and
limitations.

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

Update or add tests in [`../tests`](../tests) for script behavior. Run
`ruff check .` and `python3 -m pytest -q`; build-flow changes also require the
relevant dry-run or regression profile from [`AGENTS.md`](../AGENTS.md).
