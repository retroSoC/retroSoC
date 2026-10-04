# DMA V2

The shared DMA is a parameterized 32-bit AXI4 transfer engine with direct
register and linked-list TCD operation. It is an APB4 configuration target at
`RS_SOC_APB4_DMA_BASE` and an aggregate management-core interrupt source on
IRQ20. DMA does not use RIB or a RIB-to-AXI4 adapter.

The register ABI, IP implementation and HAL are shared across products.
The [Tiny Gen1 R2 target](tiny-soc.md) keeps `0x1000A000`, IRQ20 and eight
channels, but assigns channel 2 to DVP receive (general transfers only after
camera ownership is released), 3 to XPI/WS2812/CRC,
4/5 to Crypto and 6/7 to I2S TX/RX; 0/1 remain UART0/I2C0. Its streams and
DMA engine share PCLK, with an AXI CDC into SYS that preserves one outstanding
read and one write. Main SRAM and its independent bank frontends run in SYS;
there is no further SRAM CDC. Product capability/routing data must reject
absent endpoints without a blanket Tiny stream prohibition.
Tiny DVP keeps request selector 11 and remains unsupported until
`TINY-R2-P9` integration; a reserved/tied-off stream port is not support. The
DVP stream can target XPI NSS1 mapped PSRAM using ordinary AXI writes without selecting
XPI's indirect DMA request or creating another master. Device capacity and
serial-burst limits come from the initialized product memory configuration.
Tiny's per-target concurrency and planned credit-bounded WS2812 batches are
defined by the linked product contract. They retain this IP's direct/TCD,
priority, abort-drain and completion ABI; finite TCD chains are not cyclic
rings. `TINY-R2-P3` prepares scheduling and `TINY-R2-P6` integrates the eight
channels. These are frozen Tiny requirements, not implemented Tiny or timing
evidence; the committed Tiny baseline still has four channels.

The [PIO-lite contract](piolite.md) freezes an additional **TINY-only product
integration target**, using the shared DMA V2.1 extension below. This is a
separate feature from Tiny's performance-only R2 roadmap. Current DMA RTL/HAL
still implement V2.0; the V2.1 register, ports, discovery and lifecycle rules
are requirements for subsequent implementation, not delivered capabilities.
Mini is an affected compatibility consumer of shared DMA changes, not a
PIO-lite rollout target. Existing phase IDs and evidence remain unchanged.

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
share a context. This table describes the current Mini allocation; Tiny's
target allocation is defined by its product contract above:

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
| `004` | `IP_VERSION` | RO | Current V2.0 `0x00020000`; frozen V2.1 target `0x00020001` |
| `008` | `CAPABILITY` | RO | channel count, data width, maximum burst, stream count, descriptor=1 |
| `00c` | `GLOBAL_CTRL` | WO | bit 0 global reset |
| `010` | `GLOBAL_STATUS` | RO | any channel busy |
| `014` | `IRQ_STATE` | RO/W1C | aggregate pending channels; W1C clears test bits |
| `018` | `IRQ_ENABLE` | RW | one enable bit per channel |
| `01c` | `IRQ_TEST` | RW | software interrupt test bits |
| `020` | `ERROR_SUMMARY` | RO/W1C | bit 0 valid/W1C, bits 3:1 channel, bits 15:7 status, bits 31:16 error-address upper half |
| `024` | `REQUEST_STATUS` | RO | peripheral pacing availability |
| `028` | `SUPPORTED_REQUESTS` | RO | V2.1 target only: static implemented request bitmap; absent in V2.0 |

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

## Frozen V2.1 PIO-lite extension

### Scope and discovery

V2.1 MUST retain the existing direct-register offsets, four-bit request
selector, 64-byte TCD size/alignment and TCD request field `[15:12]`. Existing
request IDs 0-13 and their transfer kinds remain unchanged. In particular,
omitted Tiny I2C1 requests 9/10 MUST NOT be reused. No channel, AXI master,
cyclic descriptor, asynchronous stream clock or narrow-transfer mode is added.

| Request | ID | Transfer kind | Meaning |
| --- | ---: | --- | --- |
| `PIOLITE_TX` | 14 | MM-to-stream | Memory words into the selected SM TX FIFO |
| `PIOLITE_RX` | 15 | Stream-to-MM | Selected SM RX FIFO words into memory |

These are two block-level stream endpoints, not per-SM request pairs. One TX
SM and one RX SM may receive DMA service simultaneously; they may be the same
SM. Two concurrent RX DMA streams or two concurrent TX DMA streams are not
supported. Future four-SM configurations keep this endpoint limit unless a
separate extension changes the contract. Both endpoints use full 32-bit words,
`TKEEP/TSTRB=4'hf`, PCLK and the existing AXI master. Programmed byte count
terminates DMA; TX `TLAST` marks its final word and RX `TLAST` does not replace
the programmed count or terminate a PIO program. DMA completion confirms FIFO
transfer/memory-write completion, not completion of a waveform at the pins.

`SUPPORTED_REQUESTS` at `0x028` MUST return bits 0-15 for request IDs 0-15 and
zero in bits 31-16. Its cold-reset value is the build's effective implemented
mask: combine the request mask, supported transfer logic, stream-enable
parameters and actual product wiring. A reserved port, tied-off endpoint or
disabled stream MUST report zero. The value is static integration capability,
not FIFO readiness, current channel ownership or whether a PIO binding is
enabled. Writes return `PSLVERR` without changing state. `REQUEST_STATUS`
retains live pacing semantics and MUST NOT be interpreted as support discovery.

V2.1 `CAPABILITY[30:28]` MUST report the population count of implemented
stream-direction requests 1, 2, 11, 12, 13, 14 and 15 in that effective mask.
Seven is the maximum and fits the existing field. Other capability fields
retain their existing layout/encoding. The current V2.0 implementation's
hard-coded stream value 3 is historical behavior, not a reliable endpoint
inventory. V2.1 corrects the reported count without moving the field.

The two PIO ports and their grants MUST default disabled in shared-IP
instantiations. Mini keeps bits 14/15 clear and its current owners and endpoints;
updating the shared implementation does not enable PIO on Mini. Tiny asserts
each support bit only when the complete corresponding endpoint is integrated.
The product capability metadata, hardware mask and software checks MUST agree.

Software MUST check DMA identity/version before accessing `0x028`, which is
an invalid offset on V2.0. PIO DMA requires the V2.1 contract and both the
requested DMA support bit and the PIO block's capability/probe result. Product
metadata prevents probes of an absent PIO address. Absent, old-version or
unimplemented support returns `RS_ENOTSUP` before channel programming; live
readiness cannot substitute for these checks. CPU FIFO access remains a
separate PIO capability. The SVH/C register constants remain handwritten and
covered by register-parity checks.

### Endpoint binding and channel ownership

The PIO block owns one binding per direction: selected SM, exclusive DMA
channel and enable. The two enabled bindings MUST name distinct implemented
channels. Product application profiles reserve these channels explicitly;
Tiny's R2 default owners are not silently displaced. A bound mixed TCD chain
belongs entirely to that PIO session, including descriptors that use another
request. Aborting the session aborts that whole bound job.

The shared DMA receives default-disabled one-hot allowed-channel grants for
each PIO endpoint and a closing/admission guard for the reserved channels.
Direct START and every TCD activation MUST validate the transfer direction,
static request support and matching enabled channel grant before moving data.
Malformed, unsupported or unbound PIO requests report a channel configuration
error without issuing their payload transaction. TCD fetches needed to discover
an invalid descriptor still follow the normal accepted-read drain rules.

DMA exports complete job ownership and pending admission to the PIO integration.
Ownership spans the whole direct transfer or finite TCD chain, including
descriptor fetch/parse, non-PIO descriptors, suspension, accepted payload
transactions and abort/error drain. It MUST NOT be inferred from the currently
selected request or stream `TVALID`. Unrelated DMA channels continue running.

A binding enable, disable, channel/SM change or endpoint reset MUST be rejected
while either its old or proposed channel owns a job or has a pending START.
It also requires no unresolved endpoint beat/session. A same-cycle accepted
DMA START takes precedence over a conflicting binding change/reset, using the
current registered binding; rejected commands leave the old binding intact.
This rule applies even when the first/current descriptor does not use PIO.
Do not require global DMA idleness or restrict this extension to direct mode.

### Cancellation and stream cleanup

Abort is distinct from immediate endpoint reset. The PIO session first enters
closing state, disables pin output enables and stops new SM execution. Closing
MUST reject new STARTs on its reserved channels and prevent further descriptor
activation; it retains the old binding while accepted work drains. The TX
endpoint remains able to handshake/discard an already-present DMA beat even
when the SM FIFO was full. RX stops producing new words but preserves any
already-asserted `TVALID` and payload through the stream cleanup boundary.

The V2.1 DMA cancellation path MUST give abort/error cancellation priority over
new descriptor-fetch issue and descriptor activation, including simultaneous
commands. Accepted descriptor AXI reads, as well as payload reads/writes, must
complete through their terminal responses. Canceled fetched descriptors MUST
NOT activate or clear an abort request. Clear canceled queued fetch/parse work
without issuing it. Complete job ownership is released only after these
conditions hold; the current payload-only ownership test is not sufficient.

Software aborts only the bound DMA channels and waits with a bounded timeout
for complete job drain. Then the integration isolates the affected stream
endpoint and acknowledges a local stream-session reset on both sides before
flushing its residual FIFO/held RX word or changing its route. Channel idle
alone does not permit withdrawing a held RX `VALID`: a transfer can reach its
programmed byte count with residual source data. This local cleanup MUST NOT
reset the common DMA or disturb other channels. Normal, non-reset stream
operation preserves VALID and payload until handshake.

A timeout leaves outputs high impedance and the old binding closed/owned;
it does not acknowledge reset, reassign a channel or reuse memory still owned
by DMA. Recovery retries bounded drain/isolation under the product lifecycle
policy. Clock gating and endpoint reset require that complete handshake;
FIFO empty, SM stopped or a read of channel BUSY alone is insufficient.

### Required implementation evidence

The PIO-lite development order owns this extension's implementation gates.
Required evidence includes V2.0 rejection without reading `0x028`, V2.1
identity/parity/RO errors, accurate masks/counts at each staged integration,
default-disabled Mini ports, direct and finite mixed TCD transfers, endpoint
direction/channel rejection, and full-duplex use of distinct bound channels.
Exercise START versus rebind/reset, later PIO descriptors in an active chain,
suspension, descriptor-fetch backpressure, abort during fetch/parse/activation,
full TX FIFO, residual RX VALID after count completion, isolation/reset,
timeout retention and unrelated-channel progress. Formal/RTL checks must
cover route stability, no stale descriptor activation, accepted-transaction
drain and source stability outside the acknowledged local reset interval.

Run the affected DMA/GPIO host, register-parity, RTL and formal checks plus
Tiny end-to-end and affected Mini regressions for the implemented phase. The
existing verification described below is baseline coverage; it does not
establish these new V2.1 properties or a new PIO frequency/physical result.

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
