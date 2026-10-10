# Tiny MCU Verification Record

## TINY-R2-P3 implementation in progress (2026-10-08–10)

The retained source-bound compiler/layout matrix is complete for commit
`3e46cc80e2d2243233d284b7cd9583714b0773bb`, source digest
`a7fc5112cd6f20df956243c4d081a6a31ede6192cd270e3c13340557b0e58776`.
All eight configurations pass ordinary Tiny acceptance and three deterministic
Verilator cold starts. `compat-os-flat`, `perf-o2-lto-flat` and
`perf-o2-plain-banked` also pass three native Icarus cold starts, with exact
cross-simulator sample identity. The structured measurement report is
`build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json`.
It records software measurements only; it does not close phase acceptance,
physical timing, hardware bank conflict or Mini integrated-DMA gates.

Quality evidence for that committed source is complete: full Pytest reports 1629 passed and
one environment skip for missing `pypdf`; focused P3 tests and the embedded/RTL
quality checks pass. Its Tiny PR regressions pass for ICS55 and IHP130, and
Mini ICS55 behavioral-only compatibility passes. Negative STA margins and
non-blocking lint observations remain recorded as observations.

Exact commands, measurements, current evidence roots and remaining qualification
limits are in the final section of the [P3 review-fix record](tiny-soc-r2-p3-review-fixes.md).
Human review and acceptance remain required before any R2-P4 work.

### Subsequent P1 race-fix follow-up

The approved follow-up fixes WS2812 completion between register reads and
legacy TCD publication across an ISR lease acquisition. Current source is
`3e46cc8` plus the two HAL fixes and deterministic host tests; the matrix above
remains evidence for the original commit. New evidence is under
`build/ics55-tiny-2026-10-10-09-00-b4aa59f3e5d9/meta/tiny-r2-p3-races/`.
The two new tests fail before their respective fixes and pass afterward;
C format/policy/host checks and 156 focused tests pass. Mini PIO compatibility
also passes once with strict SIM_TEST_PASS and no forbidden markers. Tiny
ICS55/IHP130 PR and Mini ICS55 behavioral regressions each pass once. Final
`evidence.json` checks all 1287 source inputs, 487 Mini PIO compiled inputs and
all eight ordinary regression simulations. Lint baseline differences and
negative STA remain observations; no timing closure is claimed. See the final
review-fix section for commands, hashes, exact paths and unrun gates.

Per the maintainer's follow-up instruction, long checks default to one execution;
repeat only for a concrete failure/inconsistency or an explicit acceptance
requirement. This follow-up does not repeat the three-cold-start compiler matrix.
It does not waive any frozen qualification requirement or reattribute old runs.

### Historical development snapshot

The 2026-10-09 execution snapshot in the [P3 review-fix record](tiny-soc-r2-p3-review-fixes.md)
records all eight ordinary Tiny/Verilator compiler experiments completed, with
selected Icarus groups still running at that snapshot. The then-current full Pytest result was
1531 passed, 4 failed, 94 fixture errors and 1 skipped; configuration-declaration
and publication source/fixture drift were still open. IHP130 Tiny PR completed with
non-blocking lint observations and negative STA margin. These results do not
replace the final results above or imply human phase acceptance.

The [P3 review-fix record](tiny-soc-r2-p3-review-fixes.md) closes the retained
banked O2 Icarus finding: all three runs completed successfully and match the
three Verilator samples after artifact/log/command revalidation. The Mini
WS2812 finding remains open: the current Mini memory-only DMA data plane has
no route to WS2812 TXDATA, independently reproduced by the production crossbar
fixture. Its failed integration run is not relabeled a pass. The user explicitly
approved option A on 2026-10-08: retain this unsupported boundary, validate the
shared DMA algorithm through host/standalone checks, and use the supported Mini
PIO path for compatibility. No production fabric change is part of this follow-up;
product-integrated DMA/IRQ service budgets remain pending an actual route.

Option A is implemented and its supported-path checks pass. Mini PIO evidence
is bound at
`build/ics55-2026-10-08-22-57-d0c568d0142e/meta/tiny-r2-p3/option-a-evidence.json`:
4/16/33/65-word frames, real DONE IRQ, exact serial waveform/reset-low,
underflow/abort recovery, zero DMA starts and strict TEST_STATUS/SIM_TEST_PASS.
Focused checks report 96 passed; C/RTL quality, Ruff and diff checks pass.
The old Mini DMA failure remains failed/unsupported evidence, not a PIO pass.
The full compiler/placement matrix and broader regressions were pending in this
initial record; human phase acceptance remains pending. See the review-fix record for exact commands,
artifacts, historical attribution and unrun gates.

The user explicitly approved the P3 preflight and implementation on source
`bab01352f8f7c80e39546b04e3ed37a3d927f475`, with a clean worktree at entry.
The specification blob is `7e19de49d49efaafacccfa85671e314d53dd15a4` and the
preflight ledger blob is `bb18d58598eb7e60a166c19fc9da60407ce4bd4c`. This authorizes
continuing from the implemented R2-P2 and ICS55-P1 SAFE24 foundation; it does not
retroactively turn their recorded human-review or physical gaps into passes.
Original phase IDs, historical evidence and qualification limits are retained.

The [P3 runbook](tiny-soc-r2-software-scheduling.md) defines compiler/layout
experiments, shared finite DMA/WS2812 service, ownership and exact commands.
The initial entry recorded implementation and validation in progress; it did not
claim phase completion or performance improvement. The existing GNU toolchain
was used as requested; no dependency version has been changed.

Early development testing found a compressed-instruction acceptance bug:
`rs_mcu_unmapped_probe` assembled its faulting load as 16-bit `4108`, while
the test trap handler advances MEPC by four bytes. The performance image
therefore skipped its return, first surfacing as I/O code 10 and, with diagnostic
layout, a subsequent store-access fault. Explicit `.option norvc` around the
faulting load restores the intended fixed-width probe. The repaired performance
banked normal image passes strict Tiny acceptance. This is an acceptance-fixture
fix, not a CPU, register ABI or toolchain replacement.

Provisional development evidence is under
`build/ics55-tiny-performance-2026-10-08-16-14-b6fb322b1bce/`;
`meta/tiny-r2-p3/` retains the first failure, separate diagnostic source/ELF
and the Mini SBT sandbox failure. These are development attempts, not the final
source-frozen compiler matrix. Mini SBT required the existing environment
restriction on Unix socket creation to be lifted for the same approved command.

## TINY-ICS55-P1 implementation (2026-10-07–08)

Implementation is based on committed source
`ecac3559b0ba67fa2630003ad718657969c78af4` plus the retained working-tree diff.
The worktree was clean at entry. The preflight specification/ledger Git blobs
were `713f3d5a0d04a7b2fc4c66838e9ceaf6c7551263` and
`87bc267759d863d98f200e2740abcaa0dcba28a5`. This record is separate from the
earlier documentation/dependency refreeze and IHP130 R2 measurements.
Implementation and validation are complete for review; human phase acceptance
is still pending by this entry.

## TINY-ICS55-P1 review fixes (2026-10-08)

The read-only review found two implementation issues and both are corrected in
the current working tree:

- The quality workflow now restores the locked ICS55 PDK, SRAM views and PLL
  checkout before the mandatory Pytest step. A fresh checkout with no ICS55
  cache restored all inputs through `setup-pdk`; lock revisions and archive
  hashes were unchanged.
- The SAFE24 audit now traces SYS backwards through the selected ICS55
  `P65_1233_PBMUX` input receiver and `BUFX0P7H7R` clock buffer to
  `extclk_i_pad`, verifies constant CMOS input enables and rejects constant,
  unknown, wrong-source, inverter, mux and multiple-driver paths. It records
  the source trace in the structural report.

Focused review-fix tests pass (`128 passed`), including negative clock-source
mutations and the quality-workflow cache-miss ordering assertion. Ruff,
yamllint, actionlint, dependency-lock validation, regression dry-runs and
`git diff --check` pass. A fresh source capture, Yosys synthesis and OpenSTA
run at
`build/ics55-tiny-2026-10-08-10-05-42d5beccb726/` produce a current
`meta/tiny-ics55-p1/report.json`; this remains SAFE24 synthesis/STA observation,
not physical qualification. Human review and phase acceptance remain required.

The [platform runbook](tiny-ics55-platform.md) defines ownership and commands.
The default `configs/ci/ics55-tiny.mk` selects TINY/ICS55, HAVE_PLL=YES,
128 KiB main SRAM and external 24 MHz SYS. The PLL is physically represented
but disabled; standalone PLL192/240 tests do not enable those SoC rates.
IHP130 remains an explicit no-PLL profile, and Mini defaults are unchanged.

Changes are limited to platform/profile selection, generated identity and
filelists, technology adapters, the standalone PLL digital backend, native
pad readback, JTAG smoke, netlist/STA evidence and matching publication-source
parsing. Tiny explicitly selects 32 locked 1024x32 SRAM macros through a
default-off shared parameter; this is not R2-P4 logical SRAM banking. Tiny's
GPIO input remains enabled while driving, with the legacy Mini default intact.
No register/API, address, IRQ, DMA channel/request, package assignment or
private Crypto storage change is introduced. No new MISRA deviation applies.
Dependency versions, warning signatures and metrics policy are unchanged.

Final validation uses `BUILD_TIMESTAMP=2026-10-07-23-22`:

- Primary CI/evidence variant: `build/ics55-tiny-2026-10-07-23-22-42d5beccb726/`.
  Commands, logs and results are in `meta/tiny-ics55-p1/validation/`; the
  captured source/tools/views are selected by `meta/tiny-ics55-p1/latest-inputs.json`.
- Matched workload variant: `build/ics55-tiny-2026-10-07-23-22-b4aa59f3e5d9/`,
  APP=bringup. Each simulator runs three cold starts of the original retained
  P1 HEX, SHA-256 `ba24c2dfd727a905f39b644df254e47262c39ab4960ff2614be44402020758b2`.
  Its original image/source manifest remains under
  `build/ihp130-tiny-2026-10-05-12-30-fa1c4ce1e303/meta/tiny-r2-p1/binaries/image-ozwo38_b/`.
  The seven fixed workloads are empty-window calibration, CPU, memory, DMA
  burst 1, DMA burst 16, CPU/DMA contention and descriptor-chain DMA. There
  is no recompilation or layout experiment in this comparison.

| Gate | Current result / retained evidence |
| --- | --- |
| Focused checks after the JTAG correction | PASS; 178 platform/provenance/baseline/build tests; earlier memory/debug/clock and publication checks also passed |
| Final policy and formatting | PASS; `validation/policy.json` and `rtl-format-retry.json`; C format/policy/host tests, Ruff, locked dependency schema, RTL style/readiness and changed-file formatting |
| Regression definitions | PASS; `validation/dry-runs.json`; Tiny ICS55 PR/nightly are identical, plus IHP130 Tiny and ICS55 Mini PR expansion |
| Tiny ICS55 PR | PASS; `validation/tiny-ics55-pr.json`; firmware, Verilator SVA/JTAG, native Icarus/JTAG, Yosys, strict Tiny netlist boot and OpenSTA execution |
| Tiny IHP130 PR | PASS; `validation/tiny-ihp130-pr.json`; separate compatibility artifacts, not relabeled ICS55 evidence |
| Shared Mini compatibility | PASS for firmware, memory/pin/topology/clock-domain checks and Verilator SVA lint; `validation/mini-compatibility.json`, `mini-rtl-lint-retry.json`; full Mini PR not run |
| Source / macro audit | PASS; `meta/tiny-ics55-p1/report.json`, `syn/yosys/tiny-ics55-netlist.json`; 32 SRAM macros, 2177 CPU clocked cells on direct SYS, one PLL with constant EN=0 |
| Matched Verilator workload | PASS, three identical samples, same original HEX; all seven workload samples also equal the historical IHP130 reference |
| Matched Icarus workload | PASS after timeout recovery; runs 1/2 at 13862.428/14242.835 s and recovered run 3 at 15379.18 s. All three samples match Verilator and historical IHP130; original exit-124 attempt is retained, with per-run budgets in `matched-report.json` |
| Full Pytest | PASS; 1568 passed / 1 skipped in 3769.75 s on final source; `validation/pytest.json`; the optional publication retrieval test lacks `pypdf` |
| Warning comparison | Non-blocking FAIL observations retained; no signatures regenerated or waived |
| Metrics | Collected on the actual APP=ci_smoke variants; `validation/ics55-ci-metrics.json`, `ihp130-ci-metrics.json`; policy remains observe |

In this table `validation/` is relative to the primary variant's
`meta/tiny-ics55-p1/`. Verilator SVA CI variants use suffixes `2eb98c0e1fae`
(ICS55) and `39ea34c082ac` (IHP130); IHP130's ordinary CI variant uses
`bff91e3529ba`, all with the same fixed timestamp. Tiny netlist `netsim-boot`
uses a retained 220-byte assembly image and TEST_STATUS/SIM_TEST_PASS; it is
not the Mini UART-only boot target or full C netlist qualification.

The native source/input digest is
`9566b3f2c06b21b3e06a4513d0163cc9ffcb63e6d68dd665a31f61be6c1e9def`.
The report rechecks consumed Verilog/JSON/configuration and audit-script hashes,
source snapshots, locked tools and post-capture execution timestamps. The
seven locked Tiny tools and PDK/model inputs retain their existing versions.
Mini's first lint attempt failed at SBT's local Unix socket in the sandbox;
the same source/configuration command passed with that environment restriction
removed. The initial multi-file formatter invocation was unsupported; individual
read-only verification passed without changing source.

The original Icarus attempt is retained as failed at
`meta/tiny-r2-p1/workloads/iverilog/attempt-_fqxpoam/attempt.json` below the
matched variant. Runs 1/2 each completed all seven cases and strict Tiny
TEST_STATUS/SIM_TEST_PASS, with samples identical to Verilator. Run 3 printed
part of its final TCD record before host timeout; the missing completion marker
prevents acceptance. The generated recovery driver
`meta/tiny-ics55-p1/retry_icarus_run3.py` below the primary variant checks original
source/generated-input/model/tool/image hashes, preserves the two completed
run records, and launches a new cold start for repetition 3 only. It retains
the failed attempt and individual per-run timeout values. The recovered run 3
passed in 15379.18 seconds with the same seven samples and strict markers. HEX,
simulator model,
workload parameters and the 100000000-cycle limit are unchanged; this is an
execution-budget recovery, not a compiler, layout or architecture experiment.
The first recovery launch stopped during provenance validation before starting
simulation: the stock runtime validator requires a common timeout for all runs.
The generated recovery adapter now invokes that unchanged validator separately
with each original command's declared budget. The final phase join uses
`collect_matched_report.py` and writes `meta/tiny-ics55-p1/matched-report.json`
below the primary variant, explicitly preserving per-run budgets and the failed
attempt. It does not claim that the ordinary homogeneous-budget baseline report
command accepts a mixed-budget record. Project implementation/validator sources
and all original run records remain unchanged by this operational recovery.

Final SAFE24 core STA observations, in ns:

| PDK | WNS max | TNS max | WNS min / TNS min | Verdict |
| --- | ---: | ---: | --- | --- |
| ICS55 | -41.14 | -508669.53 | 0.00 / 0.00 | Timing FAIL; observational in this phase |
| IHP130 | -94.28 | -1594880.00 | 0.00 / 0.00 | Timing FAIL; compatibility observation |

ICS55 `sta/opensta/sys-setup.rpt` starts at the XPI reset leaf, fanout 4707,
and ends at RX FIFO storage; its SYS hold report's worst reported slack is
+0.08 ns. `coverage.rpt` records 43 inputs without input delays, 52 outputs
without output delays and 93 unconstrained endpoints. These are the retained
core-only analysis boundary, not full-chip IO closure. The clock report has
SYS 41.666666667 ns and JTAG 100 ns; no active PLL generated clock is claimed.
The electrical/recovery/removal/pulse-width/minimum-period and SRAM input/return
reports remain under the same `sta/opensta/` directory.

Direct warning checks on the CI variants report 21 new Yosys signatures for
ICS55, and 14 Yosys plus one Icarus signature for IHP130, relative to the
stored baselines. Lint comparisons report 459/403 signatures respectively.
Neither Tiny profile has a stored RTL-lint baseline, so every normalized
lint signature is classified as new. The reports include unused parameters,
empty ports, vendor model limitations and ABC's Liberty-cache fallback; they are
not counts of defects introduced by this phase. The regression preserves
their failed observation status while its functional commands pass.

The earlier development variant
`build/ics55-tiny-2026-10-07-21-00-42d5beccb726/` retains failed attempts:
missing unused SRAM interface, wrong 16 KiB macro selection, GPIO readback
failure and insufficient constant-disabled PLL proof. Corrected development
Verilator/JTAG, mapped-netlist audit and SAFE24 STA subsequently ran, but those
results are not substituted for the fresh final campaign. NFS clock-skew
warnings are retained; final variants and forced workload compilation avoid
reuse of those earlier simulator outputs.

The intermediate `2026-10-07-23-06` campaign exposed an IHP130 Icarus JTAG
testbench reset-initialization failure. Four-state waveform inspection showed
internal TRST remaining X until release because TCK started after reset. The
opt-in test now clocks TCK during asserted external reset before its TAP/DMI
sequence; no reset RTL changed. A bounded Icarus probe then completed
halt/resume. Ongoing simulations in that campaign were explicitly interrupted
before final source recapture; partial workload passes are not final evidence.
The initial full Pytest was also interrupted and restarted on final source;
its interrupted record stays in that earlier directory. After the correction,
178 focused platform, provenance, baseline and build tests passed.

The required acceptance remains command success, valid sticky TEST_STATUS,
SIM_TEST_PASS and no forbidden error marker. UART alone is insufficient.
Boot-only netlist checks are narrower than full C netlist acceptance. Timing
violations remain failures under the observational pre-final policy; no
behavioral result qualifies physical timing, analog PLL lock, PVT, power,
package or silicon. The PLL has no LOCK output, no characterized timing arcs
and an unresolved upstream license. Its ideal digital supply ties do not
define physical rail integration. Full RCU/source switching remains R2-P7.

The next action is read-only feature review followed by explicit human phase
acceptance. No commit, push, PR or next-phase advancement is authorized here.

## ICS55 default and final timing policy refreeze (2026-10-07)

The [2026-10-07 normative policy](tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07)
selects TINY/ICS55 with `HAVE_PLL=YES` and SAFE24 startup as the default target.
At refreeze, `configs/ci/ics55-tiny.mk` and TINY-ICS55-P1 platform implementation
were pending; `configs/ci/ihp130-tiny.mk` was the executable compatibility baseline.
The existing 614fa623 commit adds shared ICS55 SRAM inputs, not Tiny enablement.

All pre-final post-synthesis timing results are observations rather than phase
completion gates. Keep applicable analysis attempts, macro mapping, netlist
function, reset/protocol evidence and explicit FAIL/NOT_RUN attribution.
Functional tests, accepted-work barriers, real-time deadlines and strict Tiny
command/TEST_STATUS/SIM_TEST_PASS/forbidden-error checks remain mandatory.
No warning baseline, metric policy or RTL maturity state is promoted.

The sole final timing campaign combines TINY-R2-P11, SPI-P5, PIOLITE-P5 and
PPALITE-P5 after Tiny foundation, SPI, PIO-lite and PPALite functional work.
Their checklists require the same complete-product source/config/PDK/netlist;
none is an intermediate physical dependency of another feature's functionality.
Phase titles containing IHP130 remain historical identifiers; ICS55 is the new
default and IHP130 compatibility results must remain separately attributed.

PLL dependency: `pdk_ics55_pll`, revision
`6ebb1a8f7f4ccbccdb7f587664fdfe63cd39e61b`, upstream `PLL_V02p1`.
Its managed checkout is `.cache/retrosoc/sources/ics55_ecos_pll`.
Cell/pin-only Liberty, absence of a LOCK output and unresolved upstream license
remain explicit integration/release gaps. Acquisition is not hardware evidence.
Refreeze validation and downloaded-view hashes are recorded separately below.

The previous freeze and all executed R2-P0/P1/P2 and legacy records below retain
their original dates, profiles, source identities, measurements and verdicts.
They do not qualify ICS55 or satisfy the new platform-enablement phase.

This record accompanies the [Tiny Gen1 contract](tiny-soc.md). The active R2
verification plan below covers Target SoCs: `TINY`, feature `tiny-soc`, and
the approved performance refreeze. `R2` is a roadmap revision, not a new IP
or register ABI version. The selected executable baseline remains
`configs/ci/ihp130-tiny.mk`, IHP130, 24 MHz/no PLL; faster configurations and
their physical acceptance do not exist merely because this plan names them.

The R2 freeze itself changed documentation only. Separately authorized
R2-P1 implementation and validation are recorded below. Its functional and
measurement baseline was accepted with the explicit R2-P2 implementation
approval on 2026-10-06; the recorded physical gaps remain open. R2-P2 work is
recorded separately below; later implementation and qualification remain pending.
Historical `TINY-P0` through `TINY-P12` identifiers and evidence are preserved
under their original scope; the mapping in the main contract transfers
outstanding obligations without renaming old results or declaring them passed.
Other PDK qualification, new SPI/PIO/BootROM IP and changes to QFN64 or the
frozen IO/power-pad budget are outside the original performance-only R2
refreeze. PIO-lite is now a separately approved standard-product extension
under [piolite.md](piolite.md), with its own pending evidence matrix below;
it does not renumber or retroactively expand the R2 phase results.
SPI is also a separately approved standard-product extension under
[spi.md](spi.md), with pending evidence below. The original performance-only
exclusions remain in force for historical R2 work; the separate SPI approval
does not turn older results into SPI acceptance.
PPALite is the separately approved 2026-10-05 standard-product extension in
[ppalite.md](ppalite.md). Its RAW-compatible inline processing and source
qualification have independent pending gates; no earlier result covers them.

The executed historical sections describe the 2026-09-25 initial baseline,
with two UARTs, two I2C controllers and the legacy pad mapping. The working
tree was uncommitted when that evidence was collected and its readiness
remains `prototype`. Those results do not validate the later package,
shared-IP/clock/reset, DVP/framebuffer, R2 performance, PIO-lite, SPI or PPALite freezes.

## PIO-lite planned extension evidence

Target SoCs: `TINY`; feature slug: `piolite`; approval date: 2026-10-04.
The standard-product target adds two state machines sharing 32 x 16-bit
program storage, 32-bit ISR/OSR, 16-bit X/Y counters and separate 8 x 32-bit
TX/RX FIFOs per state machine. The engine, APB and host DMA endpoints use
PCLK at the existing 24/48/60 MHz targets. This section records required
future evidence only; no assembler/model, RTL, firmware, DMA, simulation,
formal, synthesis, timing, physical or silicon acceptance has been executed
for PIO-lite by the freeze. Four-state-machine expansion is not MVP support.

The committed `configs/ci/ihp130-tiny.mk` IHP130 24 MHz/no-PLL profile has no
PIO-lite integration. New address/IRQ/request/RCU allocations remain planned
until their complete executable paths and truthful capabilities exist. The
authoritative phase titles and requirements remain in [piolite.md](piolite.md).
The detailed case matrix and documentation-check record are maintained in the
[PIO-lite verification ledger](piolite-verification.md).

| PIO-lite phase / area | Required evidence and completion boundary | Status |
| --- | --- | --- |
| PIOLITE-P0 / contract | Approved ISA/ABI, resources, pin ownership and lifecycle; consistent linked product/GPIO/DMA allocations; preserved legacy/R2 phase IDs/titles and unchanged QFN64 terminals; documentation links and commands. | Documentation freeze only; no implementation result |
| PIOLITE-P1 / model and assembler | Deterministic encoding and model traces; valid/invalid opcodes, operands, labels, branches, wrap and program-size boundaries; shared 32-word allocation; software error handling and generated program metadata against the frozen ISA. | Pending |
| PIOLITE-P2 / core and registers | Both independent SMs, divider/delay/branch/shift/counter boundaries, TX/RX full/empty and stalled-instruction behavior; illegal accesses, W1C races, stop/abort/reset, stale-data isolation, program-write restrictions and configuration conflicts; directed/randomized model comparison and focused formal properties. | Pending |
| PIOLITE-P3 / Tiny integration and HAL | APB `0x1001C000..0x1001CFFF`, IRQ24, RCU target15, requests `PIOLITE_TX=14` / `PIOLITE_RX=15`, actual capability discovery, handwritten register parity, freestanding bounded HAL and actual R2-P6/P7 prerequisites; no fourth AXI master or ninth DMA channel. | Pending |
| PIOLITE-P3 / pad and lifecycle ownership | `USER_SELECT` reach to all GPIO0-31; unchanged ALT0/ALT1 and dedicated boot/debug/control pads; conflicts, high-impedance reset, existing GPIO synchronizer plus registered bypass/filter stage with `FILTER_ENABLE=0`, input latency and release; no new PIO synchronizer/raw-pad bypass; reject GPIO gate/reset while PIO owns any pad, including multi-target commands; clock-change and PIO gate/reset drain/restart barriers. | Pending |
| PIOLITE-P4 / DMA and protocol programs | Approved pin-level acceptance programs in Icarus and Verilator; independently checked data, edge/bit timing, first/last transfer, short frames, FIFO starvation/overflow, bounded recovery and strict Tiny terminal verdict; source-bound throughput and worst observed service gaps. | Pending |
| PIOLITE-P4 / system contention | TX channel3 only after bulk-owner release, RX channel2 only after complete camera release; no theft of Crypto4/5 or I2S6/7, correct abort/final-response drain and backpressure; CPU/control progress and real FIFO service budgets with actual permitted background traffic. | Pending |
| PIOLITE-P5 / physical product | PIO-inclusive netlist and source/profile/PDK/corner identity; area/reset load, PCLK STA, GPIO ownership paths, input synchronizers, pad setup/hold/turnaround, simultaneous switching, package/power and CDC/RDC evidence; declared engine rate distinguished from external interface rate. | Pending |

`PIOLITE-P3` depends on the applicable accepted R2-P6/R2-P7 platform behavior.
`PIOLITE-P5` may share a run with `TINY-R2-P11` only when the same PIO-inclusive
source revision, configuration and physical inputs satisfy both contracts.
An earlier R2 netlist, standalone PIO test or another SoC's result cannot
qualify the extended standard Tiny product. Preserve 128 KiB main SRAM on
the same SYS source and rate as the CPU, three external AXI owners, eight
central DMA channels and all QFN64/power assignments in every integration run.

Record exact commands and executed simulator/proof coverage when tests are
introduced; a skipped/no-op RTL test or reserved request ID is not evidence.
Firmware uses SYSCTRL `TEST_STATUS` and the strict `SIM_TEST_PASS`/result-file
policy. Hardware, pad-speed and PPA claims remain pending until the specific
source/profile/PDK evidence passes.

## SPI planned extension evidence

Target SoCs: `TINY`; feature slug: `spi`; approval date: 2026-10-04.
The future standard product adds SPI0: an 8/16-bit PCLK master with separate
8 x 32-bit TX/RX FIFOs, a bounded display transaction queue and DMA V2.2
paced fixed-MMIO requests. Slave operation and continuous double-buffer
camera/display are deferred. The committed IHP130 24 MHz/no-PLL profile has
no SPI implementation; every implementation, simulator, proof, firmware,
workload, synthesis, timing, physical and silicon result below is pending.
The detailed matrix and documentation checks belong to the
[SPI verification ledger](spi-verification.md).

| SPI phase / area | Required evidence and completion boundary | Status |
| --- | --- | --- |
| SPI-P0 - Contract and DMA Extension Freeze | Approved SPI/transaction ABI and DMA V2.2 contract; only the four reserved Gen1 ALT cells added; all 64 perimeter assignments, existing assigned alternates and legacy/R2/PIO phase IDs/titles preserved; linked address/IRQ/RCU/request values and documentation checks. | Documentation freeze only; no implementation result |
| SPI-P1 - SPI Core and Register Implementation | All CPOL/CPHA and 8/16-bit cases, first/last bits, TX/RX FIFO boundaries, partial words, timing changes, CS setup/hold/inactive and retained-CS behavior; invalid register access, W1C races, timeout/abort, stale-session isolation and handwritten register parity. | Pending |
| SPI-P2 - DMA V2.2 Paced FIFO Integration | Requests 16/17 and truthful capability support, stable grants, single-beat FIFO MMIO, memory-side bursts/boundaries, TX/RX tails, no FIFO double-pop/push, complete descriptor/accepted-response drain and no stale restart; regress existing PIO14/15 and other consumers. | Pending |
| SPI-P3 - Tiny GPIO RCU and SDK Integration | Accepted R2-P6 frozen Gen1/eight-channel routing and R2-P7 lifecycle prerequisites; APB `0x1001D000..0x1001DFFF`, IRQ25, target16, native-ready/USER handoff, raw MISO capture, complete HAL queue/error/recovery behavior and truthful absent capabilities. | Pending |
| SPI-P3 / GPIO and lifecycle | Preserve sole PIO USER ownership and its synchronizer/filter path. Reject GPIO gate/reset while PIO USER_SELECT or latched SPI sessions remain, including prefill, CS-held and closing state and combined masks; no native-ready inference from zero USER_STATUS; guard loss closes admissions, invalidates work and requires explicit recovery. Gate/reset/PCLK changes need inactive CS and complete wire/DMA/MMIO/descriptor drain. | Pending |
| SPI-P4 - Display and Snapshot Application Qualification | Pin-level display command/data checks, D/C ordering and setup, source/pixel conversion, exact counts/guards/readback, zero early wire completion, deterministic error recovery and explicit board reset/backlight/TE solution. Camera/PSRAM cases require R2-P8/R2-P9 and execute capture, verify, display, then SD save. | Pending |
| SPI-P4 / shared ownership and throughput | TX3 only after bulk/PIO release and RX2 only after full DVP/PIO release; no theft of Crypto4/5 or I2S6/7. Measure actual wire rate, source conversion/staging, payload throughput and worst admitted service gaps; strict Tiny terminal verdict in Icarus and Verilator. Nominal PCLK/SCK or double-buffer assumptions are insufficient. | Pending |
| SPI-P5 - IHP130 Timing and Physical Qualification | Same SPI- and PIO-inclusive source/profile/PDK/corner/netlist as applicable final product gates; actual PCLK STA, SCK/MOSI/CS/D-C output and MISO round-trip setup/hold, GPIO guard/handoff, CDC/RDC, local reset, gate behavior, area/power/IO/package and board evidence. | Pending |

SPI0 is allocated at `0x1001D000..0x1001DFFF`, IRQ25 and RCU target16;
`SPI_TX=16` and `SPI_RX=17` are DMA request IDs, not new channels. Keep those
capabilities absent until complete implementation. Planned RCU support is
the actual implemented target mask; `0x0001FFFF` is valid only when every
target0-16 path exists. GPIO gate/reset veto is based on actual PIO ownership
OR the hardware-latched SPI session, not mutable claims or FIFO-empty alone.

The four changed Gen1 rows are GPIO27 ALT0 SCK, GPIO28 ALT1 MOSI, GPIO30
ALT1 MISO and GPIO31 ALT1 CS_N. GPIO30 ordinary D/C replaces MISO in the
write-only display profile. R2-P6 first migrates the legacy executable PWM
capture routes from GPIO30/31 ALT1 to the already frozen GPIO24/25 ALT0.
The complete camera profile plus display consumes all 32 GPIO and preserves
GPIO29 NSS1. Board control pins and external CS/reset bias need explicit
evidence; changing the internal mux cannot prevent external contention.

`SPI-P5` can share physical runs with `PIOLITE-P5` and `TINY-R2-P11` only
when all applicable contracts are satisfied on the same SPI- and
PIO-inclusive source revision, configuration, physical inputs and netlist.
Earlier baseline/R2 or PIO-only evidence does not qualify the new product.
PCLK24/48/60 and arithmetic SCK12/24/30 MHz are target cases, not measured
payload rates or qualified pad operation. Preserve the existing 128 KiB
CPU-rate main SRAM, eight DMA channels, three external AXI owners and fixed
QFN64/power budget. Record documentation validation separately from these
pending implementation gates.

## PPALite planned extension evidence

Target SoCs: `TINY`; feature slug: `ppalite`; approval date: 2026-10-05.
The [processor contract](ppalite.md) and [case ledger](ppalite-verification.md)
own formats, exact row layout and source/route/lifecycle acceptance. The
current IHP130 24 MHz/no-PLL profile has no PPALite. No model/core, source
repair, integration, firmware, simulator, proof, performance or physical result
is supplied by this documentation freeze.

| Phase | Required evidence | Status |
| --- | --- | --- |
| PPALITE-P0 - Contract and Camera Route Freeze | Approved processing/RAW route, source correctness predicates, exact metadata/ABI, unchanged package/pinmux/phase IDs, linked resources and documentation checks | Documentation freeze only |
| PPALITE-P1 - Stream Pixel Core and Reference Model | Exact RGB/YUV ordering, Y-only grayscale, step1/2/4 and phases, odd dimensions/row padding, input markers and backpressure, counters, APB/parity and independent reference evidence | Pending |
| PPALITE-P2 - DVP Route and Source Qualification | RAW byte/sideband parity, coherent source controls/statistics/errors, full word counts, repeated snapshots, source stop/tail ordering, route barrier and isolated abort/flush; preserve DVP V2/FIFO/Mini | Pending |
| PPALITE-P3 - Tiny DMA RCU and SDK Integration | Applicable R2-P6/P7, APB `0x1001E000..0x1001EFFF`, IRQ27/target17, exact direct DMA2/request11 admission, source guards, truthful capabilities, bounded HAL and no new DMA request/master | Pending |
| PPALITE-P4 - Camera Memory and Display Qualification | R2-P8/P9 and applicable SPI prerequisites; QVGA gray/decimated patterns, SRAM/PSRAM pixel/padding/canary checks, stride-aware SD/display, delayed responses/errors/recovery and both simulators | Pending |
| PPALITE-P5 - IHP130 Timing and Physical Qualification | Same complete PPALite/PIO/SPI-inclusive source/profile/PDK/netlist for all shared gates; actual clock, reset/CDC/RDC, storage, area/power, DVP/memory/Pad and physical evidence | Pending |

PPALite adds no Pad or alternate-function assignment. RAW remains reset-default;
processed direct DMA uses the existing DVP_RX11 endpoint and camera channel2,
with padded row size rather than raw `2*W*H`. The global all-DMA barrier applies
to RAW/PROCESS route changes, not every capture in a fixed processing route.
Retain existing SPI/PIO request meanings and other channel owners.

Source SYNC/SIZE/PARTIAL detection and current16-bit word statistics require
explicit closure; PPA counts cannot validate bytes the source discarded. Test
legal odd-pixel halfword tails separately from incomplete sensor pixels, source
counts above65535 words, coherent repeated EOF/error epochs and no premature
success-path flush. PIPE_DONE can precede source EOF or target B responses;
final valid data needs every predicate. Missing PIXCLK/cleanup acknowledgement
keeps the failed session closed and owned, not reset or buffer-reusable.

The upstream512 B FIFO still fills at raw byte rate. Processing reduces output
volume but not sensor clock or the raw no-service budget. New buffering counts
as extra slack only with proven occupancy/credit coverage. No measured FPS,
physical rate or complete extended-product qualification is implied here.

## R2 pending phase acceptance

The following is the active monotonically increasing sequence. Every phase
uses the preceding accepted R2 contract and its declared prerequisites; the
old P10 -> P7 execution order below is historical. Documentation approval is
not implementation acceptance. Final physical qualification is R2-P11 work,
not a prerequisite to the architectural improvements in R2-P3 through R2-P5.

| Active phase | Required evidence and completion boundary | Status |
| --- | --- | --- |
| TINY-R2-P0 - Performance Contract and Roadmap Freeze | Reviewable requirements, exact old/new phase mapping, invariant package/IO counts, same-frequency CPU/main-SRAM ownership, explicit performance budgets, links and commands. Record actual documentation checks separately. | Documentation freeze only; no hardware result |
| TINY-R2-P1 - Reproducible Baseline, Constraints and Measurements | Reviewed source/profile/lock/tool identity; current 24 MHz functional and workload baseline; clocks, reset endpoints, constraints and timing-exception audit; counters and comparison methodology. Historical WNS is a risk reference, not a refreshed measurement. | Functional/measurement baseline accepted by explicit P2 approval on 2026-10-06; timing, warning and physical gaps retained |
| TINY-R2-P2 - Reset Distribution and CPU/SRAM Clock Feasibility | Reset distribution and payload-reset semantics; locked IHP130 main-SRAM macro timing, candidate common CPU/SRAM periods and representative paths; early clock/reset feasibility with explicit gaps. No final routed/PVT pass is implied. | Implementation and evidence ready for review; all analyzed rates retain timing failures; phase acceptance pending human review |
| TINY-R2-P3 - Software and DMA Scheduling | Compiler and placement A/B results, finite DMA ownership, burst/chunk scheduling and available-path correctness; approved option A retains product DMA/IRQ budget qualification for the platform that supplies the route. | Matrix retained on `3e46cc8`; subsequent two P1 HAL fixes and focused/compatibility checks complete in the worktree; human review/acceptance pending |
| TINY-R2-P4 - Dual-Port Hazard3 and Four-Bank Local SRAM | Actual separate I/D paths, four independent 32 KiB bank frontends, SYS-clocked physical main-SRAM macros, local latency/fairness, FENCE.I, debug/reset and early inventory/SDC/macro-binding updates. | Pending |
| TINY-R2-P5 - Per-Target Concurrent Fabric | Cross-target concurrency, one combined transaction per target, central-DMA read/write overlap, AW/W binding, errors, simultaneous faults/counters and accepted-transfer drain. | Pending |
| TINY-R2-P6 - Shared IP and Eight-Channel DMA Integration | Legacy P7 obligations; shared PWM reporting, I2S slave and alternate-input-route prerequisites; common ABI/HAL parity; Crypto banks/lifecycle; truthful capabilities and affected Mini compatibility. | Pending |
| TINY-R2-P7 - Tiny RCU and Dual-Mode Clock/Reset Integration | Legacy P8 obligations with main SRAM in SYS and XPI in MEM; atomic rate changes, all actual CDC/reset barriers, clock failures, WFI leaf gating and reserved DVP controls. | Pending |
| TINY-R2-P8 - XPI PSRAM Framebuffer Bring-up | Legacy P11 obligations: real pin-level NSS1 device transport, CPU/DMA mapped-write readback, boundaries/recovery, payload rate and worst backpressure. | Pending |
| TINY-R2-P9 - DVP Camera Profile and Frame Capture Integration | Legacy P12 obligations: unchanged DVP ABI/FIFO, DMA2/request 11, exact frame length, final-tail drain, snapshots/crops, missing-clock recovery and camera/audio exclusion. | Pending |
| TINY-R2-P10 - System Performance and Regression Qualification | Complete current-profile functional regression and workload/contention A/B, measured real-time budgets, synthesis/macro mapping, netlist checks and explicit missing coverage. | Pending |
| TINY-R2-P11 - IHP130 Physical and Product Qualification | Final joint CPU/main-SRAM timing, CTS/reset distribution, extracted PVT/IO/package/power evidence, qualified clock/PLL inputs and device operating points; close remaining legacy P9 obligations. | Pending |

### R2 clock, reset and macro evidence

For new work apply the default ICS55 binding and timing policy above. The
following matrix retains frequency and functional obligations for both
explicitly selected PDKs; historical measurements remain IHP130-only.
The main 128 KiB SRAM includes its actual physical macro clock pins. It MUST
use the same SYS source and active frequency as the CPU, with no hidden
main-SRAM divider, CPU/main-SRAM CDC or half-rate fallback. The old P6/P10
assignment of main SRAM to MEM is historical and is superseded for R2.
Four logical 32 KiB banks do not mean four physical macros: verify the real
selected-PDK mapping (32 OpenECOS 1024x32 macros for ICS55) and preserve the
complete 128 KiB capacity. Crypto's six
private banks remain additional storage in PCLK and retain their own lifecycle.

| Target profile | CPU and actual main SRAM / SYS | XPI / MEM | Shared peripherals and Crypto / PCLK |
| --- | ---: | ---: | ---: |
| Safe boot | 24 MHz | 24 MHz | 24 MHz |
| No-PLL fast, XIN96 | 96 MHz | 96 MHz | 48 MHz |
| PLL I/O | 192 MHz | 96 MHz | 48 MHz |
| PLL peak | 240 MHz | 120 MHz | 60 MHz |

Also test external XIN24 and XIN48 at the declared 24/24/24 and 48/48/48 MHz
SYS/MEM/PCLK rates. These are target cases, not qualified operating points.
At 192/240 MHz the actual main-SRAM clock periods are approximately
5.208/4.167 ns. R2-P2 must inspect the locked macro timing views, minimum
period/pulse widths, setup/hold, clock-to-output and representative bank paths.
Wait states or a registered response do not repair a violated macro minimum
clock period. An unsupported target remains an explicit delivery gap; lowering
the common CPU/SRAM rate requires a reviewed profile/contract change and must
not silently restore CPU240/SRAM120. R2-P11 adds CTS, extracted parasitics,
skew/uncertainty and actual macro/standard-cell PVT evidence before rate claims.

R2-P1 audits the existing clock/reset inventory. R2-P4 updates it, the local
path constraints and physical macro instance bindings as soon as the new bank
hierarchy exists; it must not postpone those updates until RCU integration.
R2-P7 adds dynamic SYS lifecycle, XPI MEM division and the actual domain
bridges. CPU/main-SRAM accesses remain within SYS; DMA PCLK-to-SYS and
SYS-to-XPI MEM crossings retain complete request/response and reset barriers.
Main-SRAM control access follows SYS ownership. Rate reporting must make
`SYS_HZ` authoritative for CPU/main SRAM and `MEM_HZ` authoritative for XPI.

For clock transitions, acknowledge the RCU command before blocking new target
admissions on both local CPU I/D and external AXI paths. Exercise continuing
instruction fetch and data requests while draining all accepted bank operations,
frontend responses and crossing state. Blocked-but-unaccepted requests must
remain stable rather than refill the drain set; no accepted request may be
lost, replayed or completed twice across the common SYS clock change.

The existing WFI exception gates only the idle CPU leaf after its accepted
work drains. It does not divide SYS or gate the main SRAM, fabric or DMA
service paths. Verify IRQ/debug wake and ongoing DMA access while the CPU
leaf is stopped. Cold/warm/watchdog/hart/peripheral reset, asynchronous
assertion, five valid local release edges and CPU-last release all require
directed evidence. Missing AUDIO/PIXCLK or software Crypto READY must not
block CPU startup. A reset-done indication is not Crypto READY or ZEROIZED.

For ordinary FIFOs, removing payload reset is permitted only after proving
the existing observable empty/reset/flush behavior, no stale-word visibility,
correct validity/pointer state and restart barriers. Main SRAM remains
uncleared by reset. Crypto is not an ordinary payload-reset optimization:
retain immediate invalidation, scalar clearing, full required SRAM
write-zero/readback-zero sweeps and physical FIFO-payload erasure. Test late
responses, stalled outputs, interrupted scrub and no early erasure success.

### R2 functional and performance matrix

Every row is pending and must identify its requirement, R2 phase, exact
implementation, profile and executed test. Keep functional correctness and
cycle-level performance distinct from physical frequency qualification.

| Area / phases | Required cases and objective evidence |
| --- | --- |
| Independent banks and I/D paths, R2-P4/P5 | Exercise simultaneous I and D traffic to different banks plus DMA/SDIO traffic; prove each of the four 32 KiB banks has its own frontend and can serve independently. A bank decoder behind one serialized controller is insufficient. Cover every bank boundary, byte lane, first/last word and full-capacity/alias checks. |
| Local service and fairness, R2-P4/P5 | Measure from accepted CPU AHB address phase to terminal data-phase completion, with clocks running, an uncontended bank, response capacity available and no lifecycle stall. The engineering budget is <=3 SYS cycles; report reads/writes and I/D separately. Report admission waiting separately so delayed acceptance cannot conceal latency. Same-frequency operation alone does not prove zero-wait service. Under contention, exercise beat-level bank grant fairness, maximum legal bursts and bounded service opportunities without violating AXI transaction ownership. |
| Per-target admission, R2-P5 | Each target permits at most one combined read-or-write transaction until its B or RLAST response handshake. Independent targets may progress together. Cover all requester/target combinations, same-target serialization, backpressure and target/page/alignment errors; preserve VALID payload and response identity. |
| DMA read/write overlap and AW/W, R2-P5/P6 | Central DMA may hold one outstanding read and one outstanding write; different targets overlap while same-target requests obey the combined target limit. Test W-before-AW, delayed W, stalled B/R, rejected writes and interleaved unrelated traffic. Bind every accepted W beat to the correct accepted AW owner/length; no reassignment or untagged write interleaving. |
| Faults and counters, R2-P1/P5/P10 | Inject simultaneous faults and completions on different targets. Verify deterministic first-fault retention, correct requester/address/response, no lost independent fault events, correct aggregate count and source attribution. Backpressure must not recount a held event; concurrent events must not collapse into one boolean increment. Check clear/snapshot precedence and the frozen counter overflow semantics. |
| CPU ordering and lifecycle, R2-P4/P5/P7 | Verify FENCE.I after data writes to executable SRAM, required store/response drain and instruction refetch. Exercise interrupts, debug halt/resume and hart reset with both I/D paths active; hart reset waits for accepted CPU work while unrelated DMA remains usable. Cold/system reset must discard the old session consistently, and graceful drains must retain all accepted responses. |
| Compiler and placement A/B, R2-P3/P4/P10 | Use identical workloads, input/checksum, compiler identity, ISA/ABI and recorded flags. Separate compiler-only, bank-placement-only and combined comparisons; retain linker map, text/data/BSS/stack sizes and bank assignment. Compare cycles/instructions, I/D stalls, DMA throughput and latency against a reviewed baseline, not an unrelated historical build. Validate bank-aware code, data, stack and DMA-buffer placement and instruction synchronization. |
| WS2812 finite refill, R2-P3/P6/P10 | Keep the existing register ABI and fixed-MMIO DMA path. With exclusive producer ownership, use watermark 8 and an observed FIFO level L to schedule at most min(remaining, 16-L) words. Exercise empty/full levels, short final chunks, stale observation with only consumer draining, timeout, abort and ownership release. Competing CPU/DMA producers must not invalidate the credit calculation; ownership and the submitted transfer remain finite. |
| Real-time service budgets, R2-P3/P8/P9/P10 | Account for software/IRQ delay, arbitration, DMA, bridge/APB or serial service, maximum backpressure and margin. Prove the refill/service deadline against available FIFO slack under the declared competing traffic. Record WS2812 underrun/reset-gap behavior and DVP overflow invalidation; average throughput or bank count alone is not a worst-case guarantee. Unsupported traffic combinations must be explicit. |
| Gen1 shared integration, R2-P6/P7 | Eight DMA channels and frozen channel/request bindings; RNG qualification rejection; CRC tails/FINISH; Crypto initialization/readback/lock, vectors and erasure; I2S/SDIO contention; dynamic PWM rate reporting, slave-audio and exclusive alternate-input prerequisites. Run affected Mini consumers without treating their results as Tiny evidence. |
| XPI/DVP retained acceptance, R2-P8/P9/P10 | Execute the archived transport/frame cases below under the R2 phase mapping. Retain pin-level NSS1 PSRAM, measured write backpressure, exact frame length and guard/readback checks. DVP frame-done does not complete the final DMA word or AXI write response: never flush the undrained tail or publish a valid frame early. Preserve the DVP ABI/FIFO, DMA2/request 11 and capture-then-readback/save scope. |
| Clock/reset, package and ABI, R2-P4/P7/P11 | Test the R2 domain ownership and lifecycle above, truthful staged capabilities, SRAM-only boot, fixed QFN64/32 GPIO/16 power-ground budget and unchanged frozen alternates. Maintain common addresses, IRQs, register/HAL parity and documented fault semantics; no new SPI/PIO/BootROM or extra IO is implied. |

### R2 evidence classes and required validation

| Evidence class | Required record | Claim boundary |
| --- | --- | --- |
| Functional | Actual Icarus and Verilator executions, strict terminal markers and result files, focused protocol/reset/error tests, and applicable formal/host tests separately identified | Does not establish performance or qualified clock rate |
| Performance | Reproducible workload/compiler/placement A/B, cycle and instruction counts, service latency, throughput, contention and worst observed backpressure with stated workload bounds | A simulated clock assumption is not physical frequency evidence; observed maxima alone are not a universal bound |
| Synthesis and netlist | Current selected-PDK mapping of every main-SRAM/Crypto bank, area/cells, reset fanout, critical paths, netlist boot and applicable full-function checks | Pre-final timing is observational; library area is not die area and compact netlist boot does not replace full firmware or routed timing |
| Physical | Final combined complete-product campaign: source/profile/tool/PDK/corner/SDC identity; macro checks, CTS/reset distribution, extracted setup/hold/recovery/removal, CDC/RDC, IO/package/power and device timing | Mandatory final closure; behavioral PLL and pre-layout STA do not qualify an operating point or constitute foundry signoff |

Each result must preserve commands, full logs, source revision, configuration
digest, build variant, dependency/tool identity, library corners, simulator
mode, workload and firmware identity. Record failures, skipped/no-op tests and
missing artifacts explicitly. The historical -455.18 ns WNS below belongs to
the original 2026-09-25 run; it is not the current R2 WNS or proof that any
new rate is achievable. Physical feasibility and final qualification require
new evidence for the actual CPU/main-SRAM clocks and reset distribution.

Use the implementation validation entrypoints and baseline commands in the
[main contract](tiny-soc.md), with directed R2 cases and any new committed
profiles added through the normal flow. The current IHP130 Tiny profile
remains the starting point. Register integrated cases in normal regression;
`tests/test_xpi_io.py`, `tests/test_dvp.py`, fast-flash and host-only tests do
not replace the complete required hardware route. Preserve strict
`SIM_TEST_PASS`/result-file verdicts and run affected Mini compatibility for
shared changes. Do not remove unsupported PLL/STA guards, alter dependencies,
or change warning/metric policy to manufacture a pass. Metrics remain observe
mode; synthesis, simulation and timing failures remain recorded failures.

No R2 test, benchmark or PPA result is claimed by this verification-plan edit.
Actual documentation-only validation is recorded separately after execution.

## 2026-10-07 refreeze execution record

Scope: specification/ledger/guide changes and locked PLL acquisition only.
The starting source was `614fa6237b6be5a14f51b39d1012a3ca79e1ad52`; the existing
ECC work was subsequently committed as `14a253a49aa477e82f71bdbeb752280fff99b535`
without changing the protected working-file contents. No Tiny profile, RTL,
firmware, SDC, warning baseline or metric policy was changed by this refreeze.

Validation artifacts are under
[`build/ihp130-tiny-2026-10-07-18-10-414a31ff29aa/meta/tiny-refreeze-ics55-pll/`](../../build/ihp130-tiny-2026-10-07-18-10-414a31ff29aa/meta/tiny-refreeze-ics55-pll/).
The existing IHP130 profile supplies the artifact namespace only; these are
dependency/document/tooling checks, not new IHP130 or ICS55 hardware evidence.
The proposed ICS55 Tiny profile remains absent.

| Check | Result / artifact |
| --- | --- |
| Dependency lock | PASS; `lock.json`, 31 sources and 22 archives; only the approved PLL source was added to the existing working lock |
| PLL restore and repetition | PASS; `setup.json`, `setup-repeat.json`; both logs record full SHA and all seven view hashes; checkout clean |
| Focused dependency tests | PASS; `focused.json`, 19 tests including missing/wrong views, wrong revision, dirty checkout, idempotence and component isolation |
| Ruff | PASS; `ruff.json` |
| Full Pytest | PASS; `pytest.json`, 1541 passed / 1 skipped in 3593.34 s; the optional PDF retrieval test lacks `pypdf`, not a Tiny hardware gate |
| Existing regression definitions | PASS; `tiny-pr-dry.json`, `tiny-nightly-dry.json`, `mini-ics55-pr-dry.json`; dry-runs only |
| Documentation/source audit | PASS; `audit-delivery.json`; unchanged original phase titles, package/pinmux/RCU tables, historical R2/legacy evidence and unrelated ECC contents; added local links and PLL interface checked |

The first clone failed with an HTTP/2 transport error before checkout. The
same SHA was fetched with a command-local HTTP/1.1 override, then both ordinary
helper runs passed without a version change. An initial test fixture inherited
host Git signing; the fixture now disables signing/hooks for its own temporary
commits only. No repository commit or global Git setting was made by this task.

`evidence.json` indexes the successful gates and final source/input snapshot.
The downloaded behavioral/blackbox views agree on 15 ports; min/typ/max Liberty
contains no timing arcs. No LOCK output, characterized PLL timing or resolved
upstream license was discovered. These remain pending integration/release gaps.
SoC firmware/regression executions, full-SoC synthesis/netlist/STA, physical
flows and generated publications are NOT_RUN by this documentation/dependency
scope. Full Pytest's existing isolated fixtures are not product qualification.
TINY-ICS55-P1 remains pending explicit preflight/implementation approval.

## R2-P0 documentation checks (2026-10-04)

The working-tree documentation checks passed:

- Package, power and GPIO tables match the preceding contract; all 64
  perimeter numbers remain unique and the 32 GPIO assignments are unchanged.
- All 13 legacy phase headings and planning bodies are preserved, while the
  12 approved R2 headings are unique and sequential. Requirement identifiers
  TINY-001 through TINY-036 are unique and ordered.
- The four contiguous 32 KiB ranges total 128 KiB and retain 32 physical
  4 KiB macros. SYS and XPI MEM table values match the same-frequency contract.
- The initial 24 MHz architecture block and the executed historical record
  from "Configuration and artifact roots" onward match the preceding revision.
- All 119 local Markdown links across the 13 changed documents resolve;
  referenced profile, CPU/device-model sources and test entrypoints exist.
- The local-admission clock-change rule and three-cycle latency measurement
  endpoints were cross-checked between the main contract and this matrix.

The selected executable profile remains `configs/ci/ihp130-tiny.mk`, IHP130,
24 MHz/no PLL. The following commands passed; Windows used the installed
`python` entrypoint for the two command-list checks:

```sh
python scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python scripts/regress.py --root . --suite nightly --soc TINY --dry-run
git diff --check
```

These are documentation and command-selection checks, not R2 hardware
results. No RTL, firmware, configuration, dependency, warning-baseline or
metrics-policy file is changed. No C/MISRA deviation is introduced. Firmware
compilation, RTL/formal simulation, full quality/regression suites, synthesis,
netlist, STA and physical qualification were not run in this documentation
phase. Actual main-SRAM macro timing and joint high-frequency qualification
remain pending; no SRAM or CPU maximum frequency is established here.

## R2-P1 implementation evidence (2026-10-05)

Target SoCs: `TINY`; profile `configs/ci/ihp130-tiny.mk`; PDK `IHP130`,
24 MHz/no PLL. The approved source parent is
`bfdc3ffaf6cb0a134314272ac1b0f8b504d0b09c`. These are uncommitted implementation
runs, identified by retained source/input hashes and archives in addition to
the Git parent. They must not be presented as clean-commit release evidence.
The [baseline runbook](tiny-soc-r2-baseline.md) specifies workloads, observation
endpoints, retained-image replay, commands and the clock/reset/constraint audit.

The implementation adds a separate finite measurement image, optional
testbench observers and fail-closed evidence collection. Normal Tiny
acceptance firmware, hardware, register/SDK ABI, profile, dependency versions,
warning baselines and metrics policy are unchanged. The existing flat SRAM
layout is retained; no compiler or banking experiment belongs to these results.

Environment restoration uses
`.cache/retrosoc/development/tiny-r2-p1/activate.sh`. The original local
Verilator/Icarus/OpenSTA archives did not match the lock. The new isolated
installation verifies all seven selected tool archives against the unchanged
lock; the original installations are preserved. A sandbox DNS failure and a
Yosys download timeout are retained as failed attempts; the successful restore
reused the checksum-matching local Yosys/GCC archives. Locked Python packages
and both behavioral/full-flow doctor checks passed.

Initial development evidence is under
`build/ihp130-tiny-2026-10-05-11-19-fa1c4ce1e303/meta/tiny-r2-p1/`.
The PR campaign uses `BUILD_TIMESTAMP=2026-10-05-12-15`; the final workload
campaign uses `BUILD_TIMESTAMP=2026-10-05-12-30`. Each configuration retains
its own variant. Workload attempts preserve the
binary's original identity separately from the simulator source. Early failed
instrumentation attempts are not acceptance: a comment interpreted as a tool
pragma and an incorrectly formatted AXI observation record were corrected in
the testbench without modifying production RTL. An intermediate Icarus
measurement attempt was explicitly interrupted to strengthen artifact and
repeat-consistency revalidation; its outer result records exit 130 and cannot
qualify the baseline. Independent normal acceptance and PR runs were preserved.

Current completed checks:

| Gate | Retained result and boundary |
| --- | --- |
| Lock and configuration | Dependency lock, Tiny address/pin/topology/clock-reset checks and selected tool doctors passed. |
| Focused tests | Initial 58-case Tiny/protocol/reset/SRAM/parity/collector set passed. The final collector's 41 unit tests also passed, including modified-image, mixed-repeat and mismatched-verdict rejection. Counts overlap and are not additive coverage. |
| Software and source policy | Software format/policy/host tests, Make/RTL format, owned RTL style, readiness and Ruff passed. SVA ASIC lint completed; warnings retain the unchanged observation policy. |
| Normal firmware, Verilator | Command and terminal checks passed at 3,744,261 cycles. |
| Normal firmware, Icarus | Command and terminal checks passed at the same 3,744,261 cycles; wall duration 1522.098 seconds. This is full SDK/IRQ/DMA/watchdog acceptance, not netlist or physical evidence. |
| Final workload, Verilator | Three independent cold-reset runs passed with identical records at 18,458,948 terminal cycles. |
| Final workload, Icarus | All three retry runs passed strict command/terminal/log acceptance at the same 18,458,948 cycles; wall durations 10878.451, 10851.610 and 10832.133 seconds. The earlier 10800-second attempts remain failed. |
| Cross-simulator baseline | Final report passed: all six cold-reset runs use the same retained HEX and agree on every parsed workload/observer record; source, model, firmware, log and verdict integrity checks passed. This is functional/measurement evidence, not physical qualification. |
| Regression selection | Explicit TINY/IHP130 PR and nightly dry-runs passed and select the same current Tiny matrix. Nightly adds no distinct Tiny execution. |
| Full Pytest | 1476 passed, 1 skipped in 3574.13 seconds. The skipped PDF retrieval test requires `pypdf`. The suite began before final collector hardening; the 41-case collector suite was run after that hardening. |
| PR runner | Completed with exit zero, including SVA Verilator, full-firmware Icarus, synthesis, netlist boot and STA. Warning observations failed and timing did not close; runner completion is not a physical acceptance verdict. |
| Yosys, balanced | Completed in 311.874 seconds, 207697 cells, 9107224.664998 square micrometers of library area, 32 main-SRAM macros. These are current baseline values, not a like-for-like improvement over historical results. |
| Icarus netlist boot | Strict command/terminal/checker success at 29362 cycles, 151.389 seconds. Full C firmware netlist execution remains unrun. |
| OpenSTA | Command completed in 13.521 seconds. Setup WNS -455.18 ns and TNS -13049600 ns; hold WNS/TNS zero. **Timing qualification failed.** |
| Clock/reset netlist audit | 32 direct flat main-SRAM A_CLK loads of `u_clock_buffer/clk_o`; 29605 structural reset-reachable endpoints using all arcs. This is not CDC/RDC or reset-tree timing closure. |

The retained workload image is
`build/ihp130-tiny-2026-10-05-12-30-fa1c4ce1e303/meta/tiny-r2-p1/binaries/image-ozwo38_b/`.
BIN SHA-256 is
`b98b981f397af5f3a1d9cc15157726e77a8d7f21c68c1691cdc9b1beecbf4293`;
HEX SHA-256 is
`ba24c2dfd727a905f39b644df254e47262c39ab4960ff2614be44402020758b2`.
Its `.text` is 9836 bytes, `.bss` is 76736 bytes, BIN is 10080 bytes and
remaining SRAM above `_ebss` is 44480 bytes. The normal flat linker still
reports its existing RWX LOAD-segment warning; it is not hidden by a linker
or warning-policy change.

The final Verilator attempt `workloads/verilator/attempt-vvytd6pz` and Icarus
retry `workloads/iverilog/attempt-yu79tkc8` produced the following identical
raw measurements in all six accepted runs. No partial or timed-out run
contributes to this table. Cycles and instructions cover the specified workload envelope,
including submission/polling overhead but excluding initialization, readback
and UART. Empty-window overhead is reported without subtraction.

| Case | Cycles | Retired instructions | Payload bytes | CPU kernel cycles | CPU / DMA admission-wait cycles |
| --- | ---: | ---: | ---: | ---: | ---: |
| empty | 137 | 12 | 0 | 0 | 0 / 0 |
| cpu | 98663 | 32830 | 0 | 98343 | 0 / 0 |
| memory | 754159 | 213076 | 65536 | 0 | 0 / 0 |
| dma1 | 258772 | 32594 | 65536 | 0 | 114688 / 105056 |
| dma16 | 71444 | 7601 | 65536 | 0 | 37888 / 6416 |
| contention | 1638244 | 530481 | 65536 | 1603696 | 37888 / 5520 |
| tcd | 1639540 | 530498 | 65536 | 1604848 | 39040 / 6208 |

The contention cases each execute 16 CPU kernels; the CPU-only case executes
one. Each TCD case additionally reads 4096 descriptor bytes. Full per-owner
latency, backpressure, outstanding-transaction and SRAM records are retained
in the attempt JSON/logs. Payload-per-cycle is payload bytes divided by the
whole workload envelope; contention-case values include the concurrent CPU
work and must not be labeled isolated DMA bandwidth or physical throughput.

The synthesis/netlist/STA variant is
`build/ihp130-tiny-2026-10-05-12-15-19f1e9c571ee/` (`APP=ci_smoke`).
Its netlist SHA-256 is
`69195dc4050725d5cdbb9fedc213f675cedc6470492c84b2704f8ba535b4a29f`.
The fresh STA command consumes that netlist and its generated core SDC at the
slow corner; the netlist hash differs from the inspected October 2 run.
The equal historical/current WNS values therefore remain separately attributed.
The current worst path is `u_soc.s_rst_n_reg/Q` through the reset-dependent
I2C0 FIFO data path to `u_soc.u_i2c0/u_i2c_reg.u_rx_fifo.r_storage[4]_0__reg/D`.
No reset optimization or new timing exception was used to hide that result.

The final workload variant's `meta/tiny-r2-p1/constraints/` contains
`source-audit.json`, the generated `reset-clock-audit.tcl` and its command
result, clock/reset endpoint reports, and `synthesis-sta-evidence.json` binding
the consumed libraries, netlist, SDC, reports and compact boot binaries. The
query reuses the completed netlist and unchanged SDC; it does not run PnR or
alter constraints. Synthesis uses typical 1.20 V/25 C libraries, while STA
uses the selected slow 1.08 V/125 C views and IO 3.0 V corner.

There is no committed `quality/warnings/ihp130-tiny/` baseline. Consequently
the ASIC lint observation reports 399 new signatures; the actual CI variant
reports one Icarus and 14 Yosys signatures. Icarus reports unsupported
edge-sensitive `ifnone` model paths. Yosys observations include asynchronous
load-value warnings, combinational-network messages and the temporary SCL-cache
rename/conversion fallback to Liberty. The standalone warning commands fail;
the regression preserves its existing non-blocking observation behavior.
No warning signature or metrics policy was edited. Explicit CI-variant metrics
were collected because the runner's final default-APP observation targets do
not select its CI synthesis variant.

The first final-source Icarus campaign
(`workloads/iverilog/attempt-cwvkmh4t`) reached the 10800-second host timeout
in all three runs (exit 124). Each log contains all 28 observer records and
reaches the last UART case result. Since the firmware prints these records
only after every case and complete memory readback succeeds, this establishes
continued functional progress, but the missing final terminal marker still
prevents acceptance. No RTL error or cycle-limit timeout was reported.
`validation/iverilog-timeout-diagnosis.json` retains the failed results, logs
and host-stdio tool hashes. The previously observed 22 complete observer rows
matched Verilator in all three runs; partial output was never promoted to PASS.

The retry uses the identical retained image and production RTL with
`SOC_SIM_TIME=14400` and host line-buffered output. It does not change the
100000000-cycle bound or verdict rules. All three runs completed successfully
between 18:46:45 and 18:47:31 Asia/Shanghai. The final cross-simulator
aggregation also passed. Its result is
`build/ihp130-tiny-2026-10-05-12-30-fa1c4ce1e303/meta/tiny-r2-p1/baseline-report.json`;
the exact aggregation command and exit-zero result are retained under the same
root in `validation/baseline-report.log` and `validation/baseline-report.json`.
Implementation and reproducible baseline evidence are ready for human review;
this record does not automatically accept P1 or authorize another phase.
P1 does not qualify 24 MHz timing, the QFN64 package, external Tiny JTAG,
96/192/240 MHz operation, or any later R2/PIO/SPI/PPALite phase. No additional
MISRA deviation is introduced; the automated software gates remain partial
checks rather than certification. Historical records below retain their
original source, dates, stage IDs and qualification boundaries.

### R2-P1 evidence-tool repair (2026-10-05 through 2026-10-06)

The read-only review of the seven-file implementation found two issues:
the selected `VVP` executable was not bound to the recorded locked Icarus
installation (P1), and `image.json.compiler_command` was overwritten by the
last post-processing command (P2). The original image's hashed `compile.json`
still contains the actual GCC invocation. Neither finding changes the
previously recorded simulation results or establishes a hardware failure.

The separately approved repair changes only `scripts/tiny_r2_baseline.py`,
its focused tests, this ledger and the baseline runbook. The runner validates
the selected runtime before compilation, launches its verified absolute path,
retains its version/binary/archive identity, and rechecks it with actual run
commands at aggregation. The image producer preserves the compiler command
separately from its post-processing commands. Historical artifacts are not
rewritten to add provenance that they did not originally record.

Repair evidence uses
`build/ihp130-tiny-2026-10-05-20-02-fa1c4ce1e303/meta/tiny-r2-p1/`.
The focused suite passed 55 cases, including rejection before compilation for
external/missing runtimes and invalid installation markers, retained-runtime
and launch-command checks, and compiler-command preservation. Full Pytest
passed 1492 cases with one skipped PDF retrieval test (`pypdf` unavailable),
in 3539.14 seconds. Ruff and explicit TINY/IHP130 PR/nightly dry-runs passed.
These are local results; no new hosted CI or physical run is claimed.

The new metadata-validation image is `binaries/image-watrhx9n/`. Its retained
`compiler_command` equals the actual GCC command in `compile.json`; the
independent check is retained as `validation/compiler-metadata.json` and its
log. This image does not replace the original matched binary.
Verilator attempt `workloads/verilator/attempt-86h7qnqw` passed all three
cold-reset repetitions using the explicit original
`image-ozwo38_b/tiny_baseline.hex`. Icarus attempt
`workloads/iverilog/attempt-axv8qwr6` also passed all three repetitions at
18,458,948 cycles; wall durations were 10858.884, 10844.051 and 10923.896
seconds. All completed between 00:10:02 and 00:11:22 Asia/Shanghai on October 6.
The recorded runtime is Icarus vvp 13.0 from the isolated locked installation,
binary SHA-256
`7b5521fbaf86c519603e824e189c767790424ea6914f3dadeda438136d5eaba7`.
Each retained flow command launches that absolute executable. Runtime binary,
archive and launch-command checks passed after simulation and at aggregation.

The repair root's `baseline-report.json` passed all six runs, with original HEX
SHA-256 `ba24c2dfd727a905f39b644df254e47262c39ab4960ff2614be44402020758b2`.
`validation/previous-baseline-comparison.json` additionally checks that both
simulators retain the original image manifest and identical measurements to
the preceding campaign. Only the evidence collector changed among the
archived executable inputs; the old image, old attempts and old report remain
unmodified. Both review fixes now have focused and end-to-end evidence ready
for human re-review, not automatic phase acceptance.

Production RTL, testbench, firmware, Make targets, selected profile, dependency
versions, warning baselines and metrics policy are unchanged by this repair.
The earlier failed timing qualification and all unrun physical/debug/PVT gates
remain open. No phase acceptance or subsequent-phase authorization is implied.

## R2-P2 implementation evidence (2026-10-06)

The approved starting revision is `f06c039e790e38ccaf336ff21b68619010e7cc9e`
on `dev`, clean before work. Target `TINY`, profile `configs/ci/ihp130-tiny.mk`,
PDK `IHP130`, 24 MHz/no PLL remain fixed. The
[reset/feasibility runbook](tiny-soc-r2-reset-feasibility.md) owns the commands,
reset-leaf mapping, measurement endpoints and qualification boundaries.

Before editing RTL, fresh firmware, Yosys and STA completed under
`build/ihp130-tiny-2026-10-06-09-33-19f1e9c571ee/` (`APP=ci_smoke`).
`meta/tiny-r2-p2/baseline-inputs/identity.json` retains the clean source/tools;
`baseline-artifacts.json` additionally binds generated inputs, netlist/config,
SDC and native flow results. The source input digest is
`336aa85c3f213104d0d4b875ae18a427a403bb829c775904784311fd865cbfd0` and netlist
SHA-256 is `7caefc1d53aeec3d506efea6d90a7dc3845dd8177a6bba262e9fbd3814d34631`.
Fresh setup WNS/TNS are -455.18/-13049600 ns, hold WNS/TNS zero. These new
records do not change the attribution of the equal P1 timing values.

The implementation partitions reset across the existing 16 APB targets and
one fabric leaf, with five-edge local releases and CPU-last startup. Shared
debug wrappers retain default three-stage behavior and Tiny selects five.
No FIFO/CDC managed source, Crypto erasure, memory capacity, clock operating
point, register/HAL ABI, dependency version or quality policy changes.

Development checks passed both simulators' reset/FIFO fixtures, shared
three/five-stage hart reset, Tiny protocol/generator checks, I2C recovery,
clock metadata and 128 KiB SRAM protocol/reset readback. The first four-state
fixtures lacked a post-elaboration reset edge; their startup failures were
fixed in test initialization, not by changing the design. RTL format/style and
readiness passed. Common's FIFO and warm-flush fixtures passed in both
simulators with output redirected below the candidate build tree.

The initial candidate under `build/ihp130-tiny-2026-10-06-10-05-19f1e9c571ee/`
completed synthesis/STA at aggregate max-delay WNS -94.28 ns and TNS
-1594880 ns; min-delay WNS/TNS zero. These native metrics include recovery
checks, rather than only data setup. Timing still fails. The worst path is the XPI leaf
reset driver's recovery path. The first multi-point audit stopped because
Yosys renamed a leaf wire to its APB interface alias. The audit was
corrected to resolve actual mapped leaf registers and consumed nets; this
partial campaign is not complete feasibility acceptance. A subsequent probe
also rejected an invalid Tcl name-escaping expression. The final audit resolves
the preserved leaf instances, their actual output-register pins and consumed
interface nets without relying on source-level aliases or unsafe name escaping.

Final synthesis/analysis evidence uses
`build/ihp130-tiny-2026-10-06-10-25-19f1e9c571ee/meta/tiny-r2-p2/`.
`feasibility-rke9efn7/report.json` completed all 24 source-bound points: two
netlists, three corners, and four common SYS periods. Every point retains
the exact libraries/SDC, commands, metrics, reset loads/endpoints, CPU/SRAM
paths and constraint/coverage reports. No frequency point passed timing.

| Corner | Baseline aggregate WNS at 24 MHz (ns) | Candidate aggregate WNS at 24 MHz (ns) | Candidate SYS data setup slack (ns) | Candidate SYS data hold slack (ns) |
| --- | ---: | ---: | ---: | ---: |
| Slow | -455.18 | -94.28 | -87.78 | 0.22 |
| Typical | -299.07 | -51.46 | -48.16 | 0.11 |
| Fast | -185.71 | -19.94 | -19.18 | 0.02 |

| Candidate corner | SYS96 aggregate WNS (ns) | SYS192 aggregate WNS (ns) | SYS240 aggregate WNS (ns) |
| --- | ---: | ---: | ---: |
| Slow | -125.53 | -130.74 | -131.78 |
| Typical | -82.71 | -87.91 | -88.96 |
| Fast | -51.19 | -56.39 | -57.44 |

The baseline root reset directly drives 17211 loads; the candidate root drives
85 leaf-synchronizer reset pins. All 17 leaf instances and output-register
drivers remain distinct. Largest leaf loads are XPI 4710, PWM 4193 and DMA
3212. These residual loads and their recovery/data-path violations remain
explicit early feasibility limits, not a routed reset-tree pass. Both netlists
retain exactly 32 main macros driven directly by SYS. The fast SRAM/standard-cell
temperature mismatch, missing explicit macro minimum period, and ideal-clock,
unextracted analysis limitations remain as documented in the runbook.

The fresh baseline reports 207695 cells and 9107192.081398 square micrometers
of library area; the final candidate reports 208551 cells and 9109365.619198
square micrometers. These are native balanced-synthesis observations, including
normal build-identity constants, not extracted die area or a power claim.
Final metric collection retains the unchanged observe policy. Synthetic
negative-test result JSONs were initially found by the generic collector below
the full-Pytest scratch directory. After tests completed, that directory was
moved to the separate `ihp130-tiny-2026-10-06-12-38-19f1e9c571ee` build variant,
with its original path preserved as a symlink. `test-fixture-relocation.json`
records the move and the original metric file; final native firmware, synthesis
and timing values are unchanged, and synthetic test flows are excluded.

OpenOCD 0.12.0-1 and the SBT 2.0.5 launcher bundle are restored through the existing locked helper
in `.cache/retrosoc/development/tiny-r2-p2-debug`; P1's environment is unchanged.
The initial OpenOCD download's sandbox DNS failure and the initial Mini debug
attempt's SBT local-socket permission failure are retained separately. These
are environment failures, not hardware acceptance. The retry with locked tools
and local-socket permission passed `DEBUG_GDB_PASS` in 47.323 seconds under
`build/ihp130-debug-2026-10-06-10-15-b4a322720e40/sim/verilator/debug/`.
The locked VexiiRiscv project selected sbt 1.10.0 on Ubuntu Java 17.0.18,
as recorded in the generation log; its project tool selection was not changed.
This validates shared-wrapper default compatibility, not Tiny external JTAG.

The final focused suite passed 45 cases; source format/style/readiness and
Ruff passed. The Tiny PR campaign completed with exit zero in 2185.548 seconds
under `BUILD_TIMESTAMP=2026-10-06-10-26`. Both ordinary RTL simulations passed
at 3744281 cycles; Icarus took 1603.291 seconds. Netlist boot passed at 29373
cycles in 147.240 seconds. The PR synthesis and STA commands completed, while
warning observations and timing failures retain their existing policy boundary.
This is not a full-C netlist or physical pass.

The first full Pytest run recorded 1500 passed, 2 failed, 10 fixture errors and
one skipped PDF test. Both root causes were static consumers of the approved
reset parameter change: the Tiny publication collector required the old exact
three-parameter CPU dictionary, and the debug-flow test required the old
unparameterized instance spelling. The collector now explicitly requires
`ResetSyncStages=5` and includes the reset tree in source tracking; its negative
tests reject a wrong stage count and preserve the reviewed-snapshot check.
The debug test checks actual parameter forwarding and unchanged default three
stages. These compatibility updates do not alter RTL or publication identity;
no PDF or publication snapshot is refreshed. The focused consumer suite passed
31 tests. Final full Pytest passed 1517 tests with one skipped PDF retrieval
test (`pypdf` unavailable) in 3624.06 seconds. The initial failed run remains
recorded separately; focused and full-suite counts overlap.

`consumer-inputs-rv35_5et/identity.json` in the final analysis root retains the
post-flow consumer/test increment and verifies that every archived RTL,
generator, STA and workload source input is unchanged. Original timing inputs
and reports are preserved, rather than relabeled with these later test changes.

P1-image Verilator replay passed all three runs under
`build/ihp130-tiny-2026-10-06-10-27-fa1c4ce1e303/meta/tiny-r2-p1/workloads/verilator/attempt-88f2f259/`.
All measured records match the original P1 image baseline; terminal cycles
increase from 18458948 to 18458959, separately recording the intentional
11-cycle reset-startup change. Icarus attempt
`workloads/iverilog/attempt-e147iu49` under the same workload root passed all
three runs at 18458959 cycles, in 11275.215, 11254.774 and 11341.696 wall
seconds. All three logs satisfy command success, TEST_STATUS/SIM_TEST_PASS
and forbidden-marker checks. The workload root's `meta/tiny-r2-p1/baseline-report.json`
passed cross-simulator aggregation with the unchanged original HEX and identical
measured records. This directory/record retains the P1 measurement protocol
identity; its separate RTL-source snapshot identifies the P2 candidate.

Implementation and reproducible P2 evidence are ready for human review.
Timing qualification still fails at all analyzed rates, including 24 MHz;
the current executable branch is functionally validated, not physically qualified.
Full C netlist execution, routed/PVT/IO/package/silicon qualification, exhaustive
CDC/RDC and Tiny external-JTAG qualification remain unrun. No standalone formal
qualification is claimed; this phase used directed reset/protocol checks and
an independent FIFO scoreboard with unchanged Common implementations.
No Required-rule MISRA deviation was added. Publication PDF rebuilding and
snapshot advancement were not part of the consumer-compatibility repair.
No P2 acceptance or later-phase authorization is claimed.

## Archived P6/P10 planning and documentation evidence

The remainder of this section preserves the prior planning and P10 document
checks under their original phase identifiers. Its P7/P8/P11/P12/P9 labels,
three-master topology and main-SRAM-in-MEM clock assumptions are historical,
not the active R2 architecture or order. R2-P6/P7/P8/P9 retain the applicable
shared-IP, RCU, XPI and DVP acceptance obligations, while R2-P1/P2/P10/P11
carry the outstanding baseline and qualification work. Apply the R2
clock/fabric requirements above when executing those retained tests.

### Archived P6/P10 pending Gen1 verification

P6 and P10 were documentation-only. Their recorded execution order was
P10 -> P7 -> P8 -> P11 -> P12 -> P9, preserving all P0-P9 phase IDs/titles.
The matrix below recorded required implementation and qualification coverage;
it recorded no newly executed RTL, firmware, formal, synthesis or timing result.
The existing committed IHP130 Tiny profile remained the 24 MHz baseline until
implementation introduced reviewed configurations. Pending entries below are
historical status, not new R2 results.

| Area | Required cases / acceptance | Evidence status |
| --- | --- | --- |
| Addresses and software | Match Mini bases for RNG/CRC/WS2812/Crypto/DVP and the SYSCTRL control entry; one RCU decode; unchanged DVP V2 ABI at `0x1000E000`/IRQ15; handwritten parity and common drivers with product-selected clock/routing context. | Pending P7/P8/P12 |
| Package and pinmux | Exactly 64 unique perimeter pins, 32 GPIO and 16 power/ground terminals; preserve the P6 perimeter/power table and all assigned alternates; add only GPIO12-23 ALT1 camera functions; 28 distinct GPIO with optional controls; GPIO26 alternate I2C exclusion, audio/camera exclusion, safe reset and default-interface concurrency. | Documentation scope P10; RTL/Pad evidence pending P8/P12/P9 |
| DMA and fabric | Eight channels, Crypto 4/5 and I2S 6/7, serialized channel-3 clients, exclusive camera DMA2/request 11, three AXI32 masters, target/page/alignment errors, backpressure, abort drain and IRQ propagation. Absent DVP remains unsupported before P12; no private DVP master. | Pending P7/P12 |
| Shared IP lifecycle | RNG unqualified/fault/duplicate handling, CRC tails and FINISH after DMA, WS2812 pulse/reset timing, Crypto six-bank init/readback/lock, AES/SHA/RSA vectors, reset/abort/zeroize and no early erasure acknowledgement. | Pending Tiny P7/P9; standalone results remain separately scoped |
| Clock profiles | Safe24, external XIN24/48/96, PLL192/240 model cases; SYS/MEM/PCLK rates; 1 MHz CLINT continuity; SDIO init at <=400 kHz and 48/48/40 MHz target rates. | Pending P8 |
| Clock commands and failures | Invalid/unsupported profile, partial/unmapped access, busy rejection, drain/CDC timeout, lock timeout, PLL stopped high/low, no mixed profile commit and consistent safe fallback. | Pending P8 |
| Reference loss | Stop XIN and observe loss of REF24/WDG progress; restore the external source and RESET_N before restart; no autonomous recovery claim. | Pending P8/board evidence |
| Reset and gating | Cold/warm/watchdog/hart/peripheral reset; five-edge local release, CPU-last ordering, WFI/IRQ/debug ungating, gated MMIO error and unilateral CDC reset. Missing AUDIO/PIXCLK and Crypto READY must not block CPU startup; DVP target bit 14 unsupported before actual integration. | Pending P8/P12 |
| Timing-aware shared software | UART/I2C/WS2812 configuration at PCLK24/48/60; PWM CLOCK_HZ matches committed rate; shared-IP upgrade and Mini consumer compatibility; no managed-tree patch or Tiny HAL fork. | Pending shared upgrade/P8 |
| Physical and security qualification | Characterized 96 MHz input receiver, oscillator/PLL/backend, SYS240/MEM120/PCLK60 timing, pixel/serial Pad timing, CDC/RDC, reset fanout, SRAM macros, PVT/post-layout, supply/package/IO integrity, sensor/PSRAM electrical compatibility and qualified entropy source. | Pending P9; no current qualified PLL profile |

Each implementation result must identify its source revision, exact profile,
PDK/library corner and build variant. Use both supported RTL simulators with
the strict SIM_TEST_PASS/result-file policy, then the relevant netlist and
physical gates. Run affected Mini regressions for shared changes without
using those results as Tiny evidence. Do not remove PLL/STA guards or revise
warning/metric baselines to relabel an unsupported or failing flow as passing.

### DVP and XPI framebuffer acceptance matrix

All rows below are pending; the P10 freeze does not execute them. Scope each
result to the committed IHP130 24 MHz baseline or the exact P8-introduced
configuration. Neither an unimplemented profile nor a behavioral PLL result
is a physically qualified operating point.

| Requirement / phase | Required cases and objective evidence |
| --- | --- |
| TINY-022/026, P8/P12 | GPIO12-19 data, GPIO20 raw PIXCLK, GPIO21 HREF, GPIO22 VSYNC, GPIO23 CAM_XCLK; preserve GPIO28 ALT0 as the same CLKOUT generator; off after reset, REF24/2=12 MHz, dual-route mirroring and disable-before-change. Verify camera/I2S/PWM conflicts and board inactive-driver isolation. |
| TINY-024, P11 | NSS1/GPIO29, actual 8 MiB reference geometry at `0x54000000..0x547FFFFF` within the 64 MiB aperture; device identity/init/reset, read/write LUT, SCK/CS/dummy settings, CPU and central-DMA full readback/CRC plus guard regions. Use the XPI pins, not a substituted RAM or separate controller. |
| TINY-024/025, P11 | First/last device words, allocation end and overflow, 4 KiB and serial boundaries, chosen alignment and bursts up to 16 words, maximum CS duration, wrong/absent device, timeout/abort/reset/reinitialization. Failure must not alter NOR data, boot LUT or mapped-write disable. |
| TINY-027, P11 | Per-profile mapped-write payload throughput and maximum observed backpressure, with recorded clock/LUT/burst/device settings and exercised contention. Use these measurements to define a tested input-rate budget; capacity alone is not a rate bound. |
| TINY-021/023, P12 | Execute existing DVP V2 register/format/framing/IRQ tests; connect APB/IRQ15 and stream request 11 to DMA2; truthful capability before/after integration, no changed FIFO/ABI, no extra master. Mini retains its default channel-3 binding. |
| TINY-021/024/025, P12 | End-to-end RGB565 and YUV422 snapshots/crops; repeated capture; full QVGA (153600-byte) and VGA (614400-byte) external frames at a safe measured rate; SRAM capture only with complete memory budget. Check every output byte, guard regions, DVP statistics and exact DMA byte count. |
| TINY-025, P12 | Allocation larger than frame still programs exact frame length; even cropped width accepted; odd DMA width/insufficient capacity/invalid range rejected before start; odd-width PIO retained. Delay final stream word and AXI write response after DVP frame-done: no early flush, abort or valid-buffer publication. |
| TINY-025/026, P12 | Backpressure/overflow, malformed sync/partial frame, DMA/XPI errors, lost/stopped-high/stopped-low PIXCLK, reset/abort/rearm and audio/camera mode changes. Invalid frames are discarded; accepted AXI work drains or the reset session is explicitly lost. CPU/APB stays usable without PIXCLK; no false reset-done with missing edges/barriers. |
| TINY-024/027, P12/P9 | NOR boot with PSRAM present/absent/failing, SRAM-resident XPI reconfiguration including interrupt paths, capture-then-readback/SDIO-save ordering and explicit blocking-traffic exclusions. Archive tested PIXCLK and margins, not a general FPS guarantee. |

The complete DVP -> DMA -> AXI -> XPI -> PSRAM route must execute with a
pin-level PSRAM model in Icarus and Verilator and firmware terminal verdicts
where applicable. The Verilator `--fast-flash` backend rejects writes,
nonzero slots and modified LUTs; it cannot supply framebuffer evidence.
`tests/test_psram.py` tests a different PSRAM controller, and
`tests/test_xpi_io.py` is a shared PHY/LUT check, not this complete route.
`tests/test_dvp.py` is standalone framing evidence and can return without
executing RTL when tools are missing. Check actual simulator execution and
pass markers; a collected/skipped/no-op host test is not hardware coverage.

P11/P12 must add integrated cases through the normal test/regression flow,
record exact commands and retain full logs, source/profile/PDK identity,
guards/readback checks and error snapshots. Reuse the existing PSRAM device
model under shared/Tiny verification ownership without importing Mini product
RTL or duplicating its controller. Keep hardware coverage separate from
host-only length/range/HAL tests, physical device qualification and continuous
video delivery. Shared HAL fixes require affected Mini compatibility runs.

### P10 documentation checks (2026-10-01)

Local document checks passed: unchanged perimeter/power tables, 64 unique
terminal numbers, 32 GPIO with exactly twelve new ALT1 routes, 28 distinct
camera-profile GPIO including optional controls, unchanged P0-P9 headings,
thirteen unique phase headings and correct frame-byte/KiB/DMA-word arithmetic.
The DVP register/stream sections, Tiny 24 MHz baseline and historical executed
results below were compared against the preceding revision and are unchanged.
All 111 local Markdown links in the nine changed documents passed, and the
two camera references were checked against their official sources.

Command selection was checked on Windows using the installed `python` entry
point (`python3` resolves to an unavailable Store launcher in this shell);
both dry-runs succeeded:

```sh
python scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python scripts/regress.py --root . --suite nightly --soc TINY --dry-run
git diff --check
```

The selected profile remains `configs/ci/ihp130-tiny.mk`, IHP130, 24 MHz/no
PLL. `git diff --check` passed. P10 changes documentation only: firmware,
RTL simulations/formal, synthesis/netlist/STA, full quality/regression suites
and physical gates were not run. No C/MISRA deviation, configuration,
dependency, warning baseline or metrics policy change is made or implied.

## Configuration and artifact roots

The selected profile is `configs/ci/ihp130-tiny.mk`: IHP130, 128 KiB SRAM,
24 MHz, RV32IM firmware on an RV32IMC hart with A disabled. Runs below used
`BUILD_TIMESTAMP=2026-09-25-12-00`:

- Default `bringup`: `build/ihp130-tiny-2026-09-25-12-00-d6009644a134/`.
- `APP=ci_smoke`: `build/ihp130-tiny-2026-09-25-12-00-044d45791ef7/`.
- `APP=ci_smoke HAVE_SVA=YES`:
  `build/ihp130-tiny-2026-09-25-12-00-6874f2ffdf11/`.

Configuration digests identify settings and the dependency lock, not a clean
source revision. A release requires rerunning from its reviewed commit.

## Functional and quality checks

| Check | Evidence/boundary |
| --- | --- |
| Tiny maps and source isolation | Generated address, IRQ, pad and clock/reset inputs validate; source closure excludes Mini product RTL, RIB/RIBP and HP generation. |
| AXI fabric, both simulators | Directed tests cover competing CPU/DMA requests, W-before-AW, delayed W, response backpressure, ID/RLAST, 16-beat bursts, 4 KiB crossing, alignment, reserved regions and continued operation after errors. |
| Tiny SYSCTRL, both simulators | APB tests cover unsupported controls, partial terminal writes, sticky first status, counter snapshots, first-fault retention, W1C, RTC wake and reset. |
| Verilator full firmware | `SIM_TEST_PASS`; the CI composition also passes with SVA enabled. Pin-level NOR, compressed instructions, disabled atomics, load faults, SRAM discovery, memory/UART DMA, external timer IRQ, CLINT time, RTC, GPIO, UART1 loopback, I2C NACK and watchdog reboot are exercised. |
| Icarus full firmware | Final expanded CI firmware passes at 3,705,751 cycles, matching the SVA-enabled Verilator run. |
| Icarus synthesized boot | `netsim-boot` passes at 29,362 cycles using the compact assembly image. Covers pin-level NOR, SRAM first/last words, byte writes, UART and terminal status; does not establish full C-firmware gate-level coverage. |
| SDK gates | C formatting, embedded-C policy and host tests pass, including Tiny channel/endpoint rejection compiled from the real DMA validator. No new Required-rule MISRA deviation is recorded; these partial checks do not certify MISRA conformance. |
| Focused Python tests | 112 tests passed across Tiny, address/pad generation and build/regression tooling. Shared debug-reset and SRAM/DMA register-parity checks also pass. After fixing parameterization/publication compatibility and preparing the existing MPW/device-model inputs, all 54 non-reference failures selected for rerun pass. |
| RTL policy | Changed RTL formatting, full owned RTL style audit and readiness metadata pass. Global formatting limitations are listed below. |
| Reproducibility | Dependency lock validation, Ruff, PR/nightly dry-runs and `git diff --check` pass. Tiny source packaging exports the Tiny top, actual filelist and its core timing SDC. |

The full-firmware verdict is authoritative only when both the tool result and
`result-sim-check.json` pass. UART text alone is not sufficient. Assembly netlist
acceptance uses the same strict terminal marker policy.

## Synthesis and timing

For the CI composition, Yosys completed with the IHP130 technology libraries
and 32 `tc_sram_1024x32` banks. The `balanced` report records 207,739 cells and
9,798,326.725198 square micrometers of library area. The area includes the
instantiated memory/pad hierarchy and is not a placed die-area estimate.

OpenSTA completed with the selected slow library corner and the 41.666666667 ns
system clock. Reported setup WNS is **-455.18 ns**, setup TNS is
**-13,049,600 ns**, and hold WNS/TNS are zero. The worst path starts at the
synchronized system-reset register and reaches peripheral FIFO storage through
the high-fanout reset distribution. This is an open physical/timing issue;
24 MHz is a functional target, not a timing-qualified operating point.

Reports reside under the CI variant's `syn/yosys/rpt/` and `sta/opensta/`.
The metric collector understands the Tiny top and timestamp-prefixed Yosys JSON
reports. Metrics remain in `observe` mode; no warning or metric baseline has
been edited to accept this feature.

## Commands and remaining coverage

The build/verification commands were run with the profile and timestamp above:

```sh
make CONFIG=configs/ci/ihp130-tiny.mk doctor firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke HAVE_SVA=YES firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke SIMU=IVERILOG firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke SIMU=IVERILOG netsim-boot
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke STA=OPENSTA sta
make CONFIG=configs/ci/ihp130-tiny.mk metrics package
make sw-format-check sw-policy-check sw-host-test rtl-style-check-all rtl-readiness-check
python3 -m pytest -q tests/test_tiny.py tests/test_memory_map.py tests/test_pin_map.py tests/test_script_tools.py
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

The combined IHP130 regression stops in its Mini phase because the locked
VexiiRiscv checkout is absent. Tiny can be selected independently with
`--soc TINY`, or `make CONFIG=configs/ci/ihp130-tiny.mk regress-pr`.
The initial full Pytest run completed with 1,234 passed, 26 failed, 19 skipped
and 71 errors. Parameterization/format-sensitive expectations and the Mini
publication's constant/cast parsing were corrected; the affected cases were
rerun successfully. MPW/device-model inputs and a writable test ccache resolved
additional environment failures. The remaining 16 cases require the absent
locked FLAC corpus, MLPerf Tiny models or TensorFlow oracle sources. These are
not Tiny setup dependencies. The full suite was not rerun after the focused
corrections; it is not reported as a clean full-suite pass.

The initial run, focused results, combined-regression failure and remaining
reference-input case list are retained under the CI variant's
`meta/validation/`.
Global RTL/Make formatting checks encounter existing APU/accelerator files
outside this change. Changed-file formatting is checked independently.

Remaining qualification includes reset-tree/timing closure, placement/routing,
PVT/MMMC, CDC/RDC signoff, silicon and power measurements, full C netlist
acceptance, a Tiny-specific external OpenOCD session, positive external I2C
slave transactions and comprehensive pad-level PWM/RTC coverage. Wireless,
retention, secure boot and other PDKs remain explicit deferred features.

## Shared-path migration follow-up

Mini now references the canonical shared RTL, `scripts/rtl` helpers and
`rtl/mk/software.mk` directly. The 21 Mini compatibility links and seven Tiny
helper links have been removed. Filelists, simulator/formal/synthesis rules,
Python imports, tests, publication tooling and ownership documents use the new
paths. No Git file-type changes remain. Historical warning baselines are
unchanged.

The resolved Mini `commonip.fl`, `ip.fl` and `top.fl` retain the same 299
unique sources in the same order. `netlist_support.fl` retains its two sources;
`inc.fl` adds `rtl/ip/core`. All relocated shared RTL content hashes match the
pre-migration snapshot. This follow-up changes paths, not RTL behavior or the
public hardware/software interface.

Validation after removing the links:

- 245 focused tests passed: 144 build/generator/topology/style/Tiny tests,
  96 publication/LibreLane tests and five debug-reset/SRAM simulations.
  Full-suite collection succeeds with 1,356 tests; the full suite was not
  rerun because of the reference-input gaps documented above.
- Mini `configs/ci/ihp130.mk` address/pad/topology/clock-reset checks and firmware
  build pass. Its Verilator compile reaches HP generation and stops because
  the locked VexiiRiscv checkout is missing; full Mini simulation and the
  combined regression remain unverified.
- Tiny `configs/ci/ihp130-tiny.mk`, `APP=ci_smoke HAVE_SVA=YES`, firmware and
  Verilator simulation pass again at 3,705,751 cycles. Full Icarus, synthesis
  and STA were not repeated for this path-only follow-up.
- Eleven Python CLI entrypoints work outside the repository directory.
  Mini SRAM formal filelist generation, `sv2v` conversion, filelist combination
  and dependency generation pass using the canonical shared paths, including
  the relocated SRAM header. Formal proofs were not rerun.
- Ruff, owned RTL style, readiness metadata, 251 local Markdown links and
  `git diff --check` pass. The Make formatter still reports existing EOF and
  formal-command indentation differences in APU/GA2D/formal fragments; those
  unrelated differences were preserved.

Run logs, exact commands and path snapshots are retained under
`build/ihp130-2026-09-25-12-00-9903b3d112b7/meta/validation/shared-path-migration/`.
No C register/API change or additional MISRA deviation belongs to this
follow-up; the SDK gates from the implementation record above were not rerun.

## Next review

```text
Use $retrosoc-feature-review in review mode for feature tiny-soc with Target SoCs: TINY. Review the current worktree diff against docs/ip/tiny-soc.md and docs/ip/tiny-soc-verification.md. Verify Tiny isolation, default Mini compatibility, AXI/APB/error/reset behavior and the SDK ABI. Treat the observed reset-fanout timing deficit and missing APU/NPU/VexiiRiscv inputs as explicit qualification gaps; do not claim timing closure or alter warning/metric baselines.
```
