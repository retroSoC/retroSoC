# Tiny Independent SPI Master and Display Interface

## Purpose and Research Boundary

This is the approved `spi` design freeze dated 2026-10-04 for **TINY only**.
The controller is a future standard Tiny product feature, not implemented
hardware or qualified silicon. `SPI-P0` delivers documentation only; P1-P5
require separate implementation approval and evidence. The authoritative
product, sharing and process inputs are [Tiny](tiny-soc.md), [DMA](dma.md),
[GPIO](gpio.md), [PIO-lite](piolite.md),
[engineering](../engineering.md) and [RTL policy](../rtl-coding-style.md).

The problem is to drive a display without placing its serial traffic on the
physical XPI bus used by boot NOR and optional PSRAM. SPI payload reads from
PSRAM still use XPI and contend there; a separate screen clock/data bus does
not eliminate framebuffer-memory cost. The first application is sequential
capture, verify, display and SD save, not simultaneous double-buffer video.

The committed profile remains 24 MHz/no PLL, four-channel DMA and no SPI.
Eight DMA channels, the Gen1 pin map, faster PCLK and new IP are target
contracts. This freeze does not change RTL, firmware, profiles, dependencies,
warning baselines, metrics policy or readiness. It does not implement a new
GUI framework or replace the legacy XPI LCD transport.

## Target SoCs and Integration Scope

| Item | Frozen contract |
| --- | --- |
| Target / status | TINY future standard product; MINI/STD/PRO integration deferred |
| Starting profile / PDK | `configs/ci/ihp130-tiny.mk` / IHP130, existing 24 MHz/no-PLL baseline |
| Product sources | `rtl/tiny/top`, `rtl/tiny/integration/soc_topology.json`, `clock_reset_domains.json`, `rtl/tiny/address_map/memory_map.json`, `rtl/tiny/pin_map/pin_map.json` |
| Filelists | Existing `rtl/tiny/filelist` ownership, especially `ip.fl`, `inc.fl`, `top.fl` and `tb.fl` |
| Instance / control | SPI0, APB4 `0x1001D000..0x1001DFFF`, 32-bit aligned control/FIFO words |
| IRQ / lifecycle | Tiny CPU IRQ25 and Tiny RCU target 16, additive allocations only |
| DMA | Shared V2.2, `SPI_TX=16`, `SPI_RX=17`, paced fixed-MMIO; no private AXI master or new stream endpoint |
| Pins | GPIO27 ALT0 SCK, GPIO28 ALT1 MOSI, GPIO30 ALT1 MISO, GPIO31 ALT1 CS_N; display uses GPIO30 ordinary output for D/C instead of MISO |
| Clock | PCLK for APB, core, packing/FIFOs and DMA pacing; SCK is an output, not an internal clock domain |
| SDK / application | New `rs_spi_*` freestanding HAL; Tiny display adapter in `app/board`, scenarios in existing application composition |

Preserve QFN64 and Pad count, 128 KiB main SRAM, same-frequency CPU/main-SRAM
SYS, private Crypto storage, eight-channel DMA target and three external AXI
owners. The two new 8x32 FIFOs contain 64 B local payload storage, not an
allocation from user SRAM. No managed dependency upgrade is approved.

The Gen1 map already moves legacy PWM capture from GPIO30/31 ALT1 to GPIO24/25
ALT0. SPI fills four reserved **Gen1** ALT cells only after TINY-R2-P6 implements
that routing. Current executable GPIO30/31 are not silently repurposed.
TINY-R2-P7 supplies qualified lifecycle/domain integration. Mini is a shared
DMA/GPIO compatibility consumer, not a new SPI product rollout.

R2's original performance-only scope and all TINY/PIOLITE phase IDs and titles
remain unchanged. This separate feature approval extends the future product.
Full extended-product release needs the actual SPI/PIO-inclusive netlist and
source evidence, not an earlier R2 result relabeled as covering new logic.

## Commercial References

The research was checked on 2026-10-04. Reuse architecture lessons, not vendor
RTL, binary ABI, clock limits, PPA figures or qualification claims.

| Primary reference | Evidence and selected lesson |
| --- | --- |
| [RP2040 datasheet, section 4.4](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf), build 2025-02-20 | Modes 0-3, 4-16-bit frames, separate 8x16 FIFOs and DMA demonstrate a small MCU controller. Its CPHA=0 hardware-CS word pulses are not adopted: Tiny CS is transaction controlled. Slave/TI/Microwire modes are outside this MVP. |
| [ST AN5543](https://www.st.com/resource/en/application_note/an5543-enhanced-methods-to-handle-spi-communication-on-stm32-devices-stmicroelectronics.pdf), Rev 5 November 2025 | Exact counters, FIFO/packing boundaries and distinct DMA versus BSY/EOT/TXC completion motivate explicit wire and transport status. Peripheral-clock arithmetic is not external-pad qualification. |
| [NXP MCXA153 SDK](https://mcuxpresso.nxp.com/mcuxsdk/latest/html/api/devices/MCXA153/index.html), SDK 26.09 | Continuous PCS, programmable CS delays, FIFO/DMA and separate completion events inform the transaction API. The current [MCX A data sheet](https://www.nxp.com/docs/en/data-sheet/MCXAP064M096F30.pdf), Rev 5.2 May 2026, makes SPI limits pad/mode dependent; those rates are not Tiny targets. Exact login-gated reference-manual stall semantics were not verified. |
| [Newhaven ST7789VI module](https://newhavendisplay.com/content/specs/NHD-2.4-240320CF-BSXV-FT.pdf), Rev 4 November 2023 | A 240x320 panel documents 4-wire 8-bit command/data SPI, separate D/C, optional MISO, reset and external backlight power. It provides a concrete 320x240 landscape RGB565 reference without promising pin-free reset/backlight/TE/readback. |

These vendor documentation/product families were active at the research date.
No reference establishes Tiny area, power, MTBF, Pad rate, display compatibility
or IHP130 timing closure. The existing [SPI-SD](spisd.md) is a mode 0 SD host
with its own protocol/private DMA, not this general SPI controller. Reuse
owned Common registers/FIFOs and single-clock phase-enable conventions without
changing SPI-SD or XPI's ABI or adopting their unrelated command machinery.

## Requirements and Non-goals

| ID | Normative requirement |
| --- | --- |
| SPI-01 | MUST provide one single-lane SDR master, modes 0-3, 8/16-bit frames, MSB/LSB first, TX-only, full-duplex and dummy-TX RX-only. |
| SPI-02 | MUST provide separate TX/RX 8x32 FIFOs, bounded APB access, exact packing/tail rules and CPU/DMA ownership. |
| SPI-03 | MUST run in PCLK, generate SCK with integer enables, count wire frames and distinguish segment, CS and DMA completion. |
| SPI-04 | MUST support retained-CS command/data segments with checked software D/C changes, no partial-frame starvation or fake data. |
| SPI-05 | MUST preserve the package and existing non-reserved Gen1 ALT assignments; native-ready and retained session ownership guard all activity. |
| SPI-06 | MUST use compatible DMA V2.2 requests 16/17, static discovery, source-qualified reserved MMIO credits and full job/descriptor drain. |
| SPI-07 | MUST expose a handwritten SVH/C ABI mirror, bounded `rs_status_t` HAL and static caller-owned buffers; preserve the old XPI LCD path. |
| SPI-08 | MUST close admission on error/abort, preserve accepted bus responses, retain ownership on timeout and require explicit recovery/reacquisition. |
| SPI-09 | MUST validate generic SPI and sequential QVGA capture/verify/display/SD data integrity without claiming a whole frame fits in main SRAM. |
| SPI-10 | MUST bind functional/performance/physical evidence to source, product, profile, PDK, clocks and board/slave constraints. |

DEFER slave, 9-bit/in-band D/C, three-wire bidirectional SPI, dual/quad, XIP,
CRC, I2S, multiple hardware chip selects, display command queues, strict
gapless SCK guarantees and autonomous low-power operation. Also defer
simultaneous capture/display, full-profile external PIO demonstrations,
SPI-specific burst-prefetch optimization, other PDKs and other SoC rollouts.
MUST NOT add a DMA channel/master or assume unused GPIO for reset/backlight/TE.
No architecture question blocks P1; unqualified operating points remain gates.

## Selected Architecture

### Module and data flow

Planned owned modules are `apb4_spi`, `spi_reg`, `spi_master_core`,
`spi_phase_ctrl`, `spi_word_packer`, `spi_dma_pacing` and `spi_gpio_guard`.
`spi_ctrl_if` is the new internal interface; do not repurpose the existing
SPI-SD `spi_if` contract. Names describe future sources, not current filelists.

CPU/DMA word ports feed TX FIFO and a low-lane-first unpacker, then an 8/16-bit
shifter and registered SCK/MOSI/CS outputs. The raw alternate MISO input enters
the controller's clock-enable capture path and RX packer/FIFO. FIFO payload
arrays are small local register/inferred stores; valid state, not reset of
every payload bit, hides old data. Synthesis must confirm the intended mapping.

CPU and central DMA are exclusive per FIFO direction. TX-only never places
MISO data in RX FIFO. RX-only generates the configured dummy frame and needs
no TX FIFO word. Full-duplex consumes and produces the same number of frames;
MISO must be enabled for either receive mode.

### Session, arm and segment sequencing

ENABLE establishes a latched session/pin reservation after native-ready checks,
drives CS inactive/SCK=CPOL and applies CS_INACTIVE before entering IDLE. This
initial GAP does not emit DONE. Configuration/pin preparation must
precede ENABLE. No FIFO transfer implicitly claims pins.

ARM latches FRAME_COUNT, frame width, direction, dummy value, HOLD_CS and FIFO
owners before any preload or DMA admission. It requires a positive count,
valid derived lengths, an IDLE or clean HELD boundary, empty FIFOs/packers and
fully drained old jobs/credits. TX-only requires RX binding off; RX-only
requires TX binding off. It resets per-segment counts and opens only the
directions the segment uses. CPU prefill and DMA start are allowed after ARM.

START accepts only ARMED, asserts CS if needed, applies setup delay and starts
the finite segment. It may wait for the first TX word or RX capacity without
generating clocks. Exactly FRAME_COUNT frames are transmitted. After the last
frame and hold time, SEGMENT_DONE is set. HOLD_CS=1 enters HELD with CS active;
HOLD_CS=0 deasserts CS, completes the inactive gap and sets DONE in IDLE.
END from a clean HELD boundary releases CS and applies the inactive gap.

Wire state and SEGMENT_PENDING are distinct. A segment remains pending after
its last wire edge while RX data, packers, FIFO data, DMA jobs, reserved credits
or accepted responses remain. It becomes clean only when its successful wire
completion and all data/transport obligations are satisfied. CPU RX service
and bound RX DMA may therefore continue after SEGMENT_DONE/DONE. A new ARM,
owner/configuration change, D/C change or END cannot bypass pending cleanup.

Across clean HELD boundaries only SEG_CONFIG, FRAME_COUNT, DUMMY and idle
DMA bindings may change. CPOL/CPHA, bit order, divider, all CS delays and
MISO-versus-display pin personality remain fixed for the session. Every
segment applies setup delay before its first edge, including held-CS segments,
so checked D/C changes can meet setup time. Segment hold time precedes
SEGMENT_DONE and also protects D/C hold. Software serializes the complete
session, not isolated FIFO writes; there is no hardware descriptor for D/C.

### Serial timing and starvation

DIV=N is 1..65535; `SCK_HZ=PCLK_HZ/(2*N)`. Outputs are registered in PCLK;
SCK is never used as an internal clock. The leading edge moves SCK away from
CPOL, and the trailing edge returns it. CPHA=0 presents the first MOSI bit
before the first leading edge, samples on leading edges and advances output
on trailing edges. CPHA=1 launches on leading and samples on trailing edges.
Both modes complete a frame only after exactly `2*FRAME_BITS` transitions,
including CPHA=0's final trailing edge after its final sample.

CS_SETUP, CS_HOLD and CS_INACTIVE are 1..65535 PCLK periods, reset 1. No first
SCK edge occurs earlier than CS_SETUP after START; frame preparation may add
delay, and each active half-period is at least N periods. The hold timer starts
only after the final trailing edge. CS_INACTIVE is counted from deassertion.
No output/clock edge is generated by a rejected command or timing write.

Before each frame reserve its complete TX data and potential RX word slot.
At a frame boundary, insufficient TX data or RX capacity pauses SCK at CPOL
with CS asserted; do not begin a frame that would later overflow its RX word.
The current frame never stretches internally because FIFO service is late.
RX-only can stall for RX capacity; TX-only ignores RX. Pauses can be arbitrarily
long until software timeout/ABORT, so devices with bounded interframe gaps
need separate qualification and are not promised gapless service.

FIFO eligibility uses pre-edge occupancy, without empty fall-through or full
look-ahead. At full, a push is ineligible even if a same-edge pop occurs; at
empty a pop is ineligible even if data arrives on that edge. At intermediate
levels simultaneous eligible push/pop preserves level and removes the old head.
STALL flags count waiting at frame boundaries, not intentional setup/hold gaps.

## Interfaces

### APB4 and source-qualified word ports

The APB4 target uses 32-bit data, little-endian aligned words, full-word writes
(`PSTRB=0xF`) and the repository registered response convention. Unmapped,
unaligned, partial-strobe, wrong-direction, reserved-bit and illegal-state
accesses return PSLVERR without the requested side effect. Reserved read bits
are zero. Each accepted access acts once, not once per cycle of PSEL.

FIFO accesses never wait for SCK or an external device. A CPU full-TX write or
empty-RX read returns bounded error. A qualified DMA access consumes its
reserved credit or error-completes if closing invalidated it; it cannot wait
for a future byte. This includes pending accesses at abort, allowing CPU
control and the central DMA's other writes to make progress.

Four aliases separate CPU_TXDATA/CPU_RXDATA from DMA_TXDATA/DMA_RXDATA.
Separation by address alone is insufficient. Tiny fabric/bridge integration
must deliver private latched request-origin qualification (CPU, central DMA,
other) to the SPI wrapper. CPU may use control/CPU ports but never DMA aliases;
central DMA may use only its properly credited DMA aliases; other origins
are rejected. Thus request 0 cannot bypass ownership through a CPU FIFO alias.

Capture origin with actual AXI admission, keep AW-origin associated with its
write data, and retain it through APB bridging, CDC and response backpressure.
Do not use a current arbiter grant, mutable channel register or untrusted
PPROT as origin. This private target qualifier adds no AXI master or ID and
does not replace the SoC's general access policy. P1/P2 test it as a standalone
interface; P3 must wire it through the real Tiny path before advertising DMA.

SPI has no AXI memory interface. Central DMA retains 32-bit data, at most one
read and one write outstanding, existing response/order rules and 4 KiB burst
boundaries. For this MVP, fixed-MMIO jobs retain the current single-beat policy
on both legs; a PSRAM source can incur one XPI serial setup per word. No
prefetch/stream performance is claimed by this document.

### Packing, quotas and tails

Derive in checked 64-bit arithmetic:

```text
payload_bytes   = FRAME_COUNT * (FRAME_BITS / 8)
transport_words = (payload_bytes + 3) / 4
transport_bytes = 4 * transport_words
```

ARM rejects zero count or transport_bytes greater than `0xFFFFFFFC`, before
changing state or authorizing payload. This applies to CPU and DMA modes so
register counters cannot wrap. Count `0xFFFFFFFF` is invalid in both widths:
even 8-bit mode rounds beyond 32-bit DMA capacity. TX-only has no RX quota;
RX-only has no TX quota. Enabled-direction quotas equal transport_words.

Each TX word supplies low byte first in 8-bit mode or low halfword first in
16-bit mode. Frame bit order is separately selected. RX places the first
received frame in the corresponding low lane. A final partial TX word's
unused lanes are ignored regardless of value and produce no extra frame or
clock. The final RX word zero-fills unused high lanes and is published after
its final frame completes; unused packer state is cleared at the boundary.

Accepted plus reserved TX words cannot exceed the segment quota. RX removals
cannot exceed produced words or its quota. CPU/DMA attempts beyond quota error;
surplus data cannot become the next segment's first word. Increment successful
CPU/qualified APB enqueue/pop counters once; credit reservations remain
separate from FIFO acceptance and release only with terminal bus completion.

DMA uses 32-bit width and transport_bytes, not the unrounded payload length.
Buffers must be 4-byte aligned with explicit accessible capacity at least
transport_bytes; TX padding must be initialized and readable, RX padding is
within caller-owned storage. Reject inadequate or unaligned DMA buffers; do
not implicitly overread, overwrite an adjacent object or allocate a hidden
whole-frame bounce buffer. CPU helpers handle arbitrary short 8/16-bit packets.

For RGB565, a low-halfword-first word contains pixel 0 in `[15:0]` and pixel 1
in `[31:16]`;16-bit MSB-first sends each pixel's high byte then low byte.
The panel still parses ordinary 8-bit data bytes with D/C high. Validate DVP
sensor byte-order configuration and host pixel layout instead of blindly
reusing the legacy LCD driver's high-halfword-first conversion.

### GPIO, board and D/C ownership

The fixed Tiny routes are 27/ALT0 SCK, 28/ALT1 MOSI, 30/ALT1 MISO and 31/ALT1 CS_N.
MISO_ENABLE reserves the receive route; DISPLAY_DC instead reserves GPIO30 as
ordinary push-pull software output. The two personalities are mutually
exclusive. Without either, TX-only SPI uses 27/28/31. Core route capability is
`0xD8000000`; the latched session mask reflects the selected personality.

Acquire via checked board/HAL ownership. Stop and drain conflicting PIO,
I2C alternate route, CLKOUT and XPI CS2/3 users; reject incompatible locks and
external drivers. Preserve GPIO29 NSS1 and dedicated boot/debug pins. Prepare
the prior native driver's OE inactive and SPI OE0 before changing ALT. GPIO's
automatic one-PCLK handoff applies to USER_SELECT transitions, not arbitrary
GPIO/ALT0/ALT1 changes; OUTPUT_ENABLE=0 alone does not disable an ALT driver.
Prepare safe CS-high/SCK-CPOL software fallback, change routes with drivers
disabled, and verify stable routing before ENABLE.

Read-only integration status must include USER_SELECT, USER handoff mask,
ALT_ENABLE/ALT_SELECT, relevant electrical/OE state and GPIO clock/reset
readiness. Native-ready for the session requires USER_SELECT=0 and handoff=0
on those pins, correct routes and push-pull drive (OPEN_DRAIN=0). Checking
USER_STATUS=0 alone is insufficient during USER-to-native handoff. D/C must
remain ordinary software output with OE enabled; its value is intentionally
mutable between clean segments, not an immutable guard field.

PIO remains the sole USER owner and retains mux priority; SPI is an ALT owner.
Continuous guards cover prefill, DMA-armed, active, held-CS and closing sessions.
Loss suppresses SPI's own OE/sampling, closes admission and latches fault;
another GPIO owner may still drive the pad, so this is not a claim that SPI can
force every owner high-impedance. Guard restoration never resumes stale work.

GPIO30 D/C changes occur through checked GPIO access only at a clean segment
boundary, with ordering/readback before the next START/setup delay. HAL owns
this ordering; arbitrary same-hart GPIO writes are not a security boundary.
GPIO interrupts/electrical changes on session pins require coordination.

The complete camera profile plus write-only display uses all 32 GPIO. General
SPI full-duplex and the write-only display are different pin personalities;
do not promise LCD MISO alongside D/C without another released pin. Reference
board reset is shared only with compatible panel power/reset timing; backlight
uses an external fixed current driver, not an SoC Pad. TE/touch/backlight PWM
are not MVP features. IHP130 lacks internal pull-ups: CS needs an external
inactive-high bias during reset and handoff. No board schematic is qualified
merely by this allocation.

## DMA and Interrupt Contract

### V2.2 and channel ownership

[DMA V2.2](dma.md#frozen-v22-spi-extension) is normative for shared
encoding: IP_VERSION `0x00020002`, `SPI_TX=16`/`SPI_RX=17` as MM_TO_MM, direct 5-bit
selector, TCD low request bits `[15:12]` plus high bit `control[25]`, unchanged
64 B TCD size/alignment/priority/burst fields. Request masks/status/support
become 32-bit;18..31 are reserved/unsupported. Requests 0..15 and PIO14/15 retain
meaning. SPI adds no stream endpoint, so the V2.1 stream-direction count stays
at most 7. Mini defaults SPI support off.

Probe DMA major 2/minor>=2 and the requested static support bit before writing
extended configuration or submitting a TCD. Older hardware can alias 16 to 0
or ignore bit 25; never rely on its eventual payload error. Old valid jobs
remain valid on V2.2; this is not forward compatibility of new jobs with V2.0.
No unknown future major is assumed compatible.

TX_BIND/RX_BIND each select one implemented channel and enable. Two enabled
bindings use distinct channels. Default TX borrows 3 only after bulk/PIO release;
RX borrows 2 only after DVP/PIO release. Full-duplex with active camera is not
required. Keep UART/I2C and Crypto/audio reservations; no hidden channel theft.
Binding changes require a clean IDLE/HELD boundary and complete old/new job
drain. An accepted DMA START locks the registered binding and rejects a
simultaneous rebind. The whole chain belongs to the SPI session, including
descriptor fetch/parse/suspend; it cannot contain another client's work.

SPI-P2 must inherit/implement the V2.1 complete descriptor-cancellation and
drain obligations; it need not wait for the whole PIO peripheral to be
integrated. This shared prerequisite does not mark PIOLITE-P3 complete.

### MMIO credits and completion

ARM fixes the enabled directions, FIFO owners and finite quotas. Only an armed
segment with valid GPIO/session state grants the bound channel SPI admission.
TX requires incrementing memory source and fixed DMA_TXDATA destination;
RX requires fixed DMA_RXDATA source and incrementing memory destination.
Addresses, 32-bit width, positive word-multiple count and remaining quota must
match. Other requests/channels targeting either DMA alias must be rejected,
not merely the wrong configuration of requests 16/17. Payload count across
the owned job cannot exceed the segment's remaining transport words.

Pacing readiness reserves one word at actual DMA transaction admission.
Exclusive ownership and pending-credit accounting preserve that slot/data
until the qualified APB access acts; the reservation remains tracked through
R/B completion. DMA's private address/request/channel check and the wrapper's
latched source qualifier must both agree. A credit is not permission for an
arbitrary CPU/SDIO access to consume it. Rebind/reset cannot occur while an
accepted request or its terminal response remains.

On close, stop new admissions. Already accepted writes/reads complete or
error-complete boundedly without waiting for serial data; do not fabricate RX
payload. Drain AXI/APB requests and responses plus descriptors before flushing
FIFO/packer state. This is fixed MMIO, not AXI4-Stream: no stream VALID reset
exception may replace accepted R/B completion.

Transfer success requires exact wire frames, exact word quotas, expected empty
tails, no error, and successful DMA completion including final memory responses.
Display D/C transitions also wait for this clean boundary. Transaction success
additionally requires DONE after CS release/gap. Failed partial buffers may
be reclaimed after full drain/recovery but cannot be published as valid data.

### IRQ and diagnostics

IRQ_STATE bits 0..5 are sticky SEGMENT_DONE, DONE, ABORTED, FAULT, TX_STALL and
RX_STALL. IRQ_ENABLE has the same bits plus bit 8 TX level<=TX_LOW and bit 9 RX
level>=RX_HIGH. IRQ_STATUS is the enabled sticky/level combination; its nonzero
value drives Tiny IRQ25. Watermarks are level conditions, not W1C state.
Hardware event set wins concurrent clear. RX discard does not set RX_STALL.
Mask IRQs while idle when a low-watermark condition would otherwise persist.

Expose live wire state, CS-active, session ownership, pending/clean segment,
GPIO readiness, quota/word/frame counts, FIFO levels, DMA jobs/credits,
first fault and saturating stall-cycle counters. A diagnostic read is live,
not a coherent multi-register snapshot; after completion/recovery software can
capture a stable result before beginning another segment.

## Register and Software ABI

### APB1.0 register map

Offsets below are hexadecimal relative to SPI0. Registers are 32 bits; reset
is zero except listed constants/defaults. RO writes/WO reads error. Reserved
offsets/bits error on writes and read bits are zero. Commands are one-hot WO
pulses; zero is a no-op, multiple command bits error without partial action.

| Offset | Name | Access / fields |
| --- | --- | --- |
| `000`, `004` | IP_ID, IP_VERSION | RO `0x53504930` (SPI0), `0x00010000` |
| `008` | CAPABILITY | RO bits 0 master, 1 full-duplex, 2 TX-only, 3 RX-only, 4 bit-order-select, 5 held-CS, 6 display personality, 8 frame 8, 9 frame 16; mode mask `[13:10]=0xF`; bit 7 DMA iff the complete integrated admission path is wired |
| `00C` | FIFO_CAPABILITY | RO TX depth `[7:0]=8`, RX depth `[15:8]=8`, word bits `[23:16]=32` |
| `010`, `014` | CLOCK_HZ, ROUTABLE_MASK | RO current PCLK Hz / Tiny `0xD8000000` |
| `018` | COMMAND | WO bits 0 ENABLE, 1 DISABLE, 2 ARM, 3 START, 4 END, 5 ABORT, 6 RECOVER, 7 RELEASE, 8 RESET |
| `01C` | STATUS | RO wire state `[3:0]`, CS_ACTIVE4, SESSION_OWNED5, SEGMENT_PENDING6, SEGMENT_CLEAN7, TX_WAIT8, RX_WAIT9, BUS_IDLE10, TRANSPORT_IDLE11, GPIO_READY12 |
| `020` | SESSION_CFG | RW CPOL0, CPHA1, LSB_FIRST2, MISO_ENABLE3, DISPLAY_DC4; bits 3/4 mutually exclusive |
| `024` | DIV | RW `[15:0]` 1..65535, reset 1 |
| `028`, `02C`, `030` | CS_SETUP, CS_HOLD, CS_INACTIVE | RW `[15:0]` 1..65535, each reset 1 |
| `034` | SEG_CONFIG | RW FRAME16 bit 0 (clear=8 bits), direction `[2:1]` TX_ONLY0/FULL_DUPLEX1/RX_ONLY2, HOLD_CS3 |
| `038`, `03C` | FRAME_COUNT, DUMMY | RW positive 32-bit frames / low 16 dummy; DUMMY reset `0xFFFF`, use low 8 for 8-bit frames |
| `040`, `044` | TX_BIND, RX_BIND | RW channel `[2:0]`, enable 31; disabled reset 0 |
| `048` | WATERMARKS | RW TX_LOW `[3:0]` 0..8, RX_HIGH `[11:8]` 1..8, reset `0x00000100` |
| `04C`, `050` | CPU_TXDATA, CPU_RXDATA | CPU-only WO push / RO pop, when that direction is CPU-owned and armed/pending |
| `054`, `058` | DMA_TXDATA, DMA_RXDATA | Qualified central-DMA-only WO push / RO pop with reserved credit |
| `05C` | FIFO_LEVELS | RO TX `[3:0]`, RX `[11:8]`, 0..8 |
| `060`, `064`, `068` | IRQ_STATE, IRQ_ENABLE, IRQ_STATUS | W1C sticky / RW mask / RO masked sticky+level |
| `06C`, `070` | FAULT_CODE, FAULT_FRAME | RO first low 8 code / completed-frame index at first fault |
| `074` | FRAMES_DONE | RO completed wire frames in current/last segment |
| `078` | TRANSPORT_WORDS | RO derived quota per enabled direction |
| `07C`, `080`, `084` | TX_WORDS_ACCEPTED, RX_WORDS_PRODUCED, RX_WORDS_REMOVED | RO successful FIFO events, excluding uncompleted reservations |
| `088`, `08C` | TX_STALL_CYCLES, RX_STALL_CYCLES | RO saturating 32-bit PCLK wait counters |
| `090` | SESSION_PINS | RO latched claim mask, retained through local disable/recovery until RELEASE |
| `094` | DMA_STATUS | RO bits 0 TX job, 1 RX job, 2 TX credit/response pending, 3 RX credit/response pending |
| `098` | PINS_READY | RO mask of session pins satisfying native/electrical/readiness checks |
| `09C` | PAYLOAD_BYTES | RO checked logical payload size for current/last segment |

Wire state encoding is DISABLED0, IDLE1, ARMED2, SETUP3, SHIFT4, HOLD5, HELD6,
GAP7, CLOSING8. SHIFT includes frame-boundary waits. BUS_IDLE means inactive
CS, SCK=CPOL and IDLE/DISABLED; HELD and ARMED are not lifecycle idle.
TRANSPORT_IDLE includes all bound jobs, pending DMA START/admission,
reservations, accepted requests and terminal responses, including descriptors.
It excludes the current CPU control access whose legality is being checked.
SEGMENT_CLEAN requires successful
wire completion and all enabled quotas fulfilled/removed, empty packers/FIFOs
and TRANSPORT_IDLE; before the first ARM, an empty session is also clean.

SESSION_CFG/timing writes require DISABLED, no session ownership and transport
idle. Segment configuration/bindings are writable in that initial state or a
clean IDLE/HELD session. FRAME_COUNT reset 0 is unconfigured; writing 0 or ARM
with invalid derived size fails. RESET defaults do not imply an armed segment.
WATERMARKS/IRQ controls remain writable while active. FIFO ports require the
correct source/owner and finite quota, and CPU ports reject CLOSING accesses.

ARM clears per-segment counts/packer state, not sticky IRQ history. Successful
FIFO access updates its counter once. Clear old event state deliberately before
ARM; clearing an event does not retire a pending segment or recover a fault.
Closing permits diagnostics/IRQ and recovery controls, not data/config/START.
Priority on a PCLK edge is system reset, new emergency guard fault, other
transfer fault/ABORT, accepted lifecycle/configuration command, then normal
wire/FIFO progress. Close prevents same-edge START or fresh DMA admission;
already accepted transactions from earlier edges remain drain obligations.
A FIFO request invalidated by close error-completes without its data side
effect. Valid accepted DMA admission wins only against a competing ordinary
rebind/idle command, which rejects; no speculative new binding authorizes it.

### HAL and compatibility

Handwrite future `spi_define.svh` and `crt/include/retrosoc/hal/spi_regs.h`,
with parity tests for offsets, fields, resets and enums. No register generator.
Use `crt/include/retrosoc/hal/spi.h` and matching HAL implementation ownership.
Product-generated presence, APB/IRQ/RCU wiring and SPI/DMA discovery must agree;
do not invent an ARCHINFO bit or probe an unmapped peripheral on old Tiny/Mini.

`rs_spi_*` APIs cover discovery/configuration, acquire/release, CPU or DMA
segment transfer, held-CS sessions, end, status, bounded wait and abort/recover.
They return `rs_status_t`, take caller-owned storage and `rs_timeout_t`, and
do not use heap, OS or hosted-library dependencies. Use RS_EINVAL for invalid
arguments/capacity/alignment, RS_ENOTSUP for absent/version/mode support,
RS_ETIMEOUT for wait expiry and RS_EIO for hardware/ownership failure. Report
busy/closing/lock detail through status without inventing a global status enum.

Frequency selection rounds DIV upward so actual SCK never exceeds the requested
rate or declared board/slave limit; reject an unrepresentable divider rather
than silently speeding up. Validate all 64-bit length/round-up arithmetic before
narrowing and before any DMA register write. Poll/IRQ helpers do not call DMA
APIs with unaligned or unpadded objects. Full-duplex RX draining must run while
TX progresses; waiting for all TX before reading RX can deadlock at FIFO full.

The Tiny ST7789VI adapter belongs in `app/board`; board reset/backlight policy,
panel initialization, rotation/address offsets and D/C belong there, not in a
generic bus HAL. Keep existing `crt/src/hal/lcd.c`, its GPIO2/XPI behavior,
240x135 board configuration and LVGL users unchanged unless separately scoped.
Do not copy that driver's ignored errors or pixel-halfword ordering. New
examples propagate every fallible result and use existing bringup/ci_smoke
composition, not a new APP or mandatory GUI/library dependency.

## Clock, Reset, CDC/RDC, and Lifecycle

All SPI state and pacing run in PCLK. CPU/SYS requests and source qualification
cross the existing domain bridge together. DMA payload reaches SYS through
its existing AXI bridge. MISO uses raw ALT input with controller-owned capture;
GPIO's two synchronizers plus registered filter/bypass path are not inserted
into this half-cycle timing path. There is no external internal-logic clock.

Constrain the generated SCK output and returned MISO against the selected
CPOL/CPHA/divider and board/slave timing: output Pad delay, clock flight time,
slave clock-to-data, input flight/Pad delay and setup/hold must fit the capture
window. Include CPHA=0 first-bit CS setup. A raw route or ideal digital BFM
does not establish synchronous external timing; do not mask it with blanket
false paths. PCLK 24/48/60 ideal SCK maxima 12/24/30 MHz are arithmetic ceilings,
not qualified read/write rates.

| Command / transition | Contract |
| --- | --- |
| ENABLE | DISABLED, unowned and clean only; verify native-ready, latch SESSION_PINS/SESSION_OWNED, enable inactive outputs and apply initial GAP before IDLE, without DONE |
| DISABLE | Clean IDLE only; CS inactive, no pending segment/jobs/credits/admission; revoke both bindings/grants, OE0 and DISABLED, retain session reservation until RELEASE |
| ARM / START | Clean boundary -> ARMED with latched finite quotas; ARMED -> SETUP/SHIFT; no implicit DMA or pin acquisition |
| END | Clean HELD only; release CS, apply inactive gap and set DONE; no new frame |
| ABORT | Any acquired nonclosing session; close admissions immediately, stop new frames, bounded phase-safe CS termination, enter CLOSING; repeated ABORT in CLOSING is idempotent |
| RECOVER | CLOSING only after CS inactive and complete transport drain; flush FIFO/packers/runtime/events/fault, disable bindings, enter DISABLED with configuration and session reservation retained |
| RELEASE | DISABLED, bindings/grants disabled, all jobs/credits/admission drained, FIFOs empty and verified GPIO handback; clear SESSION_OWNED/PINS, not another owner's GPIO configuration |
| RESET | DISABLED/unowned/transport-idle only; clear configuration/runtime/FIFOs/bindings/IRQ to reset defaults; complete its own APB response |

Normal ABORT during ARMED, setup, boundary wait, hold or HELD produces no new
frame; during SHIFT it finishes only the phase needed to return SCK to CPOL,
with no further receive sampling or next frame. Apply hold and inactive timing,
release CS and set ABORTED, never successful segment/transaction DONE. The
wire-close bound is at most `2*DIV + CS_HOLD + CS_INACTIVE + 2` running PCLK
cycles from accepted ABORT, independent of FIFO/DMA progress. Bus cleanup has
its own bounded software wait and external-response assumptions.

Ownership/readiness loss or unexpected reset is an emergency fault, not a
graceful waveform completion: suppress SPI OE/sampling immediately and allow
the invalid transaction to truncate. Set internal SCK=CPOL and CS inactive
without driving an unowned Pad, and mark invalid wire-close complete. RECOVER
may then run after transport drain even if the external route/readiness guard
remains invalid. It atomically disables active guard monitoring before entering
DISABLED, preventing the persistent fault level from re-entering CLOSING on
that edge. Intentional DISABLED handback is not an active-route fault.
Normal control remains reachable where
PCLK runs; closing accepted MMIO must error-complete, never await serial data.
After wire stop, abort only the bound DMA jobs and wait for payload plus
descriptor drain before RECOVER. Cancellation dominates descriptor activation.
Timeout retains the closed bindings/session and buffer ownership for later
recovery; do not reset the common DMA or reuse still-owned memory. Bound DMA,
MMIO-credit or internal quota/FIFO faults also close automatically through the
phase-safe wire-termination path; they do not require firmware to issue ABORT
before admission stops. Only ownership/readiness loss uses the emergency clamp.

Normal release disables SPI OE, sets native software GPIO OE0/ALT-disabled
fallback on the session mask, checks locks/readback/handoff, then RELEASEs
the reservation. A handback failure retains the safe reservation and returns
failure; do not reset GPIO to clear locks or automatically restart an old ALT
client. RECOVER cannot silently relinquish this ledger or enable a new session.
Do not escape CLOSING through DISABLE, START, event clearing or guard restoration.

GPIO gating/reset is vetoed by PIO USER ownership OR any latched SPI session,
including prefill, armed, held-CS, disabled-awaiting-release and closing states.
This applies to multi-target commands too. SPI target 16 gate/reset and PCLK
rate changes require released session, disabled core, inactive CS, no pending
segment or accepted transport. FIFO empty or DMA DONE alone is insufficient.
Recompute timing from CLOCK_HZ and reacquire/restart explicitly after change.

CPU-only WFI, debug halt and hart reset do not implicitly stop SPI or release
DMA memory. Restarted firmware must inspect/adopt/recover existing sessions
before programming them. A whole-system reset discards the whole traffic epoch,
clears ownership and forces user Pads high impedance; peripheral-local reset
cannot strand accepted traffic. Retain Tiny's staged local reset release.

## Errors, Recovery, Security, and Observability

FAULT_CODE values are 0 none, 1 native route/ownership lost, 2 GPIO readiness/reset
lost, 3 bound DMA error, 4 MMIO credit/protocol violation, 5 internal quota/FIFO
violation. First code and FRAMES_DONE index latch until RECOVER/RESET; for
simultaneous faults readiness precedes routing, then lowest remaining code.
Control/configuration APB misuse returns PSLVERR without changing the active
session unless it exposes an actual transport/guard violation. Fault/event
set wins clearing. Normal ABORT is reported separately, not as successful data.

TX/RX stall counters saturate and count PCLK cycles spent in the respective
frame-boundary wait. They measure service pressure, not fabricated byte-loss
counts. Snapshot output, exact pixel counts, DMA memory responses and error
state together determine valid results. A held-CS session is active even when
no clocks toggle and every FIFO is empty.

Origin-qualified FIFO ports protect functional ownership, not arbitrary
malicious firmware, secure boot or a complete bus firewall. Pin checks cannot
remove external electrical contention. No functional-safety, hotplug,
ESD/current-drive or security certification follows from this contract.

## MVP and Commercial-grade Roadmap

The exact MVP includes this master, GPIO/session guard, DMA V2.2 pacing,
freestanding HAL, independent protocol tests and the sequential display path.
Use the ST7789VI-style four-wire mode with software 8-bit commands and 16-bit
MSB-first RGB565 pixel frames, CS preserved across the command/data boundary.
The panel interprets two ordinary data bytes per pixel, not a new 16-bit panel
interface. Verify the selected panel's initialization and landscape offsets;
do not reuse 240x135 constants for the 320x240 reference.

First display color bars, gradients and odd-width/odd-pixel rectangles. Then
capture a 320x240 RGB565 frame (153600 bytes) to initialized, capacity-checked
XPI NSS1 PSRAM, wait for valid DVP frame and final DMA writes, verify/read back,
display that immutable buffer, and save/check the SD data sequentially. The
panel BFM's pixel stream must match the intended frame and the saved data.
Use bounded line/processing workspaces; do not allocate a 150 KiB main-SRAM frame.
Camera/audio exclusion and all existing pin/channel owners remain in force.

Measure actual SCK, frame time, CPU cycles, payload utilization, FIFO levels
and longest DMA stall for SRAM and PSRAM sources. At the ideal 12/24/30 MHz
serial rates, raw payload ceilings are 1.5/3/3.75 MB/s and the QVGA pixel-only
times are 102.4/51.2/40.96 ms; real transfers are slower. These are bounds, not
FPS guarantees or evidence that those physical clocks work.

Later changes may qualify double-buffer capture/display, SPI_TX memory burst
prefetch, tighter interframe deadlines or richer panels. They require an
explicit new performance/scope decision. Do not hide them inside P1-P5 or
claim the full camera/display pin profile has spare external PIO pins.

## Verification and Software Validation

The [verification ledger](spi-verification.md) maps requirements to directed,
randomized, formal, host, integration and physical cases. P1 supplies the
standalone APB/core reference behavior and independent pin BFM; P2 covers DMA
encoding/credits/cancellation; P3 covers actual source qualification and GPIO
handoff; P4 covers firmware and the sequential application.

Required coverage includes all modes/widths/bit orders; first/final edges;
DIV and CS-count boundaries; counts 0/1 and rounding overflow; nonzero TX tail
padding and zero RX tail; exact FIFO quotas; separate source/owner errors;
stall/resume without mid-frame stretch; held CS and 8-to-16-bit transitions;
DMA_DONE before wire end and RX B-response after it; ABORT at every state;
descriptor fetch/parse/activation cancellation; lost route/readiness, lock
failures, retained session after recovery and unrelated-channel/PIO progress.

New self-owned C follows MISRA C:2012 Amendment 2 with no deviation approved
here. Host-test deterministic packing/length/divider/session logic. Preserve
managed panel/library boundaries and avoid unnecessary dependencies. Tiny
firmware success requires exit 0, SYSCTRL TEST_STATUS/`SIM_TEST_PASS` and no
`FAILED`, `FATAL`, `assertion failed`, `%Error`, `SIM_TEST_FAIL` or
`SIM_TEST_TIMEOUT`; UART boot text is diagnostic only.

After relevant phase approval, use existing tooling plus the tests added by
that phase, not invented already-working SPI Make targets:

```sh
ruff check .
python3 -m pytest -q
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130-tiny.mk firmware
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --dry-run
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY
python3 scripts/regress.py --root . --suite nightly --soc TINY
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI
```

Both Verilator and Icarus must exercise independent pin-level models. Existing
Tiny profiles do not acquire new IP merely because these commands parse.
Missing R2 prerequisites, unavailable tools/models and skipped cases remain
explicit gaps, not substituted products or passing tests.

## Synthesis, Timing, and Physical Evidence

Record source SHA, lock/config digests, TINY/IHP130 variant, PCLK/SYS/MEM,
serial divider/mode/direction, Pad/board/slave loads and payloads for every
measurement. Require block/full synthesis, register/FIFO mapping, area/cells,
reset fanout/release, netlist simulation, CDC/RDC, PVT/MMMC and extracted STA.
Qualify SCK/MOSI/CS/D/C output and MISO return timing, simultaneous switching,
external CS bias, QFN64 routing and power. Review DFT/storage-test coverage;
no inferred-FIFO MBIST/ECC or production silicon status is implied.

PCLK 24 is the executable starting frequency, not existing SPI timing evidence;
48/60 require the corresponding R2 platform and physical inputs. Keep CPU/main
SRAM same-frequency qualification and existing XPI MEM constraints intact.
SPI-P5 may share a campaign with TINY-R2-P11 and PIOLITE-P5 only when the same
complete source/netlist/configuration satisfies all contracts. Missing Pad,
SRAM, clock, vendor or board evidence remains blocking for the affected claim.
Do not alter observe-mode metrics or warning baselines through this freeze.

## Development Order

Every phase targets TINY. Mini testing is shared-IP compatibility, not a rollout.
Stable IDs/titles below do not rename, reuse or advance R2/PIO phases.

| ID / title | Dependencies, scope and completion |
| --- | --- |
| SPI-P0 - Contract and DMA Extension Freeze | Approved research; freeze this specification/ledger, Tiny resources/routes, DMA/GPIO contracts and indexes. Validate links/commands/consistency/whitespace only; no implementation result. |
| SPI-P1 - SPI Core and Register Implementation | P0; owned master/APB/packing/phase/guard interfaces, register mirror and standalone protocol/negative tests. All four modes, widths, ordering, quotas, held-CS lifecycle, lint/style/formal and block-synthesis evidence. No real Tiny capability until wiring exists. |
| SPI-P2 - DMA V2.2 Paced FIFO Integration | P1 and V2.1 cancellation/compatibility obligations, implemented here if not already delivered;5-bit encoding, port/source-qualified credit interfaces, exact packing/counts, jobs/drain and old-Mini regression. Retain single-beat MMIO policy; no PIO peripheral completion prerequisite or hidden burst optimization. |
| SPI-P3 - Tiny GPIO RCU and SDK Integration | P2 plus applicable TINY-R2-P6/P7; topology/address/IRQ/RCU/filelists, four Gen1 ALT additions, latched source qualifier through fabric/CDC, GPIO readiness/ownership, bounded HAL. Firmware/simulations and unaffected Mini/PIO compatibility; no layout/source swap of legacy LCD. |
| SPI-P4 - Display and Snapshot Application Qualification | P3; board display adapter, independent panel/data oracle and three stages of display patterns, PSRAM-source display and sequential camera/verify/display/SD. Camera/PSRAM cases require R2-P8/P9. Both simulators, host boundaries, error recovery and current-source regression/measurements pass. |
| SPI-P5 - IHP130 Timing and Physical Qualification | P4 and applicable R2 system/PIO-inclusive product prerequisites; complete-netlist synthesis/netlist/STA/CDC/RDC/physical/Pad campaign. Publish only measured qualified operating points with residual gaps, optionally joint R2-P11/PIOLITE-P5. |

### Next-phase preflight handoff

```text
Use $retrosoc-feature-implementation. Stage: preflight. Feature slug: spi. Target SoCs: TINY.
Phase: SPI-P1 - SPI Core and Register Implementation.
Read docs/ip/spi.md and docs/ip/spi-verification.md. The executable starting profile is configs/ci/ihp130-tiny.mk, PDK IHP130, 24 MHz/no PLL; it has no SPI integration yet.
Plan only the frozen standalone master/APB1.0 core, packing/phase/lifecycle and source-qualified interface contracts, handwritten SVH/C parity, reference behavior, independent pin BFM and focused tests. Preserve all modes/8-16-bit packing, FIFO sizes, exact quotas, CS/D-C boundaries and bounded close/recovery semantics.
Do not implement DMA V2.2, Tiny routing/RCU/fabric integration, the SDK/display application, new profiles or later phases. Do not change the frozen ABI, increase storage/pads, alter the legacy XPI LCD path, upgrade dependencies, change quality policy, commit or push. Return SPEC_CONFLICT rather than weakening an unmet contract, and provide the scoped preflight and validation plan for explicit approval before implementation.
```

## Commercial Delivery Gaps

At freeze there is no SPI controller, DMA V2.2 implementation, origin-qualified
Tiny path, HAL/display adapter, independent panel model or SPI performance
evidence. Coverage closure, reset/CDC/RDC/DFT, extracted timing, power/Pad/board
qualification, release artifacts and silicon validation remain required. A
documentation freeze is not RTL freeze, physical signoff or approval to advance
implementation stages. No MISRA deviation, new PDK or safety/security claim is
granted here.
