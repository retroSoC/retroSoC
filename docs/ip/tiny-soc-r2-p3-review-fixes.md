# TINY-R2-P3 review fixes and validation boundary

This record covers the two P1 findings approved for follow-up on
`bab01352f8f7c80e39546b04e3ed37a3d927f475` plus the existing P3 worktree.
It does not approve Mini fabric enablement or advance TINY-R2-P4.
Earlier sections retain their original development status and attribution;
the source-bound campaign below records completed validation on `3e46cc8`.
The final section separately records the subsequent two HAL race fixes.

## Retained Tiny Icarus finding: closed

The previously running banked O2/no-LTO Icarus attempt completed successfully:

`build/ics55-tiny-performance-2026-10-08-17-20-b6fb322b1bce/meta/tiny-r2-p3/runs/iverilog/attempt-zljt308n/record.json`

All three exits are zero, with strict Tiny TEST_STATUS/SIM_TEST_PASS and no
forbidden error markers. Durations are 6229.576, 5619.359 and 5943.890 seconds.
Revalidation checks each log, command, image/model/tool artifact and all eight
workloads; the three samples also equal the retained Verilator samples at
`runs/verilator/attempt-wnwm6ynp/record.json`. The source revision is the original
retained image/model snapshot, not a replacement attribution to subsequent fixes.

The replay audit is retained under the same variant at
`meta/tiny-r2-p3/review-fixes/retained-tiny.json` and `retained-tiny.log`.
The audit also verifies that the actual Tiny image's compilation source files
and linker inputs remain unchanged. WS2812 HAL/application and Mini-only DV
changes do not create a new Tiny integration result. This closes one selected
image's cross-simulator gate, not the full eight-configuration compiler matrix.

## Mini WS2812 finding: diagnosed, still open

The original 33-word frame consumed its sixteen preloaded words, then
underflowed. Source-bound diagnostic roots are:

- `build/ics55-2026-10-08-17-35-d0c568d0142e/`: rebuilt ordinary Mini acceptance
  image with diagnostic fields; no source-cache inference is needed.
- `build/ics55-2026-10-08-21-00-d0c568d0142e/`: the same configuration with
  observation-only timestamps. FIFO-low occurred at PCLK cycle 450141;
  service first read DMA status at 452268, and DMA START at 458446 was later
  than underflow at 456621.
- `build/ics55-2026-10-08-21-00-042fb076f2e1/`,
  `build/ics55-2026-10-08-21-00-425535420bc4/` and
  `build/ics55-2026-10-08-21-00-2d7056520d6b/`: diagnostic firmware variants
  replayed on the preceding Mini model to isolate software cost. Their different
  firmware/configuration identities are retained; these are diagnostics, not
  matched-profile acceptance. The last variant starts DMA before underflow,
  yet records zero completed bytes and a DMA error, with no FIFO push observed.

The transport is unavailable in current Mini PRODUCT hardware:

1. `rtl/mini/top/soc_data_plane.sv` connects central DMA to I/O source 0,
   through PCLK-to-HP CDC and an AXI32-to-64 upsizer, to data-plane master 2.
2. `rtl/mini/top/axi4_data_crossbar.sv::decode_target` only decodes SRAM,
   SDRAM, QPI PSRAM, OPI PSRAM and XPI/Flash. WS2812 TXDATA at `0x10008010`
   is unmapped and selects error target 5. This matches the current
   [Mini data-plane contract](../axi4-interconnect.md), which gives central DMA
   memory targets rather than a DMA-to-APB route.
3. Even with a new control route, `rtl/mini/top/axi42apb4.svh` currently accepts
   only single-beat INCR. The shared DMA's specified one-beat FIXED FIFO
   transfers would require a separate compatibility correction there as well.

The new directed case in `tests/rtl/axi4_data_crossbar_tb.sv` drives the actual
production crossbar with master 2, ID `0x10`, address `0x10008010`, AWSIZE=2,
AWLEN=0 and AWBURST=FIXED. It verifies the unmapped target, master/address/write
attribution and returned SLVERR, while retaining the existing concurrency/ACL
checks. It reports:

```text
MINI_DMA_MMIO_BOUNDARY master=2 address=10008010 target=5 reason=1 response=SLVERR
```

This diagnostic passes because it verifies the existing unsupported boundary;
it does not turn the failed Mini WS2812 DMA acceptance into a pass. Its gate
and raw trace are under
`build/ics55-2026-10-08-21-00-425535420bc4/meta/tiny-r2-p3/`
as `mini-dma-mmio-boundary.{json,log}` and `mini-mmio-route-trace.{json,log}`.
No production fabric, route, ACL, clock/reset, DMA hardware or dependency is
modified by this follow-up.

## Software and verification corrections retained

- Shared service reads only the state needed in the active lifecycle state;
  diagnostic stall/CRC/remaining snapshots and DMA configuration initialization
  are removed from no-work/pending hot paths. Full configuration initialization
  still occurs before admission.
- Clear sticky FIFO-low after the actual low-level condition has ended, before
  interrupt rearm; keep set-dominant W1C behavior. Preserve the original
  `min(remaining, 16-L)` admission rule; the speculative four-word cap was
  withdrawn and is not part of the implementation.
- The fixture prepares the invariant background job before START, keeps all
  sixteen 256-byte jobs/burst-16/four-TCD traffic, enables only terminal
  channel-3 DMA events, and uses a 100-us foreground deadline checked with
  stable SAFE24 CPU cycle reads. The deliberate 600-us starvation interval is
  measured after frame startup, not before validation/preload.
- Host coverage additionally checks stale FIFO-low acknowledgement and wire
  DONE before delayed final DMA completion: neither may release the lease early.
- The observer's summary runs at finalization because the C++ harness need not
  execute another PCLK edge after TEST_STATUS. Descriptor reads overlapping an
  active refill window are counted separately. Positive Mini timing qualification
  is still missing; these changes are not presented as closing its hardware gap.

## Approved option A (2026-10-08)

The original P3 plan incorrectly assumed that the selected Mini product could
execute the shared fixed-MMIO DMA path. Changing only scheduling or accepting
UART text cannot supply the missing route. The maintainer explicitly selected
option A ("按照A执行"), correcting the validation plan without enabling Mini MMIO.

Approved P3-only correction: retain the failed Mini run and the explicit
unsupported-route diagnostic; validate the shared finite DMA service through
the existing host/standalone production-DMA/WS2812 fixtures, and use supported
Mini PIO/SDK compatibility checks. Keep product-integrated DMA/IRQ service
budget acceptance pending the platform that actually provides that path
(Tiny R2-P6). No failed DMA run becomes a passing PIO result.

`app/apps/ci_smoke/ws2812_r2.c` now performs explicitly labeled Mini PIO
compatibility checks (4/16/33/65 words, actual DONE IRQ, underflow and abort).
The wrapper observes the complete serial waveform and reset-low intervals and
asserts zero DMA starts. Its finalization summary is required in addition to
the ordinary command exit, TEST_STATUS/SIM_TEST_PASS and forbidden-marker checks.
The before-change source archive is retained at
`build/ics55-tiny-performance-2026-10-08-17-20-b6fb322b1bce/meta/tiny-r2-p3/review-fixes/option-a-2026-10-08-22-41/before-change.json`.

The software deadline/preconfiguration experiments described above refer to the
retained failed DMA fixture. They are not part of the new PIO measurement or a
claim that the absent Mini DMA route was repaired. Shared service lifecycle,
occupancy and delayed-response checks remain in the host and standalone suites.

### Option A execution results

The supported compatibility run uses
`build/ics55-2026-10-08-22-57-d0c568d0142e/`, profile `configs/ci/ics55.mk`,
SOC=MINI, PDK=ICS55, APP=ci_smoke, WS2812_P3_ACCEPTANCE=YES, HAVE_CSR=YES,
LINK_TYPE=ld2_all_sram and the locked Verilator with `--fast-flash`.
Firmware and simulator command exit successfully. The 329.941-second run has
TEST_STATUS/SIM_TEST_PASS, no forbidden markers and the additional required
PIO/observer markers:

```text
WS2812_P3_MINI_PIO PASS code=0 irqs=5 dma_mmio=UNSUPPORTED
WS2812_P3_MINI_PIO_OBSERVER frames=6 completed=4 underflows=1 aborts=2 dma_starts=0
```

All 4/16/33/65-word frames pass exact serial-waveform, length and reset-low
checks. The two additional starts exercise deliberate underflow and abort;
the underflow cleanup accounts for the second abort event. No DMA transaction
is started by this compatibility image.

`meta/tiny-r2-p3/option-a-evidence.json` binds configuration, tools, ELF/BIN/HEX,
linker map, disassembly, simulator, source archive and input hashes, compile/run
results and both additional verdict checks. The capture is explicitly post-build:
487 Verilator input sizes/mtimes are rechecked against its compilation metadata
before the source snapshot is retained; it is not mislabeled a pre-build capture.

Focused validation passes (`96 passed`), including the shared finite DMA/refill
fixtures, DMA register parity and the unsupported Mini MMIO boundary. Its exact
command/log/result are under
`build/ics55-2026-10-08-22-41-d0c568d0142e/meta/tiny-r2-p3/focused.{json,log}`.
C formatting/policy/host tests and RTL formatting/style/readiness pass under the
PIO variant's `meta/tiny-r2-p3/quality.{json,log}`. Ruff and `git diff --check`
also pass. No new MISRA deviation, dependency update, warning baseline or
metrics-policy change is introduced.

The first option-A firmware compile failed because removing the DMA include
also removed a transitive declaration of UART_BPS. The explicit core/soc.h
include fixes the build; the failure log is retained in the 22-41 variant at
`meta/tiny-r2-p3/initial-build-missing-include.log`. It is not a GNU ISA failure
and no alternative compiler was downloaded or selected.

The two review findings are addressed at their approved boundaries: retained
Tiny cross-simulator evidence is complete; the invalid positive Mini DMA gate
is replaced by explicitly approved, passing PIO compatibility plus the retained
unsupported-route diagnostic. Product DMA/IRQ budgets and the full P3 acceptance
matrix are still pending; this is not automatic phase acceptance.

Not selected: separately preflight Mini central-DMA MMIO enablement. That work
must define routing, source identity, privileged-window ACLs, clock crossings,
accepted read/write drain and reset/ownership behavior, plus one-beat FIXED
handling at the APB boundary. It is outside the current P3 software repair and
must not be folded into Tiny's later fabric phases without approval.

The full P3 compiler matrix, broader current-source regressions and final
phase acceptance remain open. Neither these diagnostics nor prior negative
STA observations qualify a new physical operating point.

## Compiler-matrix execution corrections (2026-10-09)

The intermediate snapshots below are historical. The final source-bound results
later in this record supersede their in-progress status without relabeling any
failed attempt or earlier artifact.

The initial flat-image collector could not read `_stack_point` from its symbol
listing. Flat placement now falls back to the retained linker map's explicit
`PROVIDE (_stack_point = .)` value; the exact SRAM endpoint and 4 KiB stack
headroom checks remain mandatory. Banked placement still requires its ELF symbol.

LTO links exposed compiler-generated references to the freestanding runtime
after its otherwise-unused definitions had been removed. LTO selections now
retain the existing memory and RV32 arithmetic helper symbols through linker
`--undefined` options. No hosted runtime, ISA extension or dependency is added.
The failed flat/LTO attempts under the `2026-10-09-09-00`, `10-00` and `10-45`
experiment labels remain historical failures; labels are not elapsed-time data.

The `2026-10-09-11-30` campaign was deliberately interrupted before long Icarus
coverage after its O2/LTO ordinary acceptance build exposed two self-owned
`-Wmaybe-uninitialized` warnings. Managed RTC/watchdog implementations write the
snapshot on every successful return; callers retain their error checks and now
explicitly initialize the two local snapshots. The matrix Make wrapper also
rejects self-owned C warnings from the ordinary firmware, in addition to the
existing separate measurement-image warning check. A negative test requires a
zero-exit Make command with such a warning to be recorded as failed.

The interrupted master is
`build/ics55-tiny-performance-2026-10-09-11-30-53cc6674d532/meta/tiny-r2-p3/matrix/attempt-zpde30dv/record.json`.
Its last checkpoint can still say `running`; that is not a live-process verdict
or complete campaign acceptance. Completed samples retain their original source
identity and are not relabeled as measurements of the corrected source.

### Current execution snapshot (2026-10-09, not phase acceptance)

The replacement compiler campaign is
`build/ics55-tiny-performance-2026-10-09-09-25-53cc6674d532/meta/tiny-r2-p3/matrix/attempt-fc26_1s7/record.json`,
with source digest
`e817e2d264105068aecd22f49fa7d7016765878ace168a1329dcd4f9ad864370`.
All eight configurations complete ordinary Tiny acceptance and three deterministic
Verilator measurement runs. Selected Icarus groups remain in progress at this
snapshot; this is not yet a complete cross-simulator compiler matrix.

Focused validation reports 111 passed. Full Pytest at the same source reports
1531 passed, 4 failed, 94 fixture errors and 1 skipped in 4250.64 seconds.
The exact command and complete trace are retained in the campaign root at
`meta/tiny-r2-p3/quality/pytest.{json,log}`. Diagnosed causes are:

- `test_clock_reset_domain_inventory_matches_the_rcu` requires a literal
  `AUD_CLK_HZ` declaration in every profile. The performance profile inherits
  24000000 from `ics55-tiny.mk`; its effective clock value is correct, but the
  declaration gate fails.
- Publication API metadata still binds the old `rs_dma_start` body. The changed
  lease/fence/command behavior needs semantic review, not just a digest refresh.
- Publication software metadata still binds the old assembly `premain` block.
  This also prevents dependent system/diagram/retrieval fixtures from collecting.
- The publication C fixture extracts legacy DMA entrypoints without the newly
  called `rs_dma_command` helper: 34 scenarios fail fixture compilation with
  an implicit-declaration error. The remaining 60 fixture errors belong to
  dependent publication collectors.
- One PDF inspection test skips because `pypdf` is unavailable in this environment.

Focused diagnostics are retained beside the full result as
`clock-inventory-diagnostic.{json,log}` and `publication-diagnostic.{json,log}`.
The independent CLINT test passes; its initial diagnostic did not explain the
full-suite failure. No publication revision, PDF, warning baseline or dependency
is changed to turn these failures into passes.

The IHP130 Tiny PR regression completes with exit zero under
`build/ihp130-tiny-2026-10-09-09-27-bff91e3529ba/`; its exact command and result are
`meta/tiny-r2-p3/regress-ihp130.{json,log}`. Behavioral Icarus includes JTAG
halt/resume, netlist boot requires Tiny SIM_TEST_PASS, and synthesis/STA commands
complete. Actual ci_smoke-variant metrics record 208545 cells, area
9109293.080998 in the synthesis report's units, max WNS -94.28 ns and max TNS
-1594880 ns. These are SAFE24 smoke observations, not timing closure or physical
qualification. The lint warning comparison in the separate `2dc2e5c747e5`
variant fails and remains a non-blocking regression observation.

The ICS55 Tiny PR regression also completes with exit zero under
`build/ics55-tiny-2026-10-09-09-26-42d5beccb726/`, with exact command and result
at `meta/tiny-r2-p3/regress-ics55.{json,log}`. Its source-capture/platform audit
passes at `meta/tiny-ics55-p1/report.json`. The actual ci_smoke metrics record
197703 cells, area 1786703.340799 in the synthesis report's units, max WNS
-41.14 ns and max TNS -508669.53 ns. Behavioral Icarus, JTAG halt/resume,
netlist Tiny boot, synthesis and STA commands complete; negative timing margins
remain observations, not a qualified operating point. Relative to their retained
lint baselines, ICS55 reports 459 new signatures and IHP130 403, with zero
increased or resolved signatures in either comparison. These counts are baseline
differences, not attribution of every warning to the P3 implementation.

The regression runner's final generic metrics observations use default bringup
variants. The numbers above instead come from explicit metric collection in the
actual APP=ci_smoke synthesis/STA variants, with their matching `meta/metrics.json`.
No missing result in a different variant is credited as a pass of these gates.

Mini's first behavioral-only regression stops before RTL execution because SBT
cannot create its boot socket in the sandbox. Two escalation requests time out
in automatic approval review without executing. Inspecting the installed SBT
1.10.0 implementation identifies its `sbt.server.forcestart=true` fallback, which
continues without that boot socket while the generator still sets
`sbt.server.autostart=false`. The sandboxed retry uses that environment option
and the original locked sources. Both attempts are retained under
`build/ics55-2026-10-09-09-28-d1cacf6d3b62/meta/tiny-r2-p3/` as
`regress-mini.{json,log}` and `regress-mini-no-boot-socket.{json,log}`.
The retry completes with exit zero, including SDRAM/Verilator acceptance under
the `dc24d22ad53d` variant and Icarus assembly boot under `ec9e1f2e9c2c`, both with
the selected target's successful simulation checks. This behavioral-only run
provides no Mini synthesis, netlist, STA or physical evidence. Mini lint baseline
differences remain non-blocking observations, separately retained in the
`56f28cd9230c` variant's `meta/rtl-lint-warnings.json`.

## Final source-bound P3 matrix (2026-10-10)

After the external style commit and the publication/configuration corrections
settled, the final campaign was run against commit
`3e46cc80e2d2243233d284b7cd9583714b0773bb`, source digest
`a7fc5112cd6f20df956243c4d081a6a31ede6192cd270e3c13340557b0e58776`.
Its master record is
`build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/matrix/attempt-3jy5g5vo/record.json`;
the final report is in the same root at `meta/tiny-r2-p3/report.json`.

All eight cases pass image collection, normal Tiny acceptance and three cold
Verilator runs. The selected native Icarus cases also pass three cold runs:

- `compat-os-flat`: 7464.762, 7891.159 and 7428.430 seconds;
- `perf-o2-lto-flat`: 5841.742, 5890.497 and 6149.375 seconds;
- `perf-o2-plain-banked`: 5951.447, 6345.716 and 5964.039 seconds.

The collector validates Tiny `TEST_STATUS`/`SIM_TEST_PASS`, forbidden markers,
matched retained image/model/tool artifacts, source digests, three repetitions,
and cross-simulator sample identity. `report.json` remains
`measurement_complete`; the ledger's human phase gate is still required.

The earlier 09-25, 15-10 and 16-45 campaigns remain historical: source changes
during execution included the `352b200` style commit, the configuration/publication
repairs, and the performance profile's trailing-newline change. Their raw passing
samples and provenance failures are retained and are not relabeled as final
evidence. The final campaign uses the complete committed corrections in `3e46cc8`.

### Current validation and commands

The tested primary platform is TINY/ICS55, external SAFE24 with HAVE_PLL=YES
but the PLL parked off. CPU and the existing 128 KiB main SRAM remain at SYS24.
The IHP130 compatibility profile keeps no PLL. Dependencies, warning baselines,
metrics policy, hardware integration and the frozen specification blob
`7e19de49d49efaafacccfa85671e314d53dd15a4` are unchanged by this validation.

After activating `.cache/retrosoc/development/tiny-r2-p1/activate.sh`, the matrix
and final report commands were:

```sh
make CONFIG=configs/benchmark/ics55-tiny-performance.mk SOC=TINY PDK=ICS55 \
  BUILD_TIMESTAMP=2026-10-09-17-10 SOC_SIM_TIME=21600 JOBS=3 \
  TINY_P3_RESUME=NO tiny-r2-p3-matrix
make CONFIG=configs/benchmark/ics55-tiny-performance.mk SOC=TINY PDK=ICS55 \
  BUILD_TIMESTAMP=2026-10-09-17-10 tiny-r2-p3-report
```

The current full Pytest run reports **1629 passed, 1 skipped** in 4200.10 seconds.
The one skipped PDF inspection test requires `pypdf`, absent from this environment;
it is not a hardware or simulation pass. Its command, complete log and result are
in the matrix root under `meta/tiny-r2-p3/quality/pytest.{log,json}`. The previous
4 failures and 94 fixture errors remain in their old logs; they are resolved by
the configuration declaration and publication/source-fixture corrections in
`3e46cc8`. The focused correction check also passed 149 tests with the same one
PDF skip. No PDF or publication source revision was advanced by these checks.

`ruff check .`, dependency-lock validation and `git diff --check` pass. The
current C format/policy/host and RTL format/style/readiness checks pass; their
exact Make command and outputs are retained under
`meta/tiny-r2-p3/quality/policy.{log,json}`. These are the repository's mechanical
quality checks, not complete MISRA certification; no new deviation is recorded.

Regression dry-runs selected TINY explicitly for both PDKs and MINI with
`--behavioral-only`. Tiny nightly resolves to the same commands as PR, so it was
not executed a second time. The final executions were:

```sh
BUILD_TIMESTAMP=2026-10-09-19-55 python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
BUILD_TIMESTAMP=2026-10-09-19-56 python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
JAVA_TOOL_OPTIONS=-Dsbt.server.forcestart=true BUILD_TIMESTAMP=2026-10-09-19-57 \
  python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only
```

All three exit zero. Current evidence roots and results are:

| Scope | Evidence root below `build/` | Result |
| --- | --- | --- |
| Tiny ICS55 PR | `ics55-tiny-2026-10-09-19-55-42d5beccb726/` | `meta/tiny-r2-p3/regress-ics55.{log,json}`; behavioral/JTAG, netlist boot, synthesis and STA commands pass |
| Tiny IHP130 PR | `ihp130-tiny-2026-10-09-19-56-bff91e3529ba/` | `meta/tiny-r2-p3/regress-ihp130.{log,json}`; same target-specific gates pass |
| Mini ICS55 behavioral-only | `ics55-2026-10-09-19-57-d1cacf6d3b62/` | `meta/tiny-r2-p3/regress-mini.{log,json}`; SDRAM Verilator and Icarus assembly boot pass |

Each Tiny PR's HAVE_SVA=YES Verilator acceptance has its separate configuration
variant, identified in the retained command/log. Mini's SDRAM run uses
`dc24d22ad53d` and assembly boot uses `ec9e1f2e9c2c` at the same 19-57 timestamp.
Mini behavioral-only supplies no synthesis, netlist, STA or physical evidence.

The additional IHP130 performance/banked normal-firmware check also passes:

```sh
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 \
  BUILD_TIMESTAMP=2026-10-10-00-13 SW_ISA_PROFILE=TINY_PERF SW_OPT=O2 SW_LTO=NO \
  LINK_TYPE=ld2_tiny_banked SIMU=VERILATOR firmware sim
```

Its root is `build/ihp130-tiny-2026-10-10-00-13-8648aa4845d9/`, with the exact
command/result at `meta/tiny-r2-p3/performance-banked.{log,json}` and strict Tiny
simulation check at `sim/verilator/result-sim-check.json`. This is normal
firmware compatibility; it is not an additional IHP130 compiler measurement matrix.

The ICS55 platform auditor captured inputs before this execution and successfully
produced `meta/tiny-ics55-p1/report.json` in the actual APP=ci_smoke variant. This
reuses the platform audit under P3; its original phase label is unchanged. Metrics
were explicitly collected in each actual synthesis/STA variant rather than the
regression runner's final default-bringup observation directory:

| TINY PDK | Cells | Reported library area | Max WNS (ns) | Max TNS (ns) |
| --- | ---: | ---: | ---: | ---: |
| ICS55 | 197677 | 1786686.260799 | -41.14 | -508669.53 |
| IHP130 | 208547 | 9109320.296998 | -94.28 | -1594880.00 |

Both min WNS/TNS values are zero in these smoke reports. Full reports are at
`sta/opensta/timing_metrics.rpt` and `meta/metrics.json` within the corresponding
APP=ci_smoke roots. Library area is not placed/routed die area; negative margins
remain unclosed. No 96/192/240 MHz operation, routed/PVT signoff or physical
qualification is claimed, and no half-rate main-SRAM fallback is introduced.

Lint comparisons remain non-blocking observations: ICS55 Tiny has 459 new
signatures relative to its baseline, IHP130 Tiny 403, and Mini ICS55 1536 new /
118 resolved; all three have zero increased signatures. Counts are not attribution
of every warning to P3. The reports are in each timestamp's lint variant
(`303f95040df3`, `2dc2e5c747e5`, and `56f28cd9230c` respectively), under
`meta/rtl-lint-warnings.json`. Baselines were not edited.

### Software measurements and remaining boundaries

Each row below uses the retained P3 workload (1024 words, four jobs, 4096 CPU
iterations, seed `0x12345678`). Cycle counts are raw measured windows; the report
also retains the separate empty-window calibration, retired instructions, bus
observations and CPI. These are different compiler/layout binaries, not a
matched-binary architectural speedup claim.

| Case | BIN bytes | CPU cycles | Copy cycles | Burst-16 DMA cycles | Chunk-256 cycles | Observed stack bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| compat-os-flat | 11132 | 98682 | 164096 | 18881 | 511389 | 692 |
| perf-o2-plain-flat | 10148 | 73951 | 127157 | 16520 | 373812 | 648 |
| perf-o2-lto-flat | 8592 | 73974 | 127180 | 13980 | 339167 | 552 |
| perf-o3-plain-flat | 10404 | 73951 | 127157 | 16058 | 372690 | 628 |
| perf-o3-lto-flat | 9872 | 73974 | 127180 | 13980 | 339167 | 564 |
| perf-os-plain-flat | 8000 | 74064 | 139487 | 18421 | 394248 | 692 |
| perf-os-lto-flat | 6360 | 74064 | 139484 | 14169 | 343769 | 584 |
| perf-o2-plain-banked | 10184 | 73954 | 114875 | 16523 | 374016 | 648 |

Compare compatible Os with performance Os to hold optimization/layout fixed;
compare performance O2 with/without LTO to isolate that selection; compare the
two O2/no-LTO rows for placement. BIN bytes exclude BSS, and observed stack use
does not prove a static upper bound. Each image reserves at least 4096 stack
bytes. Bank conflicts remain unavailable because P4 hardware is not implemented.
The original P1 binaries and their historical phase/source identities are retained.

Current Mini PIO compatibility is additionally retained at
`build/ics55-2026-10-09-20-00-d0c568d0142e/meta/tiny-r2-p3/pio-retry/evidence.json`.
The initial default 180-second attempt emits SIM_TEST_TIMEOUT despite emulator
exit zero, and fails the simulation checker. A retry of the identical model and
BIN with `--fast-flash -t 1800` passes in 323.930 seconds, including 4/16/33/65-word
frames, IRQ count 5, exact waveform/reset-low checks, underflow/abort recovery,
and observer totals `frames=6 completed=4 underflows=1 aborts=2 dma_starts=0`.
The evidence records the before/after model and BIN hashes, command, manifest,
compile/run logs and a post-build recheck of 487 compiled input sizes/mtimes.
It is explicitly a post-build audit; neither the failed timeout nor the original
unsupported Mini DMA attempt is relabeled as a passing run.

Product-integrated WS2812 DMA/IRQ service budgets remain deferred under approved
option A to an actual supported route, including Tiny R2-P6. Full-product,
physical, silicon and publication-PDF qualification remain outside these results.
Human review and acceptance of TINY-R2-P3 are required before authorizing any
R2-P4 implementation; this execution does not automatically advance a phase.

## Subsequent P1 HAL race fixes (2026-10-10)

This approved follow-up starts from `3e46cc80e2d2243233d284b7cd9583714b0773bb`
and preserves the preceding uncommitted documentation/evidence updates. The
specification remains blob `7e19de49d49efaafacccfa85671e314d53dd15a4`.
Only `crt/src/hal/dma.c`, `crt/src/hal/ws2812.c` and
`tests/c/test_runtime.c` change executable/test source. No public interface,
register, RTL, profile, dependency, warning baseline or metric policy changes.

- WS2812: completing between INTR_STATE and STATUS reads no longer produces a
  false I/O error. Idle without an observed sticky DONE retains ownership and
  returns to the caller; the next bounded service checks error, abort, deadline
  and completion again. No refill is admitted to an idle core. DMA response
  draining and source-buffer lifetime rules are unchanged.
- DMA: one outer interrupt save/restore spans legacy TCD configuration,
  descriptor publication and START, including ownership rejection. Nested HAL
  helpers preserve the saved mask; the blocking completion wait is outside this
  critical section. Test-only IRQ hooks model a pending ISR at mask restoration
  and do not appear in target builds.
- Deterministic production-HAL host tests cover an ISR trying to lease the
  channel during TCD publication, rejection without modifying an existing lease,
  an initially masked caller, completion between WS2812 register reads, delayed
  sticky DONE, genuine error/abort and expiry while idle. Existing final-B drain,
  timeout ownership and 16-word FIFO admission tests remain enabled.

New evidence is rooted at
`build/ics55-tiny-2026-10-10-09-00-b4aa59f3e5d9/meta/tiny-r2-p3-races/`.
The timestamp is a fixed build label; each structured result records actual UTC
start/end times. `source.json` records the base revision, dirty state, locked
tool identities, input hashes, source archive and worktree patch. Its combined
ICS55/IHP130 source/test/spec digest is
`dfa171fc1adbdfc5c7c9d31ef4ac7ba1a66710caac0fb13b869ddac89186b2f7`.
This digest's input set differs from the earlier compiler-matrix input set.

Before fixes, `host-red.{log,json}` records host test exit 10 (TCD race).
After the TCD fix alone, `host-ws-red.{log,json}` records exit 11 (WS2812 race).
Both fail the enclosing Make command. `host-green.{log,json}` passes after both
fixes; `policy.{log,json}` additionally covers the final error/abort/deadline and
interrupt-mask cases, C formatting and policy checks. `focused.{log,json}` has
156 passing tests, including P3, Tiny baseline, DMA/register parity, WS2812 RTL
and publication API behavior. No new MISRA deviation is introduced. These are
partial project checks, not complete MISRA certification.

Commands run with the existing locked environment:

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q tests/test_tiny_r2_p3.py tests/test_tiny.py \
  tests/test_tiny_r2_baseline.py tests/test_dma.py \
  tests/test_dma_register_parity.py tests/test_ws2812.py \
  tests/test_publication_api_bundle.py
ruff check .
git diff --check
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only --dry-run
BUILD_TIMESTAMP=2026-10-10-09-00 JOBS=3 JAVA_TOOL_OPTIONS=-Dsbt.server.forcestart=true \
  python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
BUILD_TIMESTAMP=2026-10-10-09-00 JOBS=3 JAVA_TOOL_OPTIONS=-Dsbt.server.forcestart=true \
  python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
BUILD_TIMESTAMP=2026-10-10-09-00 JOBS=3 JAVA_TOOL_OPTIONS=-Dsbt.server.forcestart=true \
  python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only
JAVA_TOOL_OPTIONS=-Dsbt.server.forcestart=true make CONFIG=configs/ci/ics55.mk \
  SOC=MINI PDK=ICS55 APP=ci_smoke WS2812_P3_ACCEPTANCE=YES HAVE_CSR=YES \
  LINK_TYPE=ld2_all_sram SIMU=VERILATOR VERILATOR_SIM_ARGS=--fast-flash \
  SOC_SIM_TIME=3600 BUILD_TIMESTAMP=2026-10-10-09-00 JOBS=3 firmware sim
```

Regression dry-runs passed; Tiny PR and nightly select identical commands, so
the long run is not duplicated. All three regression executions passed once;
their exact commands and verdicts are retained as
`regress-{tiny-ics55,tiny-ihp130,mini-ics55}.{log,json}` in the new evidence root.
Durations are 3210.491 seconds (Tiny ICS55), 2205.505 seconds (Tiny IHP130),
and 3170.591 seconds (Mini ICS55 behavioral-only). Mini PIO passes once in
423.766 seconds including build, with 4/16/33/65-word frames, five IRQs and
observer totals `frames=6 completed=4 underflows=1 aborts=2 dma_starts=0`.
Its variant is `build/ics55-2026-10-10-09-00-d0c568d0142e/`.

`audit.py` and `evidence.json` retain the final artifact audit: all 1287 captured
source/test/spec inputs are unchanged, 487 Mini PIO compiled inputs retain their
recorded sizes/mtimes, and the firmware/model/log/result hashes are recorded.
The Mini model audit is explicitly post-build. Eight ordinary regression
simulations are independently checked against their executable success marker,
command exit and forbidden-error rules. All selected targets, including the
current Mini assembly fixture, require `SIM_TEST_PASS`; UART output is not used
to infer success. This evidence is in addition to the separate PIO audit.

Current Tiny synthesis/netlist/STA results are in
`build/ics55-tiny-2026-10-10-09-00-42d5beccb726/` and
`build/ihp130-tiny-2026-10-10-09-00-bff91e3529ba/`. Both netlist checks pass;
STA command success does not mean timing closure. Observed max WNS/TNS remain
-41.14 ns / -508669.53 ns (ICS55) and -94.28 ns / -1594880.00 ns (IHP130),
with min WNS/TNS zero. Raw reports are `sta/opensta/timing_metrics.rpt`.
Lint baseline comparisons still fail as non-blocking regression observations:
459 new signatures for ICS55 Tiny, 403 for IHP130 Tiny, and 1536 new / 118
resolved for Mini, with zero increased signatures. No baseline was changed.
Build logs also retain a roughly four-second generated-file clock-skew warning;
these were fresh variant builds, and the input audit passed.

The old compiler/layout matrix, full Pytest and earlier timing observations stay
bound to `3e46cc8`; they are not reattributed to this follow-up. The compiler
matrix and full Pytest are not rerun for these isolated C changes (no build or
Python implementation changes). Product-integrated WS2812 DMA/IRQ budgets remain
deferred under option A; no Mini DMA-to-MMIO route is added. Human P3 acceptance
and separate approval are still required before R2-P4. Per the maintainer's
instruction, long checks default to a single execution; additional repetitions
need a concrete failure/inconsistency or an explicit frozen acceptance rule.
