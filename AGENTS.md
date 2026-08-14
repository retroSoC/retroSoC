# retroSoC Agent Development Contract

This file is the repository entry point for coding agents. Read it before
changing code, build rules, dependencies, or quality policy. If this document
conflicts with executable configuration or policy, the executable source of
truth wins.

## Repository Map and Sources of Truth

- [README.md](README.md) defines supported profiles, prerequisites, common
  flows, and release outputs.
- [docs/engineering.md](docs/engineering.md) defines reproducible inputs,
  artifact layout, warning baselines, metric promotion, and CI behavior.
- [docs/misra-c-2012.md](docs/misra-c-2012.md) defines the embedded-C MISRA
  baseline and [quality/misra/deviations.md](quality/misra/deviations.md)
  records approved Required-rule deviations.
- [crt/README.md](crt/README.md) defines the freestanding RISC-V runtime and
  SDK layout; [app/README.md](app/README.md) defines application composition.
- `Makefile`, `rtl/mini/mk/software.mk`, committed `configs/*.mk`, and the
  GitHub workflows define the active build and regression behavior.
- `quality/embedded_c_policy.json`, `quality/warnings/`, and
  `quality/metrics/policy.json` define the active quality policy.
- [rtl/README.md](rtl/README.md) defines the self-owned SystemVerilog naming,
  register-state, macro, and formatting conventions.

Do not guess a profile, tool version, dependency revision, or generated-file
location. Inspect the corresponding source of truth first.

## Top-Level Directory Guides

Every Git-tracked first-level directory has a README that defines its ownership
and validation boundary.

| Directory | Guide | Role |
| --- | --- | --- |
| `.github/` | [.github/GUIDE.md](.github/GUIDE.md) | CI, release automation, reusable actions, and ownership metadata. |
| `app/` | [app/README.md](app/README.md) | Firmware applications and integrations. |
| `dependencies/` | [dependencies/README.md](dependencies/README.md) | Locked external inputs and checksums. |
| `configs/` | [configs/README.md](configs/README.md) | Reproducible build profiles. |
| `crt/` | [crt/README.md](crt/README.md) | Freestanding runtime and SDK. |
| `docs/` | [docs/README.md](docs/README.md) | Engineering and MISRA policy. |
| `fpga/` | [fpga/README.md](fpga/README.md) | FPGA wrapper and board constraints. |
| `licenses/` | [licenses/README.md](licenses/README.md) | Third-party notices and license texts. |
| `physical/` | [physical/README.md](physical/README.md) | Physical design, managed PDK inputs, and smoke synthesis/STA flows. |
| `quality/` | [quality/README.md](quality/README.md) | Executable quality policy and baselines. |
| `requirements/` | [requirements/README.md](requirements/README.md) | Pinned Python tool requirements. |
| `rtl/` | [rtl/README.md](rtl/README.md) | RTL, testbench, and SoC integration. |
| `scripts/` | [scripts/README.md](scripts/README.md) | Build, setup, regression, and quality helpers. |
| `tests/` | [tests/README.md](tests/README.md) | Host C and Python test suites. |

Do not create project documentation inside generated/local roots such as
`build/`, `.cache/`, `.sw_build/`, or tool caches, or inside managed vendor
subtrees. When adding a new Git-tracked first-level directory, add a concise
README that states its ownership, source of truth, and validation expectations.

## Ownership and Architecture

- `crt/` is the freestanding SDK. Its active layers are `arch/riscv`,
  `include/retrosoc/{core,hal,lib,service}`, `src/{core,hal,lib,service}`, and
  `linker`.
- `app/` is the application layer. Its active areas are `apps`, `board`,
  `media`, `middleware`, `network`, `ports`, and `benchmark`.
- Consume SDK interfaces through `<retrosoc/...>` public headers. Use the
  `rs_` API namespace and `rs_status_t` for operations that can fail.
- Applications are selected by `APP`. The supported values are `benchmark`,
  `bringup`, `debug`, and `shell`; each profile is declared in
  `app/apps/<name>/app.mk`. The `debug` application is an RTL debug-transport
  acceptance image, not a user-facing firmware profile.
- Do not add new dependencies on `crt/inc`, retired `tiny` names, or legacy
  `rs_*.h`/`tiny*.h` include paths.
- Treat `app/coremark/coremark-main`, `app/fatfs/ff16`, `app/lvgl/lvgl-main`,
  and managed ports as third-party or managed code. Update them through their
  setup/integration flow, not as ordinary project source.

## Embedded C Rules

- Self-owned `crt/` and `app/` C/H code follows MISRA C:2012 with Amendment 2.
  The exclusions in `quality/embedded_c_policy.json` are authoritative; do not
  claim MISRA conformance for excluded vendor, generated, compatibility, port,
  assembly, or linker material.
- Mandatory rules are not waived. Required-rule deviations need a reviewed
  record in `quality/misra/deviations.md`; Advisory-rule exceptions require a
  proportionate review rationale. Current automated checks enforce only a
  partial mechanical subset, not complete MISRA certification.
- Keep SDK code freestanding: do not introduce hosted-library, dynamic-memory,
  or operating-system dependencies.
- Follow the project `.clang-format` style with `clang-format-14`, the version
  installed by CI. The formatter and policy gates cover self-owned C and
  header files, not all generated, assembly, or vendor files.
- Outside approved compatibility files, do not introduce `strcpy`, `strcat`,
  `strncpy`, `sprintf`, `vsprintf`, `malloc`, `free`, or `atoi`.
- Prefer bounded interfaces (`rs_strlcpy`, `rs_strlcat`, `rs_snprintf`) and
  timeout-based register waits. Check inputs, overflow boundaries, and error
  returns at SDK/API boundaries.
- Place public headers in the matching `include/retrosoc/<layer>/` directory
  and implementations in the corresponding source layer. Add deterministic
  host tests for logic that does not require real registers or board timing.

## Build and Repository Safety

- Start from a committed configuration profile. Build products belong below
  `build/<profile>-<YYYY-MM-DD-HH-MM>-<config-hash>/`; caches belong below `.cache/`. Do not
  commit generated outputs.
- Preserve unrelated worktree changes. Do not reset, discard, or reformat files
  outside the requested scope.
- All external repositories, archives, checksums, and locked tool versions are
  controlled by `dependencies/dependencies.lock.json`. Do not add direct downloads to
  workflows or setup scripts. Use the shared dependency helpers and review a
  full Git revision or SHA-256 checksum when updating the lock.
- Do not hand-edit warning baseline signatures. Regenerate only an affected
  baseline from a successful flow, review every normalized signature, and keep
  baseline changes separate from the implementation change they approve.
- Metrics are currently in `observe` mode. Do not promote them to a blocking
  gate without the documented ten successful `main` runs and reviewed baseline.

## Required Validation

Run the smallest relevant set locally, then report any gate that was not run
and why. CI is authoritative for toolchain-dependent flows.

| Change area | Minimum validation |
| --- | --- |
| Markdown or documentation | Verify links and commands, then run `git diff --check`. |
| Self-owned `crt/` or `app/` C/H | Review applicable MISRA rules and deviations; run `make sw-format-check sw-policy-check sw-host-test`; build an affected committed profile with `make CONFIG=<profile> firmware`. |
| Deterministic SDK or media logic | Extend `tests/c/test_runtime.c` and run `make sw-host-test`. |
| Python/build tooling | `ruff check .` and `python3 -m pytest -q`. |
| Dependency-lock or setup changes | `python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json`, affected setup update/doctor flow, Pytest, and affected regression. |
| GitHub Actions or CI definitions | `yamllint .github .yamllint.yml`, `actionlint`, and `python3 scripts/regress.py --root . --suite pr --dry-run` plus `--suite nightly --dry-run`. |
| RTL, configuration, linker, or hardware-facing changes | Run the affected firmware build and simulator; use `make regress-pr` for the supported PR matrix and `make regress-nightly` for extended coverage. |

The fast CI quality gate also validates the dependency lock, Python lint,
embedded-C formatting and policy, host tests, Pytest, YAML, GitHub Actions, and
both regression definitions. The regression CI runs supported Verilator and
Icarus simulations, Yosys synthesis, Icarus netlist simulation, OpenSTA timing,
warning checks, and metric collection.

## Regression Verdicts and Known Conditions

- Automated firmware completes by writing SYSCTRL `TEST_STATUS`: bit 31 is
  valid, bit 0 is pass, and bits 15:8 contain a result code. The first valid
  full-word write is sticky until reset. Testbenches emit `SIM_TEST_PASS` or
  `SIM_TEST_FAIL`; UART startup output is diagnostic only. A simulation passes
  only when its command succeeds, its log contains the configured success
  marker, and the log contains no `FAILED`, `FATAL`, `assertion failed`,
  `%Error`, `SIM_TEST_FAIL`, or `SIM_TEST_TIMEOUT` marker.
- New self-owned C compiler warnings fail the regression. New or increased EDA
  warning signatures make `check-warnings` fail when invoked directly, but the
  regression runner records them as non-blocking observations so CI uploads the
  warning and metric reports; resolved warnings are reported.
- `check-metrics` records firmware size, area, cell count, timing, and flow
  duration. It is non-blocking in the regression runner, including if a future
  policy changes the standalone command into a gate.
- Verilator currently runs through `scripts/run_flow.py`, which captures the
  emulator stdout in a pipe. UART output can therefore appear only after a
  newline or when simulation ends. Treat `sim.log` and `result-sim*.json` as
  the verdict; delayed terminal UART display is a known operational condition,
  not evidence that the simulation has failed.

## Before Hand-off

1. State the selected profile and commands run.
2. Summarize code, configuration, and public-interface changes separately.
3. Report validation results, applicable MISRA deviations, and explicitly
   identify unrun gates.
4. Mention any remaining hardware, timing, vendor, or simulator coverage gap.
