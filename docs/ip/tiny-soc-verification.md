# Tiny MCU Verification Record

This record accompanies the [Tiny Gen1 contract](tiny-soc.md). The active R2
verification plan below covers Target SoCs: `TINY`, feature `tiny-soc`, and
the approved performance refreeze. `R2` is a roadmap revision, not a new IP
or register ABI version. The selected executable baseline remains
`configs/ci/ihp130-tiny.mk`, IHP130, 24 MHz/no PLL; faster configurations and
their physical acceptance do not exist merely because this plan names them.

The R2 freeze changes documentation only. All R2 firmware, RTL/formal,
performance, synthesis/netlist, timing and physical results are **pending**.
Historical `TINY-P0` through `TINY-P12` identifiers and evidence are preserved
under their original scope; the mapping in the main contract transfers
outstanding obligations without renaming old results or declaring them passed.
Other PDK qualification, new SPI/PIO/BootROM IP and changes to QFN64 or the
frozen IO/power-pad budget are outside this refreeze.

The executed historical sections describe the 2026-09-25 initial baseline,
with two UARTs, two I2C controllers and the legacy pad mapping. The working
tree was uncommitted when that evidence was collected and its readiness
remains `prototype`. Those results do not validate the later package,
shared-IP/clock/reset, DVP/framebuffer or R2 performance refreezes.

## R2 pending phase acceptance

The following is the active monotonically increasing sequence. Every phase
uses the preceding accepted R2 contract and its declared prerequisites; the
old P10 -> P7 execution order below is historical. Documentation approval is
not implementation acceptance. Final physical qualification is R2-P11 work,
not a prerequisite to the architectural improvements in R2-P3 through R2-P5.

| Active phase | Required evidence and completion boundary | Status |
| --- | --- | --- |
| TINY-R2-P0 - Performance Contract and Roadmap Freeze | Reviewable requirements, exact old/new phase mapping, invariant package/IO counts, same-frequency CPU/main-SRAM ownership, explicit performance budgets, links and commands. Record actual documentation checks separately. | Documentation freeze only; no hardware result |
| TINY-R2-P1 - Reproducible Baseline, Constraints and Measurements | Reviewed source/profile/lock/tool identity; current 24 MHz functional and workload baseline; clocks, reset endpoints, constraints and timing-exception audit; counters and comparison methodology. Historical WNS is a risk reference, not a refreshed measurement. | Pending |
| TINY-R2-P2 - Reset Distribution and CPU/SRAM Clock Feasibility | Reset distribution and payload-reset semantics; locked IHP130 main-SRAM macro timing, candidate common CPU/SRAM periods and representative paths; early clock/reset feasibility with explicit gaps. No final routed/PVT pass is implied. | Pending |
| TINY-R2-P3 - Software and DMA Scheduling | Compiler and placement A/B results, finite DMA ownership, burst/chunk scheduling, WS2812 refill budget and workload correctness on the available platform. | Pending |
| TINY-R2-P4 - Dual-Port Hazard3 and Four-Bank Local SRAM | Actual separate I/D paths, four independent 32 KiB bank frontends, SYS-clocked physical main-SRAM macros, local latency/fairness, FENCE.I, debug/reset and early inventory/SDC/macro-binding updates. | Pending |
| TINY-R2-P5 - Per-Target Concurrent Fabric | Cross-target concurrency, one combined transaction per target, central-DMA read/write overlap, AW/W binding, errors, simultaneous faults/counters and accepted-transfer drain. | Pending |
| TINY-R2-P6 - Shared IP and Eight-Channel DMA Integration | Legacy P7 obligations; shared PWM reporting, I2S slave and alternate-input-route prerequisites; common ABI/HAL parity; Crypto banks/lifecycle; truthful capabilities and affected Mini compatibility. | Pending |
| TINY-R2-P7 - Tiny RCU and Dual-Mode Clock/Reset Integration | Legacy P8 obligations with main SRAM in SYS and XPI in MEM; atomic rate changes, all actual CDC/reset barriers, clock failures, WFI leaf gating and reserved DVP controls. | Pending |
| TINY-R2-P8 - XPI PSRAM Framebuffer Bring-up | Legacy P11 obligations: real pin-level NSS1 device transport, CPU/DMA mapped-write readback, boundaries/recovery, payload rate and worst backpressure. | Pending |
| TINY-R2-P9 - DVP Camera Profile and Frame Capture Integration | Legacy P12 obligations: unchanged DVP ABI/FIFO, DMA2/request 11, exact frame length, final-tail drain, snapshots/crops, missing-clock recovery and camera/audio exclusion. | Pending |
| TINY-R2-P10 - System Performance and Regression Qualification | Complete current-profile functional regression and workload/contention A/B, measured real-time budgets, synthesis/macro mapping, netlist checks and explicit missing coverage. | Pending |
| TINY-R2-P11 - IHP130 Physical and Product Qualification | Final joint CPU/main-SRAM timing, CTS/reset distribution, extracted PVT/IO/package/power evidence, qualified clock/PLL inputs and device operating points; close remaining legacy P9 obligations. | Pending |

### R2 clock, reset and macro evidence

The main 128 KiB SRAM includes its actual physical macro clock pins. It MUST
use the same SYS source and active frequency as the CPU, with no hidden
main-SRAM divider, CPU/main-SRAM CDC or half-rate fallback. The old P6/P10
assignment of main SRAM to MEM is historical and is superseded for R2.
Four logical 32 KiB banks do not mean four physical macros: verify the real
IHP130 mapping and preserve the complete 128 KiB capacity. Crypto's six
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
| Synthesis and netlist | Current IHP130 mapping of every main-SRAM/Crypto bank, area/cells, reset fanout, critical paths, netlist boot and applicable full-function checks | Library area is not die area; compact netlist boot does not replace full firmware or routed timing |
| Physical | Actual source/profile/tool/PDK/corner/SDC identity; macro checks, CTS and reset distribution, extracted setup/hold and recovery/removal, CDC/RDC, IO/package/power and device timing | Behavioral PLL and pre-layout STA do not qualify an operating point or constitute foundry signoff |

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
