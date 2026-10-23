# SPI Verification and Evidence Ledger

This ledger accompanies [spi.md](spi.md), targeting TINY/IHP130 and the
approved `SPI-P0..P5` roadmap dated 2026-10-04. It records required evidence,
not existing hardware capability. At freeze, SPI RTL, DMA V2.2, native routing,
HAL/display software and physical qualification are not delivered. Historical
Tiny, SPI-SD, XPI, DMA and PIO evidence does not automatically cover this IP.

## SPI-P1 review-closure checkpoint (2026-10-19)

The approved eight-file repair closes two missing verification obligations
(independent SCK timing and complete-core FIFO stall/resume) and strengthens
tool-component provenance. It does not modify production RTL, profiles,
register ABI, product integration or dependency versions. The existing
implementation remains based on `dev@e62ccdad87e1fd412eff70cc2527ad3090f16a55`.
See the [runbook](spi-p1.md) for the exact workload and checker contracts.

The new campaign completed successfully. Matching evidence roots are:

- `build/ics55-tiny-2026-10-19-07-00-bbe722dc382e/meta/spi-p1/`.
- `build/ihp130-tiny-2026-10-19-07-00-439583e27401/meta/spi-p1/`.

Tool-input schema2 rejects older incomplete inventories rather than filling
them retrospectively. The fresh formal campaign retains depth192 BMC and
the complete-window cover witness; unchanged proof depth does not cover the
new large FIFO-pressure workloads, which are checked by RTL/netlist fixtures.
Original evidence below remains historical, including the old full-Pytest
count. No human SPI-P1 acceptance, P2 implementation or product qualification
is implied. Final combined-regression/physical obligations remain open.

| Review-closure gate | Result / evidence boundary |
| --- | --- |
| Independent checker | Both simulators pass 28 synthetic traces: 17 legal cases and 11 exactly classified waveform/payload violations |
| Complete-core behavior | Both simulators pass all five fixtures; each core run retains 305 original segments plus 48 pressure completions, 16 pressure aborts and 112 phase-offset aborts |
| Mapped behavior | Both PDK netlists pass 48 original pin cases plus the same 48 pressure completions, 16 pressure aborts and 112 phase-offset aborts |
| Inventory/parity negatives | 44 pure tests pass; the focused run also includes both checker fixtures (46 passed, 8 deselected) |
| Formal, fresh execution | Phase/register induction pass; depth192 BMC passes in 769.397 s; cover passes in 193.824 s with 195 witness steps; no historical proof reuse |
| Quality / regression definitions | Ruff, formatting, owned RTL style/readiness and whitespace pass; TINY/ICS55 and TINY/IHP130 PR/nightly dry-runs pass |
| Full Pytest, one execution | 2085 passed, 1 skipped in 4980.22 s; the optional PDF retrieval test still lacks `pypdf` |
| Final integrity audit | All stage records match current implementation hashes and schema2 tool inventories; exactly the approved eight paths differ from the repair-start snapshot |

Each RTL/netlist pressure campaign records 80 observed waits, with stable
CPOL/CS/edge counts and advancing stall counters. The standalone core runtime
is 0.996 s in Verilator and 18.812 s in Icarus (excluding compilation). These
host runtimes are not hardware performance measurements.

Fresh mapping remains 7431 cells / Liberty area 19240.76 for ICS55 and 7949 /
126612.7254 for IHP130, with two 256-bit payload FIFOs and zero block SRAM
macros. Both STA executions report internal setup/hold WNS/TNS 0.00 and retain
319 missing input delays, 41 missing output delays and 42 unconstrained
endpoints. These are the same observational timing limitations, not closure.

Exact commands, stdout/result JSON, before/after source maps, JUnit and
`final-audit.json` are in the new ICS55 root's `validation/`. All test-run
source snapshots were stable; only this ledger and the runbook were updated
after full Pytest to record final results. Producer records are immutable.
The repair-start source map is retained under
`build/ics55-tiny-2026-10-19-06-48-bbe722dc382e/meta/spi-p1/validation/start-source.json`.

No firmware build was repeated: firmware inputs, product profiles and
interfaces are unchanged, and their original 23:25 results remain historical
compatibility evidence. Full product regressions, long firmware Icarus,
commercial/physical/Pad/board/silicon qualification remain unrun/deferred as
previously authorized. No warning baseline, metric policy, MISRA deviation,
dependency version, Git index or branch was changed. Independent read-only
review and explicit human acceptance remain required; readiness is still
`prototype` and all phase-acceptance flags remain false.

## SPI-P2 implementation checkpoint (2026-10-19)

The current `dev` commits implement the first shared-DMA V2.2 boundary:
five-bit request constants, TCD bit25 decode, parameterized IP version and
32-bit support/request status, plus the standalone SPI credit pacing block.
Committed Tiny and Mini instances retain V2.0/default-disabled SPI support;
this is deliberate compatibility evidence, not integrated SPI capability.

Focused P2 checks pass: DMA register/native tests, the SPI-P1 standalone
fixtures and six P2 checks covering request encoding, five-bit channel state,
default-disable policy, stream-status disable policy and credit admission/
commit/retirement. Descriptor
fetch/parse cancellation is guarded in the source and covered by the current
DMA abort assertions; descriptor-specific dynamic coverage remains unrun. Real SPI request ports,
source-origin transport through Tiny bridges, firmware discovery and product
routing remain later integration work. `phase_accepted` stays false and no
later phase is authorized.

Current focused evidence: 53 SPI/DMA/parity checks, DMA register/native tests,
SPI-P1 pure checks, P2 pacing lint and RTL fixtures, DMA formal prove/BMC/cover
and host C all pass. A prior pre-cancellation-fix full Pytest campaign passed
2089 tests with one optional PDF retrieval skip (`pypdf` unavailable); the full
campaign is intentionally unrun again after the latest shared-DMA source edits.
Publication programming validation now deliberately publishes only executable
DMA requests 0..15; SPI16/17 remain future V2.2 ABI constants and are not
treated as current product routes. The prior full-suite test log and JUnit are under
`build/ics55-tiny-2026-10-19-23-20-5f3eb7711d42/meta/spi-p2/validation-final/`.
The latest source-bound P2 lint/RTL records are under
`build/ics55-tiny-2026-10-20-22-23-5f3eb7711d42/meta/spi-p2/`; the compatibility
Tiny lint is under
`build/ihp130-tiny-2026-10-20-09-20-b00f46e87763/lint/verilator/`, and the
post-edit Mini DMA formal record is under
`build/ihp130-2026-10-20-09-13-c30fb9412aa3/formal/dma/`.

The latest Mini DMA formal prove/cover build is under
`build/ihp130-2026-10-20-22-44-c30fb9412aa3/formal/dma/`; the extended prove
command passed with the current stream-status RTL and TCD cancellation
assertions. The standard 120-second wrapper timed out; the dedicated TCD
cancellation cover remains passing under the retained formal root.

P2 remains incomplete for phase acceptance: full V2.2 block synthesis/netlist/
STA, Tiny/Mini firmware integration, real source-origin CDC/fabric wiring,
SPI request allocation, the full post-fix Pytest campaign and product
regressions are unrun. Product instances
retain V2.0/default-disabled SPI.

## SPI-P4 sub-stage A checkpoint (2026-10-23)

The approved staged preflight (display-first, camera/PSRAM cases deferred to
sub-stage B pending R2-P8/R2-P9 acceptance) is implemented on the committed
SPI-P3 base. New content: the project-owned ST7789VI four-wire adapter
(`app/board/st7789vi.c`, pure pattern/window math in `st7789vi_math.c`), the
`TINY_SPI_P4_ACCEPTANCE` image (`app/apps/ci_smoke/tiny_spi_p4.c`), the
pin-independent panel oracle (`rtl/tiny/dv/tiny_st7789_panel.sv`), the
golden checker and focused contracts (`scripts/spi_p4.py`,
`tests/test_spi_p4.py`) and host tests (`test_st7789vi_patterns` in
`tests/c/test_runtime.c`). The [runbook](spi-p4.md) records the contract.

Three defects found by the bring-up and fixed with evidence: (1) the
committed integration wired the SPI `gpio_ready_i` to the GPIO APB bridge's
transaction-level ready, which drops on every GPIO access and faulted any
mid-session D/C change required by the frozen contract; it now uses
GPIO-clock/reset-level availability (`retrosoc_tiny.sv`). (2) The adapter
issued `END` after non-held segments, which only HELD permits. (3) HAL
lifecycle gaps: `rs_spi_acquire` now also waits `BUS_IDLE` before returning a
usable session, `rs_spi_recover` waits wire-state Disabled (RECOVER retains
the session), and `rs_spi_release` skips the DISABLE step when the session is
already Disabled. SPI-P3 acceptance remains passing after the HAL changes
(`SIM_TEST_PASS Tiny cycles=1037899`).

Sub-stage A acceptance, all with the independent panel oracle and golden
geometry/pixel/FNV-1a checks passing (`spi_p4.py check`, zero problems,
violations=0, 8/8 windows, 21 commands): Verilator passes on both profiles at
`SIM_TEST_PASS Tiny cycles=43019427`
(`build/ics55-tiny-2026-10-23-01-37-106e35060a8e/`,
`build/ihp130-tiny-2026-10-23-01-38-616e0604657d/`); Icarus behavioral passes
on both profiles with the QUICK delay/geometry variant at
`SIM_TEST_PASS Tiny cycles=2710932`
(`build/ics55-tiny-2026-10-23-01-34-106e35060a8e/`,
`build/ihp130-tiny-2026-10-23-01-39-616e0604657d/`). The image covers
discovery/configuration, panel init ordering (SLPOUT/DISPON checked),
full-screen color bars and gradient, odd rectangles, a rotation variant, an
abort/recover/release/reacquire case with a clean final window, and
cycle/payload measurements. Full Pytest: 2102 passed, 1 skipped (optional
`pypdf`), 0 failed in 4442.19 s.

Sub-stage B (V21/V22: PSRAM-source display, sequential capture/verify/SD,
SRAM-vs-PSRAM performance) remains gated on R2-P8/R2-P9 human acceptance.
SPI-P5 stays deferred; `phase_accepted` stays false.

## SPI-P3 implementation checkpoint (2026-10-21)

The current authorized worktree integrates SPI-P2 into Tiny with APB4
`0x1001D000..0x1001DFFF`, IRQ25, RCU target16, the four frozen Gen1 ALT
routes and the ICS55 default/Tiny-IHP130 compatibility profiles. Tiny fabric
source qualification is carried through AXI user metadata and APB CDC; CPU,
DMA and other-owner accesses remain distinguishable at the SPI aliases. Tiny
DMA enables V2.2 requests 16/17 and checks the exact fixed FIFO MMIO addresses.

The GPIO guard uses the existing USER_SELECT/handoff and ALT/electrical state,
with raw GPIO30 input for MISO. GPIO/SPI lifecycle idle vectors include the
latched SPI session, so RCU gate/reset/rate changes cannot strand accepted
SPI work. The bounded `rs_spi_*` HAL is added under the freestanding SDK and
the `TINY_SPI_P3_ACCEPTANCE` image covers discovery, ownership and RCU target
checks.

Focused P3 source checks and Tiny firmware/lint records are retained below
`build/<variant>/meta/spi-p3/`. Full Tiny/Icarus product regression, complete
DMA contention coverage, synthesis/netlist/STA and human phase acceptance
remain required. This checkpoint does not authorize SPI-P4 or SPI-P5.

SPI-P3 Tiny Verilator acceptance (2026-10-21, same worktree): both profiles
pass with the standard `TINY_SIM_TIMEOUT=20000000` budget. Commands:
`make CONFIG=configs/ci/ics55-tiny.mk APP=ci_smoke TINY_SPI_P3_ACCEPTANCE=YES firmware sim`
and `make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke TINY_SPI_P3_ACCEPTANCE=YES firmware sim`.
Each log reports `SIM_TEST_PASS Tiny cycles=1030643` with no forbidden marker;
`result-sim.json` and `result-sim-check.json` both report `passed`. Evidence
roots: `build/ics55-tiny-2026-10-21-16-15-a257f7b03bdb/` (ICS55) and
`build/ihp130-tiny-2026-10-21-16-15-76f15177ba7a/` (IHP130). The cycle count
is dominated by SAFE24 XPI boot copy (~1.015M cycles for the 7212-byte image);
the SPI APB/RCU/TEST_STATUS sequence completes in the final ~15.6k cycles. A
1,000,000-cycle budget times out inside the boot copy loop and is not a valid
acceptance budget for this image. The same change set moves the
`TINY_SPI_P3_ACCEPTANCE` ci_smoke guard to top level in `Makefile` so
`APP=bringup` builds are rejected at parse time. UART output remained
diagnostic only; `phase_accepted` stays false.

SPI-P3 phase-gate campaign (2026-10-21, same worktree), per gate:

| Gate | Result / evidence |
| --- | --- |
| Focused stages, both profiles | PASS: `spi-p3-lint/rtl/report` each report `passed` (13 focused tests per stage); records under `build/ics55-tiny-2026-10-21-16-31-a257f7b03bdb/meta/spi-p3/` and `build/ihp130-tiny-2026-10-21-16-31-76f15177ba7a/meta/spi-p3/` |
| Quality gates | PASS: `ruff check .`, `make sw-format-check sw-policy-check sw-host-test`, `git diff --check` |
| Regression dry-runs | PASS: `--suite pr --soc TINY --pdk IHP130` and `--suite nightly --soc TINY` |
| `make regress-pr` | FAIL (first failing step identified): the Mini IHP130 firmware step emits new self-owned C warnings from `crt/src/hal/spi.c:10` (the non-Tiny fallback `RS_SPI_REG` macro dereferences raw offsets, riscv32-gcc `-Warray-bounds=`); `scripts/regress.py:329` fails the suite by policy. Later matrix steps did not run. Awaiting an implementation fix; not a design-behavior defect |
| Icarus behavioral sims, both profiles | NOT_RUN (blocked, pre-existing): Icarus elaboration of committed `rtl/tiny/dv` observers/tb fails against the sv2v-lowered `converted_soc.v` (struct fields such as `s_req_q[].state`, `s_slow_q.owner`, `u_xpi.apb4.psel`); 29 errors on each profile (`build/ics55-tiny-2026-10-21-16-31-a257f7b03bdb/sim/iverilog/`, `build/ihp130-tiny-2026-10-21-16-36-76f15177ba7a/sim/iverilog/`). Last passing Icarus behavioral run predates the committed R2-P7..P10 observer changes (2026-10-13, `build/ihp130-tiny-2026-10-13-17-06-3f1b609b0b86/`); the sv2v lowering of the referenced structs is byte-identical with and without SPI-P3, so this is not caused by this worktree |
| Full Pytest | FAIL: 16 failed, 2080 passed, 1 skipped in 4035.41 s (`/tmp/pytest_full.log` capture; one execution). All 16 failures trace to this worktree's incomplete follow-through, none pre-existing: (a) `apb4_spi` gained `session_owned_o`/`lifecycle_idle_o` but `physical/smoke/syn/yosys/apb4_spi_block_top.sv` was not updated, breaking all five SPI-P1 standalone Verilator fixture compiles; (b) `rtl/tiny/integration/clock_reset_domains.json` reset `leaf_names` omits the `spi` leaf that `soc_topology.json` lists as an APB target; (c) committed contract tests still encode the pre-P3 state and were not updated to the frozen P3 allocation (IRQ25, RCU16, 29 fabric targets, SPI lifecycle leaf, 4-bit AXI origin): `test_tiny.py::test_tiny_sources_and_abi_are_independent`, `test_tiny_protocol_contracts[fabric-*]`, `test_tiny_r2_p2.py::test_reset_inventory...`, `test_tiny_r2_p5.py::test_concurrent_fabric`, `test_target_reset_isolation`, `test_tiny_r2_p6.py` IRQ/pin and reset-policy contracts; (d) `test_publication_tiny.py` source binding still expects `s_r_data[1]` for the read-terminal condition, legitimately shifted to `s_r_data[4]` by the 4-bit origin widening |

UART output remained diagnostic only; `phase_accepted` stays false. The
`regress-pr` C-warning failure must be fixed before SPI-P3 phase acceptance;
the Icarus observer/sv2v incompatibility belongs to the R2-P7..P10 DV owners
and is routed back as a separate pre-existing defect.

SPI-P3 repair campaign (2026-10-21/22, same worktree): the five routed fixes
are implemented. (1) `crt/src/hal/spi.c` now guards every register-touching
body behind `RS_SPI_TARGET_PRESENT` (Tiny + `RS_SOC_APB4_SPI_BASE`) and
returns `RS_ENOTSUP` otherwise; the absolute-offset fallback macro is removed,
so Mini and host builds emit no self-owned C warnings. (2)
`apb4_spi_block_top.sv` and `tests/rtl/spi_test_body.svh` connect the new
`session_owned_o`/`lifecycle_idle_o` pins, restoring the SPI-P1 standalone
fixtures. (3) `clock_reset_domains.json` lists the `spi` leaf and peripheral
crossing, and `scripts/check_clock_reset_domains.py` expects them. (4) The
fabric/reset testbenches use `USER_WIDTH(4)` interfaces and matching 40/7-bit
scoreboard registers, and the committed contract tests now encode the frozen
P3 allocation (IRQ25, RCU16, 23 reset leaves, SPI lifecycle leaf,
`32'h0003_39ff` request mask). (5) The Tiny publication source contract tracks
the 4-bit origin widening (`s_r_data[4]`, `s_rin_data[6:5]`), the renamed
`decode_target`-based fabric check, the DMA request mask validation and the
uart1 tie-off.

Post-repair gates: all 16 previously failing tests pass; full Pytest reports
2096 passed, 1 skipped (known optional `pypdf`), 0 failed in 4035.08 s;
`ruff check .`, `sw-format-check`, `sw-policy-check`, `sw-host-test` and
`git diff --check` pass; Mini (`configs/ci/ihp130.mk`) and both Tiny
acceptance firmware builds are free of self-owned C warnings; the focused
spi-p3 stages pass on both profiles; the Tiny Verilator acceptance passes
again on both profiles at `SIM_TEST_PASS Tiny cycles=1030643`
(`build/ics55-tiny-2026-10-21-21-12-a257f7b03bdb/`,
`build/ihp130-tiny-2026-10-21-21-12-76f15177ba7a/`). `make regress-pr` then
passed the Mini rtl-lint, firmware, Verilator, debug and Icarus assembly steps
but the Mini Yosys smoke synthesis hit the pre-existing 10800 s host timeout
(`build/ihp130-2026-10-21-21-12-c30fb9412aa3/syn/yosys/result-synth.json`,
continuous OPT-pass progress, identical 10800 s failures on 2026-09-23 and
2026-10-02 with older configurations). Per explicit user decision on
2026-10-22, the Mini Yosys smoke synthesis and its dependent Mini
netlist/STA steps are skipped for this campaign; the recorded Mini steps
(rtl-lint, ci_smoke/shell firmware, Verilator sim, debug-sim, Icarus
assembly) all passed post-repair.

Tiny PR matrix completion (2026-10-22, same worktree): `rtl-lint` and the
R2-P7 Verilator acceptance passed inside the suite
(`SIM_TEST_PASS Tiny cycles=3859487`,
`build/ihp130-tiny-2026-10-22-07-47-3f1b609b0b86/`); the R2-P7 Icarus
behavioral step aborted the suite at the pre-existing observer/sv2v
elaboration defect (29 errors, `build/ihp130-tiny-2026-10-22-07-47-aae2707c2aa5/sim/iverilog/`).
The remaining suite steps were then executed individually with
`BUILD_TIMESTAMP=2026-10-22-07-58` pinned to one variant root: Tiny Yosys
synthesis passed in 2066.0 s with the netlist retained, `netsim-boot` passed
with `SIM_TEST_PASS Tiny cycles=36069`, and OpenSTA completed with per-corner
reports retained (`build/ihp130-tiny-2026-10-22-07-58-8232fa11e7f3/`; timing
remains observational, e.g. timing_metrics `wns min -0.48`, no closure
claimed). `check-rtl-lint` reports failed because no
`quality/warnings/ihp130-tiny/` baseline exists (every signature reads as new);
this pre-dates SPI-P3 and is non-blocking inside the regression runner.
`check-warnings` passed and `check-metrics` ran in observe mode. The Icarus
behavioral defect remains routed to the R2 DV owners; `phase_accepted` stays
false.

Icarus defect resolution (2026-10-22, later commit): the routed dv observer
defect is fixed on top of this worktree with semantics preserved; the R2-P7
Icarus behavioral acceptance passes with `SIM_TEST_PASS Tiny cycles=3859487`
(`build/ihp130-tiny-2026-10-22-12-16-aae2707c2aa5/sim/iverilog/`), matching
the Verilator cycle count exactly. Details are recorded in
[tiny-soc-verification.md](tiny-soc-verification.md#tiny-icarus-behavioral-repair-2026-10-22).

SPI-P3 review-repair round (2026-10-22, same worktree): independent review of
the full worktree delta found three P1 defects, all fixed and re-verified.
(1) `dma_axi4_master` sampled the origin channel from the live arbiter during
the AW/W/AR address phase, after arbitration advanced, so final single-beat
and contended SPI alias bursts were mis-qualified; the origin channel is now
registered at the start handshake alongside addr/beats/fixed. The new focused
`tests/rtl/dma_origin_tb.sv` (via
`tests/test_dma.py::test_dma_origin_qualifier_stays_staged_per_burst`) checks
every AR/AW/W user field per beat for a nonzero channel under idle and
contended arbitration; it fails against a reverted live-origin variant
(ar=49/aw=47 mismatches) and passes on the fix. (2) RCU feedback bit 15 had
no driver; `retrosoc_tiny.sv` now ties off `s_actual_gate[15]`/
`s_reset_held[15]`/`s_reset_ready[15]`, and the generated bridges tie
non-SPI origin/channel constants, eliminating the entire UNDRIVEN lint class
(zero entries in the post-fix lint log). (3) The clock-switch quiescence slice
`.clients_idle_i` is widened to `s_periph_idle_ref[16:1]` so SPI sessions veto
rate changes as the phase contract claims. P2/P3 follow-ups fixed in the same
round: `tiny_r2_p5_fabric_formal.sv` widened to USER_WIDTH(4), five remaining
`dma_axi4_master` instantiations tie off the origin inputs, `rs_spi_acquire`
waits on GPIO_READY alone, host tests added for the SPI divider math and the
Tiny SPI DMA aperture checks, plus comment/dead-branch/magic-number/provenance
cleanups.

Post-repair evidence (2026-10-22): full Pytest 2097 passed, 1 skipped
(optional `pypdf`), 0 failed in 4080.06 s; both SPI-P3 Verilator acceptance
runs pass at `SIM_TEST_PASS Tiny cycles=1030088`
(`build/ics55-tiny-2026-10-22-10-27-a257f7b03bdb/`,
`build/ihp130-tiny-2026-10-22-10-27-76f15177ba7a/`); the R2-P7 Verilator
acceptance still passes at `cycles=3859487`
(`build/ihp130-tiny-2026-10-22-10-27-3f1b609b0b86/`); Mini DMA formal prove
and cover both PASS (`build/ihp130-2026-10-22-10-31-c30fb9412aa3/formal/dma/`);
Mini rtl-lint passes; Tiny Yosys synthesis, `netsim-boot`
(`SIM_TEST_PASS Tiny cycles=36069`) and OpenSTA all pass under
`build/ihp130-tiny-2026-10-22-10-31-8232fa11e7f3/`; `rtl-format-check`,
`ruff check .`, `sw-format-check`, `sw-policy-check`, `sw-host-test` and
`git diff --check` all pass. Remaining gaps are unchanged: the Mini smoke-synthesis host
timeout (skipped per user decision), the missing Tiny warning baseline
(non-blocking observation), human phase acceptance, and the deferred
SPI-P4/P5 obligations. The pre-existing Icarus observer/sv2v defect listed
above was subsequently fixed (see the resolution note in the Tiny PR matrix
paragraph and `tiny-soc-verification.md`); `phase_accepted` stays false.

## SPI-P1 implementation checkpoint (2026-10-18, historical)

The approved standalone implementation starts from clean
`dev@e62ccdad87e1fd412eff70cc2527ad3090f16a55`. The
[SPI-P1 runbook](spi-p1.md) records the implementation, interface contracts,
coverage and commands. Default ICS55/PLL-present and explicit IHP130/no-PLL
compatibility remain SAFE24. Production product filelists, GPIO/RCU/address
maps, DMA V2.2, HAL/application integration and dependency versions are unchanged.
The standalone register header is additive; DMA capability remains clear.

Standalone implementation validation completed on 2026-10-19; no SPI-P1 human
acceptance or later-phase approval is recorded. Tiny P10 remains pending
complete regression closure. Read the
dated implementation results separately from the original P0 freeze record.

Evidence roots for the original candidate were:

- `build/ics55-tiny-2026-10-18-23-58-bbe722dc382e/meta/spi-p1/`.
- `build/ihp130-tiny-2026-10-18-23-58-439583e27401/meta/spi-p1/`.

Earlier attempts remain retained. In particular, initial formal tool PASS
results before `sv2v -E Assert` had no active properties and are invalid as
qualification evidence. Later induction/BMC timeouts, AIG preparation errors,
statistics-parser failures and the Icarus fixture timeout remain attributed
to their original sources. The Icarus timeout was caused by sv2v's lowering
of an early task return into millions of empty loop iterations; moving the
exit condition into the loop preserves its bound and every test case.
The 23:25 cover reached all goals but timed out during optional VCD export;
it remains failed. The 23:53 campaign disables that export, retains compact
witnesses and validates their length. Its induction and depth192 BMC reuse
the successful 23:25 subtasks only after exact model/configuration, proof
input/tool, artifact-integrity and nonvacuity checks. Original producer
identities remain in the reuse records; no historical failure is relabeled.
The 23:53 cover passed with a 195-step witness. The final 23:58 cohort follows
the repository formatter's Makefile EOF convention; its source snapshot is
distinct, and its focused gates are retained separately.

### Completed standalone results (2026-10-19)

The frozen `docs/ip/spi.md` SHA-256 is
`2c6b5c40d88973e34eb5e291c5cee40fa0128f7cc860727283e5b9c5ca32706c`.
The implementation remains an uncommitted worktree delta on the revision
above; each stage retains its actual source map, source archive, external
input hashes and commands. `report/record.json` combines checked stage records
without accepting the phase. `validation/final-audit.json` independently checks
current-source identity, retained artifact hashes, markers and result files.

| Check | Result and boundary |
| --- | --- |
| Verilator and Icarus | All four standalone fixtures pass on each simulator; 305 core segments per simulator, including 48 exhaustive mode/width/order/direction cases, DIV65535 and 256 deterministic random segments |
| Formal | Phase and register induction pass; depth192 session-core BMC passes (original producer 773.96 s); final cover passes with a 195-step witness and active-property checks; compositional scope only |
| ABI/tool negative tests | 29 pass, including all 101 handwritten SVH/C constants and rejection of stale/failed/vacuous proof reuse |
| Quality | Formatting, owned RTL style/readiness, C policy/host tests, Ruff, standalone C header compilation and whitespace checks pass |
| Full Pytest | 2068 passed, 1 skipped in 4860.55 s; optional PDF retrieval test lacks `pypdf`; no dependency was installed or changed |
| Compatibility firmware | TINY/ICS55, TINY/IHP130 and MINI/IHP130 compile successfully in the retained 23:25 campaign; no product SPI or firmware-simulation claim |
| Regression definitions | PR/nightly dry-runs pass for TINY/ICS55, TINY/IHP130 and MINI/IHP130; these are not executed full regressions |

| Block backend | ICS55 | IHP130 |
| --- | --- | --- |
| Balanced mapped cells | 7431 | 7949 |
| Liberty area | 19240.76 | 126612.7254 |
| FIFO payload / block SRAM macros | 2 x 256 bits / 0 | 2 x 256 bits / 0 |
| Standard-cell netlist fixture | PASS | PASS |
| Internal PCLK setup/hold WNS and TNS | all 0.00 | all 0.00 |

Area is the selected library's synthesis statistic, not placed area or a
cross-PDK density claim. PCLK is 41.666666667 ns; synthesis uses rounded
41667 ps. STA uses one slow library per PDK and no external delay model:
each report has 319 inputs missing input delay, 41 outputs missing output
delay and 42 unconstrained endpoints. There is no blanket reset/MISO exception.
This does not qualify serial I/O, reset recovery/removal, board timing, all PVT
corners, higher SYS/PCLK operation or a complete Tiny netlist.

Raw warnings remain retained: ABC reports combinational-network mapping in
both PDKs and six multi-output library cells in ICS55; formal lowering reports
FIFO memory expansion. Make records host/filesystem clock skew. Owned lint
passes with only the explicitly scoped managed-Common suppressions. No warning
baseline was regenerated, no metric was promoted, and no whole-product
warning/metric gate is claimed by these standalone targets.

Unrun/deferred: long full-firmware Icarus and complete supported product
regressions remain deferred to the final combined campaign; no repeated P7/VGA
campaign, full-chip synthesis/netlist/STA, commercial flow, physical/Pad/board
or silicon qualification was run. Actual DMA V2.2, latched fabric origin,
GPIO/RCU integration, CDC/RDC and SDK/display qualification remain P2/P3 or
later obligations. No new MISRA deviation is required. Independent read-only
review and explicit human phase acceptance remain the next gate; the
readiness status stays `prototype` and `phase_accepted` stays false.

## Configuration and Identity

- Current normative default: TINY/ICS55, `HAVE_PLL=YES`, SAFE24 boot under the
  [2026-10-07 Tiny policy](tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07).
  `configs/ci/ics55-tiny.mk` now exists with a parked PLL; platform acceptance
  belongs to the Tiny ledger. The profile below remains IHP130 compatibility;
  neither platform implements SPI.
- Before final qualification, post-synthesis timing is observational and all
  failures/NOT_RUN cases remain attributed. Functional/source/protocol and
  synthesis/mapping/netlist-function gates remain mandatory. SPI-P5 joins
  R2-P11/PIOLITE-P5/PPALITE-P5 after all functional phases on the identical
  complete-product source/config/PDK/netlist. No intermediate timing closure
  is required to proceed; final timing closure remains mandatory.

- Starting profile: `configs/ci/ihp130-tiny.mk`, TINY, IHP130, 24 MHz/no PLL,
  current four-channel DMA and no SPI.
- Target: SPI0 at `0x1001D000`, IRQ25, RCU16; modes 0-3, 8/16-bit frames,
  TX/RX 8x32, PCLK execution, GPIO27/28/30/31, DMA V2.2 requests 16/17.
- Gen1 native routes require the approved R2-P6 migration; higher PCLK and
  lifecycle require R2-P7. Camera/PSRAM application cases require R2-P8/P9.
- Record source SHA, dependency/configuration digests, profile, PDK, variant,
  tools, command/log/result paths, clocks/divider/mode/direction, FIFO owners,
  buffer addresses/capacities/counts, panel/board models and limitations.
- Artifacts belong below the existing timestamped configuration-hash build
  root. A dry-run, tied-off capability or skipped fixture is not evidence.
- Mini tests validate shared-DMA/GPIO compatibility with SPI support disabled.
  Final qualification must use the same SPI/PIO/PPALite-inclusive source and
  netlist as the mandatory R2-P11/PIOLITE-P5/PPALITE-P5 campaign.

## Required Case Matrix

At P0 freeze all cases had status **required, not run**. The dated P1 record
above adds standalone evidence only; later integration and physical obligations
in this matrix remain required.

| Case | Requirements | Required observation / phase |
| --- | --- | --- |
| SPI-V01 | SPI-01/03 | Modes 0-3, 8/16-bit frames, both bit orders, TX-only/full-duplex/RX-only, dummy values; independent pin BFM; P1 |
| SPI-V02 | SPI-03/04 | Exactly 2*FRAME_BITS edges, CPHA=0 final trailing edge, first-bit setup, divider 1/65535, CS delays 1/65535 and rejection of 0; P1 |
| SPI-V03 | SPI-02/04 | Low-lane-first order, counts 1/3/4/5 at 8 bits and 1/2/3 at 16 bits, nonzero TX padding ignored, RX padding zero, no extra wire frames; P1 |
| SPI-V04 | SPI-02/06 | Count 0 and checked round-up overflow, including FRAME_COUNT=0xFFFFFFFF at both widths; no ARM/state/payload effects on rejection; P1/P2 |
| SPI-V05 | SPI-02/04 | FIFO 0/1/7/8, simultaneous push/pop with frozen pre-edge rules, no mid-frame pause, RX capacity reservation and TX-only discard; P1 |
| SPI-V06 | SPI-03/04 | ARM before preload, START without data, HOLD_CS8-bit command to 16-bit pixels, clean/pending distinction, D/C setup/hold and explicit END; P1/P3 |
| SPI-V07 | SPI-02/07 | All CSR access/reset/field/source/owner checks, unsupported strobes/addresses, one-shot FIFO effects, SVH/C mirror and bounded APB responses; P1 |
| SPI-V08 | SPI-03/08 | ABORT at every wire state, bound independent of empty/full FIFO, emergency ownership-loss truncation, no success event for aborted transfer, set-over-W1C; P1/P2 |
| SPI-V09 | SPI-06 | Old selectors/TCDs unchanged, full 5-bit encode/decode and control 25, V2.0/V2.1 rejection before writes, 32-bit support/status and reserved 18..31 rejection; P2 |
| SPI-V10 | SPI-06 | Distinct bound channels, direct/finite TCD jobs, wrong address/kind/increment/count, default-disabled Mini, exact unchanged stream count; P2 |
| SPI-V11 | SPI-02/06 | CPU denied DMA aliases; central DMA denied CPU aliases/control; wrong-request/channel DMA denied its aliases; no credit stealing; P2/P3 |
| SPI-V12 | SPI-06/08 | Latched origin with AW/W and AR, CDC/backpressure, reserve-at-admission through R/B, bounded unavailable/closing FIFO error, CPU abort progress and unaffected DMA writes; P2/P3 |
| SPI-V13 | SPI-06/08 | DMA DONE before wire end, RX final B after wire end, exact quotas/tails, residual pending segment cannot ARM/rebind/change D/C/END; P2/P3 |
| SPI-V14 | SPI-06/08 | Descriptor fetch/parse/activation cancellation, simultaneous abort/start/rebind, suspended jobs, accepted-read/write drain and timeout ownership retention; P2 |
| SPI-V15 | SPI-05 | Exactly four Gen1 ALT additions, legacy PWM migration, other ALT/QFN/power pins unchanged, USER priority, native-ready handoff and raw MISO capture; P3 |
| SPI-V16 | SPI-05/08 | GPIO/ALT switch with old driver OE off, USER_STATUS0 while handoff active, locks/open-drain rejection, D/C ownership/mutable value, external CS bias model; P3 |
| SPI-V17 | SPI-05/08 | Route/readiness loss during prefill/armed/held/closing, RECOVER and DISABLE retain session, verified handback RELEASE, no auto restart or hidden global reset; P3 |
| SPI-V18 | SPI-03/08 | GPIO/SPI gate/reset and PCLK-change veto while session retained, multi-target requests, WFI/debug/hart reset, new clock rediscovery and no stale epoch; P3 |
| SPI-V19 | SPI-07 | HAL64-bit length math, alignment/capacity canaries, timeout/lock/error propagation, CPU full-duplex simultaneous service and no heap; P3/P4 |
| SPI-V20 | SPI-04/09 | Panel color bars/gradients and odd rectangles, command/data timing, 8-to-16-bit packing, cold reset/init/rotation, error injection and exact pixel oracle; P4 |
| SPI-V21 | SPI-09/10 | 153600-byte QVGA frame in initialized PSRAM, DVP validity/final-write drain, data/pixel/save checksums and sequential resource handoff; P4 |
| SPI-V22 | SPI-06/09/10 | SRAM versus PSRAM source timing, CPU cycles, wire utilization, FIFO/longest-service gaps, unrelated channel/PIO and existing XPI LCD regressions; P4 |
| SPI-V23 | SPI-03/05/10 | Block/full synthesis, FIFO mapping, netlist, reset/CDC/RDC, MISO/output PVT timing, Pad/board/package/power qualification; P5 |

The BFM must decode observed pins independently of the DUT shifter/model code.
Directed recovery cases must include initial ENABLE's inactive gap without a
spurious DONE, normal DISABLE revoking both bindings, pending DMA admission
preventing teardown, fault/ABORT versus START/FIFO ordering, and emergency
wire-close plus RECOVER with a persistently invalid route. Verify RECOVER
does not immediately re-fault while performing DISABLED GPIO handback.
Assertions/formal cover finite quota/credit conservation, stable origin and
response ownership, no stolen FIFO word, no next frame after close, legal FSM,
no stale descriptor activation, and source/clock isolation. State proof bounds
and external-response fairness assumptions; formal digital properties do not
establish analog CDC/Pad safety or arbitrary board/device liveness.

## Application Acceptance

Use an ST7789VI-style four-wire display reference in 320x240 landscape RGB565,
not the legacy 240x135/GPIO2/XPI transport. No display MISO, TE, touch or GPIO
backlight control is assumed. A separate general SPI profile covers MISO and
all four modes; the display profile uses GPIO30 D/C and validates its own mode.

1. Independent SPI slave BFM: deterministic/ramp/pseudorandom words, short
   transfers, RX-only dummy clocks, TX-only discard, stalls and held-CS chains.
2. Display-only patterns: color bars, gradients, odd widths/pixel counts,
   window endpoints and byte/pixel order. Framebuffer/pixel capture from the
   panel model must match the reference, not just an APB or DMA byte counter.
3. PSRAM-source display: initialized and capacity-checked NSS1, immutable
   source buffer, explicit aligned/padded extent, measured single-beat cost.
4. Sequential snapshot: DVP capture -> full frame/DMA-write validation ->
   PSRAM readback/optional bounded processing -> SPI display -> SD save and
   data verification. Use 153600 logical bytes for 320x240 RGB565. Keep the
   source owned and immutable until display/save complete; no hidden 150 KiB
   buffer in 128 KiB SRAM and no simultaneous next-frame capture requirement.

Record actual configured/readable SCK, frame time, CPU cycles, DMA stalls,
FIFO high/low watermarks and qualified device limits. Run PCLK 24 first;
PCLK 48/60 functional cases await executable R2 profiles and appropriate
functional device models; their physical timing is a final-campaign gate. Ideal
12/24/30 MHz ceilings and pixel-only timing arithmetic are not measured FPS.
Legacy LCD/LVGL behavior, PIO14/15 and unaffected Tiny/Mini users must remain
separate compatibility checks, not silently moved to SPI.

## Commands and Verdicts

Documentation freeze checks use:

```sh
git diff --check
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --dry-run
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI --dry-run
```

Verify local links/anchors, newly added files' whitespace, documented profile
and commands, unchanged phase IDs/package, and exactly the four authorized ALT
cell changes. These commands do not compile or simulate SPI.

P1/P2 add focused tests and existing lint/style/formal/synthesis integration;
do not invent working Make targets before those phases land. P3/P4 use the
main specification's SDK, firmware and regression commands plus affected
DMA/GPIO cases. Both Verilator and Icarus exercise pin-level protocol and
recovery. Tiny success requires exit 0, TEST_STATUS/`SIM_TEST_PASS` and no
`FAILED`, `FATAL`, `assertion failed`, `%Error`, `SIM_TEST_FAIL` or
`SIM_TEST_TIMEOUT`. UART output is diagnostic only. Mini retains its own
configured verdict; never substitute Mini coverage for missing Tiny support.

## Freeze Record and Gaps (historical P0)

| Phase | Evidence status |
| --- | --- |
| SPI-P0 | Documentation freeze complete; link/anchor, command dry-run, phase/package/ALT structure and whitespace checks passed on 2026-10-04 |
| SPI-P1 | Not started; standalone RTL/model, CSR mirror, BFM and synthesis evidence absent |
| SPI-P2 | Historical freeze entry; current implementation and evidence are recorded in the SPI-P2 checkpoint above |
| SPI-P3 | Not started; actual routing/source qualification/GPIO/RCU/HAL integration absent |
| SPI-P4 | Not started; panel adapter, pixel oracle, snapshot/save and performance evidence absent |
| SPI-P5 | Not started; SPI/PIO-inclusive physical, Pad/package and silicon qualification absent |

Executed P0 checks: `git diff --check`; 151 local Markdown links and two
anchors; new-file ASCII/fence/whitespace validation; all 25 existing Tiny/R2
phase headings and the complete QFN64 package section unchanged; 32 GPIO rows
with only four approved reserved ALT cells filled; PIO-lite specification and
ledger unchanged; all 11 changed/added files are Markdown. The three regression
dry-runs above passed using the local `python` executable. Independent
specification review closed the completion, credit, binding-release and
emergency-recovery ambiguities; that review is not behavioral validation.

No implementation, full regression, EDA or silicon result is implied by P0.
No MISRA deviation, warning-baseline update, metrics promotion, new dependency,
PDK or security/safety claim is approved. Later records must retain missing
tool/model/Pad/macro/board evidence and the exact claim it prevents.
