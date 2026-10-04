# SPI Verification and Evidence Ledger

This ledger accompanies [spi.md](spi.md), targeting TINY/IHP130 and the
approved `SPI-P0..P5` roadmap dated 2026-10-04. It records required evidence,
not existing hardware capability. At freeze, SPI RTL, DMA V2.2, native routing,
HAL/display software and physical qualification are not delivered. Historical
Tiny, SPI-SD, XPI, DMA and PIO evidence does not automatically cover this IP.

## Configuration and Identity

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
  Full qualification must use the same SPI/PIO-inclusive source and netlist
  as any shared R2-P11/PIOLITE-P5 campaign.

## Required Case Matrix

All cases currently have status **required, not run**. Later phase records
must add scoped evidence without deleting unmet conditions.

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
PCLK 48/60 cases await executable R2 profiles and physical inputs. Ideal
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

## Freeze Record and Gaps

| Phase | Evidence status |
| --- | --- |
| SPI-P0 | Documentation freeze complete; link/anchor, command dry-run, phase/package/ALT structure and whitespace checks passed on 2026-10-04 |
| SPI-P1 | Not started; standalone RTL/model, CSR mirror, BFM and synthesis evidence absent |
| SPI-P2 | Not started; V2.2 request/credit/cancellation implementation and shared compatibility evidence absent |
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
