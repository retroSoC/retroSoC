# PPALite Verification and Evidence Ledger

This ledger accompanies [ppalite.md](ppalite.md), approved on 2026-10-05 for
TINY/IHP130. PPALITE-P0 records the contract only. No pixel core, source
repair, route/DMA integration, firmware, performance or physical result below
is passed by documentation approval. Preserve historical Tiny/R2/PIO/SPI
evidence under its original scope.

## Configuration and Evidence Identity

- Current normative default: TINY/ICS55, `HAVE_PLL=YES`, SAFE24 boot under the
  [2026-10-07 Tiny policy](tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07).
  `configs/ci/ics55-tiny.mk` now exists with a parked PLL; platform acceptance
  belongs to the Tiny ledger. Existing IHP130 commands and historical records
  are compatibility evidence only; no PPALite integration is delivered.
- Pre-final post-synthesis timing is observational; failed/missing timing does
  not become a PASS or a hardware-frequency claim. Source correctness,
  functionality, synthesis/mapping and netlist-function requirements remain.
  PPALITE-P5 joins R2-P11/SPI-P5/PIOLITE-P5 after all functional phases on the
  same complete-product source/config/PDK/netlist, with final timing closure
  mandatory. Preserve every phase ID/title and prior evidence attribution.

- Starting profile: `configs/ci/ihp130-tiny.mk`, TINY, IHP130, 24 MHz/no PLL,
  four-channel current DMA and no PPALite integration.
- Future target: APB `0x1001E000`, IRQ27, RCU17, PCLK pixel processing after
  the existing DVP CDC; RAW/PROCESS exclusively share request 11/DMA2.
- Preserve 512 B DVP payload FIFO, every Pad/pinmux assignment, 128 KiB user
  SRAM at CPU SYS frequency, eight DMA channels and three external AXI owners.
- Record source SHA, lock/configuration digests, variant, tool versions,
  commands/logs/results, PCLK/SYS/MEM/PIXCLK, source/crop/active geometry,
  format/order/step/phase, output pitch, logical/physical lengths, destination
  extent, burst limits, source/target models and known limitations.
- Artifacts belong below the existing timestamped configuration-hash build
  root. Missing or skipped cases are not passing evidence. Mini is a shared
  consumer compatibility target with RAW behavior, not a PPALite rollout.

## Requirement Matrix

All implementation cases have status **required, not run** at freeze.

| Case | Requirements | Evidence / phase |
| --- | --- | --- |
| PPL-V01 | PPL-01/03 | Independent scalar and stream models for RGB565_BE/LE, input R/B exchange, four YUV orders, raw Y and exact gray RGB565; reject RGB-to-GRAY8 and illegal flags; P1 |
| PPL-V02 | PPL-03/04 | Every step 1/2/4 and legal phase pair, post-crop coordinates, 1-pixel geometry, odd dimensions and rejected empty selection; exact output dimensions; P1 |
| PPL-V03 | PPL-04 | DVP chronological byte mapping, low-pixel/lane-first output, RGB565 byte exchange, valid halfword input tail, ignored unused input lanes, zero per-row padding and no cross-row packing; P1 |
| PPL-V04 | PPL-04/08 | Checked 64-bit products, rounding, destination overflow, capacity/alignment and maximum DMA length; guard canaries and invalid ARM no-side-effect; P1/P3 |
| PPL-V05 | PPL-01/04 | Independent SOF/EOL/KEEP/STRB/ID/DEST checks, early/late/duplicate/missing markers, extra source data, exact input/output counts and late source errors; P1/P2 |
| PPL-V06 | PPL-04/06 | Dropped leading rows relocate output SOF; dropped trailing pixels/rows still drain and validate after output DMA completion, including downstream TREADY low; P1/P2 |
| PPL-V07 | PPL-01/04 | Random input gaps/output backpressure, pre-edge FIFO full/empty rules, simultaneous push/pop, stable stalled output and no overflow/data duplication; P1 |
| PPL-V08 | PPL-02/05 | Reset RAW exact data/sideband/backpressure parity, raw odd-width rejection, unchanged Mini and legacy direct/TCD behavior, processed single direct job on 2 only; P2/P3 |
| PPL-V09 | PPL-02/05/07 | Route change waits for DVP/CDC/FIFO and all DMA jobs/admissions/descriptors/responses; START wins route race, no change on failed barrier, retained PROCESS between frames without global stop; P2/P3 |
| PPL-V10 | PPL-05/06 | Exact request 11/channel 2/type/count/destination admission; stale DONE and repeat START rejection, wrong channels and processed TCD rejection before payload, unaffected other requests and unchanged capability count; P3 |
| PPL-V11 | PPL-06/10 | Source SYNC/SIZE/PARTIAL detection, malformed data outside crop, repeated frame/event/error epochs, raw counts above 65535 words and coherent source status; P2 |
| PPL-V12 | PPL-06/07 | DVP non-flushing snapshot stop, queued last word and delayed B response, late source failure after PIPE_DONE, no unintended next snapshot; FINALIZE only with complete matching evidence; P2/P3 |
| PPL-V13 | PPL-07 | Abort/fault with held output VALID, DMA drain before source flush, isolation acknowledgement, descriptor cancellation, lost PIXCLK and timeout retain ownership; no filler/global DMA reset; P2/P3 |
| PPL-V14 | PPL-07/09 | Source/processor/DMA reset and clock-change guards, multi-target lifecycle requests, RAW route independent of core reset, WFI/debug/hart reset and explicit recovery of old epochs; P3 |
| PPL-V15 | PPL-08 | Every CSR reset/access/field/state, bounded APB errors, simultaneous event/W1C priority, SVH/C parity, current versus latched result metadata, capability absent until wired; P1/P3 |
| PPL-V16 | PPL-08/09 | HAL timeout/error/resource handling, RAW helper rejecting PROCESS, no heap, source config lock/readback/CDC acknowledgement, release retaining route and immutable result context; P3 |
| PPL-V17 | PPL-09/10 | QVGA reductions below, small SRAM and qualified PSRAM, exact pixel/padding/canary checks, stride-aware SD/SPI output and no hidden whole-frame SRAM copy; P4 |
| PPL-V18 | PPL-10 | Raw-rate DVP FIFO budget, pipeline initiation/row overhead, actual bytes/CPU work/longest stalls, current-source Tiny/Mini regressions, both simulators; P4 |
| PPL-V19 | PPL-09/10 | Complete source/netlist identity, storage mapping, block/full synthesis, netlist simulation, reset/CDC/RDC/PVT/Pad/memory/physical evidence; P5 |

Formal/assertion coverage includes stable source/payload under backpressure,
excess input VALID after the accepted quota even with TREADY low, recovery
with persistent source-abort flags, preserved JOB_SEQUENCE across RECOVER,
and an acknowledged clean source error epoch before the next ARM. Include
DMA2 preparation before ARM, pending START beating ARM, and rejection of a
different request/configuration on channel 2 after payload DONE but before
capture release. Also check illegal command states without partial effects.
Also cover exact consumption/production, no state advance on rejected commands, no stale
route/descriptor activation, ownership conservation and legal cleanup order.
Record proof bounds and external response/clock assumptions. Digital proof
does not establish arbitrary sensor liveness, analog timing or silicon safety.

## Source Qualification Gate

The current source visibly leaves SYNC/SIZE/PARTIAL detection reserved and
uses a 16-bit word statistic in `dvp_core.sv`/`dvp_reg.sv`. These are known gaps,
not accepted limitations that PPALite output counts can hide. P2 must close
them with minimal shared correctness changes or identify current-revision
accepted R2 evidence that already does so. Preserve the DVP V2 register ABI,
512 B FIFO and payload contract; regress Mini consumers.

Test a valid odd-pixel line ending with KEEP/STRB=0x3 separately from an invalid
incomplete 16-bit sensor pixel. Include an extra dangling byte even when the
expected downstream words look correct, short/long raw lines/frames, crop
boundary faults, repeated snapshots/events and VGA's153600 input words.
Source counters and error/EOF/configuration handshakes must be coherent in
PCLK, with late faults retained until finalization. Do not repair a failed
frame by padding or ignoring an unimplemented source error bit.

The success path must stop capture without flushing queued data and wait for
the final DMA writes. DVP ABORT currently triggers FIFO flush: exercise drain
and isolation first on failed captures, and do not use that command as normal
completion. Missing PIXCLK may prevent cleanup acknowledgements; preserve
closed ownership until a real recovery barrier completes.

## Arithmetic and Application Cases

The following exact examples are expectations, not performance measurements:

| Case | Output | Logical row / stride | Valid bytes / DMA bytes / words |
| --- | --- | --- | --- |
| 320x240 raw 16-bit reference | 320x240 | 640 / 640 | 153600 / 153600 / 38400 |
| Y to GRAY8, step 1 | 320x240 | 320 / 320 | 76800 / 76800 / 19200 |
| Y to GRAY8, step 2/2 | 160x120 | 160 / 160 | 19200 / 19200 / 4800 |
| Y to gray RGB565, step 2/2 | 160x120 | 320 / 320 | 38400 / 38400 / 9600 |
| 319x239 active input, step 2/2, phaseX1/phaseY0, GRAY8 | 159x120 | 159 / 160 | 19080 / 19200 / 4800 |
| 5x3 active input, step 2/2, phase 0/0, GRAY8 | 3x2 | 3 / 4 | 6 / 8 / 2 |

Exercise Y values 0/16/235/255 without range expansion, and known R/G/B primary
pixels to catch byte/channel swaps. Layout and sample selection must agree
with a scalar oracle, not merely another implementation of the stream packer.
Check all row padding and pre/post allocation canaries after memory responses.

Application progression is capture known patterns -> pixel/layout verification
in SRAM/PSRAM -> SD export or SPI gray preview. Use immutable completed frames.
For odd-width RGB565, send one exact-width SPI segment per row so each row's
padding is discarded rather than emitted as pixels. Do not DMA a padded frame
as one contiguous unpadded image. GRAY8 preview uses measured bounded CPU
conversion or a separate gray-RGB565 capture, never fictional PPA memory replay.
Keep the legacy XPI LCD and existing SPI/PIO behavior unchanged.

Measure raw input rate, output bytes, core service/row cycles, FIFO occupancy,
CPU cost, longest admitted memory stalls and whole-frame time. The 512 B FIFO
budget uses raw sensor bytes, not reduced output bytes. Qualify additional
buffer credit explicitly. PCLK48/60 and physical camera rates require their
own enabled profile and timing evidence; no target becomes a measured FPS.

## Commands and Verdicts

P0 checks documentation only:

```sh
git diff --check
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --dry-run
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI --dry-run
```

Also verify local links/anchors, new-file formatting, command/profile existence,
unchanged frozen phases/package/pinmux and the unchanged DMA request/descriptor
allocation. Dry-runs verify command definitions, not PPALite implementation.

P1-P4 add focused tests using the main specification's normal host, SDK,
firmware, simulator and regression entrypoints. Both Verilator and Icarus
exercise the relevant stream/camera/memory paths. Tiny success requires exit 0,
TEST_STATUS/`SIM_TEST_PASS` and no `FAILED`, `FATAL`, `assertion failed`,
`%Error`, `SIM_TEST_FAIL` or `SIM_TEST_TIMEOUT`. UART is diagnostic only.
Preserve each Mini test's own configured verdict. P5 joins the source-bound
selected-PDK complete-product physical campaign. The ICS55 Tiny full-chip
adapter and qualification remain pending; IHP130 results retain their own PDK.

## Freeze Record and Remaining Gaps

| Phase | Status at freeze |
| --- | --- |
| PPALITE-P0 | Documentation freeze complete; link, command, arithmetic, structural and whitespace checks passed on 2026-10-05 |
| PPALITE-P1 | Not started; pixel core, model, ABI parity and standalone evidence absent |
| PPALITE-P2 | Not started; source correctness, RAW/PROCESS route and cleanup qualification absent |
| PPALITE-P3 | Not started; real Tiny admission/RCU/SDK integration and affected consumer evidence absent |
| PPALITE-P4 | Not started; camera/memory/save/display and measured performance evidence absent |
| PPALITE-P5 | Not started; full PPALite-inclusive physical, Pad and silicon evidence absent |

Executed P0 checks: `git diff --check`; 178 local Markdown links and one anchor; new-file
ASCII/fence/whitespace checks; 25 existing Tiny/R2 phase headings and six SPI
phase titles preserved; QFN64 package section and all 32 GPIO rows unchanged;
PIO-lite/SPI specifications and ledgers unchanged; only 12 Markdown files
changed/added. The three documented regression dry-runs passed using local
`python`. In-memory formula checks covered 28224 small geometry/step/phase/
pixel-width combinations and four gray-RGB565 reference values. These checks
validate documentation arithmetic, not RTL, firmware or measured performance.

No firmware, simulator, formal, synthesis, STA or physical flow was run for
this documentation-only change. Source correctness remains a pending gate.

No hardware/software phase, MISRA deviation, new dependency/PDK, warning
baseline or metrics promotion is approved by P0. Retain missing tools/models,
macro/Pad/clock views, board access and source-correctness gaps as named limits
on the corresponding claim. Documentation is not RTL or physical signoff.
