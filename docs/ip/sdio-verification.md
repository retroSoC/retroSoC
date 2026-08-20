# SD/SDIO Host Verification

This document is the verification contract for the standalone
`apb4_sdio` foundation. The protocol contract remains in
[`sdio.md`](sdio.md); this file records evidence and coverage boundaries
without changing the IP ABI.

## Verification components

| Component | Purpose |
| --- | --- |
| `tests/rtl/sdio_native_model.sv` | Native SD memory v2 SDSC/SDHC and SDIO-only function model. |
| `tests/rtl/sdio_axi_memory_responder.sv` | Deterministic 32-bit AXI responder with backpressure, split, and response-error injection. |
| `tests/rtl/sdio_command_tb.sv` | Exact command-frame launch/sample and terminal-bit checks. |
| `tests/rtl/sdio_register_tb.sv` | APB register, PIO consume, empty-read, and W1C checks. |
| `tests/rtl/sdio_standalone_tb.sv` | APB-driven SDHC/SDSC 1-bit/4-bit PIO and DMA, 1/2/3/5-byte tails, 512-byte FIFO streaming, response-token errors, aborts, clock, response, busy, and CRC/timeout paths. |
| `tests/rtl/sdio_sdio_tb.sv` | CMD5, CCCR CMD52 including high-speed capability/enable, CMD53 byte/block fixed/increment, and DAT1 line behavior. |
| `tests/rtl/sdio_dual_tb.sv` | Two independent APB/AXI/pad contexts running concurrently. |
| `tests/rtl/sdio_dma_stress_tb.sv` | 16-beat bursts, 4 KiB splitting, backpressure, AXI errors, descriptor-fetch/read/write-response abort drain, and writeback observation. |
| `rtl/mini/formal/sdio_formal*.sv` | Reduced APB/clock/AXI/descriptor formal harness and properties. |

The models are verification-only and may use timing controls, tasks, and
backing arrays. They do not copy vendor register
tables or proprietary descriptor formats.

## Traceability

| Requirement | Evidence |
| --- | --- |
| 400 kHz command flow | `sdio_standalone_tb` programs half-period 90 at 72 MHz and checks `CLOCK_ACTUAL`. |
| SDSC byte vs SDHC block addressing | `sdio_sdsc_tb` and `sdio_standalone_tb` use the same command with distinct model geometry. |
| 1-bit and 4-bit SDR read/write | `sdio_onebit_tb` plus the 4-bit standalone path; strict token/CRC checks and PIO writes cover both widths. |
| Byte lanes and tails | `sdio_standalone_tb` checks lane-0-first packing and 1/2/3/5-byte tails through PIO and DMA in both directions. |
| PIO FIFO and remaining | `sdio_standalone_tb` streams a complete 512-byte write/read with consecutive APB accesses and only completes on the final payload word. |
| Command/data terminal edges | `sdio_command_tb` and the strict native model reject a missing command end bit or data token; standalone writes verify the final CRC. |
| Consecutive PIO reads | `sdio_register_tb` checks read-consume pulses; standalone tests consume two held words without repetition. |
| CMD12/R1b and DAT0 busy | Standalone command sequence and parameterized card busy interval. |
| CMD5/CMD52/CMD53 | `sdio_sdio_tb`, including CCCR backing and function memory. |
| DAT1 active-low IRQ | `sdio_sdio_tb` checks high-level no-IRQ, low-level sticky IRQ, W1C, stopped SDCLK persistence, and high-to-low re-arm. |
| Programmable delay and fault hooks | Card tasks provide response/data delay plus one-shot CRC and timeout injection; base CRC/error tests exercise the protocol engines. |
| SG chain/writeback | `sdio_dma_stress_tb` runs a bounded two-descriptor chain and checks DONE/OWN writeback. |
| AXI 16 beats/4 KiB split/backpressure/error | `sdio_dma_stress_tb` and the reusable responder. |
| Abort | `sdio_standalone_tb` aborts command, data, and descriptor fetch through HOST_CTRL; `sdio_dma_stress_tb` aborts after payload AR acceptance and during a stalled write response, checking drain and ERROR/OWN writeback. |
| Write response token | `sdio_standalone_tb` injects accepted, CRC-error, and write-error tokens and checks distinct status. |
| W1C/counters/descriptor IRQ | `sdio_register_tb` checks persistent ERROR_STATUS W1C, DEBUG semantic bits, IRQ W1C, and descriptor event behavior; standalone checks timeout event counting. |
| 100 MHz to 50 MHz SDCLK | `sdio_50mhz_tb` with `half_period=1`. |
| Dual-context isolation | `sdio_dual_tb` checks independent status, data, and DAT1 contexts. |

## Formal boundary

`make ... formal-sdio` runs a reduced register/DMA/clock proof through the
repository SymbiYosys/Yosys/Bitwuzla flow. It does **not** claim a complete
native SD host proof. Command/data serializer, card timing, token semantics,
PIO FIFO streaming, and full byte-count termination are simulation-covered
contracts; they are not certified by this reduced formal target.

The checked harness covers:

- APB held-access response reachability and registered response stability;
- AXI address-channel legality, 32-bit alignment, maximum 16 beats, and
  no-cross-4-KiB arithmetic;
- conditional payload stability when a valid write beat remains backpressured;
- accepted-read abort drain: RREADY remains asserted until the terminal RLAST
  handshake, with an abort-after-AR cover;
- descriptor-count error reachability;
- clock transition phase observation and abort/error event observation;
- sticky-IRQ event and terminal-event covers.

The shallow proof intentionally does not claim a complete native data-block
proof. Full command/data serializer coverage, arbitrary descriptor memory
contents, and two-context formal composition remain simulation/next-stage
targets. The current tractable CI invocation is:

```sh
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG SYNTH=YOSYS STA=NONE \
  FORMAL=YES FORMAL_SDIO_DEPTH=12 FORMAL_SDIO_COVER_DEPTH=12 formal-sdio
```

## Evidence status

**Simulated:** strict native command framing including the final command end
bit, R1/R4/R5 responses including the response terminal bit, 1-bit/4-bit
data token/payload/final CRC paths, SDSC/SDHC addressing, lane-0-first
1/2/3/5-byte tails, 512-byte PIO FIFO streaming, SDIO function memory,
accepted/CRC-error/write-error tokens, DAT0 busy, active-low DAT1 sticky IRQ
behavior with W1C and stopped SDCLK, AXI split/backpressure/error responses,
both DMA directions, descriptor IRQ/writeback, command/data/descriptor abort
draining, timeout/counter events, dual-instance concurrency, and 50 MHz phase
generation.

**Formally proven at the reduced bound:** APB response stability, AXI
legality/arithmetic, reachable backpressure payload checks, accepted-read abort
RREADY obligation/terminal cover, clock phase transition checks,
descriptor-count error reachability, and abort/error event observation.
Complete native command/data behavior, token decoding, PIO FIFO accounting,
and arbitrary block transfers remain simulation evidence only. The proof does
not certify complete block transfers or board/PHY behavior.

**Planned board/PHY coverage:** 3.3 V pad electrical behavior, package and
board delay, signal-integrity margins, real SDSC/SDHC vendor cards, SDIO
module interoperability, hot removal, UHS/1.8 V, tuning, and long-duration
stress. These require hardware, PHY constraints, or specifications not
present in this repository.

## Production RTL blocker closure

All four production blockers are closed in the current RTL. They have directed
simulation evidence; the reduced formal target covers the applicable APB,
clock, AXI, and abort obligations but is not a full-host proof:

1. **Command/data terminal edges:** command serialization advances after the
   sampled edge, holds the final command bit through card observation, and
   data write token/CRC terminal holds are phase-safe in both bus widths. The
   native model now rejects repaired/shifted command frames and missing tokens.
2. **PIO read consume:** `PIO_DATA` reads require a valid word, return a
   registered stable value, and emit one consume pulse per APB read. The
   register and standalone tests exercise consecutive words.
3. **DMA abort drain:** an abort latch suppresses downstream payload delivery,
   keeps RREADY asserted after AR acceptance, drains response/RLAST, records
   response/last errors, and only then performs descriptor error writeback and
   terminalizes. Simulation and formal cover the abort-after-AR case.
4. **DAT1 host IRQ:** the pad is double-synchronized in `clk_i`, qualified
   only while DAT1 is released and the data path is idle, and active-low
   assertion is latched into IRQ bit 6 with mask/W1C behavior independent of
   SDCLK.

These tests are verification evidence, not waivers or certification claims.
