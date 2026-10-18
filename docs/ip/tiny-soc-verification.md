# Tiny MCU Verification Record

## TINY-R2-P10 quality-gate repair (2026-10-18)

The approved repair starts from `dev@5b81dea4fe0a68aabb51f42f01422068280192b2`
plus the retained P10/P7 worktree. It corrects publication metadata and tests,
normalizes exactly one final LF in each of four Make files, and appends these
two P10 documents. The maintainer explicitly extended the original eight-file
scope to ten files for the DVP circuit catalog and its tests. Production RTL,
HAL, public interfaces, profiles, dependencies, warning/metric policy and
the reviewed P7 capability correction remain unchanged. No new MISRA deviation
is introduced.

The stale PSRAM source reference predates this repair: P8 commit `f6190f91`
moved the model to `rtl/model/ESP_PSRAM64H.sv`. The publication's bulk-channel
binding also still expected the pre-P9 direct `RS_DMA_CHANNEL_BULK` call.
It now binds both the real `RS_DVP_DMA_CHANNEL` call and its Tiny/Mini
conditional definition; Mini retains bulk channel 3. Negative tests reject
a wrong call target or Mini selector without changing the HAL.

After those corrections, the first focused run reaches a further stale DVP
diagram binding. The configuration CDC now transports 128 configuration bits
plus an epoch and feeds an applied-configuration register. The approved
diagram correction records packet assembly, the 129-bit CDC path, payload
extraction and the 128-bit applied register before the core. The 42-bit payload
FIFO path remains unchanged. Directed tests reject changed CDC width,
payload slicing and bypass of the applied register. The isolated diagram
fixture now copies dependencies from the additional circuit catalog as well
as the embedded circuits; validators are not relaxed.

The execution retains each attempt rather than overwriting failed results:

| Check | Recorded result |
| --- | --- |
| Initial publication selection | 100 passed / 1 skipped / 60 errors; exposed the old DVP diagram binding |
| Diagram correction before fixture completion | 156 passed / 1 skipped / 7 failed; isolated trees lacked the register declaration source |
| Final publication selection | 163 passed / 1 skipped |
| Build-tool and Tiny configuration selections | 2 passed and 6 passed |
| Format, embedded-C policy/host tests, Ruff, final diff | PASS |
| One full Pytest execution | **2031 passed / 1 skipped**, zero failures/errors, 4854.44 s |

The sole skip remains the optional `pypdf` import. Source hashes are unchanged
during the full Pytest run. The earlier full-run 10 failures/60 errors remain
historical failures; the new run closes the current local publication/Make
quality gaps. This is not a new remote CI result.

Before/after configuration and firmware dry-run output is byte-identical for
all five build cases; the Mini Verilator lint dry-run also matches. Tiny
ICS55/IHP130 and Mini IHP130 each pass PR/nightly definition dry-runs. These
are definition checks, not executed complete hardware regressions.

| Firmware case | New variant | Build duration | Retained image comparison |
| --- | --- | --- | --- |
| Tiny ICS55 P7 | `ics55-tiny-2026-10-18-17-28-bea5da759fbb` | 4.462 s | HEX byte-identical |
| Tiny ICS55 VGA | `ics55-tiny-2026-10-18-17-28-7be4ff496b65` | 4.398 s | HEX byte-identical |
| Tiny IHP130 P7 | `ihp130-tiny-2026-10-18-17-28-3f1b609b0b86` | 4.451 s | HEX byte-identical |
| Tiny IHP130 VGA | `ihp130-tiny-2026-10-18-17-28-28a0c226bed5` | 4.523 s | HEX byte-identical |
| Mini IHP130 compatibility | `ihp130-2026-10-18-17-28-a2f660e37f72` | 6.772 s | Compilation only |

Each build succeeds without self-owned C compiler warnings and retains its
own ELF/HEX/configuration identity. No P7/VGA full-system simulation is
repeated. Directed RTL fixtures remain part of the full Pytest execution.
The separate reuse audit checks original reports, model/runtime inputs,
command equivalence, exact final-LF changes and matching loadable images.
Original simulation source digests stay attached to their original runs;
no old report or collector allowance is rewritten.

The aggregate evidence root is
`build/ics55-tiny-2026-10-18-17-28-bea5da759fbb/meta/tiny-r2-p10/quality-repair/`.
It retains `pre-edit.json`, `approved-extension.json`, source archives,
`command-equivalence.json`, `firmware-summary.json`,
`pytest-execution-source.json`, `retained-evidence-audit.json`, `report.json`
and `validation/` logs/results/JUnit. Each variant above also retains
`meta/tiny-r2-p10/quality-repair/firmware-record.json`. The
[runbook](tiny-soc-r2-system-performance.md#quality-gate-repair) records the
command matrix and ownership boundary.

The report is `quality_repair_complete` with `phase_accepted=false`.
Full long Icarus/complete supported regression and final physical/PVT/board/
sensor/frequency qualification remain open. Synthesis, netlist and STA are
not rerun for these metadata/final-LF changes. Publication identity remains
`c3de7c602a7ca0f0f9ade9d3ffb59339bc34fb8b`; PDF generation, source-baseline
refresh and visual qualification are NOT_RUN. The strict source-drift check
is preserved. `.editorconfig` still requests a final newline while the locked
mbake default removes it; this repair follows the executable gate and does
not approve a formatting-policy change. No commit, push or phase advancement
is performed.

## TINY-R2-P10 P7 capability correction (2026-10-18)

The approved follow-up repairs the stale P7 acceptance-image capability check
on `dev@5b81dea4fe0a68aabb51f42f01422068280192b2` plus the retained P10
worktree. `tiny_r2_p7.c` now requires the exact DVP-inclusive `0x00007FFF`
through an application-private constant. Production `TargetMask`, HAL,
register ABI, profiles, dependencies and quality policy are unchanged.
The architecture's `0x0003FFFF` allowed mask is not an implemented-target
expectation. No new MISRA deviation is introduced.

The added cross-source checks read the real `u_sysctrl` parameter and firmware
startup guard. They reject the old capability, unimplemented target bits,
removed/masked comparisons, and missing or ambiguous source definitions.
The focused selection passes **14 tests** (including existing register parity).
Software format/policy/host tests, Ruff and the final diff check pass.

One complete Pytest execution reports **1956 passed, 10 failed, 60 errors and
1 skipped** in 4841.86 seconds. Its 70 failure/error nodes exactly match the
previous full run and all reference the existing publication dependency on
`rtl/mini/dv/model/ESP_PSRAM64H.sv`. They remain failures; the optional `pypdf`
skip and existing Make-format issues are not repaired here. Shared validation,
JUnit results and `pytest-baseline-comparison.json` are retained under the
ICS55 evidence directory's `validation/` below.

Both PDKs pass PR/nightly dry-runs; the expansions remain identical per PDK.
Each P7 Verilator image is rebuilt in the fresh `2026-10-18-14-51` variant and
executed exactly once, without automatic retries:

| PDK | Verdict / cycles | Flow duration | Profiles | CPU gated cycles / DMA responses while gated / warm resets |
| --- | --- | --- | --- | --- |
| ICS55 | PASS / 3803591 | 1162.871 s | 2, 3, 0 | 71627 / 64 / 1 |
| IHP130 | PASS / 3799823 | 561.606 s | 1, 0 | 71634 / 64 / 1 |

Both commands and standard checkers succeed, with exactly one
`SIM_TEST_PASS Tiny`, one `P7_LIFECYCLE_PASS`, required profile coverage and
no forbidden error marker. There are no self-owned C compiler warnings.
Source, runtime/filelist and pre-launch ELF/HEX/model identities match after
execution. The normal `+p7_monitor` cold-reset assertions execute; the
diagnostic-only `P7_COLD_RESET_PASS` marker is not required. These are logical
clock/lifecycle checks, not physical frequency qualification. CPU/main-SRAM
SYS and divided XPI MEM retain their existing distinct meanings.

New evidence directories are:

- `build/ics55-tiny-2026-10-18-14-51-bea5da759fbb/meta/tiny-r2-p10/p7-capability-fix/`.
- `build/ihp130-tiny-2026-10-18-14-51-3f1b609b0b86/meta/tiny-r2-p10/p7-capability-fix/`.

Each retains `p7-record.json`, `source-before.json`, `runtime-before.json`,
`launch-identity.json`, command logs/results, `vga-reuse-audit.json` and
`report.json`. The shared `pre-edit.json` verifies both original VGA executions
against the actual source before this correction and records the original
compiler commands, binaries, logs, source archives and tool identities.
The new audit proves the subsequent P7 C edit is not consumed by the VGA build
and that its runtime/generated inputs are unchanged. Test/documentation
changes are recorded separately. Original VGA execution digests and
measurements remain attached to their original binaries; no simulation is
repeated and no collector whitelist or old report is rewritten.

This closes the selected P7 Verilator gap and retains the two passed VGA
executions. Reports use `selected_followup_complete` with
`phase_accepted=false`. The failed 09:20 P7 attempts below remain real failures
on their original source. Full long Icarus/complete supported regression,
separate publication/Make-format repairs and final physical/PVT/board/sensor
qualification remain open. No synthesis, netlist, STA or physical flow is
rerun for this acceptance-image correction; earlier evidence retains its
original attribution. No commit, push or phase advancement is performed.

## TINY-R2-P10 P7 and VGA follow-up (2026-10-18)

The maintainer approved one P7 Verilator lifecycle execution and one full
VGA/YUV422 execution per PDK, preserving the existing P10 candidate based on
`5b81dea4fe0a68aabb51f42f01422068280192b2`. Only this ledger and the P10
runbook are edited; no RTL, firmware, HAL, profile, dependency or quality-policy
input is changed. New evidence uses timestamp `2026-10-18-09-20`; the
2026-10-17 reports below keep their original identities and scope.

Both Tiny PR/nightly dry-runs pass and expand to identical commands per PDK.
This is matrix-definition evidence, not an executed complete regression.
The original P7/P9 producer phase IDs remain in their records; P10 consumes
these follow-up results without accepting another phase.

| PDK | P7 lifecycle image | Full VGA/YUV422 image |
| --- | --- | --- |
| ICS55 | FAIL, firmware code 1, simulator exit 1, 361.667 s | PASS, 13598.239 s, 73938869 cycles |
| IHP130 | FAIL, firmware code 1, simulator exit 1, 268.512 s | PASS, 9269.826 s, 73938869 cycles |

The P7 failure is a stale acceptance-image expectation. The firmware at
`app/apps/ci_smoke/tiny_r2_p7.c:133` requires `target_capability == 0x3fff`.
The DVP-inclusive integration sets `TargetMask=0x7fff` in
`rtl/tiny/top/retrosoc_tiny.sv`; `tiny_sysctrl.sv` returns that mask at
TARGET_CAP and `crt/src/hal/rcu.c` copies it into the snapshot. The retained
firmware disassembly still compares against `0x3fff`. Both simulations report
`SIM_TEST_FAIL code=1` before any `P7_CLOCK_COMMIT`, so current-revision clock
transition, WFI/DMA gating and warm-reset coverage remain unclosed.
This mismatch is the first established blocker; the later lifecycle checks
were not reached and need a fresh approved run after the fixture repair.

Git attribution identifies the old expectation in
`bc48cec74a8f3cec731c4853ac0380f9ae32c35b` and the DVP-inclusive mask in
`8f5630fb41257098b30153eeb50248bb63ebfb94`. Both predate this P10 follow-up.
The RTL capability must not be reduced to satisfy the stale test. Fixing the
acceptance image and adding a hardware/firmware capability-consistency check
requires the next approved implementation scope; no such fix or retry is
performed here. Historical P7 acceptance remains attributed to its old source.

P7 source and pre-launch binary identities were checked again after failure.
Its raw build/simulation logs, command results and causal source/commit chain
are bound by `p7-failure-evidence.json` under each follow-up directory:

- `build/ics55-tiny-2026-10-18-09-20-bea5da759fbb/meta/tiny-r2-p10/follow-up/`.
- `build/ihp130-tiny-2026-10-18-09-20-3f1b609b0b86/meta/tiny-r2-p10/follow-up/`.

Fresh VGA evidence is under
`build/ics55-tiny-2026-10-18-09-20-7be4ff496b65/meta/tiny-r2-p9/full-frame/`
and `build/ihp130-tiny-2026-10-18-09-20-28a0c226bed5/meta/tiny-r2-p9/full-frame/`.
Both profiles verify the 640x480 YUV422 frame, all 614400 payload bytes, 153600 DMA
words, 307200 pixels and guards, followed by the 7x3 RGB565 PIO crop with
42 valid/48 stored bytes. Total accepted/delivered FIFO words are 153612,
including the twelve PIO words. FIFO high-water is four words and the longest
observed backpressure is 489 SAFE24 cycles (20.375 us). Reserving 16 bytes
leaves a 480-us no-service budget at the exercised 1-MHz PIXCLK. The original
P9 runner, simulator and strict marker checker pass for each profile, with
exit zero, exactly one `SIM_TEST_PASS Tiny` and no forbidden error marker.
This closes the fresh full-system VGA/YUV422 Verilator gap for this candidate;
it is finite behavioral evidence, not a qualified camera FPS or physical rate.

The generated invocation wrapper compared a parser tuple with the JSON list
representation and recorded a false VGA collection failure. Supplemental
`vga-verification.json` checks exact JSON-normalized equality, the original
source/build/model/firmware identities, zero self-owned compiler warnings and
the strict Tiny verdict. It preserves the original collection error and does
not rerun simulation. An independent diagnostic-only `P7_COLD_RESET_PASS`
requirement in that wrapper was not reached by the real P7 failures; it must
not be used to convert their code-1 results into passes.

Both follow-up directories contain `report.json` with `status=incomplete`,
`executions_complete=true` and `phase_accepted=false`, because P7 fails.
All four simulator executions are complete, exactly once per selected case
and PDK. The source and pre-launch binary identities remain unchanged.
Full Icarus/complete regression stays deferred; the publication/Make-format
failures below still need separate repair approval. Physical/PVT/board/sensor
and qualified frequency claims remain final-product obligations. No phase,
commit or push is advanced by this follow-up.

## TINY-R2-P10 approved implementation campaign (2026-10-17)

The maintainer approved the P10 implementation plan from clean
`5b81dea4fe0a68aabb51f42f01422068280192b2`. The selected campaign completes
the executable performance/application work while keeping complete P10
acceptance pending final regression. Full long Icarus firmware stays deferred
to final Tiny qualification. This instruction does not rewrite prior P9
human-acceptance records, historical evidence or the frozen specification.

The [P10 runbook](tiny-soc-r2-system-performance.md) defines the exact workload,
ownership, measured endpoints, single-execution policy and evidence paths.
Default ICS55/PLL-present and IHP130/no-PLL compatibility retain SAFE24.
No production RTL, shared SDK ABI, dependency, warning baseline or metrics
policy change is introduced. The approved implementation and selected
performance/application/backend campaign are complete. Complete P10 acceptance
remains pending final regression and human review; no subsequent phase is
advanced by these results.

The first P10 focused campaign passes 19 new tests and 286 existing
P1/P3/P4/P5/P6/P9 tests (592.46 seconds for the latter), plus C formatting,
policy/host tests, Ruff, RTL format/style/readiness, Mini IHP130 firmware and
explicit Tiny ICS55/IHP130 PR/nightly plus Mini IHP130 PR dry-runs. Evidence is
under `build/ics55-tiny-2026-10-17-15-56-ff4b5cef6eb5/meta/tiny-r2-p10/validation/`.
The four pre-existing Make-format differences remain. Initial focused setup
and observer compiler failures were corrected before measurement; their
retained attempts do not replace the successful corrected test reports.

The matched stage passes one execution per retained image: ICS55 flat and
banked under variant `ics55-tiny-2026-10-17-15-56-a0ea4d0cd125`, and IHP130 P1
under `ihp130-tiny-2026-10-17-15-56-bcf62053a831`. Each records the original
image separately from the current RTL source and verifies complete readback,
guards and strict Tiny terminal verdicts. The observed cycle comparisons are:

| Matched image / case | Reference cycles | P10 cycles |
| --- | ---: | ---: |
| ICS55 P3 flat / CPU | 73911 | 73911 |
| ICS55 P3 flat / memory | 102568 | 102568 |
| ICS55 P3 flat / DMA16 | 16974 | 22829 |
| ICS55 P3 banked / memory | 86214 | 86214 |
| ICS55 P3 banked / DMA16 | 15802 | 22805 |
| IHP130 P1 / memory | 754159 | 639438 |
| IHP130 P1 / DMA16 | 71444 | 89513 |

The ICS55 reference is P5's execution of the identical P3 images; IHP130 uses
the repaired P1 reference. This is whole-platform evolution, not attribution
to an isolated CPU/fabric optimization. The cases include regressions and no
predetermined speedup gate. The remaining selected stages are recorded below;
the complete supported regression remains unclosed.

The one full Pytest execution completes in 5031.91 seconds with **1937 passed,
10 failed, 60 errors and 1 skipped**. All failures/fixture errors are existing
publication consumers of `rtl/mini/dv/model/ESP_PSRAM64H.sv`; the actual shared
model remains at `rtl/model/ESP_PSRAM64H.sv`. Publication sources were not
changed. This is not a global CI PASS. IHP130 ordinary acceptance plus P10
audio observations passes under `ihp130-tiny-2026-10-17-15-56-83113a53b401`:
both 256-frame audio formats and four WS frames pass, with longest WS wait
3219 PCLK cycles (budget 4800), FIFO peak 15 and complete expected recovery.
The two windows observe 2479/7565 cycles of simultaneous issues to multiple
SRAM groups; DMA R/W beat overlap in these windows is zero and remains zero
in the report. Firmware text is 42764 bytes, BSS 10128 and flat-SRAM space
above BSS is 78388 bytes; this is headroom, not a measured worst-case stack.

ICS55 ordinary acceptance plus audio observations also passes under
`ics55-tiny-2026-10-17-15-56-f3e42d54c18b`, in 3730.267 seconds. Its WS maximum
is 3220 PCLK cycles, FIFO peak 15, and the two measured bank-overlap windows
are 2460/7520 cycles. Both PDKs retain 57 direct-background jobs in the 16-bit
case and 39 finite-chain jobs in the 24-bit case; these finite service windows
are not fixed-work architectural speedup comparisons.

IHP130's P10 backend completes under
`ihp130-tiny-2026-10-17-15-56-8232fa11e7f3`. Boot passes at 36069 cycles
(641.742 seconds), compact DVP at 175649 cycles (3074.530 seconds). The
structural audit reports 32 main, six Crypto and zero PLL macros. STA command
execution succeeds but setup WNS/TNS remain -284.47/-11105854.00 ns and hold
WNS/TNS -0.49/-141.45 ns. Standalone warnings retain exit 2; metrics remain
observe-mode PASS. No timing closure or physical qualification follows.

The ICS55 software stage completes the other six P3 images once on the same
compiled model as the matched stage, under
`ics55-tiny-2026-10-17-15-56-a0ea4d0cd125/meta/tiny-r2-p10/software/`.
All eight images retain their original HEX/ELF/compiler/layout identities.
The following current-model cycles are software comparisons, separate from
the same-image architectural comparisons above:

| P3 image | CPU | CPU copy | DMA16 | Contention |
| --- | ---: | ---: | ---: | ---: |
| COMPAT Os flat | 98586 | 135381 | 25301 | 401857 |
| TINY_PERF O2 flat | 73911 | 102568 | 22829 | 301181 |
| TINY_PERF O2 LTO flat | 73919 | 98504 | 21098 | 299414 |
| TINY_PERF O3 flat | 73911 | 102568 | 22550 | 300906 |
| TINY_PERF O3 LTO flat | 73919 | 98504 | 21098 | 299414 |
| TINY_PERF Os flat | 73979 | 110779 | 24056 | 302472 |
| TINY_PERF Os LTO flat | 73979 | 110776 | 21045 | 299773 |
| TINY_PERF O2 banked | 73914 | 86214 | 22805 | 300933 |

Compiler/profile defaults are not changed based on this table. Raw instruction,
bank, wait, descriptor, stack and payload records remain in each stage record.

ICS55's backend also completes under
`ics55-tiny-2026-10-17-15-56-ff4b5cef6eb5`: compact DVP passes at 177541 cycles
in 8887.787 seconds. Synthesis reports 476025 cells and 2711070.264704
Liberty-based area. Setup WNS/TNS are -163.87/-6193132.50 ns and hold WNS/TNS
-0.31/-45.71 ns; warnings retain exit 2 and metrics remain observational.
This was the first execution of each selected long workload, not a repeat
campaign. IHP130 reports 501378 cells and 14883898.734641 Liberty-based area.

After those frozen-source runs completed, the collector/test-only correction
accounts separately for SDIO descriptor fetches and completion writebacks.
Twenty-five focused checks pass, and both retained backend bundles revalidate
with exactly those two permitted source differences. Original records and
source snapshots are unchanged. The camera campaign uses fresh
`2026-10-17-21-20` variants and passes once per PDK. ICS55 completes in
6966.317 seconds under `ics55-tiny-2026-10-17-21-20-b6ad86f0a86e`; IHP130
completes in 5002.673 seconds under `ihp130-tiny-2026-10-17-21-20-1cb7ba9e3e49`.
Both command exits are zero, contain exactly one `SIM_TEST_PASS Tiny` at
34778540 cycles and contain no forbidden error marker. These are new P10
application results, separate from historical P9 capture and P6 SDIO evidence.

Both PDKs produce identical five-phase measurements at SAFE24:

| Camera pipeline phase | Calls | Bytes | SYS cycles | Retired instructions |
| --- | ---: | ---: | ---: | ---: |
| DVP-to-PSRAM capture | 1 | 153600 | 7311485 | 1409737 |
| CPU full comparison and histogram/checksum | 1 | 153600 | 10060974 | 2140840 |
| PSRAM-to-SRAM bounce copy | 150 | 153600 | 4016550 | 388950 |
| SDIO two-sector writes | 150 | 153600 | 1686150 | 402150 |
| SDIO readback and full comparison | 150 | 153600 | 6824100 | 1667850 |

The 76800-pixel histogram and checksum `2323003269` match the independent
oracle. All 300 sectors and buffer guards pass. Raw SDIO AXI totals are
158400 read bytes and 154800 write bytes: each direction carries 153600 pixel
bytes, plus 4800 descriptor-read and 1200 status-writeback bytes respectively.
The camera FIFO accepts and delivers 38400 words, peaks at one word and has
zero observed backpressure. With the reserved 16-byte margin, the measured
occupancy leaves a 492-us no-service budget at the exercised 1-MHz PIXCLK.
This finite capture-then-save workflow does not establish continuous FPS.

The camera windows observe 200482 cycles with simultaneous issues to multiple
SRAM groups, at most two active targets, zero DMA R/W beat-overlap cycles and
zero bus response errors. Maximum completed read/write latencies are CPU
77/18 SYS cycles and SDIO 253/254; central DMA has no AXI reads in this stream
capture and a maximum write latency of 126 cycles. Initial/final pending
transactions remain in the raw observations; these are measured maxima, not
universal service guarantees. GNU `size` reports text/data/BSS of
22264/136/2768 bytes and 106096 bytes above BSS for both camera images; that
space is not a measured worst-case stack.

The final source-checked reports are:

- ICS55: `build/ics55-tiny-2026-10-17-21-20-ff4b5cef6eb5/meta/tiny-r2-p10/report/report.json`.
- IHP130: `build/ihp130-tiny-2026-10-17-21-20-8232fa11e7f3/meta/tiny-r2-p10/report/report.json`.

Both report `selected_gates_complete`, with `phase_accepted=false`. Old-stage
execution digests are preserved with exactly the two collector/test changes
listed as later validation differences; each camera's source delta is empty.
Shared C/Python/style/Mini validation is indexed by the ICS55 report and the
validation directory above, and is not repeated in the IHP130 profile report.
Exact stage commands, tool/image/model/input digests and terminal logs remain
in the referenced records. No source was changed during a long execution, and
no selected long workload was automatically repeated.

Remaining acceptance obligations are unchanged: complete PR/nightly (including
the deferred full Icarus firmware and P7 clock-transition matrix), fresh
full-system VGA coverage, physical/PVT/board/sensor and higher-frequency
qualification. The full Pytest publication failures above and existing Make
format differences in `Makefile`, `app/apps/ci_smoke/tiny.mk`,
`rtl/mini/mk/verilator.mk` and `rtl/mk/software.mk` remain explicit quality gaps.
Negative STA and warning deltas remain observations under the unchanged
policy. No new MISRA Required-rule deviation is introduced; the mechanical
checks do not establish complete MISRA certification. Human review and the
final regression closure are required before complete P10 acceptance.

## TINY-R2-P7 human acceptance and P8 implementation authorization (2026-10-15)

The maintainer explicitly confirmed P7 human acceptance and authorized the
previously approved TINY-R2-P8 implementation plan in the development session.
The accepted checkpoint is `655c5871ea1789afea1c037c1b566a7be02b2bc6`.
All seven CI workflows for that commit completed successfully, including
ICS55 run `38619690260`, IHP130 run `38619690366` and quality run `38619690155`.
This acceptance retains the source-reset and response-conservation boundaries
recorded below. Full long-running Icarus firmware remains deferred to final
Tiny qualification; negative observational STA and physical/board/rate gaps
are not waived or reclassified. Historical pending-human-review statements
below describe their original checkpoints. P8 implementation is authorized;
P8 acceptance and later phases are not implied.

## TINY-R2-P8 implementation checkpoint (2026-10-15)

The approved P8 implementation adds optional XPI NSS1/GPIO29 PSRAM and keeps
NOR/SRAM-only boot independent. The shared `ESP_PSRAM64H.sv` model is now
owned at `rtl/model` and remains compatible with Mini's separate-controller
tests. Shared XPI fixes cover byte-lane strobes, narrow-burst address
progression, serial-boundary rejection, early core termination, held read
responses, short sequences and final-command completion. The manual HAL
validates ESP-PSRAM64H identity `0d/5d/26`, 8 MiB geometry, bounded MEM24/48/96/120
timing and aligned four-beat DMA jobs.

The focused P8 campaign passed **28 tests** across both simulators, including
identity, mapped CPU/DMA paths, first/last addresses, byte/halfword/word lanes,
canaries, 4 KiB/serial boundaries, timeout/held-response/late-error cases and
forbidden-device behavior. The ICS55 full Verilator firmware passed with
`P8_RESULT code=0 profiles=3` and `SIM_TEST_PASS Tiny`; retained records are
under `build/ics55-tiny-2026-10-15-05-00-28a7d10f3a7b/meta/tiny-r2-p8/`.
Observed windows report 1024-byte CPU/DMA transfers with four-beat bursts at
SAFE24, PLL192 and PLL240. These are finite digital workload measurements,
not worst-case bounds, camera budgets, physical rates or board qualification.
The optional absent-device path is a separate bounded rejection case and does
not advertise PSRAM capability.

The handoff-required full long-running Icarus Tiny firmware was started once
but intentionally interrupted before a terminal verdict because that gate is
deferred to final Tiny qualification. Icarus P8 pin-level focused coverage
passed; the interrupted full-firmware record remains `NOT_RUN/PARTIAL` and is
not relabeled. P8 now has explicit IHP130 compatibility replay, source
snapshot/report generation, synthesis/netlist-function checks and
observational STA for both profiles. Human phase acceptance remains open.
P9 DVP, SPI, PIO-lite, PPALite and physical qualification remain unimplemented.

## TINY-R2-P9 implementation checkpoint (in progress, source 39ae718)

The entries below preserve chronological development checkpoints. For the
latest executed gates and outstanding work, see
[the row-size remediation](#p9-row-size-and-io-constraint-remediation-2026-10-17).
Earlier TIMEOUT/NOT_RUN statements retain their original attribution.

The approved P9 implementation connects the shared DVP V2 block to Tiny at
`0x1000E000`, IRQ15 and DMA2/request11. It adds the GPIO12-23 ALT1 camera
profile, RCU target bit14, the pixel-clock CDC/lifecycle declaration, the Tiny
product HAL binding, a bounded final DMA response drain and an odd-width PIO
capture helper. The Tiny camera model and P9 evidence parser are source-owned
verification inputs; Mini keeps its channel-3 DVP default.

The current source revision has passed topology generation, clock/reset-map
validation, the standalone DVP test, Tiny/IHP130 and Tiny/ICS55 firmware builds,
and the P9 host contract/evidence tests. A real P9 Verilator firmware attempt
did not reach a terminal marker within the bounded 120-second probe and is
retained as unrun/timeout evidence; it is not a pass. No P9 acceptance,
continuous FPS claim, physical sensor/IO qualification, or final Tiny Icarus
campaign is inferred from these checks.

### P9 focused integration follow-up (2026-10-15, uncommitted worktree)

The follow-up uses base `39ae71887ca427c83d39ff663ec5f0d1aa19be1a` plus
the retained worktree inputs; it is not evidence for the committed P8 tree.
`tests/rtl/tiny_r2_p9_dma_tb.sv` instantiates production DVP and DMA, extracting
the DMA parameters from Tiny's actual top-level instance. Its controlled AXI
sink represents the destination address `0x54000c00`; it does **not** instantiate
XPI, PSRAM pins, the Tiny fabric/RCU/pads or a CPU.

The fixture exposed and fixed two functional gaps:

- Tiny's old `0x31ff` mask rejected request11 in both DMA and the SDK. The
  P9 mask is now `0x39ff`, with topology, generated capability and validators
  agreeing. I2C1 requests remain unsupported; Mini's mask is unchanged.
- Shared DVP event toggles were decoded only on rising edges, losing every
  second notification. Both synchronized edges now generate an event. The
  fixture checks two frame-starts, two frame-completions and four line ends.
  The DVP register ABI, 512-byte payload FIFO and Mini channel binding remain
  unchanged.

The 4x2 RGB565 case verifies all 16 destination bytes, word sidebands, canaries,
DMA2/request11 admission, exact bytes_done/remaining and lifecycle drain.
Frame-done occurs while the last stream word is withheld; completion remains
false through that hold and a separately delayed final B response (each held
for at least 30 system cycles). A second execution reuses the binary and
returns final SLVERR, checking that DONE and confirmed byte accounting cannot
publish a successful frame. A subsequent 3x2 PIO snapshot checks 12 valid bytes,
both partial line words, repeated interrupts and final FIFO empty without
success-path abort/flush.

Verilator and Icarus focused executions pass command status, their explicit
`SIM_TEST_PASS Tiny P9 focused DVP DMA` marker and forbidden-marker checks.
This CPU-less test has no SYSCTRL TEST_STATUS; it cannot satisfy the full Tiny
firmware gate, which still requires TEST_STATUS and the configured terminal
marker. Sixteen DVP/P9/SDK tests and nine source/topology rejection tests pass.
C format/policy/host tests, RTL format/style/readiness, Ruff and diff checks
pass. Both selected P9 firmware profiles build without C warnings after
replacing negative canary indexing with an explicitly bounded guard address.
Make still reports approximately 38 seconds of filesystem clock skew; full
compiler/link commands ran and their outputs are retained. No warning baseline
or additional MISRA deviation was introduced.

Focused compile/simulation logs, failed diagnostic attempts, quality results
and PR dry-runs reside under
`build/ics55-tiny-2026-10-15-13-20-d336f87100e2/meta/tiny-r2-p9/`.
`focused-final.json` records the 16-test invocation; `source-checks.json`
records the nine-test invocation. `focused-source-final/` retains a snapshot and
hashes of the focused inputs (not a physical/whole-product qualification
manifest). Firmware logs/results are under `meta/tiny-r2-p9/` in
`build/ics55-tiny-2026-10-15-15-25-9a44f7871af5/` and
`build/ihp130-tiny-2026-10-15-15-25-064cd640790c/`.

P9 remains **in progress**. The preceding session reported a 100k-cycle timeout
before a P9 firmware stage marker, with CPU instruction fetch waiting in the
slow/XPI response path. Its `diagnose-progress-100k.log` is empty on disk:
this is session-reported diagnostic context, not retained, source-bound
measurement evidence or proof of a permanent deadlock. Do not reconstruct
that missing log or promote its inferred cause. Bounded failed probes remain
TIMEOUT; full terminal acceptance remains NOT_RUN.
The newly built firmware was not simulated in this follow-up. The current
firmware still lacks full payload readback and measured FIFO/backpressure
records (its printed zeros are placeholders, not measurements). Full
QVGA/VGA, YUV422/crop/error/recovery/service-budget cases, actual DVP-to-XPI
transport, current synthesis/mapping/netlist and observational STA remain open.
Full repository Pytest and full PR/nightly executions were not run in this
focused handoff; dry-runs still select P7 firmware, not the P9 image. Long
Icarus firmware remains deferred to final qualification. Human P9 acceptance
and P10 advancement are not implied.

### P9 approved P1 remediation (2026-10-15, 16-22 campaign)

The approved remediation remains on `dev`, base `39ae718`, with uncommitted
P9 sources. The shared DVP now acknowledges error W1C through a clear epoch
and coherent pixel-status mailbox, preserves simultaneous new source errors,
and executes ABORT/FLUSH only at command acceptance. Configuration START is
held behind an outstanding error clear; an applied configuration register
prevents an unaccepted mailbox payload from changing an active frame.
Snapshot completion stays stopped until a disabled configuration rearms it.
The existing ABI and 512-byte payload FIFO are unchanged.

The real C HAL now decodes ACTIVE at bit1, initializes all DMA/CRC options,
derives exact frame/crop length rather than treating capacity as length,
rejects odd-width DMA/undersized buffers/address overflow, and checks new
frame statistics, FIFO empty and final DMA responses. Failed DMA drain returns
without source FIFO erasure. Abort and error clearing are bounded; a stopped
pixel clock cannot be acknowledged as recovered. Mini's channel3/maximum
burst default and Tiny's channel2/four-beat binding are tested separately.

The firmware compares every DMA payload word and odd-row PIO word, including
padding and guards. The camera uses a deterministic frame-independent pattern
and a default 1 MHz candidate PIXCLK; PIO crops 7x3 from the same input frame.
FIFO/backpressure records come from verification-only handshake observers.
The parser rejects malformed terminal markers, inconsistent dimensions/frame
counts, missing readback/observations and stale or failed run identities.
These changes do not themselves constitute full-firmware acceptance.

Retained validation:

- **28 focused tests pass** after the configuration-barrier correction:
  shared DVP, P9 topology/ABI, both simulator backends and parser/provenance
  negative cases. The controlled backend checks delayed final stream/B,
  SLVERR, stopped-high/low PIXCLK, START ordering, simultaneous new error/W1C,
  repeated events and no unsolicited snapshot restart.
- The real XPI backend captures **16x8 / 256 bytes** through production
  DVP/DMA2/XPI and the NSS1 PSRAM pin model, then reads every word and both
  canaries through mapped AXI/serial transactions. It also checks **7x3 PIO**
  (42 valid bytes in 48 bytes of row-padded storage). No PSRAM backdoor supplies
  the expected result. Both Verilator and Icarus pass strict command/marker
  checks. These fixtures bypass CPU, product pads, fabric and RCU.
- Fourteen P8 pin-level compatibility scenarios passed in the earlier
  42-test combined invocation; their production XPI/model sources were not
  changed by the subsequent DVP configuration-barrier fix.
- Real HAL host tests pass for Tiny and Mini, including initialized CRC
  fields, capacity rejection, odd-width PIO, no success before B, and no source
  abort when DMA cleanup remains busy. C format/policy, RTL format/style/
  readiness, Ruff, dependency-lock validation and diff checks pass. No new
  MISRA deviation or warning-baseline edit is introduced.
- Both ICS55 and IHP130 P9 firmware builds pass without C warnings. The
  shared DVP register-shell formal prove/cover passes, including hardware
  events winning over simultaneous software clears. The final Tiny ASIC top
  elaborates in Verilator lint; this is not synthesis or CDC/RDC signoff.

Evidence root:
`build/ics55-tiny-2026-10-15-16-22-9a44f7871af5/meta/tiny-r2-p9/remediation/`.
`barrier-tests.json` and `barrier-pytest/` retain the final functional test
invocation and per-simulator logs; `focused.json` retains the earlier combined
42-test run. `current-quality.json` and `final-rtl.json` record the quality
checks. `source/` captures the earlier inputs; `source-final/` captures the
configuration-barrier test inputs. A subsequent local unused-output lint
annotation is recorded separately; it does not relabel an earlier binary's
source digest. Formal evidence is under
`build/ihp130-2026-10-15-16-22-c30fb9412aa3/formal/dvp/`.
IHP130 firmware evidence is under
`build/ihp130-tiny-2026-10-15-16-22-064cd640790c/meta/tiny-r2-p9/remediation/`.

One 120-second startup diagnostic used the same campaign's **pre-configuration-
barrier binary**, with its original source snapshot retained. It exited 124
and is TIMEOUT, not PASS. Unlike the earlier empty log, its streamed
`boot-before-config-barrier.log` shows continuing fetch/XPI progress:
at cycle 570000 the diagnostic counters are 5194/6195 and the last progress
sample is 569975. Addresses `0x74..0x84` match the retained ELF's `app_loader`
copy loop. These handshake counters are startup diagnostics, not retired
instruction/performance measurements. The observation does not support a
permanent XPI deadlock; it does not prove eventual boot or P9 capture success.
No further long firmware run was started.

All four Tiny PR/nightly dry-runs pass but still select P7 firmware. Full
PR/nightly/Pytest, final-source top-level firmware simulation, synthesis,
mapping/netlist checks and observational STA remain unrun in this remediation.
The final-source full-SoC binary was not rebuilt after the last configuration
barrier; focused simulations and top lint cover that correction. Full Icarus
firmware remains deferred. Full QVGA/VGA, VGA word-counter width, YUV422,
sensor-rate/service-budget, product mode-transition and physical qualification
remain P9/final-campaign gaps. Filesystem clock-skew warnings are retained.
This closes the scoped remediation work for review, not human P9 acceptance;
P10 is not authorized by these results.

### P9 review fixes: rearm, admission and notifications (2026-10-15)

The next approved review-fix handoff addresses the four additional P1 findings
on the same `39ae718` worktree. No new register, channel, clock domain, dependency
revision or physical operating point is introduced.

- The HAL uses the existing STATUS.ENABLE bit to observe applied pixel-domain
  enable state, while CTRL remains requested control readback. Successful
  captures can rearm the same configuration through an acknowledged,
  non-flushing disable/enable sequence. Capture helpers use the supplied
  timeout for their new start waits. Tiny and Mini host tests model delayed
  application and execute consecutive DMA and PIO captures.
- PIO rejects busy/suspended DMA before touching stream mode, IRQ state or
  FIFO contents, and rejects active/nonempty source rearm. Startup failure
  after this helper starts DMA uses its own drain/abort cleanup; rejected
  configuration does not abort another owner.
- Configuration/command epochs keep lifecycle idle low until the source
  applies the configuration or drains the command. Armed capture waiting
  for VSYNC is busy. Local reset-ready requires a fresh native status packet.
  Global CPU boot already uses internal leaf/APB/AXI prerequisites rather
  than the local-reset readiness vector, and that production expression is
  unchanged. The fixture extracts both actual expressions and tests absent
  PIXCLK global-boot independence separately from local-reset acknowledgement.
- Error causes are retained in a pending mask and transferred by an
  acknowledged mailbox. Even pairs of errors cannot cancel as sampled toggle
  parity did. Tests cover paired errors, cleared IRQ not reasserting from an
  old sticky level, and notification of a new occurrence of the same cause.

The controlled fixture now includes the production Tiny peripheral controller:
gate/reset requests time out without being applied while configuration or
commands are pending; armed capture blocks gating, and fully drained capture
permits it. The actual XPI/PSRAM and 16x8 DMA/7x3 PIO checks remain in both
simulators. These are focused controller/HAL/RTL tests, not complete pad-level
mode-transition or full firmware qualification.

Before the fixes, the retained C host command failed and the new Icarus cases
reported `pending configuration reported idle` and `paired faults lost their
interrupt`. Icarus returned zero for those fatal statements; the separate
strict simulation checks correctly marked them failed. Those diagnostic logs
are under the `17-15` variant below. Their temporary Pytest converted image
was subsequently removed by Pytest cleanup and is not claimed as retained.

The `17-15` combined campaign passed **50 tests**, including 14 P8 serial-PSRAM
compatibility cases. Final `17-55` source replay passed **36 DVP/P9/evidence
tests**, with the unchanged P8 sources retaining their earlier compatibility
evidence. Each compiled controlled fixture is reused for response error,
clear recovery, pending control, paired errors, native reset and rearm cases.
The formal register-shell prove/cover and both clock-domain inventories pass.
The formal/DVP register sources are unchanged since the passing `17-15` proof.
C format/policy/host tests, RTL format/style/readiness, Ruff and diff checks
pass; no additional MISRA deviation or warning-baseline update was made.

Both final Tiny profiles build firmware without C warnings. The final ICS55
full-SoC Verilator executable was also compiled into a fresh variant. Its
`prepared-build.json` was captured before outputs existed; the build identity
binds unchanged **1808 input hashes** to the resulting ELF, HEX and simulator.
`validate_run()` verifies those artifact bytes, the matching build-source and
configuration records, and the executable/firmware launch arguments. Negative
tests reject existing outputs, changed inputs, stale artifacts and wrong
launches. A build identity alone is not a passing simulation result.

Final evidence:
`build/ics55-tiny-2026-10-15-17-55-9a44f7871af5/meta/tiny-r2-p9/review-fixes/`.
The final IHP130 build is
`build/ihp130-tiny-2026-10-15-17-55-064cd640790c/meta/tiny-r2-p9/`.
Earlier combined tests and negative logs are under the corresponding ICS55
`17-15` variant's `meta/tiny-r2-p9/review-fixes/`; formal reports are under
`build/ihp130-2026-10-15-17-15-c30fb9412aa3/formal/dvp/`.
The final source digest is
`728ed683fcc027929c479d2302f24ffdd642912d51f752bc5ff2c8097d2e2404`.
Filesystem clock-skew and existing EDA warnings remain observations.

No new full-firmware simulation, broad PR/nightly/Pytest, synthesis, netlist,
STA or physical flow was run in this handoff. Full QVGA/VGA/YUV422, VGA counter
width, service-budget and complete product-transition coverage remain open;
the long Icarus firmware gate stays deferred. The earlier 120-second startup
diagnostic remains historical TIMEOUT evidence. Human P9 acceptance and P10
advancement are not implied by these scoped fixes.

### P9 START/ABORT ordering correction (2026-10-15, uncommitted worktree)

The approved correction retains the `39ae718` source baseline and fixes the
reviewed START/ABORT race in the shared DVP. An accepted ABORT retires older
unsent register-side configuration requests. The command CDC now carries
the last issued configuration epoch; a pixel-domain cancellation record
prevents that configuration from rearming the core if it applies after ABORT.
The normal config acknowledgement still completes. A subsequent different
applied config epoch retires the record before epoch reuse, and commands do
not wait for an active frame's blocked config. Later writes and the existing
acknowledged disable/enable recovery remain usable. The external DVP V2 ABI,
512-byte FIFO, Mini transport binding and Tiny DMA2/request11/IRQ15/RCU14 are
unchanged. No C implementation, dependency, warning baseline or metric policy
was changed by this correction; no new MISRA deviation was introduced.

Two pre-fix Icarus attempts reproduced `stale START resumed after ABORT`:
`before.json` covers an unsent START behind W1C and repeated ABORTs;
`before-single.json` covers an already issued START and one ABORT. Each raw
Icarus invocation returned zero with a Fatal marker; the Pytest verdict was
correctly failed. Both source snapshots, converted images and logs are retained.

After correction, the focused command passed **36 tests**. The existing
controlled binary was reused for three new scenarios in each simulator:
`abort_order`, `abort_active`, and `abort_applied`. They cover stopped-high/low
PIXCLK, pending and in-flight START, repeated/coalesced commands, the delayed
config application, active capture with a blocked config, and a later START
queued after ABORT. Existing DMA tail/late-response, error notification,
lifecycle, rearm and actual XPI/PSRAM cases also passed. These are behavioral
fixtures, not complete Tiny firmware or physical evidence.

The first quality command stopped at fixture formatting. The final quality
command passed RTL format/style/readiness and the Tiny/Mini C host tests;
Ruff passed. Only whitespace in `tiny_r2_p9_dma_tb.sv` changed after the passing
test run. `format-equivalence.json` binds the identical token sequence and
verifies all other tested input hashes are unchanged; the old test source
snapshot is retained instead of relabeling its binary. The shared register
formal prove/cover passed, including cancellation of pending config under
arbitrary config readiness. This is a register-shell proof, not complete CDC
formal qualification. Both Tiny PDK PR/nightly dry-runs passed; they still
select P7 firmware and cannot establish P9 acceptance.

The two Tiny firmware/Verilator builds use fresh variants and prepared input
records; their completion and artifact hashes are recorded separately in each
variant's `build.json` and `build-identity.json`. A compiled simulator is not a
passing full firmware simulation. The retained executable hashes and versions
identify the tools actually used. The strict R2-P1 cached-archive installation
audit was unavailable because `RETROSOC_DEVELOPMENT_CACHE` is unset; that audit
is not claimed, and no tool installation or version was changed.

Evidence roots:

- `build/ics55-tiny-2026-10-15-19-15-9a44f7871af5/meta/tiny-r2-p9/abort-order/`
- `build/ihp130-tiny-2026-10-15-19-15-064cd640790c/meta/tiny-r2-p9/abort-order/`
- Register formal: `build/ihp130-2026-10-15-19-15-c30fb9412aa3/formal/dvp/`

The final build input map contains 1750 entries, digest
`2bf849e9868ea0e7e24fbaedc7207db8bd6f5df13b3128b8ad797d37287921b1`.
It uses the existing P8 source collector for both PDKs; formal inputs and
documentation are recorded separately. It is a new evidence set, not a
replacement for the earlier 1808-entry collector or its historical claims.
Full firmware simulation, broad Pytest/PR/nightly execution, synthesis/mapping,
netlist, STA and physical flows remain unrun in this scoped correction.
QVGA/VGA/YUV422, VGA counter width, service budgets and full product mode
transitions remain open. Long full-firmware Icarus remains deferred to final
Tiny qualification; neither P9 human acceptance nor P10 advancement is implied.

### P9 retained-binary QVGA replay (2026-10-15, timed out)

The approved validation-only handoff reused the reviewed ICS55 SAFE24 build
`ics55-tiny-2026-10-15-19-15-9a44f7871af5` without recompilation or RTL/HAL/test
changes. Its `APP=ci_smoke TINY_P9_ACCEPTANCE=YES` image requests one 320x240
RGB565 frame through DMA2/request11 into NSS1 PSRAM at `0x54010000`, complete
153600-byte readback/guards, and a subsequent 7x3 odd-width PIO check. The
retained HEX SHA-256 is
`615f08b42cf9490b0574edddc8f9e15d4e171de8e9dd3694060ce7280e8c09a1`.
The build/source/runtime identities were checked before execution; the
1750-entry input map and 296 runtime inputs remained unchanged afterward.

Exactly one ICS55 attempt ran from **2026-10-15 19:44:56 to 21:44:56 CST**
(`11:44:56..13:44:56 UTC`). The command exited **124** at **7200.012 seconds**;
`result-sim.json` records a terminal failed result and
`child_cleanup_pending=false`. `acceptance.json` classifies the attempt as
**timeout**, with null measurements and `phase_accepted=false`. There was no
automatic retry or extension. The independently prepared IHP130 image was
**NOT_RUN** because ICS55 strict acceptance was the prerequisite. Both profile
PR dry-runs passed; their P7 matrix is not P9 firmware acceptance.

The immutable launch command is in the attempt's `result-sim.json`. It uses
`timeout --foreground --kill-after=30s 7200s`, `stdbuf -oL -eL`, the retained
Verilator executable and HEX, `+max_cycles=40000000`, `+tiny_p8_psram`,
`+tiny_p9_camera`, and `+tiny_p9_half_ns=500`. It does not enable
`+tiny_p9_progress`, which also enables a second UART character observer.
The 1 MHz camera input is a candidate digital model rate, not qualification.

The complete 164-byte simulation log contains model initialization,
`P9_STAGE CAMERA_PINS_START`, and `P9_STAGE CAMERA_PIN pin=15`. Approximately
32-, 64-, and 94-minute external checks retained that same last stage.
There is no `CAMERA_PINS_DONE`, PSRAM-init, frame/PIO/observation record or
`SIM_TEST_PASS`/`SIM_TEST_FAIL` terminal marker. The strict checker rejected
the missing success records and unsuccessful command; absence of a forbidden
error string does not make a timed-out command pass. No frame size, throughput,
FIFO high-water or hardware timing measurement is claimed from this attempt.

Read-only diagnosis confirms that the last marker is emitted inside
`rs_p9_camera_pins()` after the GPIO15 call. `rs_gpio_configure()` performs
ordinary register accesses without a software polling loop; the GPIO register
shell's APB response is not qualified by PIXCLK, and the camera GPIO12-23
assignment does not replace UART0 GPIO8/9. These checks do not establish the
root cause or the exact stopped instruction. Without current PC/bus/cycle
samples, the final UART write response, later GPIO accesses, CPU/fabric state
and simulation progress cannot be distinguished. A deterministic hardware
deadlock or regression in the START/ABORT correction is not established by
this one attempt. A separately approved focused progress diagnostic is needed;
repeating the full two-hour acceptance run is not the next step.

Evidence:
`build/ics55-tiny-2026-10-15-19-15-9a44f7871af5/meta/tiny-r2-p9/qvga-replay/attempt-01/`.
It retains launch/source/library identity, raw log, command and marker verdicts,
before/after inputs, interval snapshots and the final diagnosis. IHP130's
conditional NOT_RUN record is under the matching `19-15-064cd640790c` variant's
`meta/tiny-r2-p9/qvga-replay/`. Existing focused/formal evidence is unchanged.
Strict tool-install archive audit, full QVGA success, VGA counter width,
YUV422, service budgets, product transitions, synthesis/netlist, STA and
physical qualification remain open. Full long Icarus remains deferred; no P9
acceptance or P10 advancement is authorized by this failed replay.

### P9 passive GPIO/UART diagnostic preparation (2026-10-15, build blocked)

The approved diagnostic plan adds only an opt-in `+tiny_p9_diag` observer to
`rtl/tiny/dv/tiny_p9_observers.svh`. It writes a separate trace without enabling
the legacy duplicate UART character observer. It records native-domain CPU
address/response counts, GPIO/UART APB requests and responses, clock/reset and
CDC state, slow-path state and UART FIFO/drain signals. It observes the accepted
UART line for GPIO15, then ends after 100000 REF cycles; the independent
diagnostic cap is 5000000 cycles. These are diagnostic endpoints, not firmware
acceptance markers. No RTL/HAL functionality, public ABI, profile, dependency,
warning baseline or metrics policy was changed.

The fresh diagnostic variant is
`build/ics55-tiny-2026-10-15-22-04-9a44f7871af5/`. Its prepared input identity
differs from the retained `19-15` build only in that observer. The original
ELF/HEX and generated filelists remain unchanged. RTL formatting, full owned
style/readiness and the Tiny/ICS55 PR dry-run passed. Verilator translated the
model and generated its C++ makefile, but the single build command exited 2
after 13.351 seconds during C++ precompiled-header compilation:

```text
ccache: error: Failed to create temporary file for /run/user/417800035/ccache-tmp/tmp.cpp_stdout.sRJsDx: Read-only file system
```

The direct compile-command replay omitted `CCACHE_DIR` and `CCACHE_TEMPDIR`
normally exported by `rtl/tiny/Makefile`; both were unset. This is the confirmed
build-launch failure, not an established defect in the observed SoC. The
generated C++ sources are retained, but there is no diagnostic executable or
simulation attempt. In accordance with the approved stop-on-failure/no-retry
instruction, the command was not retried and the 900-second diagnostic was
**NOT_RUN**. IHP130, full QVGA acceptance and all broader gates remain unrun.

Evidence is under the new variant's
`meta/tiny-r2-p9/gpio-diagnostic/attempt-01/`: `prepared-model.json`, source
snapshot, quality/dry-run results, failed `compile.json`/`compile.log`, and
`build-diagnosis.json`. The concrete recovery is to restore the repository's
existing ccache environment and resume the generated C++ makefile in place;
it does not require another Verilator translation or firmware build. That
continuation needs explicit authorization under this handoff's stop condition.
The original QVGA timeout root cause remains unknown. The new observer has
not yet been exercised, and no P9 acceptance or P10 advancement is implied.

### P9 UART initialization root-cause diagnostic (2026-10-15)

The maintainer authorized continuation after the ccache failure. Restoring
the existing `CCACHE_DIR` and `CCACHE_TEMPDIR` values from `rtl/tiny/Makefile`
allowed the generated C++ makefile to finish in 82.963 seconds with exit 0.
`cpp-resume.json` retains that command and its environment identity separately
from the original failed `compile.json`. Verilator translation and firmware
compilation were not repeated. Prepared source, generated C++, retained ELF/HEX
and runtime inputs matched before the continuation; the final simulator and
runtime-library hashes are bound in `model-identity.json`.

Exactly one ICS55 SAFE24 diagnostic ran from 22:29:54 to 22:36:16 CST
(`14:29:54..14:36:16 UTC`). It exited 0 after 382.716 seconds, ending at REF
cycle **2085487**, exactly **100000 cycles** after the GPIO15 UART marker at
**1985487**. The wall limit was 900 seconds, the diagnostic cap 5000000 cycles
and the outer guard 6000000 cycles. `P9_DIAG_END reason=post_pin15` means the
diagnostic window was collected; it is not `SIM_TEST_PASS` or P9 acceptance.
There was no simulation retry, IHP130 run or full QVGA replay.

The trace localizes the original apparent GPIO stall to missing UART
initialization in the P9 acceptance application:

- `tiny_r2_p9.c:162` disables interrupts and calls `rs_p9_camera_pins()` without
  first initializing UART. That helper immediately calls `printf`.
  `_premain_init()` only initializes IRQ tables and enables counters; the
  retained ELF has no linked `rs_uart_init`/`rs_uart_configure` symbol.
- At REF cycle 2000000 the TX FIFO is full: 64 pushes, zero pops, count 64,
  TX enable 0, config-valid 0, baud integer/fraction 0 and TX busy 0. The same
  condition remains in all nine snapshots through cycle 2080000.
- CPU fetch completion addresses `0x30000e64` and `0x30000e74` map to the
  retained ELF's `rs_uart_write()` TX_FULL polling loop. There are **3097**
  completed SYS-side reads of UART STATUS `0x10001018` returning `0x1060`
  without an APB error. CPU, GPIO and UART clocks continue, resets are released,
  gates/disabled masks are zero and clock/peripheral blocking is clear.
- Both GPIO APB endpoints complete all 232 observed-count transactions. The
  last GPIO request is the successful write of `0x00080000` to OE_CLEAR
  `0x1001401c`, completing GPIO19 configuration. GPIO16 is not the stalled
  transaction; the software is printing the next pin-group progress line.

The first two complete stage lines consume 54 bytes. The next ten bytes,
`P9_STAGE C`, fill the 64-byte FIFO. The Verilator UART model prints accepted
FIFO writes even while TX is disabled; those characters are not evidence of
serial-wire transmission. In the original line-buffered timeout run the last
complete line was therefore GPIO15. Normal diagnostic `$finish` flushes the
partial next line, which appears before `P9_DIAG_END` in the console log.
The HAL wait is bounded, not an infinite hardware deadlock: `rs_uart_write()`
polls up to `RS_TIMEOUT_DEFAULT`, and `putch()` discards the timeout result,
so each later printf character can incur another full polling budget.

The source-bound report is
`build/ics55-tiny-2026-10-15-22-04-9a44f7871af5/meta/tiny-r2-p9/gpio-diagnostic/attempt-01/diagnosis.json`.
It retains the trace, 208 complete snapshot groups, counter/clock consistency
checks, run/build identities, ELF disassembly and source evidence. The minimum
follow-up is a checked UART initialization before the first P9 printf, with
UART-init failure reported directly through SYSCTRL TEST_STATUS without
another printf. This is a P9 firmware acceptance-image defect; this diagnostic
does not authorize or implement that fix, change shared HAL/RTL behavior, or
implicate the START/ABORT correction.

This turn changed only this ledger and generated evidence/cache outputs.
No public interface, dependency version, warning/metrics policy or MISRA
deviation changed. The original two-hour timeout remains failed evidence;
QVGA success, VGA/YUV422, service budgets, mode transitions, IHP130 replay,
synthesis/netlist, STA and physical qualification remain open. Full long
Icarus stays deferred. P9 human acceptance and P10 advancement remain pending.

### P9 UART startup correction and focused replay (2026-10-16)

The approved application fix initializes UART before the first P9 diagnostic
print. `tiny_r2_p9.c` reads the RCU snapshot and passes its `pclk_hz` to the
existing `rs_uart_init()` at 921600 baud. A failed snapshot or UART setup writes
SYSCTRL `TEST_STATUS` failure code 4 directly and enters the terminal loop,
without calling `printf`. The internal `p9_startup.h` helper is tested with
success, zero-clock, callback failure and null-input cases. Shared UART/DVP/RCU
HALs and RTL were not changed; no MISRA deviation was added.

The ICS55 and IHP130 P9 firmware builds at
`build/*-tiny-2026-10-16-22-20-*` both completed successfully. Software
format/policy/Host tests, Ruff and the 36 P9 evidence tests passed. Existing
filesystem clock-skew warnings remain observations.

One ICS55 focused diagnostic reused the previously compiled passive-observer
model and loaded the new HEX. It ran for 410.539 seconds and ended after the
approved 100000-cycle post-GPIO15 window. `CAMERA_PINS_DONE` was emitted;
UART snapshots reported `enable=1`, `config_valid=1`, `baud_int=26`,
`baud_frac=11`, cumulative push/pop counts above 64 and 215 zero-count FIFO
samples. This confirms the UART startup correction and FIFO drain behavior.

The run then reached `PSRAM_INIT_START` and reported `PSRAM_INIT_FAIL` before
frame capture. It is therefore **not** P9 acceptance and does not justify an
IHP130 replay. The raw runner record conservatively marked the attempt failed
because it expected one exact `pushes=64 pops=64 count=0` sample; the retained
`assessment.json` applies the approved cumulative drain criterion and records
UART as passed while classifying the overall P9 workload as blocked at PSRAM
initialization. No automatic retry or full QVGA replay was started.

Evidence:
`build/ics55-tiny-2026-10-16-22-20-9a44f7871af5/meta/tiny-r2-p9/uart-startup/attempt-01/`.
The previous UART-root-cause diagnostic remains under the `22-04` variant and
is preserved as historical evidence. The next issue is the existing PSRAM
initialization path or its retained model interaction; it requires a separate
review/diagnostic. VGA/YUV422, service budgets, IHP130 simulation, full Icarus,
synthesis/netlist/STA and physical qualification remain open. P9 acceptance and
P10 advancement remain pending.

### P9 GPIO29 NSS1 correction and focused replay (2026-10-17)

The approved follow-up adds the missing PSRAM chip-select admission to the P9
acceptance image. Before camera setup and `rs_xpi_psram_initialize()`, the
application now configures GPIO29 as ALT0 with no pull, no trigger and a high
output default. The topology already binds GPIO29 ALT0 to `xpi.nss_o[1]` with
output enable asserted; the helper and the source-order/static binding test
keep the firmware admission aligned with that binding. A direct SYSCTRL
failure code 2 is used if the configuration callback fails, without printing
before the UART startup path is ready.

Both ICS55 and IHP130 P9 firmware builds completed successfully. The focused
P9 evidence suite now has 37 passing tests, including the UART/GPIO startup
host test and the GPIO29-before-PSRAM static binding check. Embedded-C format
and policy checks, the host C suite, Ruff and `git diff --check` pass. No shared
HAL/RTL, dependency, warning baseline or MISRA deviation changed in this
correction.

One ICS55 diagnostic reused the retained passive-observer model and loaded the
new firmware. It exited 0 because the diagnostic observer deliberately called
`$finish` after the bounded post-GPIO15 window; this is not the Tiny simulation
acceptance gate. The console reached `CAMERA_PINS_DONE` and
`PSRAM_INIT_START`, with no `PSRAM_INIT_DONE` or `PSRAM_INIT_FAIL` before the
observer ended. The trace records a successful GPIO29 OE_CLEAR write, released
clocks/resets and a healthy UART (`pushes=160`, `pops=160`, `count=0`, enabled
and configuration-valid). The last CPU slow-path sample was an XPI APB write at
`0x1000900c`, so the evidence proves entry into PSRAM initialization but does
not establish its completion or a PSRAM/model failure. The post-pin15 window
was insufficient to distinguish a long initialization sequence from a later
XPI transfer issue.

Source-bound evidence is under
`build/ics55-tiny-2026-10-17-00-10-9a44f7871af5/meta/tiny-r2-p9/gpio29-psram/attempt-01/`.
`assessment.json` binds the ICS55 manifest, firmware HEX, retained model,
command, console, trace and result hashes. The previous UART replay remains
historical under the `22-20` variant. IHP130 simulation, full QVGA acceptance,
Icarus, synthesis/mapping/netlist, observational STA, physical qualification
and broad regression remain unrun. P9 acceptance and P10 advancement remain
pending; the next diagnostic needs an XPI APB/transfer observer or a separately
approved longer bounded PSRAM-only window.

### P9 XPI/APB diagnostic (2026-10-17, stall attribution corrected)

The approved diagnostic added passive XPI-domain observations to the existing
P9 observer: APB request/response sequence, controller ownership, mapped and
indirect busy state, core busy/done/error, FIFO counts and error address/code.
The observer remains verification-only and leaves all design handshakes
untouched. Verible RTL formatting and the changed-only RTL style check pass.

One ICS55 run used the independently compiled observer model and the same
GPIO29-corrected firmware. It reached `CAMERA_PINS_DONE` and
`PSRAM_INIT_START`. During PSRAM initialization, all **164 XPI APB requests
and 164 responses** completed with `error=0`. At the final samples the XPI
controller was enabled and idle (`mm_busy=0`, `indirect_busy=0`,
`core_busy=0`, owner none, TX/RX FIFOs empty, no error event). This rules out
an APB response stall or an XPI core still being busy at the diagnostic end.

The CPU sample shows an in-flight instruction read at `0x30002a4c` in the
`rs_xpi_psram_validate_dma()` loop. The earlier interpretation that this
request was stuck is withdrawn: completion counters continue to increase,
and the longer-window replay below completes the validation. A single
`LocalWait` sample does not establish a persistent stall.
The final `P9_DIAG_SLOW` record still shows
the preceding XPI APB address only because it is the retained slow-path
request register; the XPI APB observer has no pending request. The run ended
at the observer's normal `post_pin15` `$finish`, so it is diagnostic evidence,
not Tiny acceptance and not proof of a PSRAM device failure. No SRAM, XPI or
application defect is established by this sample.

Evidence is under
`build/ics55-tiny-2026-10-17-00-10-9a44f7871af5/meta/tiny-r2-p9/xpi-diagnostic/attempt-01/`.
`assessment.json` records the model/source hashes, command, result and trace.
The simulation model was compiled before a subsequent mechanical Verible
format-only rewrite of the observer; the rewrite passed formatting/style
checks and did not change RTL behavior. IHP130, full QVGA, Icarus, synthesis,
netlist, STA, physical qualification and broad regression remain unrun. P9
acceptance and P10 advancement remain pending.

### P9 ICS55 local SRAM response diagnostic (2026-10-17)

The next scoped diagnostic added only passive signals for Tiny SRAM group 0:
instruction client request/grant, arbitration issue, outstanding read owner and
bank, bank-2 select/data, and the registered instruction response. The CPU
state is sampled alongside these signals. No SRAM, CPU or macro RTL was
modified.

One ICS55 run reached the same P9 boundary. The final sample at instruction
address `0x30002a4c` showed an in-flight local read (`pending=1`, owner 0,
bank 2) at the observer sampling edge, but this is right-censored evidence:
the preceding CPU samples continued to complete instruction fetches. These
are bus completion counts, not architectural instruction-retirement counts.
Between REF cycles
2190000 and 2220000, instruction requests/responses advanced by 3333, 3334
and 3333 respectively. The XPI controller remained idle with all 164 APB
responses complete and no error.

The cause of the missing `PSRAM_INIT_DONE` marker is the bounded
diagnostic window, not a proven SRAM deadlock. `rs_xpi_psram_validate_dma()`
validates every four-beat burst in the 320x240 RGB565 frame. Each beat is four
bytes, so its loop executes `153600 / 16 = 9600` iterations. The earlier
38400-iteration/1.5-million-cycle estimate confused beats with bytes and is
withdrawn. The retained disassembly at
`0x30002a34..0x30002a64` is the loop body and increments the cursor by the
16-byte burst size (`a6 = a3 << 2`, with `a3=4` at the call site).
The 100000-cycle post-pin15
observer window ends while this deterministic validation loop is still
running. The SRAM sample must not be promoted to an SRAM RTL failure.

Evidence is under
`build/ics55-tiny-2026-10-17-00-10-9a44f7871af5/meta/tiny-r2-p9/sram-diagnostic/attempt-01/`.
`assessment.json` binds the current observer source, independent model,
firmware, command, console and trace. Verible RTL format/style checks pass.
The run is diagnostic-only and ended at the normal observer `$finish`; it is
not Tiny acceptance. IHP130, full QVGA, Icarus, synthesis, netlist, STA,
physical qualification and broad regression remain unrun. The longer bounded
ICS55 replay below retains the same firmware but recompiles the observer
model to support a longer stop window. No SRAM RTL fix is justified.

### P9 diagnostic-window root cause confirmed (2026-10-16 run timestamps)

The `long-diagnostic/attempt-01` replay uses the same HEX SHA-256
`232e7a7ca00df295b46c30388f62b165963d2832df071013cd36d8488109e369`.
Only verification observer stop configuration was extended with
`+tiny_p9_diag_long` (2000000 post-pin15 REF cycles). Production CPU, SRAM,
XPI, HAL and workload inputs were not changed during this diagnosis.
The model was rebuilt, so this is matched-firmware evidence, not a claim
that the earlier simulator executable was reused.

The trace records GPIO15 at REF 2129996, `PSRAM_INIT_START` at 2168195,
`PSRAM_INIT_DONE` at **2564848**, and `DMA_CAPTURE_START` at **2572839**.
The original window ended at 2229996, **334852 cycles before** the observed
completion marker. START to DONE spans 396653 cycles; this includes both
PSRAM initialization and DMA admission validation (and marker printing),
not a measurement of the validation function alone. The marker is after
both calls in the application's short-circuit condition, so its absence
previously obscured which operation was executing.

At the disputed SRAM sample, bank data `0x40ee8733` already matches the
retained ELF instruction at `0x30002a4c`; `pending=1` describes a macro read
already issued, while bank select need not remain asserted during response
registration. The group's `s_read_pending_q` supplies the next registered
response. Later fetch completions and the DONE marker disprove the prior
claim that this sample establishes a missing SRAM response.

The run exited 0 after 769.997 wall seconds at REF 4129996 due to the
diagnostic `$finish`. No `SIM_TEST_PASS Tiny` was observed; capture completion
and full P9 acceptance remain open. This finding resolves the short-window
startup diagnosis only, not the original pre-UART-fix timeout or downstream
DMA/capture behavior. Raw logs and original run results remain unchanged;
the earlier XPI/SRAM assessment interpretations are explicitly superseded.
Evidence: the same variant's `meta/tiny-r2-p9/long-diagnostic/attempt-01/`,
including `assessment.json`, `trace.log`, `console.log` and `result-sim.json`.

### P9 observer isolation and single full-workload attempt (2026-10-16)

The approved correction separates generic NSS1 population (`+tiny_psram`)
from the legacy P8 campaign (`+tiny_p8_psram`). P8's four-window, mapped-write
and absent-device terminal checks remain intact. Both population flags retain
the shared active-CS check. P9 documentation now uses the generic flag.
No production CPU/SRAM/XPI/DVP/DMA RTL, HAL, register ABI, PDK input,
dependency revision, warning baseline or MISRA deviation changed in this
correction; the earlier P9 worktree remains uncommitted on base `39ae718`.

The new `tiny_p9_monitor.svh`, included by the existing P9 observer, counts
camera VSYNC, DVP frame events, DMA2 confirmed bytes and remaining work,
XPI handshakes/errors and CPU bus completions. The report uses native-clock
samples with REF timestamps. It never calls `$finish` and cannot be combined
with the early-stop diagnostics or legacy UART progress observer. These
observations do not establish atomic cross-domain snapshots or physical rates.

Validation before the single full-SoC launch:

- 26 observer behavior cases passed in Icarus and Verilator, compiling each
  fixture once and reusing it. They covered P8 missing windows/writes,
  absent-device writes, generic and legacy CS violations, conflicting monitor
  modes and continued execution beyond 5000000 cycles. A separate static
  assertion failed because Verible wrapped a plusargs call; the assertion was
  made whitespace-insensitive and its focused rerun passed. The initial
  failure summary and per-case raw logs are retained.
- 52 P8 pin-level compatibility/P8-P9 evidence tests passed. RTL format/style/
  readiness, Ruff and dependency-lock validation passed. ICS55 PR/nightly
  dry-runs passed but still select P7 firmware, so they are not P9 execution.
- The new ICS55 firmware and Verilator model built successfully. The prepared
  build record binds 1426 unchanged input hashes to ELF/HEX/model artifacts,
  with a pre-build source archive. The HEX equals the earlier GPIO29-corrected
  HEX: `232e7a7ca00df295b46c30388f62b165963d2832df071013cd36d8488109e369`.
  Existing EDA and filesystem clock-skew warnings remain in the logs.

Exactly one ICS55 SAFE24 full-workload attempt ran with a 40000000-cycle /
10800-second cap, generic PSRAM, 1 MHz camera and non-terminating monitor.
It ended with **exit 1 after 1397.023 seconds**, not a timeout or diagnostic
early stop. It reached `PSRAM_INIT_DONE`, then firmware reported
`READBACK_FAIL word=0`, `P9_RESULT code=3` and `SIM_TEST_FAIL code=3`.

The final REF-7400000 progress sample records one frame started/completed,
38400 accepted and delivered words, DMA bytes_done=153600, remaining=0,
DMA/DVP errors=0, FIFO high-water=1 and backpressure=0. XPI counted 9602 AW/B
transactions and 153608 written bytes, consistent with 9600 four-beat payload
bursts and two guard writes. These counts do **not** prove payload contents.
Reaching the readback loop implies the preceding capture/pixel-count and both
guard checks passed. The later `guards=0` field reflects aggregate failure,
not an observed corrupted guard. Expected word0 is `0x02030001`; the actual
loaded word is not logged, so the mismatch's root cause is unresolved. No
PIO completion or full-frame readback pass is claimed, and no automatic retry
or speculative production fix was performed.

The run also exposed a monitor logging defect: stdout progress split a
character-stream UART `P9_FRAME` line. The final source writes monitor records
to a required `+tiny_p9_monitor_log=<file>` instead. Twelve focused monitor
cases passed after this correction, proving separate output, missing-path
rejection, conflicting-mode rejection and survival beyond the old cycle cap.
Final full-TB Verilator lint, RTL quality and Ruff checks passed. The final
observer suite then passed all **29 tests** after restricting the test
driver's monitor-log argument to monitor scenarios; `$test$plusargs` prefix
matching otherwise activates the monitor in unrelated fixture cases. This
post-run fix has its own source snapshot and has **not** been replayed in a
full firmware simulation. It does not relabel or repair the failed raw log.

Evidence root:
`build/ics55-tiny-2026-10-16-11-24-9a44f7871af5/meta/tiny-r2-p9/observer-isolation/`.
`campaign.py` retains the exact explicit profile/build/run commands;
`prepared-build.json`, `source/`, `build-identity.json` and `tool-identity.json`
record provenance. `attempt-01/` retains launch, console, structured exit,
bound result, assessment and readback diagnosis. `observer-tests/`,
`compatibility-tests/` and `monitor-fix-tests/` retain the short runs.
`monitor-final-source.json` identifies the separate-log correction's scope.
`final-observers.json` and `final-observer-source.json` bind the final short
suite and its source snapshot separately from the failed full-SoC executable.

The scoped observer correction is ready for review, but the P9 workload is
**failed** and human phase acceptance remains open. IHP130 firmware replay,
full long Icarus, full-repository Pytest/PR/nightly, current synthesis/netlist,
STA and physical qualification remain unrun in this correction. P10 is not
authorized. The next focused diagnosis must capture the first camera bytes,
DVP stream word, DMA destination write and XPI/CPU read value before assigning
the mismatch to a packing, sampling or storage boundary.

### P9 external camera/audio pad isolation (2026-10-16)

The approved P1 correction changes only the external P6 board drivers on
GPIO17 and GPIO15: they release to high impedance in `+tiny_p9_camera` mode.
The former otherwise supplies the audio reference; the latter otherwise
loops GPIO14 codec output back to GPIO15 input. P6's oscillator, delayed
startup/CPU independence check and stop/recovery logic remain unchanged.
The production GPIO mux cannot disconnect an external testbench driver, so
ALT1 selection alone did not prevent the old collision. The frozen camera/
audio exclusion contract now applies to both sides of the pads.

`tests/test_tiny_p9_pad_isolation.py` extracts the actual P6 startup and driver
statements, top-level camera assignments and generated pad/DVP routes into
`tiny_p9_pad_isolation_tb.sv`. It uses the production ICS55 pad wrapper and
DVP core. Icarus uses native ICS55 functional IO definitions; Verilator uses
the existing compatible functional IO model. The fixture bypasses the GPIO
register controller, CPU, full interconnect, DMA, XPI and PSRAM, so its result
is not full-system memory acceptance or physical pad qualification.

Retained results:

- Eight initial cases passed across Icarus/Verilator: delayed audio startup
  and loopback, 512 byte/audio-level combinations, all 64 words of a 16x8
  camera frame, and expected rejection of simultaneous legacy codec drivers.
  The positive first word is `0x02030001` in both simulators. The combined
  negative case reports expected byte `0x04` versus `0x0c` in Verilator and
  `0x0X` in Icarus, exposing D3 contamination by the codec loopback.
- Two additional audio-clock-only negative cases passed as tests by detecting
  the required failure. Reconnecting the legacy GPIO17 reference corrupts
  DVP word0 to `0x02230021` in Verilator and `0x02X300X1` in Icarus, versus
  `0x02030001`. These are deliberate fixture failures, not passing product
  runs. They demonstrate first-word corruption at the DVP input boundary;
  they do not reconstruct the actual CPU value missing from the prior
  full-SoC log.
- Five existing ICS55 GPIO/P6 I2S/pin-contract checks passed. RTL format,
  changed-only style, readiness, Ruff and diff checks passed. No embedded-C,
  public ABI, production RTL, dependency, warning baseline or metrics policy
  was modified; no MISRA deviation was introduced.
- A fresh explicit ICS55 SAFE24 P9 firmware/model build passed with 1426
  unchanged pre/post-build source hashes and archived inputs. The HEX equals
  the prior failed run's `232e7a7ca00df295b46c30388f62b165963d2832df071013cd36d8488109e369`.
  Existing clock-skew and EDA warnings remain in the logs. Build success
  alone is not a functional verdict for the new full-SoC model.

Evidence:
`build/ics55-tiny-2026-10-16-12-20-9a44f7871af5/meta/tiny-r2-p9/pad-isolation/`.
`focused.json`/`focused-tests/` retain the eight initial cases;
`clock-negative.json`/`clock-negative-tests/` retain the two added negatives;
`compatibility.json` retains the five existing checks. `build-campaign.py`
records the exact profile/build commands, while `prepared-build.json`,
`source/`, `tool-identity.json`, `build-identity.json` and `completion.json`
retain build provenance. The fixture and model sources were not modified
during the final full-model build.

As explicitly scoped, no full-SoC replay was launched. The previous
`observer-isolation/attempt-01` remains failed evidence; full QVGA payload
readback and subsequent PIO completion remain unverified after this fix.
IHP130 firmware replay, full Icarus, full-repository Pytest/PR/nightly,
synthesis/netlist, STA and physical qualification were not run. P9 human
acceptance and P10 advancement remain pending. If a later replay still
fails, collect the first camera bytes, pad/DVP words, correlated DMA AW/W
data and XPI/CPU read response in a separate bounded log before changing
production logic or expected payload values.

### P9 matched-firmware ICS55 replay after pad isolation (2026-10-16)

The maintainer authorized exactly one bounded validation-only replay of the
reviewed `12-20` build. Before launch, all 1426 current inputs and the retained
ELF/HEX/model hashes matched `pad-isolation/build-identity.json`; they remained
unchanged after execution. No compilation, production-source change, or
automatic retry occurred. The image is the same HEX used by the earlier
failed run; the model includes the camera/audio pad isolation and the
separate progress-log correction.

The explicit target is `configs/ci/ics55-tiny.mk`, TINY/ICS55, SAFE24,
`APP=ci_smoke`, `TINY_P9_ACCEPTANCE=YES`, full 320x240 RGB565 camera at a
500 ns pixel half-period. The retained `pad-isolation/replay.py` launches the
existing `sim/verilator/emu` and `sw/retrosoc_fw.hex` through `run_flow.py` with
`timeout --foreground --kill-after=30s 10800s`, `+max_cycles=40000000`,
`+tiny_psram +tiny_p9_camera +tiny_p9_half_ns=500 +tiny_p9_monitor`, and an
absolute `+tiny_p9_monitor_log` path. No diagnostic early-stop mode is enabled.
`replay-01/launch.json` retains the exact argv and build/source binding.

The replay **passed the specified workload** with exit 0 after **3460.503
wall seconds**, emitting `SIM_TEST_PASS Tiny cycles=18570772`. The normal
Tiny testbench observes SYSCTRL TEST_STATUS before emitting this marker;
`P9_RESULT code=0 frames=1 bytes=153600` is present. `check_simulation.py`
reports no missing marker or rejected error, and source-bound
`scripts/tiny_r2_p9.py::validate_run()` passes.

- The QVGA DMA2/request11 frame confirms all **153600 bytes**, complete
  payload readback and both guards. `DMA_CAPTURE_DONE` is present; the
  previously observed word0 mismatch does not recur in this matched image.
- The subsequent **7x3 PIO** crop confirms **42 valid bytes in 48 storage
  bytes**, complete readback, row padding and guards.
- The terminal observer records **38412 accepted/delivered words**, FIFO
  high-water **3 words** and maximum backpressure run **504 consumer-clock
  cycles**, at the tested 1 MHz camera clock. These are session observations
  including PIO, not a worst-case service bound, sustained FPS, or a physical
  sensor/IO-rate qualification.

Evidence directory:
`build/ics55-tiny-2026-10-16-12-20-9a44f7871af5/meta/tiny-r2-p9/pad-isolation/replay-01/`.
`console.log` retains intact UART verdict records, `progress.log` contains
separate periodic observations, and `result-sim.json`, `result-sim-check.json`,
`bound-result.json`, `launch.json` and `assessment.json` retain command,
source/configuration and artifact provenance. The prior failed
`observer-isolation/attempt-01` and all short diagnostic attempts remain
historical evidence with their original verdicts.

This closes the scoped ICS55 QVGA/PIO replay gate only. The broader P9
qualification matrix (including VGA/YUV422 and complete product-level
error/mode/recovery coverage), IHP130 replay, full long Icarus, broad
regression, synthesis/netlist, STA and physical qualification were not run
in this replay. No MISRA deviation, public-interface, dependency,
warning/metric-policy or operating-point change was made. Human P9 phase
acceptance and P10 advancement remain pending.

### P9 row-size and IO-constraint remediation (2026-10-17)

The maintainer approved the focused P9 remediation and selected reduced
validation: one RECOVERY and QVGA execution per PDK, current-RTL full-size
focused tests, and fresh synthesis/compact netlist checks with observational
STA. Full-SoC VGA keeps its original historical identity. Source remains
`39ae71887ca427c83d39ff663ec5f0d1aa19be1a` plus the uncommitted worktree;
the frozen Tiny specification and dependency lock remain unchanged.

Evidence starts at
`build/ics55-tiny-2026-10-17-09-35-ff4b5cef6eb5/meta/tiny-r2-p9/row-size-remediation/`.
`before/` retains the pre-change inputs. `counterexample-sources/` retains
the new test with the unfixed core, and `counterexample.json` records two
expected failures: both Icarus and Verilator report zero ERROR_STATUS for
4x2 configured geometry with 6+2 source pixels. The new RTL detects excess
pixels before counter wrap and short rows at HREF fall, independently of
crop selection, through the existing SIZE/error-event/cleanup contract.
It changes no register, FIFO size, DMA allocation or SDK interface.

The host HAL rejection/recovery check and nine LibreLane scenario tests
pass. The new `default`/`camera` IO profile keeps ordinary GPIO constraints
separate from camera input delays and uses separate output roots. These
tests are not physical-flow or board qualification. The original format
attribution is corrected below: Tiny's final newline was introduced in P9,
while the four other recorded differences predate P9. Only the scoped Tiny
Makefiles are formatted; unrelated files and policy remain untouched.

Corrected focused RTL passes 14 tests: both simulators execute all twelve
malformed-row/recovery cases, actual XPI integration, VGA statistics/readback
and the new legal 65535-pixel row. C format/policy/host tests, RTL format/style/
readiness, Ruff and the three selected PR dry-runs pass. Mini IHP130 firmware
also builds. The global Make formatter still reports the four pre-existing
differences; the scoped Tiny Makefiles no longer appear in that failure list.

The single full Pytest run records **1915 passed, 13 failed, 60 errors and
1 skipped** in 5016.09 seconds. Three failures expose P9 integration inventory
drift: the commercial product Make policy still lists six clock domains,
and its tests plus the older Tiny reset-inventory test expect the pre-DVP
domain/leaf counts. The canonical inventory and Tcl product overlay already
contain DVP. The remediation additionally synchronizes
`physical/commercial/config/products/tiny.mk`, `tests/test_commercial_flow.py`
and `tests/test_tiny_r2_p2.py`; it adds no new clock or timing exception and
does not run commercial EDA. The original three failures remain retained;
targeted post-correction results are recorded separately, not substituted
into the original full-suite report.
The complete commercial-flow/Tiny-P2 targeted replay passes 50 tests in
15.01 seconds after these inventory corrections.

The other ten failures and sixty fixture errors are publication-source
validation failures for the obsolete `rtl/mini/dv/model/ESP_PSRAM64H.sv`
path. `39ae718` already contains that reference in
`publications/datasheets/system-reference.json`, while the model is tracked
at `rtl/model/ESP_PSRAM64H.sv`. Publication files were not changed here. The
single skipped publication test reports missing optional `pypdf`. These
remain explicit repository/environment gaps, not passing global CI evidence.

The selected full-SoC and backend campaign has now completed. Every functional
run passes command status, the strict Tiny TEST_STATUS/terminal marker and
forbidden-error scanning, with unchanged frozen inputs through execution:

| PDK / workload | Variant suffix after `2026-10-17-09-35-` | Terminal cycles | Simulation seconds |
| --- | --- | ---: | ---: |
| ICS55 / RECOVERY | `bf63475ab984` | 3058688 | 563.588 |
| IHP130 / RECOVERY | `7da598c5c377` | 3058688 | 393.120 |
| ICS55 / QVGA_RGB565 | `9a44f7871af5` | 18601389 | 3362.665 |
| IHP130 / QVGA_RGB565 | `064cd640790c` | 18601389 | 2294.190 |

Each workload was built and run once per PDK. RECOVERY retains seven cases,
six validated frames/six IRQs, eight board controls and two audio sessions.
QVGA checks every one of the 153600 bytes and both guards, then the 7x3 PIO
crop. Both profiles report 38412 accepted/delivered words, high-water 4 and
308 PCLK cycles of longest backpressure. All four HEX files match their
corresponding `2026-10-16-23-24` images exactly; the normal-workload cycle counts
also match. Wall-time differences are simulator observations, not SoC speedup.
The original full-SoC VGA result remains historical; current focused VGA
checks do not relabel that old full-system run.

The new backend variants are
`ics55-tiny-2026-10-17-09-35-ff4b5cef6eb5` and
`ihp130-tiny-2026-10-17-09-35-8232fa11e7f3`. Each retains its stage commands,
results and immutable artifact identities in
`meta/tiny-r2-p9/row-size-remediation/backend/`. Both syntheses and structural
audits pass with 32 main SRAM and six private Crypto macros, plus one ICS55
PLL macro and no IHP130 PLL macro. The source remains SAFE24; these are not
physical operating-point qualifications.

| PDK | Synthesis seconds | Reported cells | Liberty-based top area | Netlist boot cycles | Netlist DVP cycles / simulation seconds |
| --- | ---: | ---: | ---: | ---: | --- |
| ICS55 | 2490.163 | 476025 | 2711078.944704 | 36449 | 177541 / 9433.690 |
| IHP130 | 2233.433 | 501337 | 14883493.669841 | 36069 | 175649 / 3747.858 |

The compact DVP check verifies all 64 words using the unchanged assembly
image. Each backend compiled its netlist simulator for boot once and reused
that same hashed executable for DVP. No synthesis or long simulation was
retried. Existing filesystem clock-skew warnings remain in the logs; all
outputs were created in fresh variants and source/artifact checks passed.

OpenSTA executes successfully but reports negative slack. All values below
are current post-synthesis observations in ns, not timing closure:

| PDK | Setup WNS | Setup TNS | Hold WNS | Hold TNS |
| --- | ---: | ---: | ---: | ---: |
| ICS55 | -163.87 | -6193132.50 | -0.31 | -45.71 |
| IHP130 | -284.47 | -11105854.00 | -0.49 | -141.45 |

ICS55 smoke coverage lists 42 inputs without input delay, 52 outputs without
output delay, 42 unclocked register/latch pins, five pins with multiple clocks
and 146 unconstrained endpoints. IHP130 lists 42/51 missing input/output
delays, five pins with multiple clocks and 89 unconstrained endpoints.
These reports consume the existing smoke SDC, not the new LibreLane IO
scenarios. Report limits and missing physical/board constraints remain explicit.

Standalone warning checks fail relative to the stored baselines: ICS55 has
523 RTL-lint and 20 Yosys new signatures; IHP130 has 471 RTL-lint, 13 Yosys
and one Icarus signature. These are new-to-baseline counts, not attribution
of every warning to this patch. OpenSTA warning checks pass. Both metric
checks retain `observe` policy. No warning baseline, dependency version or
quality policy was changed; no new MISRA deviation is introduced.

Exact long-run entrypoints and outcomes are retained in `frames-*/` and each
backend stage JSON. Both full-system workloads use `scripts/tiny_r2_p9.py run`
with timestamp `2026-10-17-09-35`, jobs 4, a 500 ns pixel half-period and the
approved RECOVERY 20000000-cycle/7200-second or QVGA 40000000-cycle/10800-second
limits. Backend synthesis uses `SIMU=IVERILOG SYNTH=YOSYS`, balanced mapping
and a 10800-second synthesis allowance. RTL lint selects `SIMU=VERILATOR
SYNTH=NONE` for its functional PDK models. Netlist consumers use
`SIMU=IVERILOG SYNTH=NONE`; DVP uses the profile defaults of 10800 seconds
(ICS55) and 7200 seconds (IHP130), with the unchanged 300000-cycle guard.

`closure.json` under the remediation evidence root independently validates
the retained functional logs, binaries, source identities, netlists and
matched previous HEX files, and indexes timing, warning and metric artifacts.
`format-scoped.json` confirms all three Makefiles touched by the remediation
pass the existing formatter. The original complete-Pytest report and the
four remaining global format failures are not relabeled as passing CI.
The verification-ledger completion text is a documentation-only update after
the frozen-source executions. P9 human acceptance remains pending; there is
no commit, push or automatic P10 advancement. Full long Icarus firmware,
broad PR/nightly execution, and physical/PVT/board/sensor qualification remain
unrun as described by the approved reduced campaign.

### P9 remaining-acceptance functional campaign (2026-10-16/17)

After review of the XPI correction, the maintainer authorized resuming the
remaining-acceptance plan. The source remains base `39ae718` plus the archived
worktree. This follow-up changes validation firmware, verification monitors,
focused tests and evidence checking; it does not redesign the reviewed XPI
patch or alter product RTL/ABI, dependency versions, warning/metric policy or
operating-point qualification. All full-system runs below use SAFE24 and a
500 ns camera pixel half-period.

The added service-budget case passes in Icarus and Verilator. It retains
480 input bytes without consumer service, checks all words after service and
source clock resume, then deliberately exceeds FIFO capacity and verifies
overflow/cleanup. The fixture reserves 16 bytes for source-word/packing and
observation skew, giving a nominal empty-FIFO admission limit of 496 us at
1 MHz. A fixture correction was necessary: at external clock pause, only
119 words had entered the FIFO and the 120th was still held in the source
output register. Reading it before another pixel edge returned the previous
FIFO word. The corrected test checks FIFO empty and verifies that held word
after resume; it does not weaken payload comparison or modify production
logic. Initial failures and the diagnostic `index=119`/held-word record remain.

Two full ICS55 RECOVERY development attempts also failed and are retained:

- `ics55-tiny-2026-10-16-22-51-bf63475ab984`: firmware received four matching
  audio loopback words, but the old P6 wire observer required its unrelated
  512-word incrementing pattern. An opt-in RECOVERY observer now verifies
  eight constant 16-bit wire samples per audio session; default P6 still
  checks all 512 incrementing samples. Extracted-observer tests verify both
  positive paths and deliberate corruption rejection in both simulators.
- `ics55-tiny-2026-10-16-23-08-bf63475ab984`: the first DMA frame completed
  correctly, but the draft firmware registered external IRQ id 15 instead
  of the generated DVP external id 13. SoC vector bit 15 maps through the
  CPU's `[31:2]` slice; external id 15 belongs to WS2812. The application now
  uses `RS_SOC_EXT_IRQ_DVP`, with a generated-map/wrapper binding regression.
  The actual interrupt requirement remains one handler invocation per frame.

Neither failure was a newly demonstrated product RTL defect. Each retry
followed a concrete verification/application correction and used a fresh
variant. No failure artifact was overwritten or promoted to PASS.

The final functional runs all pass command status, SYSCTRL TEST_STATUS,
strict Tiny terminal marker, forbidden-marker scanning and source/build/run
identity checks:

| Profile / workload | Build variant | Terminal cycles | Wall seconds |
| --- | --- | ---: | ---: |
| ICS55 Tiny / RECOVERY | `ics55-tiny-2026-10-16-23-24-bf63475ab984` | 3058688 | 569.889 |
| IHP130 Tiny / RECOVERY | `ihp130-tiny-2026-10-16-23-24-7da598c5c377` | 3058688 | 397.719 |
| ICS55 Tiny / QVGA_RGB565 | `ics55-tiny-2026-10-16-23-24-9a44f7871af5` | 18601389 | 3463.139 |
| IHP130 Tiny / QVGA_RGB565 | `ihp130-tiny-2026-10-16-23-24-064cd640790c` | 18601389 | 2331.387 |

Each variant retains its records under `meta/tiny-r2-p9/full-frame/`.
RECOVERY reports seven successful cases, six validated captures and six DVP
IRQs, two stopped-clock reset rejections (`RS_ETIMEOUT`, fault bit 1), eight
board controls and two independently decoded audio wire sessions. Captures
include repeated RGB565/YUV422 DMA, a nonzero-origin crop, PSRAM and small
SRAM destinations, complete data/guard checks, and capture after each reset
and audio/camera roundtrip. Audio verifies a finite loopback prefix, then
explicitly disables/flushes the remaining queued tail before pin handoff;
it is not a full P6 audio-workload replay.

RECOVERY intentionally aborts two source frames. Its old cumulative
`P9_OBSERVATION` counters report 416 accepted versus 288 delivered words;
the 128-word difference belongs to discarded sessions. The cumulative
high-water value of 129 is **not current FIFO occupancy** across flush/reset
and is not used as service-budget or successful-frame acceptance evidence.
The dedicated RECOVERY parser instead requires all case/frame/IRQ/board and
stopped-clock diagnostic records.

QVGA verifies all 153600 DMA bytes and both guards, 38400 words/76800 pixels,
zero XPI error, then a 7x3 PIO crop with 42 valid/48 storage bytes. Each
session reports 38412 accepted/delivered words, high-water 4 words and longest
backpressure 308 PCLK cycles (12.833 us at 24 MHz). These are finite digital
model observations; they do not qualify arbitrary contention or physical FPS.
The same RECOVERY HEX is used across PDKs (`6b7f36b7...36b536a7`), as is the
QVGA HEX (`9557f6d2...8abb2a1c`); full digests remain in each build identity.

Focused evidence is under
`build/ics55-tiny-2026-10-16-22-40-9a44f7871af5/meta/tiny-r2-p9/acceptance/`.
The combined focused run initially had 84 passes and the two service-fixture
failures; corrected controlled runs pass in both simulators. Audio observer
and recovery parser checks pass 12 cases, and the generated IRQ binding case
passes. C format/policy/host tests, RTL format/style/readiness, Ruff, diff
checks and both Tiny PR dry-runs pass. No new MISRA deviation is introduced.
The retained `vga-reuse.json` documents the original VGA evidence identities
and the error-report-only/opt-in-control change impact; VGA was not rerun or
relabeled as a new-source result.

Exact full-system commands use `python3 scripts/tiny_r2_p9.py run`, explicit
`--pdk ICS55` or `--pdk IHP130`, `--timestamp 2026-10-16-23-24 --jobs 4
--pixel-half-ns 500`, and `--workload RECOVERY --max-cycles 20000000
--wall-timeout 7200` or `--workload QVGA_RGB565 --max-cycles 40000000
--wall-timeout 10800`. Each final selected workload runs once; the two QVGA
profiles ran independently in parallel. Failed RECOVERY attempts retain their
earlier timestamps and exact launch records.

Backend evidence uses `ihp130-tiny-2026-10-17-00-31-8232fa11e7f3` and
`ics55-tiny-2026-10-17-01-01-ff4b5cef6eb5`, both under `build/`. Each has
`meta/tiny-r2-p9/backend/` with the original source snapshot and synthesis
command. Both balanced syntheses and structural macro/domain audits pass:

| PDK | Synthesis wall seconds | Reported cells | Liberty-based top area | Main / Crypto / PLL macros |
| --- | ---: | ---: | ---: | --- |
| IHP130 | 2538.737 | 500331 | 14886954.637841 | 32 / 6 / 0 |
| ICS55 | 2767.803 | 477040 | 2710554.224704 | 32 / 6 / 1 |

Area is the Yosys `stat` top-design value, not a placed die/core measurement.
Both netlist boot checks also pass strict Tiny command/marker/error checks:
IHP130 uses 36069 cycles and 669.884 simulation seconds; ICS55 uses 36449
cycles and 1847.863 simulation seconds. Several execution corrections remain
explicitly attributed:

- The first IHP130 netlist elaboration failed because an opt-in legacy RTL
  progress block still referenced hierarchy removed by synthesis. The block
  now has a `RETROSOC_SOC__TINY_NETLIST` exclusion. The testbench is absent
  from both actual synthesis filelists, so neither synthesis was rerun.
- The first ICS55 netlist elaboration selected SRAM stubs and omitted the
  standard-cell/IO/PLL simulation models because this campaign's helper
  incorrectly carried `SYNTH=YOSYS` into `netcomp`. Using `SYNTH=NONE` for
  simulation selects the existing locked models. No PDK or product-source
  change was needed. The original missing-module errors remain retained.
- The original IHP130 compact DVP run hit its 1800-second host timeout
  (exit 124), without a terminal functional verdict. The **same HEX** passes
  in the retained IHP130 Verilator model in 177716 cycles, checking all 64
  words. This is a diagnostic runtime measurement, not netlist acceptance.
  `TINY_P9_NETLIST_WALL_TIMEOUT` initially defaulted to 7200 seconds; the
  300000-cycle guard and all payload checks are unchanged. ICS55 uses an
  explicit 10800 seconds because its measured boot model is slower. An early
  ICS55 7200-second attempt was deliberately terminated after this speed estimate
  became available; it is an interrupted attempt, not a DUT functional fail.

The broad source guards intentionally stopped helpers when the testbench or
timeout-only Make rule changed. The resumes retain separate consumer input
snapshots, immutable netlist/config/model/image hashes and the exact deltas;
they do not relabel either original synthesis as a fresh execution. Completed
continuations are `meta/tiny-r2-p9/backend-dvp-resume/` for IHP130 and
`meta/tiny-r2-p9/backend-dvp-budget-10800/` for ICS55. Their durable assessment
files retain the DVP, firmware, STA and warning/metric stage status and commands.

IHP130 has completed the continuation: compact DVP passes in 175649 cycles
(3167.831 stage seconds), followed by a passing ordinary `ci_smoke` firmware
build, STA execution and metric collection/check. The DVP log passes strict
Tiny terminal/error scanning, and the replay retains the original compact
image and compiled simulator hashes. OpenSTA reports setup WNS/TNS of
-280.11/-11170202.00 ns and hold WNS/TNS of -0.48/-120.41 ns. This is a
current post-synthesis observation, **not timing closure**. The smoke coverage
report lists 42 inputs without input delay, 51 outputs without output delay,
6 register/latch pins with multiple clocks and 89 unconstrained endpoints.
Its SYS/MEM/PCLK period is 41.67 ns; the DVP pixel constraint is 83.33 ns,
separate from the 1 MHz behavioral stimulus. Reported paths are bounded by
the existing report limits and are not an exhaustive violation census.

IHP130 `check-warnings` fails on 13 new-to-baseline Yosys signatures and one
Icarus signature (68 instances of unsupported edge-sensitive `ifnone`).
OpenSTA's warning check passes. These EDA deltas remain observations under
the existing regression policy; no baseline was edited. The metric policy
remains `observe`.

ICS55 also completes the continuation: compact DVP passes in 177541 cycles
(9847.549 stage seconds), followed by a passing ordinary `ci_smoke` firmware
build, STA execution and metric collection/check. Its setup WNS/TNS are
-162.61/-5895612.00 ns; hold WNS/TNS are -0.34/-46.23 ns. The coverage report
lists 42 inputs without input delay, 52 outputs without output delay,
42 unclocked register/latch pins, 5 register/latch pins with multiple clocks
and 146 unconstrained endpoints. These remain explicit smoke-constraint and
physical-qualification gaps, not timing closure. ICS55 `check-warnings`
fails on 20 new-to-baseline Yosys signatures, including PLL supply-pin
constant resolution and multi-output cell observations; Icarus and OpenSTA
warning checks pass. No warning baseline or metric policy changed.

The compact HEX is identical across PDKs:
`91abc81261ee978b86bca3b40de94f6d2f2dff38b0d46522f083ffe56b0b5d4e`.
After both continuations completed, the default host budget was aligned to
the **already executed** explicit parameters: ICS55 10800, IHP130 7200.
This changes only default selection in the new test target; the retained
executions already used these exact budgets. Per-PDK Make dry-runs verify the
final default commands, and a one-line source-delta check binds this final
Makefile change to the run snapshots. No additional simulation is needed to
validate that command-default correction.

`acceptance/closure.json` binds the functional results, synthesized netlists,
compiled models, macro audits, timing/metric reports and warning deltas to
their retained hashes. `acceptance/final-defaults/assessment.json` records
the subsequent default-only source delta and dry-runs. Later changes relative
to the passing RECOVERY/QVGA binaries are limited to the netlist-only TB
diagnostic guard, netlist host-time budget and runbook; those original binary
and source identities remain unchanged. The earlier VGA reuse rationale
also remains historical, with these additional changes outside its active
functional path. The scoped campaign is complete for review, not automatic
P9 human acceptance.

The additional Make-format check failed on formatter differences
in `Makefile`, `app/apps/ci_smoke/tiny.mk`, `rtl/mk/software.mk`,
`rtl/tiny/Makefile` and the unmodified `rtl/mini/mk/verilator.mk`. Copies from
before the timeout-rule change reproduce the differences; this comparison
does not establish that all differences predate P9. Review against `39ae718`
confirmed that Tiny's final newline was introduced in P9; the other four
files already had final newlines at the phase base. The row-size remediation
fixes the scoped Tiny difference and keeps unrelated debt separate.
`acceptance/format-attribution/` retains the original comparison.
No unrelated file was reformatted. Ruff, RTL format/style/
readiness and `git diff --check` pass. Full long Icarus firmware, the full
Pytest suite, broad repository regression and physical qualification remain
separate unrun gates. P9 human acceptance and P10 advancement remain pending;
no commit/push.

### P9 shared XPI error-report alignment correction (2026-10-16)

The maintainer approved the narrowly scoped shared-XPI preflight. The patch
changes `xpi_mm.sv` and `xpi_indirect.sv` only in their diagnostic metadata
outputs/assignments: while the existing error/timeout event is asserted, all
four fields bypass from the matching next-state bundle. Otherwise outputs
retain the existing registered values. No event delay, AXI response/FSM,
register offset/encoding, wrapper arbitration, first-error retention, W1C
priority, reset, dependency or warning/metric policy is changed. Mapped
pre-LUT/beat errors report PC zero; polling reports address zero and polling
budget expiry reports PC zero. Core errors retain their actual fault PC.

The final 32-bit directed fixture was run against archived **unfixed** RTL:
11 cases fail on metadata and the existing W1C-priority case passes. This
includes real mapped rejection, indirect and polling sequence errors,
poll-transfer/poll-interval timeout and mapped core errors. Thus indirect
and polling failures are now reproduced, not only inferred from source.
Initial development attempts had incorrect polling offsets and a default
64-bit AXI test interface; those logs remain diagnostic history. The valid
before/after comparison is `baseline32.json` versus `final-source-tests.json`.

On the final corrected source, **36 tests pass** (12 cases each for Tiny
Icarus, Tiny Verilator and Mini's Verilator wrapper with its native backend).
They check code/address/slot/PC, enabled IRQ causes, sticky first-error hold
across a second cause, W1C/rearm, exact simultaneous W1C/event priority,
normal transfer/reset, malformed WLAST/WSTRB, held B response, and core
sequence/timeout errors. The fixture drives real APB/AXI/LUT operations with
deterministic external serial input and does not force DUT state.

The original P9 XPI-protection regression passes in **both simulators**:
`ERROR_STATE=0x80000003`, address `0x54000c00`, INFO `0x13` (slot 1, PC 0),
AXI-error interrupt set, DMA error with zero confirmed bytes, unchanged PSRAM
guards/payload, subsequent mapped readback and source PIO recovery. Another
**16 existing tests pass** for pin-level PSRAM boundaries/lanes/timeout/held
reads/short reads/late errors, PHY pads and the fast-flash model. Those two
regression groups ran before an identifier-only style correction; the final
36-case suite and builds cover the final name. Mini wrapper coverage uses
the native branch; the fast-flash model is checked separately, not a full
Mini fast-boot acceptance run.

Final RTL format/style/readiness, Ruff and diff checks pass. A local signal
was renamed to `s_err_report` following the style gate; no baseline was edited.
Tiny ICS55 and IHP130 `APP=ci_smoke` firmware builds and RTL lint pass, and
Mini IHP130 firmware builds. Source inputs remain unchanged through each
build; ELF/HEX/manifest hashes and source snapshots are retained. Existing
EDA/clock-skew warnings remain, with no new C compiler warning observed.
No embedded-C API or MISRA deviation changed.

Exact focused commands (run through the retained result/log wrapper):

```sh
python3 -m pytest -q tests/test_xpi_error_report.py
python3 -m pytest -q tests/test_tiny_r2_p9.py -k 'dvp_dma_drain and xpi'
python3 -m pytest -q tests/test_tiny_r2_p8.py tests/test_xpi_io.py tests/test_xpi_fast_flash.py
make rtl-format-check rtl-style-check rtl-readiness-check
ruff check .
git diff --check
```

Builds used `BUILD_TIMESTAMP=2026-10-16-22-33 JOBS=4 APP=ci_smoke
SIMU=VERILATOR`, explicit SOC/PDK, and the following profiles/targets:

| Profile | Targets | Build variant |
| --- | --- | --- |
| `configs/ci/ics55-tiny.mk` | `firmware rtl-lint` | `ics55-tiny-2026-10-16-22-33-ff4b5cef6eb5` |
| `configs/ci/ihp130-tiny.mk` | `firmware rtl-lint` | `ihp130-tiny-2026-10-16-22-33-8232fa11e7f3` |
| `configs/ci/ihp130.mk` | `firmware` | `ihp130-2026-10-16-22-33-a2f660e37f72` |

Evidence root:
`build/ics55-tiny-2026-10-16-22-21-9a44f7871af5/meta/tiny-r2-p9/xpi-error-alignment/`.
`before-source/`, `baseline32/`, `final-source-tests/`, `p9-tests/` and
`compatibility-tests/` preserve the source/log distinctions. `build-validation.py`
and each `tiny-ics55/`, `tiny-ihp130/`, `mini-ihp130/` directory retain exact
build commands/results and identities. This root groups focused host-driven
tests; its name does not turn behavioral tests into ICS55 physical evidence.

The diagnosed XPI metadata blocker is corrected and ready for review.
RECOVERY/QVGA/VGA full-system campaigns, full Mini simulation, full-repository
Pytest/PR/nightly, synthesis/netlist, STA and physical qualification were not
run in this scoped correction. Existing VGA PASS records remain bound to
their original RTL and are not relabeled as runs of this shared-XPI patch.
Draft recovery/netlist work is preserved; subsequent P9 gates require their
own source-bound execution. P9 human acceptance and P10 advancement remain
pending; no commit or push was performed.

### P9 remaining-acceptance checkpoint: XPI diagnostic blocker (2026-10-16)

The approved remaining-acceptance plan was started on base `39ae718` plus
the existing worktree. No production RTL or HAL was changed. The directed
DVP fixture now drives actual overflow, missing-line size errors, odd-byte
partial rows, overlapping HREF/VSYNC, invalid format, recovery payloads and
repeated YUV crops at a nonzero origin. The first recovery test wrote CTRL
before the asynchronous ABORT completed and correctly received an APB error;
the fixture was corrected to wait for native abort completion and FIFO drain,
matching the existing HAL. Both simulators then passed the controlled cases.

The combined focused suite passed **86 tests** in 104.31 seconds before the
new XPI-protection scenario was added. C format/policy/host tests, RTL
format/style/readiness, Ruff and diff checks passed. Both Tiny PR definitions
were dry-run. The compact `app/asm/tiny_p9_netlist.S` assembles successfully
after adding the generated topology include directory to its build rule;
that is assembly-build evidence only, not netlist simulation.

Draft validation additions include the explicit RECOVERY application,
opt-in external board controls (UART-command observation changes only camera
model clock and camera/audio population), strict seven-case result parsing,
and the compact `netsim-dvp` target. RECOVERY intends to exercise real IRQ15,
repeated DMA/crop, rejection, SRAM capture, stopped-high/low reset rejection
and audio/camera roundtrip. Its firmware build and full-system behavior have
**not** been validated. No completed recovery or netlist gate is claimed.

The next focused gate failed deterministically in both Verilator and Icarus:
after initializing real NSS1 PSRAM, the test disables mapped writes through
the public XPI slot configuration and sends production DVP/DMA2 traffic to
`0x54000c00`. DMA reports error without DONE and with zero confirmed bytes.
The APB diagnostic reads `ERROR_STATE=0x80000000` and the first-error address
assertion fails. Icarus exits zero on its Fatal, but the forbidden-marker
scan rejects it; Verilator exits nonzero. Neither run is a pass. The checks
after the failing address assertion, including guard/recovery readback,
remain unexecuted in this new scenario.

The root cause is an event/metadata cycle mismatch in shared production XPI:
`xpi_mm.sv` raises combinational `axi_error_event_o` while assigning the new
code/address/slot to `_d`. Its metadata outputs still expose `_q`.
`apb4_xpi.sv` forwards the current event with those old fields, and
`xpi_reg.sv` latches them as the sticky first-error record on that edge.
The observed valid bit with code NONE matches this ordering. Error IRQ
classification also uses the old code and is therefore at risk; that IRQ
consequence has not yet been separately measured. The indirect/poll engine
contains the same output/event pattern and needs review, not an inferred
claim that every path was reproduced. This is a shared Tiny/Mini diagnostic
defect, not a regression introduced by these verification additions.

Evidence root:
`build/ics55-tiny-2026-10-16-22-00-9a44f7871af5/meta/tiny-r2-p9/acceptance/`.
`fault-tests*` retains the original fixture failure and corrected controlled
run; `focused.json`/`focused.log` retain the earlier 86-test pass;
`xpi-protection.json`/`xpi-protection.log` and `xpi-protection-tests/` retain
the two failures. `checkpoint.json` and `post-failure-source.json` retain
this partial status and a post-failure source archive, explicitly not a
pre-build provenance claim. The initial direct Pytest invocation lacked its
basetemp parent and executed no tests; the recorded run_flow invocation
created the evidence parent before running the actual tests.

Per the approved stop-on-failure boundary, RECOVERY/QVGA full-system runs,
synthesis/mapping, netlist boot/DVP checks and STA were not started. The
remaining service-budget/boundary coverage is also incomplete. Existing VGA
and prior focused results retain their original identities; new verification
controls are not retroactively included in them. A separately approved shared
XPI fix and focused tests are required before resuming dependent gates.
No dependency/warning/metrics policy, MISRA deviation, commit or phase
acceptance change was made; P9 remains incomplete and P10 is not advanced.

### P9 campaign existing-output protection correction (2026-10-16)

The scoped P2 review correction moves the campaign's existing ELF/HEX/model
and evidence-directory checks before directory creation, evidence writes or
`generate_filelist manifest`. Previously a built variant without a full-frame
evidence directory could have its manifest/filelists rewritten before
`prepare_build()` rejected its outputs. Rejection now returns nonzero without
writing into that variant. Dangling output/evidence symlinks are also treated
as occupied paths. The existing pre-compilation check remains in place.

The evidence/tooling suite passed **54 tests** in 0.93 seconds. Twelve added
runner-level cases cover both ICS55 and IHP130: each existing ELF, HEX or
simulator, existing evidence, a dangling ELF symlink, and a fresh variant.
Rejection tests retain exact file bytes, file/directory modification times
and directory contents, and allow only the read-only configuration query.
The positive orchestration test executes one mocked generation/build/run/check
sequence. These are Python tests with fake external tools, not new firmware
builds or simulator acceptance. The exact validation command was:

```sh
python3 -m pytest -q tests/test_tiny_r2_p9_evidence.py --basetemp=build/ics55-tiny-2026-10-16-21-34-7be4ff496b65/meta/tiny-r2-p9/runner-guard/pytest
```

The retained `tests.log` and `tests.json` are under that same `runner-guard/`
root. Ruff and `git diff --check` also pass. This follow-up changes only
`scripts/tiny_r2_p9.py`, its evidence tests and this ledger; no profile,
public interface, firmware, RTL, dependency, policy or MISRA deviation changed.

Both earlier `14-23` full-frame evidence directories remain unmodified:
the build/log and ELF/HEX/model hashes still match their recorded identities.
Their input maps differ from the current worktree only in the runner and its
tests. Keep those PASS results bound to their archived source dictionaries;
do not rewrite them as runs of the corrected runner. No long simulation,
firmware build, full-repository Pytest, broad regression, synthesis/netlist,
STA or physical flow was rerun for this scoped tooling correction. Existing
P9 acceptance gaps and human phase acceptance remain unchanged.

### P9 VGA/YUV422 full-frame campaign (2026-10-16)

The maintainer approved the scoped full-frame preflight and its implementation.
This record covers base `39ae71887ca427c83d39ff663ec5f0d1aa19be1a` plus the
archived uncommitted inputs, not the committed P8 tree. The application adds
`TINY_P9_WORKLOAD=VGA_YUV422` with a distinct configuration digest; the default
QVGA_RGB565 and quick paths retain their existing selection. A private frame
helper supplies checked geometry and deterministic payload expectations.
The evidence parser now binds format/dimensions/counts to that selection and
rejects incompatible camera arguments, quick substitution, missing statistics,
old artifacts or failed commands. The one-shot campaign entrypoint reuses the
existing build, snapshot and durable run-result helpers. No production RTL,
HAL ABI, CDC/reset, FIFO, DMA scheduling, dependency or warning/metric policy
was changed in this follow-up. No new MISRA deviation was introduced.

Focused validation passed **53 tests** in 77.43 seconds, including actual
DVP/DMA/XPI focused simulations, workload configuration identity and negative
evidence cases. C format/policy/host tests, Ruff and diff checks passed. Both
Tiny PR definitions were dry-run, not executed. Commands and observed results
are summarized in the ICS55 evidence root's `prelaunch-checks.json`; its raw
interactive quality output remains in the development-session transcript.

Both fresh full-SoC Verilator executions passed, **exactly once per PDK**, at
SAFE24 with a 500 ns pixel half-period. Each captures a 640x480 YUV422 frame
through production DMA2/request11, XPI and NSS1 PSRAM at `0x54010000`, verifies
all 614400 bytes and both guards, then rearms for a 7x3 RGB565 PIO crop from
the VGA sensor geometry (42 valid bytes, 48 storage bytes, full readback and
guards). This proves the tested raw byte transport and format-change/rearm
sequence, not sensor color calibration or the entire recovery matrix.

| Target/profile | Exit and terminal verdict | Wall seconds | Source inputs |
| --- | --- | ---: | ---: |
| TINY / `configs/ci/ics55-tiny.mk` / ICS55 | 0; `SIM_TEST_PASS Tiny cycles=73938869` | 13703.038 | 1427 |
| TINY / `configs/ci/ihp130-tiny.mk` / IHP130 | 0; `SIM_TEST_PASS Tiny cycles=73938869` | 9291.077 | 1387 |

Both runs report `P9_RESULT code=0 frames=1 bytes=614400`, 153600 words,
307200 pixels and zero XPI error. The Tiny testbench emits its terminal
marker from SYSCTRL TEST_STATUS; the command checker and workload/source
validator both pass with no forbidden error marker. Input hashes remain
unchanged before/after build and run, and the retained artifacts match their
build identities. Both profiles use HEX SHA-256
`52e806373c30c03c6c5022ef928bb23b0689176dafde123ec09448e160f1db79`;
ELF and simulator hashes remain separately recorded. Existing EDA/clock-skew
warnings are retained; no new C compiler warning was observed.

Each session observes 153612 accepted/delivered FIFO words including PIO,
high-water 4 words and longest backpressure 489 PCLK cycles (20.375 us at
24 MHz). These finite model observations are not worst-case service bounds,
continuous FPS, physical timing or a qualified sensor/PSRAM operating rate.

Exact invocations, each with `--jobs 4 --pixel-half-ns 500
--max-cycles 160000000 --wall-timeout 43200`, were:

```sh
python3 scripts/tiny_r2_p9.py run --pdk ICS55 --workload VGA_YUV422 --timestamp 2026-10-16-14-23 --jobs 4 --pixel-half-ns 500 --max-cycles 160000000 --wall-timeout 43200
python3 scripts/tiny_r2_p9.py run --pdk IHP130 --workload VGA_YUV422 --timestamp 2026-10-16-14-23 --jobs 4 --pixel-half-ns 500 --max-cycles 160000000 --wall-timeout 43200
```

Evidence roots:

- `build/ics55-tiny-2026-10-16-14-23-7be4ff496b65/meta/tiny-r2-p9/full-frame/`
- `build/ihp130-tiny-2026-10-16-14-23-28a0c226bed5/meta/tiny-r2-p9/full-frame/`

Each retains source archives, tool executable identities, prepared/build
identities, exact launch arguments, console and separate progress logs,
terminal command/check results, bound results and `assessment.json`.
Tool executable hashes were checked; a new downloaded-tool archive audit
was not performed. No retry or three-sample repetition occurred.

This closes the scoped VGA/YUV422 plus subsequent PIO workload for both
profiles. Current-source QVGA full-system replay, the remaining product-level
error/mode/recovery matrix, full-repository Pytest and broad regression,
current synthesis/mapping/netlist-function checks, observational STA and
physical qualification were not run in this campaign. Full long Icarus stays
deferred to final Tiny qualification. Historical QVGA and earlier focused
evidence retain their original identities. **P9 human acceptance and P10
advancement remain pending.**

### P9 full-width word statistics correction (2026-10-16)

The approved correction expands the shared DVP pixel-domain word counter
from 16 to 32 bits and the completed-frame statistics mailbox from 128 to
144 bits. The packet is `{drop[31:0], words[31:0], pixels[31:0], lines[15:0],
frames[31:0]}`. Core output, both CDC-side vectors, the existing Common
`cdc_2phase` instance and register unpacking now preserve all fields. The
separate 128-bit configuration path, handshake/reset behavior, V2 software
register map, 512-byte payload FIFO, Tiny/Mini DMA bindings and strict HAL
completion comparisons remain unchanged. This fixes the previously
documented 153600-to-22528 VGA word-count truncation.

Validation uses a new CPU-less `dvp_stats_tb` with real pixel traffic through
the shared DVP wrapper, FIFO, statistics CDC and APB. No DUT counter is forced
or preloaded. Each backend compiles once and reuses the binary for boundary
cases. Both Icarus and Verilator pass all four cases:

| Geometry | Expected words | Coverage |
| --- | ---: | --- |
| 510x257 | 65535 | Original 16-bit limit |
| 512x256 | 65536 | First high bit; stopped/resumed host clock |
| 640x480 | 153600 | VGA count and payload, YUV422 mode, host-clock pause |
| 511x256 | 65536 | Odd-row halfword/tkeep padding count path |

All stream payload words and sidebands are checked against an independent
scoreboard. APB verifies frame/line/pixel/word/drop/error statistics, retention
of the preceding completed frame during active capture, and a subsequent
4x2 frame with count reset to four words. These **8 tests passed** in 218.602
wall seconds in total; they do not instantiate the CPU, DMA, XPI or PSRAM.
The VGA/YUV422 result is therefore a focused statistics/stream result, not
the full external-framebuffer qualification.

The real Tiny and Mini HAL host tests accept a complete VGA count and reject
the deliberately truncated count with `RS_EIO`, without weakening production
HAL checks. The affected DVP/P9/pad regression passes **48 tests**. Shared
register-shell formal prove and cover pass, including arbitrary nonzero
high statistics fields, coherent update/hold, zero-extended line count and
the existing event/configuration properties. This is not whole-CDC/RDC
formal signoff. C format/policy, RTL format/style/readiness, Ruff and diff
checks pass. No dependency, warning/metric policy or MISRA deviation changed.

Fresh P9 firmware/Verilator models build successfully for both
`configs/ci/ics55-tiny.mk` and `configs/ci/ihp130-tiny.mk`, each with
`SOC=TINY APP=ci_smoke TINY_P9_ACCEPTANCE=YES SIMU=VERILATOR`, SAFE24 and
`BUILD_TIMESTAMP=2026-10-16-13-50`. The prepared-build records retain 1430
ICS55 and 1390 IHP130 unchanged input hashes respectively, archived sources
and ELF/HEX/model hashes. Both builds retain existing EDA/clock-skew warnings.
No full-SoC executable was launched, and the prior passing QVGA run is not
relabeled as a pass for these new RTL inputs.

Evidence roots:

- `build/ics55-tiny-2026-10-16-13-50-9a44f7871af5/meta/tiny-r2-p9/word-count/`
  retains `stats.json`, per-case logs in `stats-tests/`, `host.json`,
  `regressions.json`, `quality.json`, source/build identities and `summary.json`.
  `build-campaign.py` records exact build commands for both PDKs.
- `build/ihp130-tiny-2026-10-16-13-50-064cd640790c/meta/tiny-r2-p9/word-count/`
  retains the separate IHP130 source/build identity and results.
- `build/ihp130-2026-10-16-13-50-c30fb9412aa3/formal/dvp/`
  retains the Mini-profile shared register-shell prove/cover reports; the
  exact `formal-dvp` command is also recorded in the ICS55 evidence root's
  `formal.json`. It is not a Mini full-product simulation.

Full VGA/YUV422 PSRAM capture/readback, current full-system replay and the
remaining P9 product-level error/mode/recovery matrix are still open.
Full long Icarus, broad repository regression, synthesis/netlist, STA and
physical qualification were not run. The scoped counter/statistics fix is
ready for review; human P9 acceptance and P10 advancement remain pending.

## TINY-R2-P8 P1 correction follow-up (2026-10-15)

The review identified two evidence-blocking issues and both were corrected.
`rs_xpi_psram_validate_dma()` now checks every emitted burst against the
configured 1 KiB serial boundary, the 4 KiB DMA page boundary, capacity and
alignment before a session starts. The P8 workload begins at
`0x54000c00`, an aligned legal boundary; aligned crossing and malformed cases
remain rejected by host tests and the XPI directed tests. The MEM observer now
maps AW/W/AR/B/R stall counters to the correct output fields and records the
maximum observed CS duration.

After the correction, the P8 focused suite and C/RTL checks passed again. A
fresh ICS55 Verilator replay passed SAFE24/PLL192/PLL240 with
`P8_RESULT code=0 profiles=3` and `SIM_TEST_PASS Tiny`; a fresh IHP130 SAFE24
replay passed with `P8_RESULT code=0 profiles=1` and `SIM_TEST_PASS Tiny`.
Evidence is retained below the corresponding `build/*-08-00-*/meta/tiny-r2-p8`
directories. These are behavioral/model results only. Full long Icarus remains
deferred to final Tiny qualification. Both profiles also have current
synthesis, netlist boot and observational STA records; source-bound promoted
reports are retained under each profile's promoted evidence directory. Human
P8 acceptance remains open.

## TINY-R2-P7 source-reset integration contract (2026-10-14)

The follow-up review identified a missing source-side reset proof, not a
reproduced product failure. The AXI bridge does not support arbitrarily
resetting an active source while leaving its slave session alive. Flushing
the FIFO cannot cancel a request already accepted by that slave. Production
Tiny prevents that sequence: DMA local reset requires engine, admission and
fabric drain before resetting the source; XPI's SYS source reset is a common
system reset that also resets its MEM endpoint. Neither production bridge
uses warm clear. These preconditions are part of the integration contract,
not a claim of unrestricted unilateral-reset support by the standalone bridge.

`tests/rtl/tiny_p7_source_reset_tb.sv` uses the production DMA master,
admission, CDC, lifecycle controller and reset tree. The test extracts the
actual top-level instances, drain/block synchronizers and generated DMA/XPI
reset bindings, so a hand-copied reset policy cannot silently replace them.
An independent outstanding scoreboard survives local reset and rejects
premature reset. The AXI target is a controllable behavioral slave; unrelated
CPU/APB/SDIO work and the DMA completion mailbox are idle. This is a focused
integration test, not a full-SoC firmware or formal CDC/RDC signoff result.

The scenarios cover stalled AR/AW, partial W, downstream W backpressure,
delayed R/B, source-held R, drain timeout without reset, post-reset reads and
writes, and common system reset during an outstanding read. The same binary
is reused at SAFE24, XIN48, XIN96, PLL192 and PLL240 domain ratios. They test
digital ordering only; the clock generators do not qualify a PLL or PDK rate.
A negative run falsifies both idle observations and must trip
`P7_SOURCE_RESET_UNDRAINED`; Icarus may return zero for sv2v's lowered fatal,
so the forbidden marker and missing PASS still make that simulation invalid.

Evidence for this correction is retained under
`build/ics55-tiny-2026-10-14-06-00-ff4b5cef6eb5/meta/tiny-r2-p7-source-reset/`.
The first focused attempt's test-driver failure is retained in `focused-1.log`;
it is not a DUT failure or acceptance result. The final `directed.log` and
`result-directed.json` record **54 passed in 191.71 seconds**. This includes
ten positive source-reset runs (five ratios in each simulator) and two
expected-negative broken-drain runs inside the two new Pytest cases.
RTL format/style, clock/reset inventory, Ruff, both Tiny PDK PR dry-runs and
`git diff --check` pass. The verification-only source comparison is retained
in `verification-update.json`: only the two test files differ; 1728 other
technical inputs and tool identities match. The design,
firmware, configuration, dependencies and physical inputs are unchanged from
the `06-00` source snapshot; the new tests do not relabel earlier simulations
as new executions. Full Icarus firmware remains deferred to final Tiny
qualification. Human P7 acceptance is still required.

## TINY-R2-P7 response conservation correction (2026-10-14)

The earlier review recommendation to give abort unconditional priority over
source response retirement was incorrect. A cycle with an already exposed
normal B/R handshake followed by an abort produced two completions for one
request. Four read/write tests reproduced this in Verilator and Icarus. The
failed candidate, diagnostics and source archive are retained below
`build/ics55-tiny-2026-10-14-04-00-ff4b5cef6eb5/meta/tiny-r2-p7-response/`.
The `04-00` synthesis/netlist/STA results belong to that rejected candidate;
their successful boot does not close the protocol finding.

The corrected bridge holds presented responses in source-owned registers.
Remote reset cannot revoke VALID or rewrite their payload under backpressure,
and a completed source handshake is never followed by a second completion.
Only missing read beats receive DECERR, with RLAST at the original burst end;
a reset write consumes the remaining W beats before emitting B. Outstanding
tracking is one transaction per direction, matching the existing Tiny paths.
The payload reset uses the five-edge source link barrier. An unfinished warm
clear quarantines the bridge until a real destination reset; a FIFO clear
cannot by itself cancel remote slave state or authorize re-use of late replies.
Production DMA/XPI clear inputs remain tied low; no new software reset API,
autonomous AXI timeout, DMA owner, or later-phase capability is introduced.

The new tests distinguish completed/held responses from missing responses,
cover simultaneous clear and response handshakes, remote reset with READY high,
backpressure, partial bursts and late-response quarantine. That campaign's
full directed selection passed 52 cases. Earlier 36-case and rejected-
candidate passes did not cover these failures and are not proof of the repair.
The failed same-cycle candidate and diagnostics remain in the response
evidence directory.
The final input snapshot is
`build/ics55-tiny-2026-10-14-06-00-ff4b5cef6eb5/meta/tiny-r2-p7-response/final/source-final.json`.
The `06-00` backend campaign is bound to the final source snapshot and all
requested post-fix gates pass. Its variants are
`build/ics55-tiny-2026-10-14-06-00-ff4b5cef6eb5/` and
`build/ihp130-tiny-2026-10-14-06-00-8232fa11e7f3/`. ICS55
synthesis/netlist/STA durations are `2108.388/1655.980/43.594 s`, with WNS
max/min `-152.03/-0.31 ns` and TNS max/min `-5622052.50/-44.14`; IHP130
durations are `1934.515/578.869/47.109 s`, with WNS max/min
`-253.43/-0.49 ns` and TNS max/min `-10035324.00/-153.37`. Netlist boot
emitted `SIM_TEST_PASS Tiny netlist boot` for both PDKs. These timing values
remain observational and do not qualify closure or an operating point.
Full Icarus firmware remains deferred by the maintainer to final Tiny
qualification. It is not a current P7 gate; protocol correctness and human
phase acceptance remain required.

## TINY-R2-P7 final verification campaign (2026-10-13)

The [P7 runbook](tiny-soc-r2-clock-reset.md) records the current implementation,
exact profile-specific commands, workload definitions and source snapshot.
The integrated design now drives actual SYS/MEM/PCLK consumers, CPU-only WFI
gating, local reset barriers, CLKOUT and the single ICS55 PLL backend. It keeps
the 32 main SRAM macros at CPU SYS and six private Crypto macros at PCLK.
Future target capabilities remain absent. No later phase is authorized here.

Development validation includes 68 passing Tiny P7/SYSCTRL/P5 directed tests
and a later complete 52-case P7 directed pass,
plus both simulators' real Hazard3 IRQ/debug wake, clock-pause and retained-debug
warm-reset/aborted-command cases. RCU validation now rejects invalid or BUSY
staging writes with PSLVERR, and the CLKOUT waveform test exposed and corrected
enable/divisor ordering. HAL tests cover invalid, absent, busy, gated-reset and
sticky-timeout/error boundaries. These short checks complement the final long
flows; they do not replace full firmware or netlist acceptance.

Source evidence is retained at
`build/ics55-tiny-2026-10-13-17-05-f3e42d54c18b/meta/tiny-r2-p7/source.json`.
The final command matrix and its retained corrections are listed in the runbook.
Default ICS55/IHP130 and external XIN48/96 P7 firmware pass in both simulators.
Each profile's cycle count and WFI/DMA/reset observations match across simulators.
Both watchdog-corrected full Verilator firmware runs pass the unchanged P6
peripheral/wire/AXI collector and JTAG. The two corresponding full Icarus
replays were intentionally interrupted with exit 130 after the maintainer
requested that this long-running gate move to the final Tiny phase; their
partial logs and interrupted result records are retained, but they are not
acceptance evidence.
Both PDKs pass synthesis, structural macro binding and Tiny netlist boot.
Current core STA remains observational and negative, with the coverage limits
explicit in the runbook. These are historical campaign results; current phase
acceptance requires the response correction above and human review. The full
Icarus firmware gate belongs to final Tiny qualification. No high-rate physical operating point is
qualified by these functional simulations or SAFE24 core STA.

## Historical TINY-R2-P7 CDC/reset correction follow-up (2026-10-14)

This checkpoint predates the response-conservation correction and is
superseded by the `06-00` campaign above. It is not current-source acceptance.
The P7 review identified two source-bound gaps. The XPI fabric target and bridge source side release with
the SYS reset endpoint, while the XPI/MEM side retains its MEM leaf reset. The
Tiny AXI CDC bridge synchronizes destination reset loss, invalidates its
protected request/response state and blocks new source admissions. Its original
single-DECERR completion claim was insufficient for held responses and bursts;
the later response-conservation correction supersedes that claim. The existing DMA/XPI
instances retain their explicit bridge boundaries and the XPI bridge now uses
the split SYS/MEM reset mapping.

The new `tests/rtl/tiny_axi4_async_bridge_tb.sv` passes under both Verilator
and Icarus for normal read response, reset-aborted read/write, DECERR,
no-replay and bridge recovery. The complete
`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q tests/test_tiny_r2_p7.py`
selection eventually passed 52 tests after the later corrections; that count
does not belong to the `01-20` implementation. `make --silent rtl-format-check rtl-style-check-all`
and `git diff --check` pass. An ICS55 default-profile Verilator `comp` also
passes; its existing PDK and simulator warnings remain observations. The
checkpoint's synthesis, netlist boot and observational STA gates passed for
both PDKs. Its historical evidence is retained under
`build/ics55-tiny-2026-10-14-01-20-ff4b5cef6eb5/` and
`build/ihp130-tiny-2026-10-14-01-20-8232fa11e7f3/`. ICS55 reports WNS
max/min `-144.40/-0.31 ns` and TNS max/min `-4859636.50/-45.04`; IHP130
reports WNS max/min `-257.81/-0.47 ns` and TNS max/min `-9807803.00/-100.68`.
These remain observational negative timing results, not closure or operating
point qualification. The long-running full Icarus firmware gate remains
intentionally deferred to the final Tiny phase; no physical flow was run.

## Historical initial P7 checkpoint, superseded (2026-10-13)

The following incomplete checkpoint belongs to earlier development snapshots.
Its unconnected/missing-path statements do not describe the final campaign.

This checkpoint starts from committed source `43a3c8d453b6d41df3536719ebc6d1f4521bc7cd`,
specification blob `7e19de49d49efaafacccfa85671e314d53dd15a4`, Tiny/ICS55
profile `configs/ci/ics55-tiny.mk`, and the locked PWM revision
`38efaf5e20f084a00148920087c60cadab61839b`. The dependency lock validator
passes with digest `263402a34f2e315ca46ef4bf6366aab64935bd8de7abab3e469f513e988b0208`.

The implementation adds the Tiny-owned RCU register bank and handwritten
`rcu.h`/`rcu_regs.h`/`rcu.c` contract, reports SAFE24/domain-rate snapshots,
connects committed PCLK/SYS rate reporting to the upgraded PWM and SDIO
`CLOCK_ACTUAL` paths, and adds focused APB coverage for identity, capability,
profile rejection/commit, status and write-only command behavior. Verilator
and Icarus SYSCTRL focused tests pass; ICS55 Verilator and Icarus top-level
compilation, Tiny firmware linking, C format/policy/host tests and the SDIO
suite pass. Build logs are retained under the generated
`build/ics55-tiny-2026-10-13-09-00-f3e42d54c18b/` and
`build/ics55-tiny-2026-10-13-10-30-f3e42d54c18b/` roots.

A Tiny-owned `tiny_clock_reset_subsystem` backend is now source-bound and
filelisted. Its SAFE24/no-PLL focused test passes in both simulators and covers
five-stage SYS/MEM/PCLK reset release, external-profile handling and rejected
PLL requests. A second focused test exercises the behavioral PLL lock-timeout
path in both simulators; it does not claim successful macro lock or frequency
qualification. The backend is intentionally not advertised or wired into the
CPU/fabric yet; its SYSCTRL profile/apply handshake is now connected, while
the backend instance is now present in the Tiny top and its SYS output clocks
the CPU, fabric, SRAM, AXI interfaces and system reset tree. XPI now crosses
from SYS to the backend MEM clock through the Tiny-owned warm-flush AXI bridge.
The RCU command checks CPU/fabric/target idle observations and the XPI bridge
before accepting a transition. PCLK outputs are still not connected to all
peripheral consumers.

The focused command is
`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q tests/test_tiny_r2_p7.py`;
its four cases passed. Supporting gates were
`make --silent rtl-format-check rtl-style-check-all`,
`make --silent sw-format-check sw-policy-check sw-host-test`,
`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q tests/test_script_tools.py -k 'run_flow'`,
`ruff check scripts/run_flow.py tests/test_tiny_r2_p7.py`, and
`python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json`.
The current ICS55 top-level compile used
`source .cache/retrosoc/development/tiny-r2-p1/activate.sh && CCACHE_DISABLE=1 make --silent CONFIG=configs/ci/ics55-tiny.mk APP=ci_smoke SIMU=VERILATOR HAVE_SVA=YES BUILD_TIMESTAMP=2026-10-13-16-30 comp`
and exited zero. These are source/compile/focused checks; none is a strict
full firmware terminal verdict or physical qualification.

The long-run diagnostic also confirmed that the emulator itself exits normally
with a Tiny timeout at a bounded cycle count and uses about 26 MiB RSS. The
earlier `status=running` records lacked a verified terminal result. The initial
diagnosis attributed this to sandbox cleanup without sufficient evidence;
that conclusion is withdrawn. Separate tool invocations can have different
PID namespaces, so process absence in one does not establish that another
command died. `run_flow.py` now records `parent_pid` and `child_pid`
in the running result and writes a failed terminal result for unexpected
Python exceptions; long runs must remain attached to one polling session.

This is not phase acceptance. The current RTL now uses the backend SYS clock
for the system/fabric path, but does not yet provide the required executable
MEM/PCLK clock consumers, full CDC bridges, WFI leaf gating, PLL lock/loss
recovery, or target-local five-cycle reset sequences. A full Tiny Verilator firmware
run was started but did not produce a terminal `TEST_STATUS`/`SIM_TEST_PASS`
verdict and was stopped; no physical, STA or netlist qualification is claimed.
The remaining P7 clock/reset implementation and strict terminal regressions
require a follow-up correction before human phase approval.

## TINY-R2-P6 implementation complete, human review pending (2026-10-12)

The maintainer approved the P6 preflight on
`b3b30a72cd6ef5340c28e5044c96cd13258ec5a6`, against unchanged specification blob
`7e19de49d49efaafacccfa85671e314d53dd15a4`. The
[P6 runbook](tiny-soc-r2-shared-integration.md) records eight-channel/shared-IP
integration, the explicitly retained historical ASIC wrapper and publication,
and the separate source-bound validation scope. Development diagnostics are
not final acceptance; no P7 or physical-frequency qualification is implied.

Initial integration exposed a shared I2S sample-LSB assembly defect and a
Verilator packed-tri1 board-model limitation. The runbook records their narrow
corrections. Directed SDIO integration additionally exposed command admission,
transmit/receive pause and multi-burst descriptor-retirement defects, plus
manual card-model gaps; their independent reproductions are recorded there.
Both Tiny PDKs have complete Verilator and Icarus functional verdicts and
netlist boots. Yosys synthesis and OpenSTA run for both PDKs with the exact
32-main plus 6-private-Crypto macro bindings. The final audit is
`build/ics55-tiny-2026-10-12-11-50-2eb98c0e1fae/meta/tiny-r2-p6/audit-result-v3.json`;
the source-bound evidence is `evidence.json` in the same directory. The
functional report retains four simulator records, all workload/AXI/device
observations and the Mini compatibility result.

Observed setup/hold slack remains negative: ICS55 WNSmax/WNSmin −84.93/−0.31 ns
and IHP130 −165.41/−0.51 ns. Warning checks report new signatures from the
existing policy's observation flows; no baseline or metrics policy was edited.
The full Pytest attempt remains recorded as 1634 passed, one optional `pypdf`
skip, five failures and 60 fixture errors; all 65 failed/error nodes pass in
the explicit repair selection, and the affected consumer suite passes 512 with
one optional skip. These overlapping counts are not a clean full-suite rerun.
Final human review, complete-product timing closure, package/QFN64 binding and
physical signoff remain pending. Earlier P5 results and failed P6 attempts
retain their original attribution.

## TINY-R2-P5 P1 protocol correction; validated, review pending (2026-10-12)

The maintainer requested correction of the reset write-drain/read-retention
failures and publication-binding mismatch. The implementation starts from
`4e6ab1a6fb445521703f0bfa412d3a1e8a38cd69`; the specification remains blob
`7e19de49d49efaafacccfa85671e314d53dd15a4`. The [P5 runbook](tiny-soc-r2-concurrent-fabric.md)
describes preserved upstream spill responses, complete read/error bursts,
write drain before B, latched downstream cancellation and first-error capture.
Profiles remain Tiny/ICS55 SAFE24 with parked PLL and Tiny/IHP130 compatibility.

Current evidence is isolated under
`build/ics55-tiny-2026-10-11-23-35-b4aa59f3e5d9/meta/tiny-r2-p5-p1/`.
The older `09-30` campaign failed overall: 1669 Pytest passes, one skip,
two failures and ten errors (publication), plus independent R stability and
W-before-B violations. Its passing ordinary regressions, PPA and replay are
historical observations, not acceptance of the repair.

Final focused validation passes 101 tests. Full Pytest passes 1685 tests,
with one optional `pypdf` skip and no failures; these counts overlap. Both
Tiny PDK PR regressions pass, including six strict simulation verdicts,
synthesis, netlist boot and the 32-macro/common-SYS binding check. Each
simulator passes all 28 reset scenarios, including three production DMA
drain cases; normal-target, arbitrary-target-reset and fault-collector
induction/SAT checks pass. Complete terminal/fault publication bindings and
three unsafe-completion mutation tests pass without changing the reviewed
publication SHA. RTL format/style/readiness, Ruff and diff checks pass.

`source.json` and `evidence.json` bind 2011 technical inputs to digest
`f670789a2379a8d2e6c59f5ecd714ca0237bb6f1cfe749a2f29b0794d356b5f0`,
locked tools, exact command results and retained artifacts. No warning
baseline, metric policy, shared DMA/SDK implementation or public ABI changed.
The lint signatures/counts match the preceding `09-30` campaign; the existing
baseline comparison remains a non-blocking observation. STA remains unclosed:
max WNS is -70.04 ns ICS55 and -127.01 ns IHP130. The runbook records full
area/timing observations and limitations. Matched-image replay, full-function
C netlist qualification, PDF promotion and physical qualification were not
repeated for this bounded correctness repair. P5 human review/acceptance and
all P6+ work remain separate.

## TINY-R2-P5 target-reset isolation repair; focused validation (2026-10-11)

Superseded attempt: later protocol checks rejected its response flushing and
early B/RLAST behavior. The four focused passes below remain historically
accurate but were insufficient to establish reset isolation.

Following the P5 review, the fabric now receives the explicit 23-entry target
reset vector. A reset blocks new admission and downstream handshakes, flushes
response spill state, and converts any accepted target session into a held
DECERR terminal response. The existing owner credit is released only by the
upstream RLAST/B handshake, preventing stale response replay or a permanently
busy direction. No target map, public register, DMA capacity, clock profile or
later phase was changed.

The focused command
`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q tests/test_tiny_r2_p5.py -k 'target_reset_isolation or concurrent_fabric'` passed 4 tests: both
Icarus and Verilator reset-isolation tests and both existing concurrent-fabric
tests. `make rtl-format-check rtl-style-check-all rtl-readiness-check-all`
also passed. This is a focused implementation check; the prior P5 campaign
reports remain source-bound to their recorded snapshots and have not been
rewritten or relabeled. The retained focused logs are under
`build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/reset-repair-tests/`.

## TINY-R2-P5 implementation; validated, review pending (2026-10-10)

The maintainer approved the single-phase P5 plan on clean commit
`3131762b35e0ebfcd196395f955e7c1005bd18e7`, specification blob
`7e19de49d49efaafacccfa85671e314d53dd15a4`. The P4 input hashes match this
starting source, but earlier reports retain their original snapshot attribution.
The [P5 runbook](tiny-soc-r2-concurrent-fabric.md) records target-local ownership,
sixteen APB branches, reserved inactive SDIO owner 2, concurrent-fault accounting
and the unchanged public ABI/clock/memory boundaries.

The completed campaign is under
`build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/`;
the earlier `18-25` root retains development attempts. Full Pytest reports
1679 passed and one optional `pypdf` skip. Both Tiny PDK PR regressions pass,
including synthesis, netlist boot and clock/macro binding. The real CPU/DMA
fixture records 13 overlapping DMA read/write beat cycles, 27 independent control
completions, hart-reset isolation and abort drain on both simulators. Scoped
target-control/fault proofs and retained P4 latency/streaming checks pass.

Initial image executions passed but aggregation correctly failed on an Icarus 13
temporary-expression population-count defect. The only subsequent source change
is P5 opt-in testbench instrumentation. `source.json` retains the original
snapshot for the unchanged DUT/full-suite/ordinary-regression/PPA results;
`monitor-source.json` records the corrected monitor. Only affected image
measurements and monitor checks were repeated. `monitor-diagnosis.json` retains
the reproduction and original discrepancy; no comparison rule was relaxed.

Final `report.json` has identical banked observations across simulators. Against
repaired P4, burst1 cycles change 91306→65527 flat and 89365→65502 banked; burst16
changes 17897→16974 and 17317→15802. CPU/copy cycles are unchanged; small
contention/TCD/chunk256 increases remain explicit. The final combined input
digest is `0f3ed21f6fd6e932ff2532aab8c9964e71cf4b972e4c27e2c8ca6ab1f22c1015`.
`evidence.json` rechecks 2010 inputs and binds both snapshot scopes, six ordinary
simulations, final matched-image runs, 15 focused/formal artifacts and reused
unchanged Mini compatibility evidence. Library area grows 5.56%/6.95%; max WNS
is -64.75 ns ICS55 and -111.93 ns IHP130. Timing remains unclosed/observational.
The runbook records exact commands, source attribution, warning observations,
measurements and unrun qualifications. Human phase acceptance is pending.
Shared DMA/Mini/SDK behavior, dependencies and warning/metrics policy remain
unchanged. No P6 execution or physical-frequency qualification is authorized.

## TINY-R2-P4 throughput repair; validated, review pending (2026-10-10)

Following the read-only P4 review, the maintainer approved the bounded-buffer
repair plan for the P2 external-SRAM throughput regression. The changed Tiny
group/frontend keep local I/D single-operation semantics, reserve external
response capacity and overlap burst issuance/retirement; W is captured before
macro arbitration and B follows complete commit-response drain. Common FIFO
and register dependencies, ABI, clock/macro bindings and the pre-P5 external
attachment remain unchanged. No shared Mini debug code is changed by this fix.

Fresh evidence belongs under
`build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/`.
The preceding P4 report below remains the pre-repair comparison, and does not
qualify these new changes. The final audit rechecks 1972 technical inputs,
six fresh regression simulations and three immutable-image executions. Full
Pytest reports 1659 passed and one optional `pypdf` skip. Both Tiny PDK PR
regressions pass, including synthesis, netlist boot and clock/macro bindings.
Streaming/backpressure/error/reset checks and response conservation/fairness
induction pass; all six SRAM fixtures retain three-cycle local completion and
one-cycle steady read/write beat spacing. Initial style failures and focused
development attempts remain separate from final qualifying results.

Matched burst16 DMA cycles fall from 36713 to 17897 (flat) and 36489 to 17317
(banked), reductions of 51.25% and 52.54%. All banked observations match across
Verilator and Icarus. CPU/copy/burst1 cycles remain unchanged from pre-repair
P4; burst1 overhead and 8.34%/4.81% burst16 overhead versus original P3 remain
explicit. The combined input digest is
`58daf68fbb9dee199b3085a73ef07d22eb3de6d00ba875c462e85b76b6091a0d`.
`evidence.json` binds the source, artifacts, comparison and reused unchanged
Mini behavioral evidence. All long gates ran once; Tiny nightly matched PR
and was not duplicated. Setup WNS remains negative (-36.88 ns ICS55,
-97.37 ns IHP130), with warning/metrics observations and baselines preserved.
The [runbook](tiny-soc-r2-local-memory.md) records exact commands, measurements
and unrun qualifications. Human review remains required; no P5 execution or
physical-frequency qualification is implied.

## TINY-R2-P4 implementation and validation; review pending (2026-10-10)

The maintainer approved P4 preflight and implementation on clean source
`4db27524a6282ca40d76b935415b89f043d6ea83`, specification blob
`7e19de49d49efaafacccfa85671e314d53dd15a4`. The [P4 runbook](tiny-soc-r2-local-memory.md)
records architecture, lifecycle, physical binding and matched-image boundaries.
P3 results retain their original source attribution; no historical phase or
physical qualification is automatically promoted.

Development evidence is under
`build/ics55-tiny-2026-10-10-10-05-b4aa59f3e5d9/meta/tiny-r2-p4/`.
All planned functional gates completed: 1659 Pytest passes and one optional
`pypdf` skip; Tiny ICS55/IHP130 PR and Mini ICS55 behavioral compatibility pass.
Both Tiny netlists pass boot and the four-group/32-macro/common-SYS binding
checks. Local uncontended latency is three cycles; group-control induction
passes. Setup and hold timing remain negative and observational.

`report.json` retains single-execution matched-binary results; the banked image
matches exactly across Verilator and Icarus. CPU-copy cycles improve about
19%/25% for flat/banked images, while isolated burst-16 DMA cycles increase
about 2.2 times. This external-frontend throughput regression requires review;
no blanket speedup or automatic phase acceptance is claimed. `evidence.json`
rechecks 1972 source inputs and binds the gate, image, model, log and report
artifacts. Exact commands, measurements and unrun qualifications are in the runbook.

External fabric stays serialized until P5, which is not authorized. Default
Tiny stays ICS55 SAFE24 with PLL off; IHP130 is explicit compatibility.

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
| TINY-R2-P4 - Dual-Port Hazard3 and Four-Bank Local SRAM | Actual separate I/D paths, four independent 32 KiB bank frontends, SYS-clocked physical main-SRAM macros, local latency/fairness, FENCE.I, debug/reset and early inventory/SDC/macro-binding updates. | Implementation and planned functional validation complete on `4db2752` plus retained worktree snapshot; matched-image DMA throughput regression and human phase acceptance pending review; timing remains observational |
| TINY-R2-P5 - Per-Target Concurrent Fabric | Cross-target concurrency, one combined transaction per target, central-DMA read/write overlap, AW/W binding, errors, simultaneous faults/counters and accepted-transfer drain. | Pending |
| TINY-R2-P6 - Shared IP and Eight-Channel DMA Integration | Legacy P7 obligations; shared PWM reporting, I2S slave and alternate-input-route prerequisites; common ABI/HAL parity; Crypto banks/lifecycle; truthful capabilities and affected Mini compatibility. | Pending |
| TINY-R2-P7 - Tiny RCU and Dual-Mode Clock/Reset Integration | Legacy P8 obligations with main SRAM in SYS and XPI in MEM; atomic rate changes, all actual CDC/reset barriers, clock failures, WFI leaf gating and reserved DVP controls. | Human accepted 2026-10-15 at `655c587`; full long Icarus firmware and physical/timing gaps remain explicitly deferred |
| TINY-R2-P8 - XPI PSRAM Framebuffer Bring-up | Legacy P11 obligations: real pin-level NSS1 device transport, CPU/DMA mapped-write readback, boundaries/recovery, payload rate and worst backpressure. | ICS55/IHP130 Verilator, focused dual-simulator, synthesis, netlist boot, STA and promoted reports complete; full long Icarus deferred and human P8 acceptance pending |
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
