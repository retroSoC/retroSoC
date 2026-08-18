# DMA MVP

The Mini SoC DMA is a four-channel, direct-register transfer engine. It is an
APB4 configuration target at `RS_SOC_APB4_DMA_BASE`, a native 32-bit AXI4
master, and an aggregate management-core interrupt source on IRQ20. DMA does
not use RIB or a RIB-to-AXI4 adapter.

## Scope and limits

- Four independent channel contexts share one AXI4 master (`ID=0`).
- The current Mini integration supports 32-bit transfers only. `8`- and
  `16`-bit width encodings deliberately fail validation; software must not
  claim narrow-transfer support.
- Direct-register mode supports MM-to-MM, memory/fixed-MMIO, MM-to-I2S
  AXI4-Stream, and I2S/DVP AXI4-Stream-to-MM transfers.
- Scatter-gather, cyclic descriptors, 2D stride, width conversion, unaligned
  data realignment, cache coherency, multiple IDs, and asynchronous stream
  clocks are not implemented.

The core parameters are `AddrWidth`, `DataWidth`, `NumChannels`,
`MaxBurstBeats`, and `FifoDepth`. The production Mini instance is 32-bit,
four channels, sixteen beats, and sixteen words of buffering. The direct
engine rejects an unsupported data width at elaboration rather than implying
that the 64/128-bit roadmap is verified.

## Channel ownership

Firmware uses deterministic channels so unrelated drivers never silently
share a context:

| Channel | Owner |
| --- | --- |
| 0 | UART0 TX/RX |
| 1 | I2C0 TX/RX |
| 2 | I2C1 TX/RX |
| 3 | Bulk client: I2S player/self-test, DVP capture, WS2812, XPI/QSPI, and benchmark |

Bulk clients must serialize use of channel 3. Applications configure the
channel explicitly through `rs_dma_configure()`; there is no hidden global DMA
context.

## Register ABI

The APB4 window is 4 KiB. Offsets are defined manually in
`rtl/ip/peripheral/dma_define.svh` and
`crt/include/retrosoc/hal/dma_regs.h`; `tests/test_dma_register_parity.py`
compares both definitions.

| Offset | Register | Access | Description |
| ---: | --- | --- | --- |
| `000` | `IP_ID` | RO | `DMA4` identification |
| `004` | `IP_VERSION` | RO | MVP version |
| `008` | `CAPABILITY` | RO | channel count, data width, maximum burst, stream count, descriptor=0 |
| `00c` | `GLOBAL_CTRL` | WO | bit 0 global reset |
| `010` | `GLOBAL_STATUS` | RO | any channel busy |
| `014` | `IRQ_STATE` | RO/W1C | aggregate pending channels; W1C clears test bits |
| `018` | `IRQ_ENABLE` | RW | one enable bit per channel |
| `01c` | `IRQ_TEST` | RW | software interrupt test bits |
| `020` | `ERROR_SUMMARY` | RO/W1C | bit 0 valid/W1C, bits 3:1 channel, bits 15:7 status, bits 31:16 error-address upper half |
| `024` | `REQUEST_STATUS` | RO | peripheral pacing availability |

Each channel occupies `0x80` bytes beginning at `0x100 + channel * 0x80`.

| Channel offset | Register | Access | Description |
| ---: | --- | --- | --- |
| `00` | `CH_CTRL` | WO | `START`, `SUSPEND`, `RESUME`, `ABORT`, `RESET` commands |
| `04` | `CH_CFG` | RW idle | kind, width, increment bits, priority |
| `08`, `0c` | `SRC_ADDR`, `DST_ADDR` | RW idle | source and destination addresses |
| `10` | `BYTE_COUNT` | RW idle | byte length; must be nonzero and a multiple of four |
| `14` | `REQUEST_SEL` | RW idle | software or peripheral selector |
| `18` | `BURST_CFG` | RW idle | requested 1–16 beat maximum |
| `1c` | `EVENT_ENABLE` | RW | done, half, error interrupt enables |
| `20` | `STATUS` | RO | busy, suspended, done, aborted, error, incoming stream `TLAST` seen |
| `24` | `EVENT_STATUS` | RO/W1C | done, half, error sticky events |
| `28`, `2c` | `ERROR_STATUS`, `ERROR_ADDR` | RO | first channel error type, AXI response/direction, address |
| `30`–`44` | progress/counters | RO | current addresses, remaining, bytes done, 64-bit stall count |

Writes with unsupported strobes/offsets, writes to read-only registers, a
`START` or `RESET` on a busy channel, a global reset while any channel is
busy, or active-config writes return `PSLVERR`.
Configuration is shadowed while idle and latched on `START`. Reads have no
side effects. Command bits are pulses, not stored levels.

## Programming model

Populate `rs_dma_config_t`, call `rs_dma_configure(channel, &config)`, then
`rs_dma_start(channel)`. `byte_count` is always bytes. The driver validates
channel, enum, pointer range, overflow, alignment, byte count, priority,
burst, and legal stream/request combinations before writing registers.

`rs_dma_wait()` succeeds only after `done`; it returns `RS_EIO` for abort or
error. `rs_dma_get_status()` and `rs_dma_get_error()` are non-destructive.
Use `rs_dma_abort_wait()` before resetting a channel that may still be
draining accepted traffic. Use `rs_dma_irq_enable()`, `rs_dma_irq_pending()`, and
`rs_dma_irq_clear()` for the aggregate IRQ; acknowledge per-channel events by
writing `EVENT_STATUS`. `rs_dma_irq_enable()` enables done, half, and error
events for each selected channel.

## AXI4 and stream behavior

The master can own at most one read transaction and one write transaction, as
required by the current fabric. Read and write schedulers are independent.
They choose the highest channel priority first and use Common's round-robin
arbiter among equal priorities at burst boundaries.

Aligned incrementing memory regions issue `INCR` bursts up to 16 beats. A
burst never crosses 4 KiB and is only sent after the DMA FIFO reserves the
full read burst or contains the full write burst. Fixed and APB4/MMIO
transfers are one-beat `FIXED` transactions. AXI `SLVERR`, `DECERR`, bad ID,
and malformed `RLAST` are recorded against the owning channel; the first
global error remains sticky until W1C/reset.

I2S TX consumes the MM-to-stream path and receives `TLAST` on the final
32-bit word with `TKEEP/TSTRB=4'hf`. I2S RX and DVP RX use stream-to-MM;
programmed byte count terminates the transfer and incoming `TLAST` is recorded
as diagnostic status only. AXI4-Stream backpressure preserves all source
payload sidebands.

## Suspend, abort, and completion

Suspend takes effect at a burst boundary. A stream TX suspend waits for any
already asserted `TVALID` beat to handshake, then stops further beats. Resume
re-enables scheduling. Abort prevents new reads/writes, drains accepted AXI
transactions through `RLAST`/`B`, and only then flushes channel data. It never
withdraws an accepted AXI4 or AXI4-Stream `VALID`.

Done, half (`bytes_done >= length / 2` once), aborted, and error state are
channel-local. `bytes_done` advances only after a successful write response
or final stream-source handshake. XPI completion is pulsed only for QSPI/XPI
request selections; unrelated DMA completions cannot advance XPI state.

## Validation boundary

`tests/rtl/dma_error_tb.sv` uses a native AXI4 BFM for exact counts, 4 KiB
splits, 16-beat bursts, backpressure, stream transfer, and response error
isolation. `tests/rtl/dma_reg_tb.sv` covers APB4 decode, busy configuration
protection, W1C events, and aggregate IRQ behavior.
`tests/rtl/ws2812_dma_tb.sv` verifies fixed MMIO writes and FIFO backpressure
through native AXI4. The MVP remains single-clock inside DMA;
I2S/DVP CDC responsibility stays with their controllers. Physical memory
burst coalescing, cache maintenance, board throughput, and 64/128-bit paths
require separate evidence.
