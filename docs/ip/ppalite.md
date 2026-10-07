# Tiny PPALite Streaming Pixel Processor

## Purpose and Research Boundary

This is the approved `ppalite` specification freeze dated 2026-10-05 for
**TINY only**. PPALite is a future standard Tiny feature, not implemented
hardware, measured performance or silicon qualification. PPALITE-P0 is a
documentation gate; later phases require separate approval and evidence.

PPALite reduces camera data before its first memory write: select pixels and
lines, extract Y from YUV422, normalize RGB565 ordering, and pack aligned
output rows. It is not a memory-to-memory graphics engine. The authoritative
inputs are [Tiny](tiny-soc.md), [DVP V2](dvp.md), [DMA](dma.md), [SPI](spi.md),
[PIO-lite](piolite.md), [engineering](../engineering.md) and the
[owned RTL policy](../rtl-coding-style.md). Mini's [GA2D](ga2d.md) private
AXI64/two-dimensional DMA architecture is not imported.

This freeze changes documentation only. It does not change RTL, firmware,
configuration, dependencies, warning baselines, metrics policy or readiness.
The executable Tiny baseline remains 24 MHz/no PLL, four DMA channels and no
PPALite. Source qualification gaps below remain explicit prerequisites.

## Target SoCs and Integration Scope

The [2026-10-07 Tiny refreeze](tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07)
selects default TINY/ICS55, `HAVE_PLL=YES`, SAFE24 boot, retaining IHP130
compatibility. `configs/ci/ics55-tiny.mk` is planned, not executable until
TINY-ICS55-P1. Existing commands below retain their IHP130 scope. Pre-final
post-synthesis timing is observational; source integrity, functionality,
protocol, synthesis/mapping and netlist-function gates are unchanged.
PPALITE-P5 joins R2-P11, SPI-P5 and PIOLITE-P5 after all functional stages on
one complete-product netlist. Phase IDs/titles, including historical IHP130
titles, and prior evidence remain intact. No processor integration is delivered
by this platform/timing refreeze.

| Item | Frozen boundary |
| --- | --- |
| Target / deferred products | TINY future standard product; MINI/STD/PRO integration deferred |
| Default target / planned profile | ICS55, `HAVE_PLL=YES`, SAFE24 boot; `configs/ci/ics55-tiny.mk` pending TINY-ICS55-P1 |
| Starting profile / PDK | `configs/ci/ihp130-tiny.mk`, IHP130, existing 24 MHz/no-PLL baseline |
| Product ownership | `rtl/tiny/top`, `rtl/tiny/integration/soc_topology.json`, `rtl/tiny/integration/clock_reset_domains.json`, `rtl/tiny/address_map/memory_map.json` and existing product filelists |
| Shared source | `rtl/ip/multimedia/axi4s_dvp.sv`, `dvp_core.sv`, `dvp_reg.sv`; DVP V2 APB/stream contract and existing 512 B payload CDC FIFO |
| Control / IRQ / RCU | APB4 `0x1001E000..0x1001EFFF`, Tiny CPU IRQ27, RCU target 17 |
| Data path | DVP PCLK output -> exclusive RAW/PROCESS route -> existing `DVP_RX=11`, central DMA channel 2 -> SRAM/qualified XPI PSRAM |
| Clock | PCLK throughout PPALite, including control, buffers, formatter and route; existing DVP PIXCLK CDC remains upstream |
| Software | New `rs_ppalite_*` HAL; shared DVP/DMA lifecycle helpers; application-owned display/save adapters |

Preserve QFN64, every Pad/pinmux assignment, 128 KiB main SRAM, CPU/main-SRAM
same-frequency SYS, private Crypto storage, eight-channel DMA target and three
external AXI owners. No DMA request, channel, master, stream endpoint or
external pin is added. PIO requests 14/15, SPI requests 16/17, all existing
register/descriptor encodings and the stream-direction count remain unchanged.
Mini must retain its RAW DVP integration and receive affected shared-IP
compatibility tests, not PPALite capability.

TINY-R2-P6/P7 provide platform/DMA/clock/reset prerequisites. R2-P8/P9 provide
qualified PSRAM and camera integration; accepted fixes may satisfy the source
requirements here without duplicate work. Existing TINY, R2, PIOLITE and SPI
phase IDs/titles remain unchanged. The original performance-only R2 exclusion
of new accelerators remains historical scope; this separate approval extends
the future standard product and cannot retroactively expand old evidence.

## Commercial References

Research was checked on 2026-10-05 using primary sources. Reuse functional and
lifecycle patterns, not vendor RTL, register encodings or qualification claims.

| Reference | Evidence and selected reuse boundary |
| --- | --- |
| [STM32F446RE product](https://www.st.com/en/microcontrollers-microprocessors/stm32f446re.html) and [data sheet](https://www.st.com/resource/en/datasheet/stm32f446re.pdf), DS10693 Rev 11 | Active/in-volume-production MCU with 128 KiB SRAM provides a closer resource-class comparison. Its [official DCMI extension interface](https://raw.githubusercontent.com/STMicroelectronics/stm32f4xx-hal-driver/master/Inc/stm32f4xx_hal_dcmi_ex.h) exposes byte and line selection. Reuse selection before memory traffic; do not import pin availability, clock rates or its DMA ABI. |
| [ESP32-P4 PPA programming guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32p4/api-reference/peripherals/ppa.html), stable documentation served as ESP-IDF v6.1 | Memory-picture scale/rotate/mirror, blend and fill use explicit geometry, buffer rules and transaction completion; performance depends on shared PSRAM bandwidth. Reuse checked sizes and ownership, not bilinear scaling, large graphics scope, caches or vendor throughput. |

These official product/software resources were available at the research date.
The ST camera application-note/full reference-manual retrieval was incomplete;
the verified byte/line-selection claim is grounded in the official HAL header,
not an uninspected timing chapter. No comparable Tiny block area, power,
CDC/RDC, external-camera timing or PVT qualification is established by either
reference. Larger PPA/PXP/GA2D capability is a separate roadmap, not this MVP.

## Requirements and Non-goals

| ID | Normative requirement |
| --- | --- |
| PPL-01 | MUST process one camera stream and one finite frame at a time in PCLK, after the existing DVP CDC and before the first memory write. |
| PPL-02 | MUST preserve reset-default RAW bypass and select PROCESS exclusively; no simultaneous RAW/processed fanout or extra DMA endpoint. |
| PPL-03 | MUST support the frozen YUV luma/RGB565 matrix, explicit byte/channel order, independent 1/2/4 sampling steps and legal phases. |
| PPL-04 | MUST validate input framing, consume dropped pixels/lines, pad each output row independently and report exact logical/transport layout. |
| PPL-05 | MUST use exact direct `DVP_RX=11`/DMA2 admission for PROCESS and preserve RAW request/descriptor behavior. |
| PPL-06 | MUST separate pipeline completion from valid-frame publication and preserve source error observation through finalization. |
| PPL-07 | MUST close admission, drain accepted traffic and isolate before source abort/flush; timeout retains ownership, never fabricates data or resets unrelated DMA. |
| PPL-08 | MUST expose a handwritten APB/SVH/C ABI, truthful discovery, bounded freestanding HAL and deterministic reference-model/host tests. |
| PPL-09 | MUST preserve all product Pad, SRAM, clock, master/channel and earlier feature/phase boundaries. |
| PPL-10 | MUST qualify source correctness, data integrity, raw-rate FIFO budgets and source-bound physical evidence separately. |

DEFER memory replay/CPU-fed production input, multiple outputs, RGB-to-gray
arithmetic, full YUV-to-color conversion, arbitrary scaling, interpolation,
averaging/antialiasing, convolution, rotation/mirroring, blend/fill, Bayer,
RGB888, YUV420, JPEG, line/frame RAM, descriptor queues, lossless continuous
video, simultaneous capture/display, other SoCs and other PDKs. Do not add
general graphics acceleration or change the selected DVP/SPI roles implicitly.
There is no unresolved architecture choice blocking P1; absent integration
and qualification remain explicit phase gates.

## Selected Architecture

### Hierarchy, buffering and processing order

Planned owned modules are `apb4_ppalite`, `ppalite_reg`, `ppalite_core`,
`ppalite_stream_guard`, `ppalite_decimator` and `ppalite_packer`. A Tiny-owned
`ppalite_route_ctrl` contains the retained source selector, capture ownership
and DVP/DMA lifecycle guards. Use a dedicated `ppalite_if` and handwritten
`ppalite_define.svh`. These names describe future files, not current sources.

The processor uses two 32-bit input slots, an 8x32 output FIFO and a 32-bit
packing register plus small pixel/control registers and sidebands. No complete
line or frame is stored locally. These are explicit small inferred/register
storage exceptions, not allocations from the 128 KiB user SRAM. Follow Common
register/FIFO conventions and verify actual synthesis mapping. Reset/flush
validity and pointers so stale payload is inaccessible; no security-erasure
claim follows from logical clearing.

The order is input-word validation, chronological pixel decode, line/pixel
selection, format normalization/conversion, output-byte ordering, row packing
and output FIFO. Skipped data still advances input geometry and error checks.
The design target is one logical pixel per PCLK in steady-state service with
input available and output capacity. It is not one 32-bit input word per
cycle: a full input word contains two pixels. Measure row-boundary overhead
and stalls separately rather than converting the target into a camera FPS.

### Format matrix

Processing mode requires DVP `BYTE_SWAP=0` and `PIXEL_SWAP=0`. DVP FORMAT must
be RGB565 for RGB input or YUV422 for the four YUV layouts; source geometry,
crop and format must agree with the PPALite configuration snapshot.

With these DVP settings, chronological sensor bytes `b0, b1, b2, b3` appear as
`TDATA={b2, b3, b0, b1}`: the first two-byte pixel is the low halfword and its
first sensor byte is `[15:8]`. Do not assume sensor byte 0 is memory lane 0.

| Input encoding | Output | Exact operation |
| --- | --- | --- |
| RGB565_BE=0 | RGB565 | First sensor byte is pixel bits 15:8; normalize optional input R/B exchange, then select and pack |
| RGB565_LE=1 | RGB565 | Swap bytes within each input pixel first, then optional R/B exchange, select and pack |
| YUYV=2 or YVYU=4 | GRAY8 or gray RGB565 | Extract Y from `[15:8]` and `[31:24]` of a full DVP word |
| UYVY=3 or VYUY=5 | GRAY8 or gray RGB565 | Extract Y from `[7:0]` and `[23:16]` of a full DVP word |

RGB input to GRAY8 is invalid. RGB input R/B exchange swaps the two five-bit
channels while preserving G6; it is not a color-space matrix. YUV modes
discard chroma and do not expose a processed YUV output. Preserve the unsigned
Y value exactly, including a sensor's limited-range values; do not silently
expand 16..235, apply gamma or claim BT.601/BT.709 conversion.

Gray RGB565 is `((Y >> 3) << 11) | ((Y >> 2) << 5) | (Y >> 3)`.
It still costs two bytes per pixel. Canonical RGB565 output stores the first
pixel in the low halfword with its low byte in the low memory lane. Optional
output byte exchange reverses bytes within each RGB565 pixel only; it never
reverses pixel or row order. RGB_SWAP is legal only for RGB inputs and output
byte exchange only for RGB565 output; unsupported combinations error.

### Geometry and fixed sampling

DVP owns the rectangular crop. PPALite INPUT_SIZE is the active post-crop
width/height, each 1..65535. Source crop coordinates remain DVP coordinates;
PPALite X/Y and sampling phase start at the first cropped pixel/line.

STEP_X and STEP_Y independently select 1, 2 or 4. PHASE_X/Y are less than both
the corresponding step and actual input dimension. Select coordinates
`phase + k*step` while less than the input dimension. Thus:

```text
out_w = ceil((in_w - phase_x) / step_x)
out_h = ceil((in_h - phase_y) / step_y)
```

Default step 1/phase 0 retains every pixel. Selection is nearest retained-sample
decimation, not interpolation, averaging or alias suppression. Every input
pixel and every cropped line, including discarded trailing lines, must still
be consumed and validated. When no output is pending or needed, a deasserted
downstream TREADY must not prevent finishing discarded input after DMA has
already accepted the complete smaller output image.

## Interfaces

### Input stream and source prerequisites

Input is the existing PCLK DVP AXI4-Stream:32-bit data, TKEEP/TSTRB, TUSER[0]
SOF, TLAST EOL and zero ID/DEST. Validate on accepted beats before publishing
their pixels. SOF is required on exactly the first input word; TLAST must
match the last word of each configured active line. A full two-pixel word
requires KEEP=STRB=0xF. Only the final word of an odd-width line may use 0x3;
its upper halfword is ignored. Other masks, mismatched strobes, extra/missing
SOF/EOL, lines, pixels or data after the expected image fault the capture.
After the last expected input word has been accepted, any additional asserted
input VALID is an excess-data fault even if the processor has deasserted
TREADY. Do not hide a trailing extra beat behind input-complete backpressure.
The failed beat follows the isolated cleanup boundary; it is never transformed
into another output row.

An odd cropped YUV width is legal for Y extraction because chroma is discarded;
the physical sensor must still produce its declared valid YUV422 raster.
A legal 16-bit line tail is not a partial sensor pixel. A 16-bit pixel with
only one sensor byte is a source PARTIAL error and cannot be repaired by padding.

PPALite cannot see sensor bytes discarded before the DVP stream. Source
qualification therefore MUST close or reuse verified fixes for these current
implementation gaps before claiming integrated support:

- `dvp_core.sv` currently marks SYNC/SIZE/PARTIAL paths reserved and forces
  those flags low. Detect malformed raw lines/frames and incomplete pixels,
  including events outside a selected crop; do not substitute downstream counts.
- The current word statistic is only 16 bits in the core/status packet, despite
  a 32-bit software register. Preserve exact counts for accepted profiles,
  including VGA's153600 raw words; correct internal width/CDC transport rather
  than accepting wrap or weakening the expected count.
- Verify coherent PCLK active/configuration/command/statistics handshakes,
  every repeated frame event, snapshot rearm behavior and error clearing.
  A stale event or unsynchronized idle observation cannot authorize routing.
- The current convenience helper aborts before awaiting DMA completion.
  Correct success-path stop/drain ordering and provide a checked non-flushing
  stop after the snapshot boundary; ABORT/FLUSH is not successful completion.

These are source-correctness obligations in P2, not new DVP formats or a larger
FIFO. Preserve DVP V2 register offsets/meanings, pixel payload contract and
512 B capacity, with affected Mini regression. Already accepted R2-P9 fixes
may supply evidence; their existence must be verified on the current source.

### Output rows and layout

Output is the same 32-bit stream shape. Use KEEP=STRB=0xF on every beat and
ID/DEST=0. TUSER[0] marks the first word actually emitted, even if leading
input lines are discarded. TLAST marks the final padded word of each retained
row; it is not end-of-frame for DMA. Do not emit a row tail before consuming
and validating the complete corresponding input line, including dropped pixels.

GRAY8 packs the first selected sample into bits 7:0, then successive byte lanes.
RGB565 packs the first selected pixel into bits 15:0, then bits 31:16, after any
explicit output byte exchange. At each retained EOL, zero-pad high unused
lanes, emit the final complete word and clear the packer. Never carry pixels
or padding across a row boundary.

Calculate in checked 64-bit arithmetic:

```text
row_bytes       = out_w * bytes_per_pixel
stride_bytes    = 4 * ceil(row_bytes / 4)
valid_bytes     = row_bytes * out_h
transport_bytes = stride_bytes * out_h
dma_words       = transport_bytes / 4
input_words     = ceil(in_w / 2) * in_h
```

Reject zero dimensions, invalid phases, transport_bytes greater than
`0xFFFFFFFC`, insufficient capacity or address addition/range overflow before
ARM or DMA programming. The destination is word-aligned; prefer 64-byte frame
alignment where the selected memory/burst policy permits. Allocation includes
all row padding, not only valid_bytes. Actual SRAM/initialized PSRAM capacity
and serial-boundary rules remain independent checks. Pixel/word/line counters
must not wrap on any accepted geometry; logical byte products may need 64 bits.

Input slots and output FIFO use pre-edge occupancy, without empty fall-through
or full look-ahead. Valid output and all sidebands remain stable under
backpressure. No full FIFO overwrite, fabricated source bytes or filler output
to satisfy an oversized DMA transfer is permitted.

### APB4 and configuration ownership

APB4 uses 32-bit aligned little-endian registers and full-word writes
(`PSTRB=0xF`). Unmapped, unaligned, partial-strobe, wrong-direction, reserved
field and illegal-state accesses return bounded PSLVERR without the requested
side effect. Reads of WO and writes to RO error. No APB access waits for a
sensor clock, FIFO data or DMA completion. There is no production CPU input
or output pixel port; standalone tests drive the stream interface instead.

The Tiny DVP integration guard exposes coherent host-side configuration,
pending-command/CDC state, active/enable, FIFO/stream state, frame statistics
and errors. Processing ARM freezes the source geometry/format/crop snapshot.
While capture-owned, reject DVP geometry/format/stream changes and premature
ABORT/FLUSH; allow only the ordered enable, non-flushing boundary stop and
isolated cleanup operations below. Preserve diagnostic reads. The guard
interprets requested updates with their strobes; it does not repurpose DVP
register bits. Mini/default RAW behavior remains unaffected.

An accepted DVP configuration/command update or pending CDC exchange takes
precedence over a competing PPALite ARM, which rejects. Once ownership is
latched, prohibited source mutations reject without changing the snapshot.
An actual source reset, configuration mismatch or error closes the capture.
This coordination is functional ownership, not protection against arbitrary
malicious same-hart firmware or an IOMMU.

## DMA and Interrupt Contract

### RAW and PROCESS routing

Reset-default RAW directly preserves DVP data, sidebands and backpressure to
the existing DMA DVP port. It does not run a PPALite conversion or create PPA
interrupts. Raw odd-width DMA rejection remains unchanged. Only PROCESS
normalizes partial row tails into full DMA words. No RAW/processed fanout.

A route **change** requires source enable cleared and acknowledged, source
idle, configuration/command/statistic/flush exchanges complete, empty DVP and
PPALite FIFOs/packers, no held stream beat, no capture owner and **all central
DMA jobs and pending admissions/descriptors/responses idle**. Checking only
the currently decoded request is insufficient because a TCD may later select 11.
An accepted DMA START on the same edge wins; the route write errors and the
registered selector remains unchanged. A same-value route write is a no-op.

The selector remains fixed through a complete capture and recovery. It may
stay PROCESS between frames, so configuration/ARM/release within that mode
requires only the associated source/channel/endpoint to be idle; unrelated
DMA jobs may continue. Returning to RAW is an explicit route change with the
full barrier, not an implicit side effect of successful capture or RECOVER.

Legacy RAW helpers must check product metadata and selected route and return
RS_ENOTSUP before programming a processed capture. Absent PPALite means normal
RAW behavior without probing an unmapped address. Raw bypass and existing Mini
request/channel behavior remain usable without programming PPALite.

### Processed DMA admission

PROCESS MVP uses one exact direct STREAM_TO_MM job on channel 2/request 11,
32-bit width, fixed/unused stream source 0, incrementing aligned memory
destination equal to the latched DESTINATION and BYTE_COUNT=transport_bytes.
The armed job must fit CAPACITY_BYTES and its checked address extent.
Processed TCD jobs are deferred;
reject them before fetch/payload admission on the reserved channel. RAW direct
and TCD capabilities keep their previous meaning. PIO/SPI cannot borrow 2 while
this camera session owns it; other existing channel owners are unchanged.

The integrated DMA receives a private route/armed/channel/length admission
guard. In PROCESS only an armed PPALite capture may admit request 11, only on
channel 2 with the exact current-job parameters. Reject other channels, wrong
kind/count/direction and repeated starts before payload. Latch a current-job
admission token; stale DMA DONE from a previous transfer is never completion.
Prepare/reset the idle channel and its exact direct configuration before ARM.
ARM rejects a busy channel, pending channel 2 admission or mismatched shadow
configuration. An accepted channel 2 START wins a competing ARM, which rejects.
After ARM, reserve the entire channel through RELEASE/RECOVER, not only its
request 11 service interval: other requests must not start there or overwrite
its configuration/completion state after the payload job finishes. Only the
single matching START and prescribed closing ABORT/drained RESET are allowed;
diagnostic/IRQ access remains available. Capture release does not reset or
reserve another client's channel 2 use after ownership is relinquished.
Whole-job drain includes pending starts, accepted memory work and descriptor
state, using the already required V2.1 cancellation fixes. The complete Tiny
standard product also retains SPI's V2.2 extension.

This integration adds no DMA register, request number, descriptor field,
stream-count encoding or AXI master. `SUPPORTED_REQUESTS[11]` remains static
camera-endpoint support; it is not the selected format or route. Query PPALite
discovery/ROUTE for processing support. No new DMA ABI version is assigned
solely for this private integration guard; capability must remain absent until
the guard and its rejection/drain paths actually exist.

Memory output retains the central DMA's aligned INCR bursts, at most 16 beats
and 4 KiB boundaries, and the selected target's stricter limits. PPALite is not
the SPI fixed-MMIO path and does not inherit its single-beat restriction.
TLAST is diagnostic EOL, not transfer termination. SRAM/PSRAM writes become
complete only after all destination responses. CPU buffer ownership and
`fence rw, rw` remain mandatory; no cache, coherence or external-RAM boot policy
is introduced.

### Completion and interrupts

PIPE_DONE requires every expected cropped input line/pixel consumed and
validated, including trailing discarded lines, and every derived output word
handshaken to DMA. It may precede sensor frame end or final memory responses.
DMA may finish earlier than input draining when the final input rows are dropped.
Neither event alone permits buffer publication or a new capture.

FINALIZE additionally requires the current source frame completion/statistics,
an acknowledged non-flushing source stop, empty source/pipeline endpoints,
matching raw source counts, no DVP/PPALite/owned-DMA/target error and exact
successful DMA completion including final B responses. Source LINE_COUNT is
the full sensor frame height, not cropped height; PIXEL_COUNT and WORD_COUNT
describe selected DVP pixels/words. Compare these meanings correctly with the
source snapshot. Frame sequence must advance exactly once modulo 32 bits.
Keep observing late source errors until this validation completes.

IRQ_STATE bits 0..4 are sticky PIPE_DONE, FRAME_VALID, FAULT, ABORTED and
OUTPUT_STALL. IRQ_ENABLE masks these sources; IRQ_STATUS is their enabled
combination and drives Tiny IRQ27. Set wins concurrent W1C. Clearing an event
does not release ownership, validate data or escape recovery. DVP IRQ15 and
DMA IRQ20 retain their existing independent roles.

## Register and Software ABI

### APB1.0 map

All offsets are hexadecimal, relative to the PPALite window. Registers are
32-bit; reset 0 unless stated otherwise. Reserved read bits are zero. Mutable
processing configuration is writable only in IDLE with no capture owner.
Result fields come from the latched job, not later shadow configuration.
Configuration updates or a route change invalidate RESULT_VALID; a same-value
ROUTE no-op does not. Returned
software frame descriptors and their memory are still caller-owned objects.

| Offset | Name | Access / fields |
| --- | --- | --- |
| `000`, `004` | IP_ID, IP_VERSION | RO `0x5050414C` (PPAL), `0x00010000` |
| `008` | CAPABILITY | RO bits 0 camera input, 1 GRAY8, 2 RGB565, 3 RGB_SWAP, 4 output-byte-swap, 5/6/7 step 1/2/4, 8 RAW bypass; bit 9 PROCESS integration only when the complete qualified source/admission path is wired |
| `00C` | BUFFER_CAPABILITY | RO input words `[7:0]=2`, output words `[15:8]=8`, word bits `[23:16]=32`; no line/frame RAM |
| `010` | CLOCK_HZ | RO actual PCLK Hz, not sensor PIXCLK or CPU SYS |
| `014` | ROUTE | RW bit 0 RAW0/PROCESS1 with the route barrier; retained through RECOVER |
| `018` | COMMAND | WO one-hot bits 0 ARM, 1 FINALIZE, 2 RELEASE, 3 ABORT, 4 RECOVER, 5 RESET; zero no-op |
| `01C` | STATUS | RO state `[2:0]`: IDLE0/ARMED1/RUNNING2/DRAINING3/VERIFY4/COMPLETE5/CLOSING6; OWNER8, INPUT_DONE9, PIPE_DONE10, SOURCE_DONE11, DMA_DONE12, RESULT_VALID13, SOURCE_QUIET14, TRANSPORT_IDLE15 |
| `020` | CONFIG | RW input code `[2:0]` from format table; OUTPUT_GRAY8 bit 4, RGB_SWAP5, OUTPUT_BYTE_SWAP6 |
| `024` | INPUT_SIZE | RW active width `[15:0]`, active height `[31:16]`, both nonzero |
| `028` | SAMPLING | RW X step code `[1:0]`, Y `[3:2]`:0/1/2=>1/2/4; X phase `[9:8]`, Y phase `[17:16]`; code 3 invalid |
| `02C` | DMA_BINDING | RO channel `[7:0]=2`, request `[15:8]=11`, processed direct-only bit 16=1 |
| `030`, `034` | DESTINATION, CAPACITY_BYTES | RW caller's aligned destination and full available padded extent; range checked by HAL/platform before ARM |
| `038` | OUTPUT_SIZE | RO latched output width low 16 / height high 16 |
| `03C`, `040` | ROW_BYTES, STRIDE_BYTES | RO logical row size / four-byte-aligned stored row pitch |
| `044`, `048`, `04C` | VALID_BYTES, TRANSPORT_BYTES, EXPECTED_WORDS | RO checked latched layout; accepted values fit 32 bits |
| `050`, `054` | JOB_SEQUENCE, SOURCE_SEQUENCE | RO current/last local job / completed source frame sequence |
| `058`, `05C`, `060` | INPUT_WORDS, INPUT_PIXELS, INPUT_LINES | RO consumed valid-input counters, 32-bit |
| `064`, `068`, `06C` | SELECTED_PIXELS, OUTPUT_WORDS, OUTPUT_LINES | RO selected pixels, words handshaken and retained rows emitted |
| `070`, `074` | INPUT_STALL_CYCLES, OUTPUT_STALL_CYCLES | RO saturating 32-bit PCLK counters |
| `078` | FIFO_LEVELS | RO input `[1:0]`, output `[7:4]`, output high-water `[15:12]` |
| `07C`, `080`, `084` | IRQ_STATE, IRQ_ENABLE, IRQ_STATUS | W1C sticky / RW mask / RO enabled events |
| `088`, `08C` | FIRST_ERROR, ERROR_POSITION | RO code low 8 / offending post-crop X low 16 and Y high 16 |
| `090` | SOURCE_ERROR | RO sticky per-job copy of DVP error bits |
| `094` | DMA_ERROR | RO sticky per-job copy of bound-channel DMA error status |
| `098` | RESULT_CONFIG | RO CONFIG snapshot associated with the result geometry/sequence |
| `09C` | SOURCE_GEOMETRY | RO full source FRAME_SIZE snapshot; crop details retained internally and in software frame context |

Geometry/configuration writes validate scalar fields/combinations; ARM checks
cross-field/source agreement and complete derived arithmetic before state
changes. Reads of derived fields before the first ARM return 0. Every accepted
ARM increments JOB_SEQUENCE modulo 32 bits, clears per-job validity, errors,
counts and packing state, and latches the complete immutable job descriptor.
IRQ history is cleared deliberately by software rather than mistaken for a
new completion. No FIFO pixel access offsets are provided.

| Command | Legal state and effect |
| --- | --- |
| ARM | PROCESS/IDLE, no owner, valid source snapshot/layout and prepared idle DMA2; latch job and ownership, enter ARMED |
| FINALIZE | VERIFY and every source/pipeline/memory validity predicate true; set RESULT_VALID/FRAME_VALID and enter COMPLETE, retaining ownership |
| RELEASE | COMPLETE with clean source/pipeline/bound transport; drop capture reservation into IDLE, retaining route/result |
| ABORT | Any owned nonclosing state; invalidate RESULT_VALID and enter CLOSING; repeated ABORT in CLOSING is idempotent |
| RECOVER | CLOSING with the acknowledged cleanup predicates below; clear failed per-job state and release ownership into IDLE |
| RESET | RAW/IDLE, unowned and quiescent; restore processing defaults without a route change |

All other states or multiple command bits return PSLVERR with no partial
command effect. ABORT in unowned IDLE is rejected, not a new capture event.

### HAL, metadata and consumers

Handwrite `ppalite_define.svh` and
`crt/include/retrosoc/hal/ppalite_regs.h` with register/field/reset/enum parity
tests. The public HAL is `crt/include/retrosoc/hal/ppalite.h`, implemented in
the matching source layer. Generated product presence, IRQ/RCU metadata and
CAPABILITY.PROCESS must agree; do not probe an unmapped IP or invent an
ARCHINFO bit. Existing DMA ABI version and effective support are checked
before capture, not inferred from request readiness.

`rs_ppalite_*` groups cover probe, checked layout calculation, configuration,
route selection, finite capture/start/wait, status, abort/recover and release.
Fallible operations return `rs_status_t`, with `rs_timeout_t` for bounded waits
and static caller-owned state/buffers. Use RS_EINVAL for geometry/layout/range
errors, RS_ENOTSUP for absent/unsupported modes or wrong RAW route,
RS_ETIMEOUT for missing progress and RS_EIO for source/pipeline/DMA failures.
No heap, OS, hosted-library or new global status enumeration is required.

The frame result records base/capacity, width/height, pixel format, byte order,
row_bytes, stride_bytes, valid_bytes, transport_bytes, job/source sequence and
valid/error status. Keep layout math in deterministic host-testable helpers.
Only successful FINALIZE can create a valid result; failed partial data is
invalid even if a prefix or checksum looks plausible. Memory can be reclaimed
after complete failed-session drain without calling its contents a valid frame.

Display/save consumers must use this descriptor. For odd-width RGB565, a
whole padded allocation is not a contiguous pixel array: use one SPI segment
per row with logical pixel count and physical stride-sized DMA transport.
SPI discards each segment's final padding while retaining CS as required.
Canonical little-endian RGB565 uses SPI16/MSB-first; an explicitly swapped
byte layout needs the corresponding 8-bit wire handling, not a second swap.

GRAY8 may be saved/exported with stride metadata or stripped row padding by
bounded software. Display it by a separately measured bounded CPU line/chunk
conversion, or capture directly in gray RGB565 mode. There is no PPALite
memory-replay conversion in this MVP. Preserve the legacy XPI LCD driver and
existing SPI transaction ABI; board display policy remains in `app/board`.

## Clock, Reset, CDC/RDC, and Lifecycle

PPALite is a PCLK processor, not a PIXCLK peripheral. The existing DVP
`cdc_fifo_warm_flush`, configuration/command/statistic handshakes and staged
pixel reset release stay upstream. Coherent source-status/idle sidebands must
be qualified; raw pixel-domain active signals or host shadow values alone are
not proof of stopped capture or committed configuration.

The retained route/control guard must not change merely because the processing
core resets or gates. RAW bypass does not depend on core pipeline progress.
Normal local reset/gating requires RAW, no capture owner, source quiet and
clean endpoints/associated transport. A PCLK rate change follows the full
Tiny client-quiesce barrier. Re-arm explicitly at the new actual rate; do not
resume a partially processed frame. RCU target 17 appears only after the whole
idle/reset/route path exists. Source/DMA reset or readiness loss during capture
invalidates it and closes admission rather than concealing ownership.
While capture-owned, reject DVP/GPIO/CAM_XCLK, central-DMA or PPALite lifecycle
operations that would interrupt the session, including combined reset/gate
masks. This protects the existing camera source; it adds no Pad assignment.
SOURCE_QUIET means source enable cleared and acknowledged, inactive capture,
empty FIFO/stream and completed configuration/command/statistic/flush exchanges.
It does not mean that source error flags have already been cleared.

Normal capture sequence:

1. Select PROCESS at the full route barrier. Reserve the DVP source, DMA2 and
   destination; initialize/check any external memory and board camera profile.
2. Configure DVP stopped, snapshot enabled, stream enabled, swaps disabled and
   valid full-frame/crop geometry. Complete old source cleanup, clear errors
   and wait for real configuration/CDC acknowledgement.
3. Calculate layout and prepare the idle DMA2 configuration without START.
   Configure PPALite and ARM. Latch the source baseline sequence and parameters;
   keep DVP stopped until the exact guarded DMA job is admitted.
4. Start that DMA job, then enable DVP for the next snapshot. First accepted SOF
   moves ARMED to RUNNING. Source/configuration monitoring remains active.
5. Consume the entire cropped stream, including discarded tails. DRAINING
   waits for pending output; PIPE_DONE enters VERIFY, not reusable IDLE.
6. Observe the single source-frame completion and stop source enable without
   abort/flush, preserving all queued data. Wait for source stop acknowledgement,
   endpoint drain, exact DMA completion/responses and all source validity checks.
7. FINALIZE atomically verifies the predicates and sets FRAME_VALID/COMPLETE.
   RELEASE clears capture ownership and returns IDLE while retaining the route
   and result descriptor. Only then publish/consume the destination.

STOP/FINALIZE may not use the current convenience helper's early ABORT path.
Extra SOF/data or a late source error before finalization invalidates the job.
Normal snapshot stop must prevent an unintended second capture without
withdrawing a valid first-frame tail. No queue or automatic continuous rearm.

ABORT or any source/stream/count/owned-DMA fault immediately enters CLOSING,
blocks new admission/source start and new transform effects, and retains the
route/owner. Keep already asserted output VALID/payload stable. Abort the
bound DMA and drain accepted memory/descriptors/responses first; after the
old stream is isolated and acknowledged, execute DVP ABORT/FLUSH and PPALite
flush. Source ABORT currently flushes its CDC FIFO, so it must not withdraw a
live upstream beat before the coordinated isolation boundary. No fabricated
tail words, early route switch or global DMA reset is allowed.

RECOVER requires bound transport fully drained, stream isolation acknowledged,
source stopped, command/warm-flush/reset barriers complete and old payload
inaccessible. It clears failed per-job state and releases capture ownership
into IDLE, retaining PROCESS/configuration for explicit rearm. If PIXCLK is
missing or a barrier cannot acknowledge, remain CLOSING and owned. Retry
bounded recovery after the source clock returns or use the separately governed
whole-system reset; never report a successful local reset or reusable buffer.
RECOVER is accepted only in CLOSING. It clears local failed-job counters,
validity, first-error copies and IRQ_STATE, but retains configuration,
IRQ_ENABLE, route and the monotonic JOB_SEQUENCE until RESET/system reset.
Persistent source flags from cleanup cannot defeat a legal RECOVER: normal
capture-fault monitoring is enabled only in ARMED/RUNNING/DRAINING/VERIFY,
not CLOSING or unowned IDLE. The next ARM requires an acknowledged clean source
error epoch. Recovery does not clear the source's registers behind its owner.

RESET is legal only in RAW/IDLE, without ownership and with source/endpoint
quiescence; clear processing configuration/FIFOs/counters/IRQ to defaults and
complete the current APB response. Reset-default route is RAW, but a local
command cannot implicitly switch PROCESS to RAW. The full route barrier must
first be satisfied. Whole-system reset discards the entire traffic epoch.

Priority is system reset, source/fault/ABORT close, accepted lifecycle command,
then normal data progress. Close prevents same-edge ARM/new DMA admission;
previously accepted work still drains. Accepted DMA START wins a competing
ordinary route write; accepted source updates/pending CDC defeat ARM. The
current CPU control access is excluded from its own idle test. WFI, debug
halt and hart reset do not silently clear independent capture ownership;
restarted firmware must discover and recover/adopt it before reconfiguration.

## Errors, Recovery, Security, and Observability

FIRST_ERROR codes are 0 none, 1 source error/reset/readiness, 2 source configuration,
3 input framing/sideband, 4 input geometry/count, 5 output/FIFO/quota,
6 bound DMA/target response, 7 explicit abort. The first code/position is sticky
until RECOVER/RESET or a legal new ARM; simultaneous source errors precede
other classes, then lower code wins. Preserve source/DMA status before clearing
their W1C state. Harmless rejected APB configuration writes have no capture
side effect; actual source changes/errors cannot be ignored.
ERROR_POSITION is the post-crop detection coordinate when available; source,
reset or DMA faults without a localizable pixel use `0xFFFFFFFF`. It does not
invent a precise location for sensor data discarded before the stream.

Input counters include dropped pixels/lines; output counters include retained
pixels/lines and complete padded words. INPUT_STALL counts valid source beats
blocked by the processor, OUTPUT_STALL counts valid output beats held by DMA,
both in PCLK cycles with saturation. FIFO high-water and exact layout explain
pressure; they do not prove arbitrary service latency or sensor timing.

The upstream 512 B DVP FIFO still receives complete raw input. Its no-service
budget remains `(512 - occupancy - margin) / raw_active_byte_rate`, not the
reduced output rate. Selection does not lower sensor PIXCLK. Do not count
PPALite/DMA buffering as additional raw slack without a verified occupancy/
credit argument. The camera cannot obey AXI backpressure; source overflow
invalidates the whole frame even if destination capacity is sufficient.

No security, source authentication, memory protection, lossless continuous
capture, functional-safety or pixel-quality certification is implied. Padding
and source checks prevent accidental corruption, not malicious firmware or
electrical interference. No pixel data is valid merely because PIPE_DONE fired.

## MVP and Commercial-grade Roadmap

The exact MVP is this camera-inline pipeline, RAW preservation, one-frame
direct capture, format/stride-aware HAL, source qualification and sequential
memory/save/display acceptance. For 320x240 two-byte input with no row padding:

| Output | Dimensions | DMA bytes / words |
| --- | --- | --- |
| RAW reference | 320x240 | 153600 / 38400 |
| Y to GRAY8, step 1 | 320x240 | 76800 / 19200 |
| Y to GRAY8, step 2 on both axes | 160x120 | 19200 / 4800 |
| Y to gray RGB565, step 2 on both axes | 160x120 | 38400 / 9600 |

These are layout calculations, not speed or SRAM-allocation guarantees.
GRAY8 saves bytes; gray RGB565 avoids a display conversion but remains two
bytes/pixel. Software, stack and other buffers still occupy main SRAM. Test
both small SRAM buffers and initialized/qualified NSS1 PSRAM, with explicit
capacity checks and no external-RAM boot dependence.

Compare input/output pixels against an independent scalar model, then memory
canaries/padding and saved or displayed pixels. SPI preview uses the frozen
SPI hardware and board adapter, respecting row stride and actual dimensions.
Measure cycles, CPU work, bytes written, FIFO pressure, longest stalls and
whole-frame time at available PCLK24/48/60 operating points. No vendor PPA
throughput or theoretical pixel rate becomes a Tiny FPS promise.

Larger graphics, memory replay, filtering, more channels and double buffering
require a new scope/ABI/resource decision. Do not silently grow the MVP to
match ESP32-P4 PPA or Mini GA2D.

## Verification and Software Validation

The [verification ledger](ppalite-verification.md) records the complete case
matrix and evidence gaps. P1 supplies a scalar reference and independent stream
BFM, with RTL differential tests and protocol assertions. P2 qualifies actual
DVP source behavior, route isolation and cleanup; P3 wires real Tiny metadata,
DMA/RCU/SDK; P4 supplies camera/memory/save/display evidence.

Mandatory cases include every input layout, RGB swap/output byte order, step/
phase combination, odd/one-pixel dimensions, legal halfword input tails,
nonzero ignored input padding and zero output padding, overflow arithmetic,
missing/extra SOF/EOL/pixels/lines, late source errors, dropped leading/trailing
rows, output completion before input completion, random backpressure, stale
DMA DONE, delayed final B, route/START/source-update races, RAW compatibility,
abort with held VALID, missing PIXCLK and recovery without global DMA reset.
Exercise more than 65535 source words and repeated snapshots for source gating.

New self-owned C follows MISRA C:2012 Amendment 2; no deviation is granted here.
Use deterministic host tests for layout, pixel conversion, range and consumer
stride handling. Preserve Tiny's exit 0 + TEST_STATUS/`SIM_TEST_PASS` verdict
and reject `FAILED`, `FATAL`, `assertion failed`, `%Error`, `SIM_TEST_FAIL` or
`SIM_TEST_TIMEOUT`. UART text is diagnostic. Mini retains its own verdict.

After authorization of the corresponding implementation phase, use existing
tools and the focused tests that phase adds, not imaginary PPALite targets:

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

The current committed profile lacks PPALite integration; successfully parsing
these commands is not its execution. Verilator and Icarus must both exercise
stream and real pin-level camera/memory paths as applicable. Skipped fixtures,
source gaps and unavailable tools/models remain visible failures or unrun gates.

## Synthesis, Timing, and Physical Evidence

Bind every result to source SHA, dependency/configuration digests, default
TINY/ICS55 or explicit TINY/IHP130 compatibility
variant, PCLK/SYS/MEM/PIXCLK, geometry/format/phase, source/target models,
burst limits and board assumptions. Require block/full synthesis, actual small
storage mapping, area/cells, activity-based power, reset release/fanout,
netlist simulation, CDC/RDC, PVT/MMMC and extracted timing.

PCLK24 is the baseline environment, not existing PPALite timing proof. PCLK48/60
functional tests require R2 clock/platform implementation, not intermediate
physical qualification; PPALite does not qualify CPU/main-SRAM
192/240 MHz. DVP input Pad timing, camera clock/lifecycle and XPI/PSRAM source-
bound performance remain separate gates even though no new Pad is added.
Review DFT/local-storage test coverage without inventing SRAM MBIST/ECC claims.

PPALITE-P5 must join the final R2-P11, PIOLITE-P5 and SPI-P5 campaign on the
same complete-product source/netlist/configuration with all required evidence.
Earlier netlists do not cover new routing, storage, reset or timing load.
Missing macro/Pad/clock/vendor/board inputs remain explicit qualification gaps;
metrics stay observe-mode and warning baselines are not waived by this freeze.

## Development Order

All phases target TINY. Shared DVP/DMA consumer testing on Mini does not enable
PPALite there. IDs and titles are stable and do not replace earlier roadmaps.

| Phase / title | Dependencies, changes and completion |
| --- | --- |
| PPALITE-P0 - Contract and Camera Route Freeze | Approved research; freeze this contract/ledger, RAW/PROCESS route and source predicates, layout/ABI and cross-document product integration. Check links/commands/consistency/whitespace; documentation only. |
| PPALITE-P1 - Stream Pixel Core and Reference Model | P0; owned stream core, validator, decimator, formatter, buffers, APB/register mirror and scalar/stream models. Exact pixels/layout, protocol/backpressure, invalid cases, parity, lint/style/formal and block-synthesis evidence. No Tiny capability claim. |
| PPALITE-P2 - DVP Route and Source Qualification | P1; coherent source guards, RAW bypass, route/barrier/epoch behavior and DVP correctness prerequisites. Close minimal shared error/statistic/snapshot/CDC/drain defects or reuse accepted fixes, retaining DVP ABI/FIFO and Mini behavior. Source integrity must be proved, not inferred from PPA output. |
| PPALITE-P3 - Tiny DMA RCU and SDK Integration | P2 plus applicable R2-P6/P7; APB/IRQ27/RCU17/topology/filelists, exact direct DMA2 admission, complete-job drain, capability and bounded HAL. Existing DMA cancellation obligations are prerequisites; no new DMA encoding/master/channel. Target firmware and affected Tiny/Mini tests pass. |
| PPALITE-P4 - Camera Memory and Display Qualification | P3 plus R2-P8/P9 and display's applicable SPI stages; SRAM/PSRAM captures, pixel/padding/canary checks, SD/stride-aware preview, repeated/error recovery, both simulators, full regressions and measurements. No continuous-video or FPS guarantee without separate evidence. |
| PPALITE-P5 - IHP130 Timing and Physical Qualification | Historical title; default ICS55. P4 plus all product functional prerequisites; mandatory final campaign with R2-P11/SPI-P5/PIOLITE-P5 on the identical complete-product design, closing source-bound synthesis/netlist/STA/CDC/RDC/physical/power/Pad gates. |

### Next-phase preflight handoff

```text
Use $retrosoc-feature-implementation. Stage: preflight. Feature slug: ppalite. Target SoCs: TINY.
Phase: PPALITE-P1 - Stream Pixel Core and Reference Model.
Read docs/ip/ppalite.md and docs/ip/ppalite-verification.md. Default target: ICS55/HAVE_PLL=YES with SAFE24 boot and planned configs/ci/ics55-tiny.mk; require accepted TINY-ICS55-P1 before integrated default-platform work. Current executable reference: configs/ci/ihp130-tiny.mk, IHP130, 24 MHz/no PLL, no PPALite. Apply the 2026-10-07 observational pre-final timing policy and mandatory complete-product final campaign; do not invent an executable profile or relabel historical results.
Plan only the frozen standalone pixel/stream core, input validation, 1/2/4 sampling, exact format/row packing, small buffers, APB1.0 and handwritten SVH/C parity, scalar reference, independent stream BFM and focused tests. Preserve Y-only grayscale, RAW contract, resource limits and all earlier phase IDs.
Do not implement DVP source repairs, Tiny routing/DMA/RCU integration, the complete SDK/display application or later phases. Do not add memory replay, RGB-to-gray arithmetic, interpolation, row/frame SRAM, DMA requests/masters, dependencies, profiles or quality-policy changes. Return SPEC_CONFLICT rather than weakening an unmet contract, and provide the scoped preflight/validation plan for explicit approval. Do not commit or push.
```

## Commercial Delivery Gaps

At freeze the processor/model, source repairs, route/admission/lifecycle,
register mirror, HAL, stride-aware consumers and PPALite evidence are absent.
Reusable verification, coverage closure, reset/CDC/RDC/DFT, extracted timing,
power/board qualification, release artifacts and silicon validation remain
required. A documentation freeze is not RTL freeze or permission to advance
implementation stages. No MISRA deviation, new PDK or security/safety claim
is approved here.
