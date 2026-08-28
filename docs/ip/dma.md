# DMA V2

The Mini SoC DMA is a parameterized 32-bit AXI4 transfer engine with direct
register and linked-list TCD operation. It is an APB4 configuration target at
`RS_SOC_APB4_DMA_BASE` and an aggregate management-core interrupt source on
IRQ20. DMA does not use RIB or a RIB-to-AXI4 adapter.

## Scope and limits

- Eight independent channel contexts share one AXI4 master (`ID=0`) in the
  production Mini integration; channels 0-5 retain existing ownership,
  channel 6 is reserved for HP boot, and channel 7 is reserved.
- The current Mini integration supports 32-bit transfers only. `8`- and
  `16`-bit width encodings deliberately fail validation; software must not
  claim narrow-transfer support.
- Direct-register mode supports MM-to-MM, memory/fixed-MMIO, MM-to-I2S/crypto
  AXI4-Stream, and I2S/DVP/crypto AXI4-Stream-to-MM transfers.
- Linked-list mode fetches 64-byte, 64-byte-aligned TCDs and follows
  `next_ptr` for one-dimensional transfers.
- MM-to-MM accepts arbitrary non-zero byte counts with aligned addresses and a
  partial final write beat. Stream endpoints remain word based.
- Cyclic descriptors, 2D stride, width conversion, unaligned realignment,
  cache coherency, multiple IDs, and asynchronous stream clocks are deferred.

The core parameters are `AddrWidth`, `DataWidth`, `NumChannels`,
`MaxBurstBeats`, and `FifoDepth`. The production Mini instance is 32-bit,
eight channels, sixteen beats, and thirty-two words of buffering. The engine
rejects an unsupported data width at elaboration rather than implying that a
64/128-bit roadmap is verified.

## Channel ownership

Firmware uses deterministic channels so unrelated drivers never silently
share a context:

| Channel | Owner |
| --- | --- |
| 0 | UART0 TX/RX |
| 1 | I2C0 TX/RX |
| 2 | I2C1 TX/RX |
| 3 | Bulk client: I2S player/self-test, DVP capture, WS2812, XPI/QSPI, and benchmark |
| 4 | Crypto input: memory-to-AES/SHA stream |
| 5 | Crypto output: AES stream-to-memory |
| 6 | HP Linux boot loader |
| 7 | Reserved |

Bulk clients must serialize use of channel 3. Crypto reserves channels 4 and
5 so a full-duplex AES transfer does not contend for the bulk context. Applications configure the
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
| `004` | `IP_VERSION` | RO | V2.0 |
| `008` | `CAPABILITY` | RO | channel count, data width, maximum burst, stream count, descriptor=1 |
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
| `10` | `BYTE_COUNT` | RW idle | byte length; MM-to-MM permits a partial final beat, stream requests are word based |
| `14` | `REQUEST_SEL` | RW idle | software or peripheral selector |
| `18` | `BURST_CFG` | RW idle | requested 1–16 beat maximum |
| `1c` | `EVENT_ENABLE` | RW | done, half, error interrupt enables |
| `20` | `STATUS` | RO | busy, suspended, done, aborted, error, incoming stream `TLAST` seen |
| `24` | `EVENT_STATUS` | RO/W1C | done, half, error sticky events |
| `28`, `2c` | `ERROR_STATUS`, `ERROR_ADDR` | RO | first channel error type, AXI response/direction, address |
| `30`–`44` | progress/counters | RO | current addresses, remaining, bytes done, 64-bit stall count |
| `48` | `TCD_HEAD` | RW idle | 64-byte-aligned descriptor address; zero selects direct mode |
| `4c` | `TCD_COUNT` | RW idle | maximum descriptors to follow |
| `50` | `CRC_EXPECTED` | RW idle | CRC32/ISO-HDLC expected value |
| `54` | `CRC_RESULT` | RO | CRC result for the current transfer |

Writes with unsupported strobes/offsets, writes to read-only registers, a
`START` or `RESET` on a busy channel, a global reset while any channel is
busy, or active-config writes return `PSLVERR`.
Configuration is shadowed while idle and latched on `START`. Reads have no
side effects. Command bits are pulses, not stored levels.

## Programming model

Populate `rs_dma_config_t`, call `rs_dma_configure(channel, &config)`, then
`rs_dma_start(channel)` for direct mode. For linked-list mode, populate one or
more 64-byte `rs_dma_tcd_t` records and call `rs_dma_submit_tcd_chain()`.
`byte_count` is always bytes; MM-to-MM may use a partial final beat while
stream requests remain word based.

`rs_dma_wait()` succeeds only after `done`; it returns `RS_EIO` for abort or
error. `rs_dma_get_status()` and `rs_dma_get_error()` are non-destructive; the
status includes the hardware `crc_result`.
Use `rs_dma_abort_wait()` before resetting a channel that may still be
draining accepted traffic. Use `rs_dma_irq_enable()`, `rs_dma_irq_pending()`, and
`rs_dma_irq_clear()` for the aggregate IRQ; acknowledge per-channel events by
writing `EVENT_STATUS`. `rs_dma_irq_enable()` enables done, half, and error
events for each selected channel.

## AXI4 and stream behavior

The master can own at most one read transaction and one write transaction, as
required by the current fabric. Descriptor fetches share the read master with
data reads; read and write schedulers remain independent. They choose the
highest channel priority first and use Common's round-robin arbiter among equal
priorities at burst boundaries.

Aligned incrementing memory regions issue `INCR` bursts up to 16 beats. A
burst never crosses 4 KiB and is only sent after the DMA FIFO reserves the
full read burst or contains the full write burst. Fixed and APB4/MMIO
transfers are one-beat `FIXED` transactions. AXI `SLVERR`, `DECERR`, bad ID,
malformed `RLAST`, invalid TCDs, and CRC mismatches are recorded against the
owning channel; the first global error remains sticky until W1C/reset.

The OPI PSRAM window at `0x48000000-0x4fffffff` is an ordinary MM-to-MM source
or destination. It does not consume a peripheral request selector and shares
bulk channel 3 with the other memory and stream clients. A transfer outside
the configured OPI device size terminates through the normal AXI error path;
the DMA must not infer capacity from the larger SoC aperture.

I2S TX and crypto input consume the MM-to-stream path and receive `TLAST` on the final
32-bit word with `TKEEP/TSTRB=4'hf`. I2S RX and DVP RX use stream-to-MM;
programmed byte count terminates the transfer and incoming `TLAST` is recorded
as diagnostic status only. AXI4-Stream backpressure preserves all source
payload sidebands. Crypto output is also stream-to-MM and requires the AES
engine's final `TLAST`; crypto request selectors are 12 and 13.

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

## TCD and coherency contract

Each TCD is 64 bytes and must be 64-byte aligned. Words 0-9 contain
`next_ptr`, source/destination, byte count, strides, `y_count`, control,
expected CRC, and CRC seed. Words 10-13 are software writeback fields (the
static HAL adapter fills them) and words 14-15 are reserved. V2 implements
`y_count=1` and zero strides; a zero `next_ptr` terminates the chain.

The control word contains `VALID`, source/destination increment, CRC enable and
final, interrupt enables, kind/request, priority, and burst fields. CRC uses
CRC-32/ISO-HDLC (`0xEDB88320`, init/xorout `0xffffffff`). Descriptors and data
must be in DMA-visible uncached/shared memory. Callers issue `fence rw,rw`
before start and after completion; no cache snoop or IOMMU is implied.

## Validation boundary

`tests/rtl/dma_error_tb.sv` uses a native AXI4 BFM for exact counts, 4 KiB
splits, 16-beat bursts, TCD fetch, CRC, tail strobes, and response error
isolation. `tests/rtl/dma_reg_tb.sv` covers APB4 decode, busy configuration
protection, W1C events, and aggregate IRQ behavior.
`tests/rtl/ws2812_dma_tb.sv` verifies fixed MMIO writes and FIFO backpressure
through native AXI4. `tests/rtl/dma_crypto_tb.sv` verifies both crypto stream
endpoints, backpressure, data preservation, and final `TLAST`. The V2 MVP remains single-clock inside DMA;
I2S/DVP CDC responsibility stays with their controllers. Physical memory
burst coalescing, cache maintenance, board throughput, and 64/128-bit paths
require separate evidence.

## Commercial alignment

The linked-list/FIFO boundary follows the STM32U5 GPDMA pattern; TCD alignment,
channel arbitration, and halt-on-error follow NXP eDMA; and the staged roadmap
keeps TI UDMA TR/ring features separate from the first release. AMD AXI DMA's
4 KiB protection and independent descriptor path are the reference for the AXI
rules. These are active vendor references: [STM32U5 RM0456](https://www.st.com/resource/en/reference_manual/rm0456-stm32u575585-armbased-32bit-mcus-stmicroelectronics.pdf),
[NXP eDMA](https://mcuxpresso.nxp.com/api_doc/dev/4336/a00013.html),
[TI UDMA](https://software-dl.ti.com/mcu-plus-sdk/esd/AM62X/latest/exports/docs/api_guide_am62x/DRIVERS_UDMA_PAGE.html),
and [AMD AXI DMA PG021](https://docs.amd.com/r/en-US/pg021_axi_dma/Feature-Summary).
Cache maintenance remains an explicit software contract, consistent with the
[ESP-IDF DMA memory rules](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/memory-types.html).
