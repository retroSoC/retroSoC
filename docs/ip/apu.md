# Mini Audio Processing Unit

## Purpose and Research Boundary

This document is the authoritative architecture, interface, microcode, software,
and verification contract for the retroSoC Mini Audio Processing Unit (APU).
The stable feature slug is `apu`. The APU provides autonomous WAV/PCM, MP3,
and native FLAC decode, fixed-point sample processing, private DMA, direct I2S
streaming, and continuous keyword spotting (KWS).

The APU is deliberately coreless. LP loads one validated codec-microcode bundle
at startup and HP or LP later submits jobs. The APU contains a bounded codec
sequencer and fixed processing engines; it does not contain Hazard3, VexiiRiscv,
a DSP CPU, a general-purpose instruction set, or a C runtime.

The design was frozen on 2026-09-02 from these repository sources of truth:

- `rtl/mini/address_map/memory_map.json` for the reserved `APB4_APU` window;
- `rtl/mini/integration/soc_topology.json` for APB4, IRQ, resource, and data
  integration;
- `rtl/mini/integration/clock_reset_domains.json` for clock/reset and CDC/RDC;
- `docs/lp-hp-architecture.md`, `docs/axi4-interconnect.md`, and
  `docs/axi4-stream.md` for the control, memory, and stream planes;
- `docs/ip/dma.md`, `docs/ip/i2s.md`, `docs/ip/jpeg.md`, `docs/ip/xpi.md`, and
  `docs/ip/resource-controller.md` for DMA, stream, fixed-pipeline,
  programmable-LUT, and lifecycle patterns; and
- `dependencies/dependencies.lock.json` for managed inputs.

APU-P2 implements the private AXI4 DMA, descriptor ring scheduler, fair Gateway
A arbitration, and the production audio stream router with two 64-word Common
FIFOs. The shell reports only private-DMA and ring capabilities; public direct
start, ring doorbell, and APU stream routes remain fail-closed until their
later-phase engines exist. No claim is made that microcode, sequencer, codec
engines, KWS, codec conformance, Linux driver, timing closure, power closure,
CDC/RDC signoff, or silicon qualification exists.

## Commercial References

The selected design uses public architectural lessons and does not reproduce
proprietary decoder RTL or microcode.

| Reference | Relevant behavior and status | Reuse boundary | Avoided boundary |
| --- | --- | --- | --- |
| [Cadence Tensilica HiFi DSP family](https://www.cadence.com/en_US/home/resources/product-briefs/tensilica-hifi-dsp-family-pb.html) | Current programmable audio/voice IP with codec, bitstream, SIMD, and AI support. | Keep codec behavior updateable and separate scalar control from fixed arithmetic. | Do not import a DSP core, proprietary ISA/toolchain, floating point, or vendor PPA claims. |
| [Ceva-BX1](https://www.ceva-ip.com/product/ceva-bx1/) | Current compact controller/DSP with MACs, queue management, accelerator ports, and light-AI support. | Use bounded queues and explicit accelerator commands. | Do not instantiate a controller core or project 7 nm frequency/GMAC data onto Mini. |
| [NXP FlexSPI](https://mcuxpresso.nxp.com/api_doc/dev/1315/group__flexspi.html) | Active programmable command-LUT controller with distinct mapped and indirect data paths. | Reuse the model of host-loaded, validated sequences executed by a hardware sequencer. | A serial-memory phase LUT is much simpler than audio parsing; its eight-instruction scale is not reused. |
| [CAST H264-D-BP](https://www.cast-inc.com/compression/avc-hevc-video-compression/h264-d-bp) | Current standalone streaming decoder IP with zero host decode overhead, errors, bit-accurate model, and AXI wrappers. | Reuse autonomous decode, flow-controlled streams, explicit errors, and independent BAM delivery. | Video codec gates, memory, throughput, and PPA are not Audio/Mini evidence. |
| [AMD Audio Formatter](https://docs.amd.com/r/en-US/pg330-audio-formatter/Features) | Maintained AXI4 memory/stream audio mover with DMA, completion/error interrupts, timeout, and graceful halt. | Reuse independent memory/stream paths, bounded halt, and period/error observability. | It formats PCM/AES audio and is not a compressed-file decoder. |
| [MP3 hardware/software co-design](https://scholars.ncu.edu.tw/en/publications/a-hardwaresoftware-co-design-of-mp3-audio-decoder/) | A programmable parser controls dedicated IMDCT/filterbank hardware, showing the split between irregular bitstream control and regular arithmetic. | Implement irregular parsing in bounded microcode and regular kernels in fixed engines. | Its process, area, frequency, and embedded parser processor are not reused. |
| [RFC 9639 FLAC](https://datatracker.ietf.org/doc/rfc9639/) | Current standards-track FLAC definition; decode uses integer bit parsing, Rice residuals, fixed/LPC prediction, and channel decorrelation. | Implement the native streamable decoder using integer primitives and bounded history. | Ogg/Matroska/MP4 mappings and the full 1..8-channel standard are outside MVP. |
| [MLPerf Tiny KWS](https://github.com/mlcommons/tiny/blob/master/benchmark/training/keyword_spotting/README.md) | Reproducible 49 by 10 INT8 MFCC/DS-CNN workload with 12 classes and a 90 percent quality threshold. | Use its operator set, corpus, accuracy threshold, and reproducibility rules. | Do not claim an MLPerf result unless the applicable runner and reporting rules are followed exactly. |

The selected pattern is bounded microcode plus fixed decoder primitives. A
general-purpose processor is not retained as normative behavior. Separate
per-format RTL is also not selected because it would duplicate bitstream,
entropy, arithmetic, DMA, and recovery logic and make fixes silicon changes.

## Requirements and Non-goals

### MVP requirements

| ID | Requirement |
| --- | --- |
| `APU-MVP-001` | The APU MUST expose APB4 configuration at the reserved `APB4_APU` window `0x1001_3000..0x1001_3fff`. |
| `APU-MVP-002` | The APU MUST use a private 32-bit AXI4 DMA master for microcode, model, descriptors, compressed input, and optional PCM output. |
| `APU-MVP-003` | The APU MUST expose 32-bit AXI4-Stream PCM input and output integrated with existing I2S RX/TX streams. |
| `APU-MVP-004` | WAV/PCM, MPEG-1/2/2.5 Layer III MP3, and native FLAC decode MUST execute entirely in the coreless APU. |
| `APU-MVP-005` | LP MUST load one bundle containing all three codec entry points before handoff; successful load MUST lock microcode until hard reset. |
| `APU-MVP-006` | The codec sequencer MUST execute only the bounded V1 microcode ISA and MUST NOT execute RV32, C, ELF, or arbitrary system-memory instructions. |
| `APU-MVP-007` | Continuous 16 kHz mono KWS MUST use an independent fixed MFCC/INT8 DS-CNN engine and MUST run concurrently with decode. |
| `APU-MVP-008` | DMA, sequencer, primitive, stream, resampler, and KWS work MUST have timeout, abort, first-error, and recovery behavior. |
| `APU-MVP-009` | Microcode, KWS model, descriptors, tables, and buffers MUST use versioned, bounds-checked formats with no dynamic allocation. |
| `APU-MVP-010` | The APU MUST integrate as Resource Controller index 7 and route its interrupt exclusively to LP IRQ31 or HP PLIC source 10 according to owner. |
| `APU-MVP-011` | Hardware/software register, descriptor, microcode, and model definitions MUST remain independently handwritten and pass parity tests; no register generator is allowed. |
| `APU-MVP-012` | Compatible Common APB4, AXI4, AXI4-Stream, register, FIFO, round-robin, synchronizer, and warm-flush CDC components MUST be reused. |
| `APU-MVP-013` | LP/HP host software MUST remain freestanding at SDK boundaries and MUST NOT introduce hosted I/O, `malloc`, or `free`. |

### Target requirements

- Sequencer, primitive engines, KWS, SRAM banks, and DMA MUST be independently
  clock-gateable when idle, subject to later physical implementation evidence.
- Microcode capacity, arithmetic lane count, SRAM bank geometry, and internal
  pipelines MUST remain outside the public job/HAL ABI.
- Every normal completion, rejection, timeout, trap, xrun, handoff, and reset
  MUST be diagnosable without a waveform.
- A commercial release MUST add full conformance, reusable VIP, coverage,
  CDC/RDC, DFT/MBIST, PVT/MMMC, power, post-layout, and silicon evidence.

### Deferred work and non-goals

The following work is DEFERRED outside Phases 0 through 8 and MUST NOT be
silently inserted into an MVP phase:

- AAC, HE-AAC, Opus, Vorbis, Ogg-FLAC, ALAC, WMA, Dolby, DTS, LC3, or any
  format beyond the three frozen entry points;
- encoding, transcoding, MPEG Layer I/II, more than two channels, object audio,
  TDM, PDM, beamforming, AEC, or ANC;
- a general-purpose processor, DSP core, arbitrary microcode compiler, C/ELF
  execution, runtime code download per job, or HP software decode fallback;
- hardware cache coherency, IOMMU, virtual contexts, preemption, or more than
  one active decode job;
- an independent retained KWS power island, PCLK-independent cold wake, DVFS,
  or quantified always-on power claim;
- microcode/model signatures, secure boot, encryption, anti-rollback, DRM, or
  protected-content claims;
- ECC, repair, or production MBIST for APU SRAM; and
- a generic NPU or arbitrary TFLite/ONNX operator runtime.

## Selected Architecture

### Module hierarchy

```text
apb4_apu
  apu_reg
  apu_microcode_loader
  apu_job_scheduler
  apu_dma
  apu_codec_sequencer
    apu_control_store       (2048 x 64, 16 KiB)
    apu_scalar_registers    (16 x 32)
    apu_loop_stack
  apu_bitstream_engine
  apu_entropy_engine
  apu_reconstruction_engine
  apu_transform_engine
  apu_resampler
  apu_local_sram            (112 KiB)
  apu_kws_frontend
  apu_kws_engine
  apu_stream_router
```

There is no CPU inside this hierarchy. `apu_codec_sequencer` cannot issue a
system load/store, execute from AXI memory, address APB4, take a CPU interrupt,
or run a compiler-generated program. It fetches one validated 64-bit control
word per cycle from local control store and orchestrates fixed engines.

Total local storage is 128 KiB:

| Region | Capacity | Use |
| --- | ---: | --- |
| control store | 16 KiB | 2048 64-bit instructions containing WAV, MP3, FLAC, and common subroutines |
| codec table/scratch | 24 KiB | Huffman tables, MP3 reservoir/coefficient state, FLAC predictor/Rice state |
| compressed/PCM staging | 16 KiB | input and output DMA/stream buffers |
| KWS | 64 KiB | model weights, 49 by 10 history, and tiled activations |
| common/result reserve | 8 KiB | descriptors, counters, CRC, and bounded temporary state |

The regions are statically partitioned. Software discovers capacities through
capability registers but never physical bank count. The implementation uses
existing 4 KiB technology SRAM abstractions and records the actual macro map in
PPA evidence.

### Fixed engines

- Bitstream engine: 64-bit refill reservoir, 1..32-bit peek/get/skip, byte
  alignment, frame sync, CRC8, and CRC16.
- Entropy engine: table-driven MP3 Huffman pair/quad, canonical symbol decode,
  unary scan, Rice/Rice2 remainder, sign restoration, and bounded table index.
- Reconstruction engine: four initial 32x32-to-64 fixed-point MAC lanes,
  rounding, shifts, saturation, MP3 requant/stereo, and FLAC fixed/LPC order
  0..32 plus channel decorrelation. Lane count is implementation-private.
- Transform engine: MP3 IMDCT6/18, DCT32/polyphase synthesis, overlap/history,
  and fixed coefficient-table access.
- Resampler/packer: deterministic fixed-point polyphase conversion, volume,
  downmix, S16/S24 saturation, memory packing, and I2S packing.

The sequencer issues a kernel command and either continues independent scalar
work or waits for completion. Each kernel has a specified maximum latency and
cannot access outside its assigned local-memory range.

### Independent KWS

I2S RX feeds a dedicated KWS input FIFO, mono/downmix, 16 kHz resampling,
512-point fixed FFT/MFCC, and a 16-lane INT8/INT32 DS-CNN engine. Supported
operators are Conv2D, depthwise 3 by 3, pointwise 1 by 1, bias,
requantization/ReLU, global average pool, and fully connected.

KWS evaluates a 49 by 10 INT8 window every 100 ms. Score threshold and 1..255
consecutive-hit debounce are programmable. KWS does not use codec microcode or
codec MAC lanes, so it remains live during file decode. Only SRAM arbitration,
PCLK, stream routing, IRQ collection, and lifecycle control are shared.

### Control and data flow

1. LP programs read/write ACLs and the `APUMC` bundle address/size/CRC.
2. Private DMA loads the complete WAV/MP3/FLAC bundle. Hardware and the offline
   verifier validate header, capabilities, control flow, ranges, loop bounds,
   tables, and CRC before publishing valid.
3. Successful load automatically sets a hard-reset-cleared microcode lock.
   HP cannot load or replace microcode.
4. LP similarly loads and locks one `APUM` KWS model, then may hand APU
   ownership to HP.
5. The owner submits a direct job or advances a descriptor ring. The scheduler
   selects the frozen codec entry, fetches compressed input, and starts the
   sequencer.
6. PCM is written to memory or emitted through AXI4-Stream to I2S TX. Progress
   advances only after successful AXI responses or stream handshakes.
7. Concurrent I2S RX KWS maintains its own FIFO and model context. Stable KWS
   hits and codec/DMA events enter the aggregate sticky interrupt state.

There is one active decode job plus continuous KWS. Accepted AXI4 or
AXI4-Stream transfers are never withdrawn. Decode abort stops new work, drains
accepted traffic, terminates the sequencer, and flushes local codec state only
after drain.

## Interfaces

### APB4 configuration

The APU is a 32-bit APB4 slave at `0x1001_3000..0x1001_3fff`. Registers are
naturally aligned and follow the repository setup/access and response-retention
contract.

- Reads have no side effects except explicit snapshot results.
- RW registers honor byte strobes. Commands, addresses, sizes, CRCs, ring
  control, and portals require `PSTRB=4'hf`.
- Unaligned/unmapped accesses, unsupported strobes, invalid direction,
  active-configuration writes, or illegal commands complete with `PSLVERR`.
- Configuration is latched on job start or KWS enable.
- Command bits are pulses, not stored levels.

### Private AXI4 DMA

The APU provides one PCLK-domain 32-bit AXI4 master with 32-bit addresses,
one-bit ID/user, and ID zero. It occupies the unused third input of I/O Gateway
A and uses the existing PCLK-to-HP `axi4_async_bridge` and 32-to-64 upsizer.
It retains global data-master identity 3; the eight-master crossbar and global
ID width do not expand.

Gateway A MUST replace its fixed-priority selection with a burst-boundary
Common round-robin arbiter among APU, SDIO0, and USB2. Ownership is retained
through terminal `B` or `RLAST`; a continuously eligible source cannot starve
while downstream traffic completes.

DMA behavior:

- one internal read and one internal write transaction may be active, although
  the shared gateway may serialize addresses;
- aligned 4-byte addresses, arbitrary nonzero byte counts, and partial final
  write strobes;
- 1..16-beat `INCR` bursts that never cross 4 KiB;
- 64-byte-aligned microcode/model images and 128-byte-aligned descriptors;
- `AxCACHE=0`, data-only attributes, and no executable system-memory access;
- reads from SRAM, SDRAM, QPI, OPI, or XPI; writes to SRAM, SDRAM, QPI, or OPI;
- inclusive local read/write base/limit ACLs, with reset denying all access;
- `SLVERR`, `DECERR`, bad ID, malformed `RLAST`, ACL overflow, timeout, or
  bridge flush recorded against the active load/job; and
- abort blocks new addresses, drains accepted responses, then discards local
  in-flight codec data.

The DMA no-progress timer runs only while an AXI request is presented or an
accepted AXI read/write/descriptor transaction is outstanding. A handshake on
`AW`, `W`, `B`, `AR`, or `R` is progress and reloads the full nonzero
`DMA_TIMEOUT` value. Merely holding `VALID`, moving data between local FIFOs,
or waiting on a codec/stream endpoint is not DMA progress. The first cycle with
an unaccepted address/data `VALID` or an accepted transaction starts the epoch.
Expiry blocks new AXI addresses, records error 17 against the owning direction
and address, and drains any accepted transaction before terminal completion.
The timer stops when no AXI request or response is pending and clears on abort,
soft reset, resource reset, or hard reset.

Gateway A has one fabric identity, so local first-error and per-client counters
are required for attribution. Handoff conservatively waits for APU, USB2, and
SDIO0 gateway traffic to become idle.

### AXI4-Stream

The APU input/output use 32-bit `axi4_stream_if` in PCLK with ID/destination/
user zero and `TKEEP/TSTRB=4'hf`.

- S16 stereo packs the earlier sample in `[15:0]` and later sample in
  `[31:16]`, matching I2S.
- S24 uses one signed sample in `[23:0]` and sign extension in `[31:24]`.
- Mono playback is duplicated to I2S left/right; mono memory output remains
  mono.
- Payload and sidebands remain stable under backpressure.
- `TLAST` marks the final PCM word of a finite decode job; continuous KWS does
  not depend on `TLAST`.

TX producer and RX consumer are selected independently. Reset preserves the
existing central-DMA route. APU mode selects APU-to-I2S TX and I2S RX-to-KWS,
which may operate concurrently. Active-direction route changes are rejected.
No external pad is added; I2S retains audio-clock-domain sampling and CDC.

Phase 2 implements and verifies the production stream router and two 64-word
Common FIFOs through a test-only wrapper, but it has no production APU PCM
producer or KWS consumer. Consequently, in the SoC integration through Phase 2,
`CAPABILITY0.STREAMS` remains zero and any `STREAM_ROUTE` direction value 1
returns `PSLVERR`. Reset value 0 continues to select central DMA. The test-only
wrapper is in the verification filelist only, drives the production FIFO/router
interfaces directly, and creates no register, descriptor operation, capability,
or synthesized diagnostic path. TX value 1 becomes legal only when the first
codec stream producer is delivered; RX value 1 becomes legal only with KWS.

A TX direction is active when its route is APU and at least one of the endpoint
session-active input, a nonempty TX FIFO, or an asserted unaccepted output
`TVALID` is true. An RX direction is active when its route is APU and at least
one of the endpoint session-active input, a nonempty RX FIFO, or an accepted
but unretired input beat is true. A `STREAM_ROUTE` write that changes one
direction returns `PSLVERR` while that direction is active; changing only the
inactive direction or rewriting the same value is legal. Phase-2 production
endpoint session-active inputs are tied low.

`STREAM_WATERMARK` programs an RX/input high watermark in bits `[7:0]` and a
TX/output low watermark in bits `[15:8]`; `[31:16]` are reserved zero. Each
value is 0 (disabled) or 1..64 words. The input event occurs on an occupancy
crossing from below to greater-than-or-equal-to its threshold and rearms below
the threshold. The output event occurs on a crossing from above to
less-than-or-equal-to its threshold while TX is active and rearms above it.
The events set sticky IRQ bits 6 and 7. Setting a threshold to zero disables
future events and resets its crossing detector but does not clear an already
sticky IRQ; software clears that through `IRQ_STATE`. Hardware set wins a
same-cycle W1C.

## DMA and Interrupt Contract

### Direct and ring operation

Direct mode uses `JOB_*` registers. Ring mode uses 2..256 power-of-two entries.
Each descriptor is exactly 128 bytes and 128-byte aligned. Head is hardware
owned; tail is software owned.

Software writes payload, sets OWN last, executes `fence rw,rw`, advances tail,
and rings the doorbell. Hardware fetches only owned descriptors, writes all
results, clears OWN, advances head, then raises completion. An unowned head
stalls without consumption. An invalid owned entry completes with error and
advances head; stop-on-error prevents the next fetch. IOC overrides coalescing.

Phase 2 does not add a public diagnostic operation and does not make decode or
KWS executable. Because every public operation depends on later phases,
`START_DIRECT` and `RING_DOORBELL` continue to return `PSLVERR` until valid
locked microcode and the selected format/KWS capability are both present.
Phase-2 verification instead instantiates the production DMA and ring scheduler
behind a verification-only backend. The backend drives the internal transport
request/completion interface, exercises memory-to-memory direct transfers,
fetches public 128-byte descriptors, supplies deterministic result writeback,
and tests OWN-last, unowned stalls, invalid-owned completion, wrap, coalescing,
abort, and every bus error. It is excluded from behavioral/synthesis product
filelists and has no public opcode or runtime path. Thus successful P2
direct/ring verification does not pull microcode, primitives, codecs, or KWS
forward.

For non-IOC completions, an internal pending-completion count increments after
descriptor result writeback and OWN clear. A zero-to-one transition starts a
coalescing timeout epoch loaded from `RING_COALESCE[31:16]`; the timer decrements
once per PCLK cycle. A ring event is generated when the post-completion pending
count reaches `RING_COALESCE[7:0]` or the timer expires with a nonzero count.
Either event clears the pending count and stops the epoch. An IOC completion
immediately generates one ring event covering the IOC descriptor and all prior
pending completions, then clears the count/epoch regardless of the programmed
threshold. IRQ W1C does not reset or rearm the count/timer. Ring disable,
abort, soft/resource/hard reset, or stop-on-error terminal writeback clears the
pending count and timer. Both coalescing fields remain nonzero as already
required by the P1 ABI. If an error descriptor also has IOC, its terminal
writeback first generates the IOC ring event covering pending completions, then
stop-on-error halts and clears the coalescing state; the error IRQ is collected
independently.

### Descriptor ABI

| Word | Field | Direction and meaning |
| ---: | --- | --- |
| 0 | `CONTROL` | SW to HW: operation `[3:0]`, input format `[7:4]`, output mode `[9:8]`, downmix 10, resample 11, IOC 30, OWN 31. |
| 1 | `RESULT_STATUS` | HW to SW: done 0, error 1, aborted 2, error code `[8:3]`, stage `[12:9]`, AXI response `[14:13]`. |
| 2 | `INPUT_ADDRESS` | Aligned compressed-file or diagnostic PCM source. |
| 3 | `INPUT_LENGTH` | Nonzero source bytes. |
| 4 | `OUTPUT_ADDRESS` | Aligned PCM destination; zero only for stream output. |
| 5 | `OUTPUT_CAPACITY` | Destination bytes; zero only for stream output. |
| 6 | `INPUT_CONFIG` | Expected rate `[16:0]`, channels `[18:17]`, source bits/sample `[25:20]`; zero fields mean derive. |
| 7 | `OUTPUT_CONFIG` | Rate `[16:0]`, channels `[18:17]`, PCM format `[20:19]`. |
| 8 | `JOB_FLAGS` | Strict decode bit 0; all other V1 bits zero. |
| 9 | `KWS_CONFIG` | Memory-window threshold `[7:0]`, debounce `[15:8]`; zero for decode. |
| 10 | `RESULT_INPUT_USED` | Bytes consumed. |
| 11 | `RESULT_OUTPUT_BYTES` | PCM bytes written or streamed. |
| 12 | `RESULT_FRAMES` | PCM sample frames produced. |
| 13 | `RESULT_SOURCE_INFO` | Detected rate `[16:0]`, channels `[18:17]`, bits/sample `[24:19]`. |
| 14 | `RESULT_CYCLES` | Saturating job cycle count. |
| 15 | `RESULT_DETAIL` | Format-, microcode-, or primitive-specific diagnostic. |
| 16-17 | `COOKIE` | Opaque 64-bit value preserved. |
| 18-19 | `START_TIMESTAMP` | 64-bit PCLK cycle timestamp. |
| 20-21 | `FINISH_TIMESTAMP` | 64-bit PCLK cycle timestamp. |
| 22 | `KWS_RESULT` | Class `[7:0]`, score `[15:8]`, hit 16 for memory-window operation. |
| 23 | `MICROCODE_BUILD_ID` | Low 32 bits of the loaded `APUMC` build ID. |
| 24-31 | Reserved | Software writes zero; hardware writes/preserves zero. |

Operation 0 is file decode and operation 1 is one KWS memory window. Input
format 0 is WAV/PCM, 1 MP3 Layer III, and 2 native FLAC. Output mode 0 is
memory and 1 is I2S stream. PCM format 0 is interleaved S16_LE and 1 is
S24_32LE. All other V1 encodings fail validation.

### Interrupts

| Bit | Sticky event |
| ---: | --- |
| 0 | direct job done |
| 1 | ring/coalescing event |
| 2 | stable KWS hit |
| 3 | microcode load done |
| 4 | model load done |
| 5 | abort done |
| 6 | input watermark |
| 7 | output watermark |
| 8 | first error |
| 9 | stream underrun/overrun |
| 10 | sequencer trap/watchdog |
| 11-31 | reserved |

`IRQ_ENABLE` gates delivery, not collection. `IRQ_TEST` sets implemented state
only. `IRQ_STATE` is W1C; hardware set wins a simultaneous clear. `irq_o` is
the OR of enabled sticky state.

The APU is Resource Controller index 7. LP owner routes to APB-peripheral group
bit23 and Hazard3 IRQ31. HP owner suppresses LP delivery and routes to HP PLIC
source10. Reset masks both. Hardware never delivers one event to both owners.

## Register and Software ABI

### Register map

Unlisted offsets are reserved and return `PSLVERR`.

| Offset | Register | Access | Reset | Contract |
| ---: | --- | --- | ---: | --- |
| `0x000` | `IP_ID` | RO | `0x41505530` | ASCII `APU0`. |
| `0x004` | `IP_VERSION` | RO | `0x00010000` | Public ABI V1.0. |
| `0x008` | `CAPABILITY0` | RO | implementation | Bits 0..2 WAV/MP3/FLAC, 3 private DMA, 4 ring, 5 streams, 6 KWS, 7 sequencer, 8 resampler. P1 is `0`; P2 is `0x00000018`; MVP has 0..8 set. |
| `0x00c` | `CAPABILITY1` | RO | implementation | Control-store KiB `[7:0]`, data SRAM KiB `[15:8]`, max channels `[17:16]`, max source-rate kHz `[25:18]`; P1/P2 are `0`; MVP is 16/112/2/96. |
| `0x010` | `COMMAND` | WO | `0` | Start-direct 0, abort 1, soft-reset 2, ring-kick 3, microcode-load 4, model-load 5, clear-counters 6. |
| `0x014` | `STATUS` | RO | `0x00000100` | Microcode valid 0, model valid 1, busy 2, ring 3, decode 4, KWS listening 5, quiesced 6, aborting 7, idle 8, sequencer trapped 9. |
| `0x018` | `IRQ_STATE` | RW1C | `0` | Sticky events. |
| `0x01c` | `IRQ_ENABLE` | RW | `0` | Event enables. |
| `0x020` | `IRQ_TEST` | WO | `0` | Software event injection. |
| `0x024` | `ERROR_STATUS` | RW1C | `0` | Valid 0/W1C, code `[6:1]`, stage `[10:7]`, AXI response `[12:11]`, descriptor index `[20:13]`. |
| `0x028` | `ERROR_ADDRESS` | RO | `0` | First failing AXI/local/PC address. |
| `0x02c` | `ERROR_DETAIL` | RO | `0` | First format/opcode/primitive/model diagnostic. |
| `0x030` | `SEQUENCER_TIMEOUT` | RW idle | `0x0000ffff` | Nonzero maximum no-retirement cycles. |
| `0x034` | `STREAM_ROUTE` | RW idle | `0` | TX `[1:0]`: DMA0/APU1; RX `[3:2]`: DMA0/APU1. |
| `0x038` | `STREAM_STATUS` | RO | P1 `0`, P2+ `0x00000014` | Frozen live/sticky allocation below. |
| `0x03c` | `OWNER_STATUS` | RO | `0` | Resource owner `[1:0]`, owner lock 8, quiesce 9, reset request 10. |
| `0x040` | `READ_BASE` | RW idle/LP | `0xffffffff` | Inclusive local DMA read base. |
| `0x044` | `READ_LIMIT` | RW idle/LP | `0` | Base greater than limit denies all. |
| `0x048` | `WRITE_BASE` | RW idle/LP | `0xffffffff` | Inclusive local DMA write base. |
| `0x04c` | `WRITE_LIMIT` | RW idle/LP | `0` | Inclusive write limit. |
| `0x050` | `DMA_TIMEOUT` | RW idle | `0x0000ffff` | Nonzero no-progress timeout. |
| `0x054` | `ABI_DIGEST` | RO | `0` until MVP | CRC32 digest over the complete frozen V1 tables; partial P1..P7 implementations report zero. |
| `0x058` | `SEQUENCER_STATUS` | RO | `0` | PC `[10:0]`, class `[14:11]`, opcode `[18:15]`, wait 19, loop-active 20. |
| `0x05c` | `SEQUENCER_RETIRED` | RO | `0` | Saturating instructions retired in current frame/block. |
| `0x060` | `STREAM_WATERMARK` | RW idle | `0` | RX/input high `[7:0]`, TX/output low `[15:8]`, reserved `[31:16]=0`; zero disables, otherwise 1..64. Added in P2. |
| `0x080` | `MC_IMAGE_ADDRESS` | RW idle/LP | `0` | 64-byte-aligned `APUMC` address. |
| `0x084` | `MC_IMAGE_SIZE` | RW idle/LP | `0` | Exact nonzero bundle bytes. |
| `0x088` | `MC_EXPECTED_CRC` | RW idle/LP | `0` | Expected payload CRC32, equal to header. |
| `0x08c` | `MC_STATUS` | RO | `0` | Busy, valid, header/range/control-flow/table/CRC/capability errors. |
| `0x090` | `MC_ABI` | RO | `0` | Loaded microcode ISA ABI. |
| `0x094` | `MC_BUILD_ID_LO` | RO | `0` | Build ID low. |
| `0x098` | `MC_BUILD_ID_HI` | RO | `0` | Build ID high. |
| `0x09c` | `MC_LOCK` | RO | `0` | Set automatically after successful load; hard reset clears. |
| `0x0a0` | `MC_ACTUAL_CRC` | RO | `0` | Observed microcode payload CRC32. |
| `0x0a4` | `MC_LOAD_COUNT` | RO | `0` | Saturating successful-load count. |
| `0x100` | `JOB_CONTROL` | RW idle | `0` | Descriptor word0 operation/format/output/downmix/resample without OWN/IOC. |
| `0x104` | `JOB_INPUT_ADDRESS` | RW idle | `0` | Direct input address. |
| `0x108` | `JOB_INPUT_LENGTH` | RW idle | `0` | Direct input bytes. |
| `0x10c` | `JOB_OUTPUT_ADDRESS` | RW idle | `0` | Direct output address. |
| `0x110` | `JOB_OUTPUT_CAPACITY` | RW idle | `0` | Direct output capacity. |
| `0x114` | `JOB_INPUT_CONFIG` | RW idle | `0` | Descriptor word6. |
| `0x118` | `JOB_OUTPUT_CONFIG` | RW idle | `0` | Descriptor word7. |
| `0x11c` | `JOB_FLAGS` | RW idle | `0` | Descriptor word8. |
| `0x120` | `JOB_STATUS` | RO | `0` | Frozen live/sticky allocation below. |
| `0x124` | `JOB_INPUT_USED` | RO | `0` | Result input bytes. |
| `0x128` | `JOB_OUTPUT_BYTES` | RO | `0` | Result output bytes. |
| `0x12c` | `JOB_FRAMES` | RO | `0` | Result PCM frames. |
| `0x130` | `JOB_SOURCE_INFO` | RO | `0` | Detected source geometry. |
| `0x134` | `JOB_CYCLES` | RO | `0` | Saturating job cycles. |
| `0x138` | `JOB_DETAIL` | RO | `0` | Diagnostic detail. |
| `0x180` | `RING_BASE` | RW idle | `0` | 128-byte-aligned descriptor base. |
| `0x184` | `RING_SIZE` | RW idle | `0` | 2..256 entries, power of two. |
| `0x188` | `RING_HEAD` | RO | `0` | Hardware index. |
| `0x18c` | `RING_TAIL` | RW | `0` | Software index. |
| `0x190` | `RING_CONTROL` | RW idle | `0` | Enable 0, stop-on-error 1. |
| `0x194` | `RING_STATUS` | RO | P1 `0`, P2+ `0x00000004` | Frozen live/sticky allocation below. |
| `0x198` | `RING_COMPLETED` | RO | `0` | Saturating completion count. |
| `0x19c` | `RING_COALESCE` | RW idle | `0x00010001` | Count `[7:0]`, nonzero timeout `[31:16]`. |
| `0x1a0` | `RING_DOORBELL` | WO | `0` | Write one to rescan. |
| `0x200` | `KWS_MODEL_ADDRESS` | RW idle/LP | `0` | 64-byte-aligned `APUM` address. |
| `0x204` | `KWS_MODEL_SIZE` | RW idle/LP | `0` | Exact model bytes. |
| `0x208` | `KWS_MODEL_EXPECTED_CRC` | RW idle/LP | `0` | Expected payload CRC32. |
| `0x20c` | `KWS_CONTROL` | RW idle | `0` | Enable 0, memory-window 1, clear-history pulse 2. |
| `0x210` | `KWS_CONFIG` | RW idle | `0x00000380` | Threshold `[7:0]` 128, debounce `[15:8]` 3. |
| `0x214` | `KWS_STATUS` | RO | `0` | Listening, inference busy, history full, hit, overrun, model valid/locked. |
| `0x218` | `KWS_RESULT` | RO | `0` | Class `[7:0]`, score `[15:8]`, stable hit 16. |
| `0x21c` | `KWS_TIMESTAMP_LO` | RO | `0` | Detection timestamp low. |
| `0x220` | `KWS_TIMESTAMP_HI` | RO | `0` | Detection timestamp high. |
| `0x224` | `KWS_FRAME_COUNT` | RO | `0` | Accepted feature frames. |
| `0x228` | `KWS_INFERENCE_COUNT` | RO | `0` | Completed inferences. |
| `0x22c` | `KWS_HIT_COUNT` | RO | `0` | Stable hits. |
| `0x230` | `KWS_OVERRUN_COUNT` | RO | `0` | Dropped/late windows. |
| `0x234` | `KWS_MODEL_STATUS` | RO | `0` | Busy, valid/lock, header/range/size/CRC/operator errors. |
| `0x238` | `KWS_MODEL_ACTUAL_CRC` | RO | `0` | Observed payload CRC32. |
| `0x300` | `PERF_CONTROL` | RW | `0` | Enable 0, clear pulse 1, snapshot pulse 2. |
| `0x304` | `PERF_STATUS` | RO | `0` | Snapshot valid and overflow summary. |
| `0x308..0x354` | `PERF_*` | RO snapshot | `0` | Ten 64-bit pairs: active cycles, input/output bytes, decoded frames, DMA read/write stalls, stream stalls, sequencer instructions, KWS cycles, and faults. |

P2 freezes these status layouts. Reserved bits read zero and writes to every
status register return `PSLVERR`.

| `STREAM_STATUS` bits | Semantics |
| ---: | --- |
| 0 | `TX_ACTIVE`, live according to the active-direction definition in the stream contract. |
| 1 | `RX_ACTIVE`, live according to the active-direction definition in the stream contract. |
| 2 | `TX_FIFO_EMPTY`, live; reset one from P2 onward. |
| 3 | `TX_FIFO_FULL`, live. |
| 4 | `RX_FIFO_EMPTY`, live; reset one from P2 onward. |
| 5 | `RX_FIFO_FULL`, live. |
| 6 | `TX_UNDERRUN`, sticky until IRQ-state stream-xrun W1C or reset. |
| 7 | `RX_OVERRUN`, sticky until IRQ-state stream-xrun W1C or reset. |
| 15:8 | Saturating low-byte count of TX words accepted by I2S since counter clear/reset. |
| 23:16 | Saturating low-byte count of RX words accepted from I2S since counter clear/reset. |
| 31:24 | Reserved zero. |

The two xrun bits clear together when software W1C-clears IRQ bit 9. A new xrun
in that cycle wins and leaves the corresponding status/IRQ state set.

| `JOB_STATUS` bits | Semantics |
| ---: | --- |
| 0 | `BUSY`, live while a direct or ring-owned job has not reached terminal writeback. |
| 1 | `DONE`, sticky terminal success. |
| 2 | `ERROR`, sticky terminal failure. |
| 3 | `ABORTED`, sticky terminal abort. |
| 4 | `DIRECT_ACTIVE`, live while the current job came from direct registers. |
| 5 | `INPUT_PENDING`, live while input AXI/stream work is outstanding. |
| 6 | `OUTPUT_PENDING`, live while output AXI/stream work is outstanding. |
| 7 | `WRITEBACK_PENDING`, live while descriptor/direct results have not retired. |
| 13:8 | Terminal six-bit error code. |
| 17:14 | Terminal four-bit stage. |
| 19:18 | Terminal AXI response. |
| 31:20 | Reserved zero. |

`DONE` denotes success and is mutually exclusive with `ERROR`. `ABORTED` may
coexist with `ERROR` when drain encounters a higher-priority fault. Terminal
sticky/result fields clear when a new valid internal/public job is accepted or
on soft/resource/hard reset; they do not clear on status read.

| `RING_STATUS` bits | Semantics |
| ---: | --- |
| 0 | `ACTIVE`, live after scheduler start until disabled, aborted, or stopped. |
| 1 | `STALLED_UNOWNED`, live while head points to an unowned descriptor. |
| 2 | `EMPTY`, live when head equals tail and no descriptor/writeback is pending; reset one from P2 onward. |
| 3 | `ERROR`, sticky after a descriptor/ring error. |
| 4 | `WRAPPED`, sticky after head wraps to zero. |
| 5 | `COALESCE_PENDING`, live while pending-completion count is nonzero. |
| 6 | `WRITEBACK_PENDING`, live while result/OWN-clear is outstanding. |
| 7 | `STOPPED_ON_ERROR`, sticky when stop-on-error halts after terminal writeback. |
| 15:8 | Live pending-completion count used by coalescing. |
| 23:16 | Last descriptor index whose result writeback and OWN clear completed. |
| 31:24 | Reserved zero. |

Ring sticky fields, pending count, last index, and coalescing epoch clear on a
legal ring-enable transition from zero to one or on soft/resource/hard reset.
Status reads and IRQ W1C do not clear them.

Capability bits describe implemented hardware, not whether a codec job is
currently legal. P2 reports `CAPABILITY0=0x00000018` for private DMA and ring,
while format, streams, KWS, sequencer, and resampler bits remain zero;
`CAPABILITY1=0`. A caller must require both the requested format/KWS bit and the
necessary engine/model state before submitting. The P2 stream router is not
advertised because its production endpoints remain unavailable. `ABI_DIGEST`
is zero for every partial Phase1..7 build and becomes the nonzero CRC32 over
the complete canonical V1 register/field/descriptor/`APUMC`/`APUM`/opcode/
format/IRQ/error tables only in the Phase8 supported MVP. A zero digest means
prototype/incomplete ABI and is not a compatibility hash for a subset.

Hardware set wins same-cycle W1C. Snapshot captures all 64-bit counters
atomically; software reads low then high.

`MICROCODE_LOAD` and `MODEL_LOAD` require LP owner, quiesced/idle state,
valid ACLs, and a clear corresponding lock; KWS must also be disabled for model
load. `START_DIRECT` requires valid locked microcode and a validated direct
job whose requested format/KWS capability is set. `RING_KICK` requires an
enabled valid ring plus valid locked microcode and a supported operation at
head. `ABORT` requires active work. `SOFT_RESET` and `CLEAR_COUNTERS` require
idle. Therefore P2 continues to reject start and doorbell while accepting and
validating their configuration registers. Violations return `PSLVERR` without
changing state.

### `APUMC` microcode bundle ABI

The bundle starts with a 64-byte header:

| Word | Field |
| ---: | --- |
| 0 | magic `0x41504d43` (`APMC`) |
| 1 | header version `[31:16]`, required microcode ISA ABI `[15:0]`; V1 is `0x00010000` |
| 2 | total bundle bytes |
| 3 | instruction count, 1..2048 |
| 4 | 64-byte-aligned instruction offset |
| 5 | table/constant offset |
| 6 | table/constant bytes, limited by local table region |
| 7 | entry-descriptor offset |
| 8 | entry count; V1 requires exactly 3 |
| 9 | required hardware capability mask |
| 10 | maximum declared local scratch bytes |
| 11 | CRC32/ISO-HDLC over all bytes after the header |
| 12-13 | 64-bit build ID |
| 14-15 | reserved zero |

Three 32-byte entry descriptors follow. Each contains format ID, entry PC,
program first/last PC, scratch base/size, maximum loop count, maximum retired
instructions per frame/block, and required primitive mask. IDs 0/1/2 are
WAV/MP3/FLAC and must each appear exactly once.

Instructions are little-endian 64-bit words:

```text
63     60 59     56 55     52 51     48 47     44 43     40 39      32 31       0
+---------+---------+---------+---------+---------+---------+----------+-----------+
| class   | opcode  | pred    | dst     | src0    | src1    | aux      | immediate |
+---------+---------+---------+---------+---------+---------+----------+-----------+
```

Registers and predicates outside their defined range are illegal. Predicates
are always, zero, nonzero, less-than, greater/equal, bitstream-end, FIFO-ready,
and kernel-done. Opcode classes are:

| Class | Operations |
| ---: | --- |
| 0 | `NOP`, `END`, `TRAP`, forward conditional jump/call, `RET`, loop setup/back, bounded wait |
| 1 | move/immediate, add/sub, and/or/xor, logical/arithmetic shift, compare, min/max, saturate |
| 2 | bitstream refill/peek/get/skip/align, frame sync, CRC8, CRC16 |
| 3 | Huffman symbol/pair/quad, unary scan, Rice/Rice2, sign restore |
| 4 | bounded local load/store/table read, FIFO pop/push |
| 5 | requant, stereo, IMDCT6/18, DCT32/polyphase, fixed/LPC, decorrelate, resample, PCM pack |
| 6 | input refill, output commit/stream, DMA wait, frame commit, job result, event |
| 7-15 | invalid in V1 |

Within each class, V1 opcode numbers are fixed:

| Class | Opcode allocation |
| ---: | --- |
| 0 | 0 NOP, 1 END, 2 TRAP, 3 JUMP_FWD, 4 CALL_FWD, 5 RET, 6 LOOP_SETUP, 7 LOOP_BACK, 8 WAIT |
| 1 | 0 MOV, 1 MOVI, 2 ADD, 3 SUB, 4 AND, 5 OR, 6 XOR, 7 SHL, 8 SHR, 9 SAR, 10 CMP, 11 MIN, 12 MAX, 13 SAT |
| 2 | 0 REFILL, 1 PEEK, 2 GET, 3 SKIP, 4 ALIGN, 5 FRAME_SYNC, 6 CRC8, 7 CRC16 |
| 3 | 0 HUFF_SYMBOL, 1 HUFF_PAIR, 2 HUFF_QUAD, 3 UNARY, 4 RICE4, 5 RICE5, 6 SIGN_RESTORE |
| 4 | 0 LD32, 1 ST32, 2 TABLE8, 3 TABLE16, 4 TABLE32, 5 FIFO_POP, 6 FIFO_PUSH |
| 5 | 0 REQUANT, 1 STEREO, 2 IMDCT6, 3 IMDCT18, 4 DCT32_POLY, 5 FIXED, 6 LPC, 7 DECORRELATE, 8 RESAMPLE, 9 PCM_PACK |
| 6 | 0 INPUT_REFILL, 1 OUTPUT_COMMIT, 2 OUTPUT_STREAM, 3 DMA_WAIT, 4 FRAME_COMMIT, 5 JOB_RESULT, 6 EVENT |

Unallocated opcodes in every valid class are illegal. Class-specific use of
`dst`, `src0`, `src1`, `aux`, and `immediate` is defined by the assembler and
reference-interpreter tables covered by `ABI_DIGEST`; a use not declared by
those frozen V1 tables is rejected rather than ignored.

Only the dedicated loop-back instruction may branch backward. Its counter is
nonzero, bounded by the entry manifest and hardware limit 65535, and decrements
on every taken branch. Conditional jumps/calls are forward only. Call depth is
four. Every entry must reach `END` or `TRAP` under the static verifier; runtime
instruction and no-retirement watchdogs provide a second bound.

Local accesses are restricted to the entry scratch/table ranges. DMA commands
refer only to the active validated descriptor; microcode never supplies a raw
system address. Unknown opcode, PC/table/local range failure, stack error,
undeclared primitive, excessive loop, nonzero reserved field, or CRC mismatch
keeps `MC_STATUS.VALID` clear.

`apu-mcasm` is the single assembler/verifier and produces the binary, symbols,
control-flow/loop report, primitive manifest, deterministic trace input, and
ABI digest. A separate Python interpreter executes the exact ISA for BAM and
microcode/RTL differential tests. Neither tool accepts C, ELF, RV32, dynamic
linking, or runtime code generation.

### `APUM` KWS model ABI

The 64-byte model header contains magic `APUM`, header/model ABI, total bytes,
operator-set ID 1, MFCC geometry 49 by 10, class count 12, parameter bytes,
scratch bytes, signed asymmetric INT8/INT32 quantization ID, payload CRC32,
64-bit model ID, default threshold/debounce, and reserved zero words.

The converter accepts only the frozen KWS operators and static tensor shapes.
Unknown operator, dynamic shape, floating point, unsupported quantization,
class count other than 12, excessive scratch, bad range, or CRC failure keeps
model valid clear. Successful LP load automatically locks the model until hard
reset.

### HAL and compatibility

`<retrosoc/hal/apu.h>` owns discovery, ACL, microcode/model load, direct/ring
submit, stream routing, KWS, interrupt, error, statistics, bounded wait, abort,
and reset. Fallible functions return `rs_status_t` and waits take a timeout.
`<retrosoc/hal/apu_regs.h>` independently mirrors every public constant.

V1 is append-only. Existing offsets, descriptor size, opcode/format/error/IRQ
IDs, `APUMC`, `APUM`, ownership, and lock semantics cannot change within major
version 1. Incompatible behavior requires a new major version and capability
negotiation; software fails closed on unknown major versions.

`STREAM_WATERMARK` at `0x060` is the sole P2 ABI append. P1 continues to return
`PSLVERR` for that formerly reserved offset, while P2 implements it; no P1
offset, accepted field, reset value, or reserved mask is repurposed. P2 updates
the independently handwritten SVH/C tables and parity tests together.

## Clock, Reset, CDC/RDC, and Lifecycle

APB4, DMA source, sequencer, local SRAM, fixed engines, KWS, and stream router
run in PCLK. Mini caps PCLK at 48 MHz. Correctness is required at all supported
dividers; real-time MVP performance is qualified only at 48 MHz.

I2S retains `clk_aud_i`, `rst_aud_n_i`, and existing `cdc_2phase`/
`cdc_fifo_warm_flush` crossings to PCLK. APU consumes only synchronized PCLK
streams. APU AXI crosses PCLK to HP through the existing Common warm-flush
bridge. Topology adds an `apu_data` crossing to the clock/reset inventory;
internal streams remain same-domain.

- Hard/PCLK reset invalidates microcode/model, clears their locks, denies DMA,
  and clears jobs, KWS history, IRQ, errors, and counters.
- Soft reset is idle-only. It resets scheduler, sequencer, engines, streams,
  KWS history, IRQ, and first error while preserving validated locked
  microcode/model and ACLs.
- Busy recovery is abort, wait abort-done/idle, then soft reset. Busy soft reset
  returns `PSLVERR`.
- Resource reset blocks new work, drains accepted AXI/stream traffic, then uses
  soft-reset semantics.
- Quiesce blocks new jobs, stops sequencer at a frame/block boundary, stops KWS
  after the current feature/inference, drains DMA/output, and reports idle only
  after all engines/FIFOs and Gateway A are idle.
- Microcode/model load is legal only with LP owner, quiesced, idle, valid ACL,
  and corresponding lock clear. HP cannot load or unlock them.
- Owner change follows Resource Controller block-new, CDC acknowledgement,
  drain, owner update, and release. Retained KWS enable resumes under the new
  owner; the finite gap is counted.

Unilateral HP reset does not reset PCLK APU state. The AXI bridge warm-flushes
and the active job waits for recovery or timeout. Unilateral PCLK reset
invalidates local state and requires bridge epoch recovery. The inventory and
formal checks do not replace commercial CDC/RDC signoff.

## Errors, Recovery, Security, and Observability

### Error allocation

| Code | Meaning |
| ---: | --- |
| 0 | no error |
| 1 | invalid configuration/APB command |
| 2 | invalid descriptor/ring |
| 3 | unsupported format/feature |
| 4 | malformed container/header |
| 5 | truncated stream |
| 6 | codec CRC/checksum |
| 7 | entropy/decode failure |
| 8 | reconstruction/resampler/PCM failure |
| 9 | invalid microcode header/range/control flow |
| 10 | microcode CRC/capability failure |
| 11 | sequencer trap/watchdog |
| 12 | invalid KWS model/range/operator |
| 13 | KWS model CRC |
| 14 | KWS arithmetic/tensor failure |
| 15 | AXI read response/protocol |
| 16 | AXI write response/protocol |
| 17 | DMA timeout |
| 18 | stream underrun |
| 19 | stream overrun |
| 20 | abort terminal result |
| 21 | resource reset/forced lifecycle termination |
| 22 | FIFO/local-memory/arithmetic overflow |
| 23-63 | reserved |

Stages are APB/config 0, loader 1, descriptor/ring 2, DMA read 3, bitstream 4,
entropy 5, reconstruction/transform 6, resampler/PCM 7, DMA write/stream 8, KWS
frontend 9, KWS inference 10, and lifecycle 11.

First error is immutable until W1C/reset. Later faults increment counters but
do not overwrite code, stage, address/PC, detail, AXI response, or descriptor
index. A requested, successfully drained abort or quiesced resource reset sets
terminal status/IRQ but not first error; code20/21 enters first error only when
forced, timed out, or accepted work was lost.

Simultaneous terminal conditions use this fixed first-error precedence:

1. Hard/PCLK reset clears all status and records no retained error.
2. Forced resource reset or lifecycle loss records code21.
3. AXI write response/protocol failure records code16.
4. AXI read response/protocol failure records code15.
5. DMA no-progress timeout records code17.
6. RX stream overrun records code19.
7. TX stream underrun records code18.
8. A forced abort records code20.

A normal resource reset or successfully drained software abort is not an error.
When several non-reset events coincide, every applicable sticky IRQ/status and
counter is updated, but only the highest item above enters the immutable first
error. An AXI fault observed while abort drains therefore outranks abort. RX
overrun outranks TX underrun because it represents lost input. Hardware event
capture outranks a same-cycle first-error or IRQ W1C.

Format errors terminate the owning job. AXI protocol loss, sequencer trap,
watchdog, impossible internal state, or repeated timeout quiesces the whole APU
until abort/reset. Bad microcode/model never publishes valid or unlocks
execution.

### Security boundary

There is no hardware coherency. Microcode/model bundles, descriptors, input,
output, and writeback use DMA-visible non-cacheable/shared memory or explicit
64-byte CBO maintenance plus `fence rw,rw`. Descriptor OWN is the ownership
handoff point.

Every byte of every DMA burst must fit the local inclusive ACL. Range arithmetic
is overflow checked. Microcode cannot address system memory, APB, or another
local partition directly. LP-only load, static verification, capability checks,
CRC, automatic lock, watchdog, and fail-closed traps are reliability controls,
not authentication. MVP claims no secure boot, confidentiality, DRM,
functional safety, ASIL, or IEC 61508 compliance.

### Observability

The APU exposes loader/model status, current PC/class/opcode, retired
instructions, sticky first error, descriptor results, ring state, stream
FIFO/xrun state, KWS result/timestamp, and atomic snapshot counters. Required
64-bit counters are active cycles, input/output bytes, decoded frames, DMA
read/write stalls, stream stalls, sequencer instructions, KWS cycles, and
faults. Counters saturate.

No waveform-only state is required to diagnose completion, rejection, trap,
bus fault, timeout, abort, xrun, model failure, or lifecycle failure.

## MVP and Commercial-grade Roadmap

### Exact MVP

- WAV RIFF PCM: mono/stereo, 8/16/24/32-bit, 8..96 kHz, checked unknown-chunk
  skip and deterministic sign extension/truncation/saturation without dither.
- MP3: MPEG-1/2/2.5 Layer III, mono/normal/joint/dual stereo, CBR/VBR,
  8..48 kHz, 8..320 kbit/s, and bounded legal ID3v2 skip. Layer I/II and
  unqualified free-format streams fail closed.
- Native FLAC: mono/stereo, 16/24-bit, 8..96 kHz, constant/verbatim/fixed/LPC
  order0..32, Rice/Rice2, independent/left-side/side-right/mid-side, CRC8/16,
  and bounded metadata skip. Ogg mapping is unsupported.
- S16_LE or S24_32LE memory/I2S output; fixed-point resampling to 48/96 kHz,
  including 44.1-to-48 kHz.
- Continuous KWS: 16 kHz mono S16, one-second history, 10 ms feature stride,
  49 by 10 INT8 MFCC, 12 classes, inference each 100 ms, configurable threshold
  and debounce.
- One decode job plus concurrent KWS, direct/ring DMA, APB4, LP/HP ownership,
  interrupts, ACL, timeout, abort/reset, first error, and counters.

### MVP acceptance

1. WAV and FLAC produce bit-exact approved PCM; MP3 conformance vectors exceed
   96 dB PSNR with exact frame/sample/channel accounting.
2. The official MLPerf Tiny KWS 1000-utterance set reaches at least 90 percent
   top-1 through the hardware MFCC/inference path.
3. At 48 MHz PCLK, 320 kbit/s 48 kHz stereo MP3 and continuous KWS run
   concurrently with zero I2S underrun and zero KWS overrun under the qualified
   AXI service envelope.
4. 24-bit/96 kHz FLAC completes without xrun; byte/frame/cycle/stall counters
   match the scoreboard.
5. `APUMC` static verification, instruction interpreter/RTL differential,
   opcode mutation, loop/stack/range/watchdog, loader atomicity, and trap paths
   all fail closed as specified.
6. Random AXI backpressure, 4 KiB boundaries, tails, every AXI error,
   ring wrap, abort/reset at every state, stream backpressure, and LP/HP
   handoff complete with the specified result or bounded error.
7. RTL/C register, descriptor, `APUMC`, `APUM`, instruction, format, IRQ, and
   error definitions pass parity tests.
8. IHP130 firmware, behavioral, formal, synthesis, netlist, and OpenSTA
   evidence is reviewed with no unowned warning; metrics remain under policy.

Post-MVP work may optimize MAC lanes, pipeline kernels, bank SRAM, or add a
dedicated fabric identity only after counters identify a bottleneck. It must
preserve V1 public ABI and microcode capability semantics. Deferred codecs,
power, coherency, or security require a new approved phase/spec revision.

## Verification and Software Validation

### Golden models and tools

- `apu-mcasm` and the Python microcode interpreter are self-owned and tested
  from the same frozen ISA definitions without generated register RTL.
- WAV uses the existing bounded reader model extended for the frozen subset.
- MP3 primitive and full-flow vectors are derived from standards/conformance
  material and compared with two independent decoders; the maintained
  [AOSP fixed-point decoder source](https://android.googlesource.com/platform/frameworks/av/+/b7a5619/media/libstagefright/codecs/mp3dec/src/)
  is a partitioning/reference input, not shipped APU code.
- FLAC uses RFC 9639, locked Xiph libFLAC, and the official
  [FLAC test files](https://github.com/ietf-wg-cellar/flac-test-files).
- MLPerf Tiny inputs/model/converter revision and generated `APUM` are locked
  and reproducible.

All new external corpora or reference packages require exact revisions or
archive checksums in the dependency lock. Managed source retains notices and
does not become evidence of self-owned MISRA conformance.

### Required evidence matrix

| Area | Required evidence |
| --- | --- |
| APB/register | Decode, waits, strobes, RO/WO, busy protection, W1C/set priority, reset, capability, and RTL/C parity. |
| DMA/ring | Native AXI BFM plus the P2 verification-only backend cover internal direct/ring ownership, writeback, wrap, coalescing epochs/IOC, 4 KiB split, tails, ACL overflow, faults, abort, and timeout without a public diagnostic operation. |
| Streams | P2 verification-only endpoints cover both production router/FIFO directions, random backpressure, watermark/xrun, active detection, and route protection; later phases add S16/S24/TLAST and concurrent codec/KWS product endpoints. |
| Assembler/loader | Syntax and semantic rejection, deterministic binary, all control-flow/loop/stack/range checks, CRC, capability, atomic valid/lock, mutation/fuzz. |
| Sequencer/formal | PC/control-store bounds, only bounded loop-back, counter decrement, call depth, watchdog, no system/APB access, descriptor-only DMA handles, legal traps. |
| Primitives | Bitstream/CRC, every Huffman/Rice mode, arithmetic extremes, saturation, transform/LPC/resampler differential, latency bounds. |
| Codecs | Complete-file differential, sample/rate/channel counts, malformed/truncated/adversarial corpus, metadata limits, reservoir/LPC extremes, long playlists. |
| KWS | MFCC differential, every INT8 layer tensor, converter rejection, official accuracy, threshold/debounce, continuous stream and overrun. |
| SoC | Address/topology, Gateway A fairness, Resource7, IRQ31/PLIC10 exclusion, cache maintenance, handoff, warm flush, HP reset, USB2/SDIO0 contention. |
| Software | HAL validation/timeouts/errors, microcode/model load, owner handoff, bare-metal acceptance, and Linux ASoC tests when delivered. |

An internal KWS result is not called MLPerf unless the exact applicable rules
and runner are followed. File interoperability alone is not codec certification.

## Synthesis, Timing, and Physical Evidence

The committed MVP profile is `configs/ci/ihp130.mk`. Block and full-SoC
synthesis use locked Yosys. OpenSTA analyzes the 20.833 ns/48 MHz PCLK target
and existing asynchronous relationships. Correctness at slower dividers is
required but no slower-clock real-time claim follows.

Evidence includes:

- control-store and local-SRAM macro count/utilization;
- sequencer, entropy, transform, reconstruction, resampler, and KWS cells/area;
- max/min WNS/TNS, worst APU paths, reset/fanout, clock gates, and black boxes;
- instruction/control-store high-water, maximum frame instruction count,
  loop/call high-water, local SRAM high-water, and primitive cycles;
- decoder/KWS cycles, DMA/stream stalls, sustained bandwidth, and concurrent
  workload utilization;
- netlist simulation, warning JSON, metrics JSON, and manifest evidence.

No target area or power number is approved before measurement. A successful
tool exit is not closure. Commercial release additionally needs qualified SRAM
views for every product PDK, CDC/RDC, scan/ATPG, MBIST/repair, PVT/MMMC, CTS,
extracted STA, activity power, IR/EM, SDF, package/board audio timing, and
silicon characterization.

## Development Order

The following phase IDs and titles are frozen. They MUST NOT be renamed,
renumbered, or reused; later work receives a new phase.

### Phase 0 - Freeze Coreless Microcode Architecture and ABI

ID: `APU-P0`.

Scope: this specification, requirements, coreless hierarchy, ISA, `APUMC`,
`APUM`, descriptor/register/error/IRQ ABI, format limits, KWS baseline, golden
models, dependency plan, and stable phases.

Changes: documentation/index/RTL guide only. It freezes future public
interfaces but changes no executable RTL, address map, software, dependency,
clock/reset inventory, or CI.

Validation:

```sh
git diff --check
```

Completion: all links/commands resolve, rejected processor/host-decode behavior
is absent from normative requirements, and all deferred work is explicit.

### Phase 1 - APB4 Shell, Resource Ownership, and IRQ Topology

ID: `APU-P1`.

Scope: APB register shell, reset/capability/command/error/IRQ, fail-closed
datapath stubs, Resource index7, APB slot, LP IRQ31, HP PLIC10, HAL discovery,
manual C/SVH definitions, and parity tests.

Dependencies: Phase0.

Public changes: activates `APB4_APU`, extends resource count and IRQ topology;
no DMA, microcode, stream, or CDC behavior is implemented.

Validation:

```sh
make check-memory-map check-soc-topology
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke firmware
```

Completion: every APB/reset/access case and topology/parity check passes;
datapath commands return the frozen unsupported/error behavior.

### Phase 2 - Private AXI4 DMA and Audio Stream Routing

ID: `APU-P2`.

Scope: direct/ring DMA, descriptors, ACL, fair Gateway A arbitration,
PCLK-to-HP integration, stream router/FIFOs, I2S directions, abort/drain, bus
errors, P2 status/watermark semantics, and counters.

Dependencies: Phase1 and existing Common interfaces/FIFO/CDC/arbitration.

Public changes: implements DMA/ring/ACL transport, the appended
`STREAM_WATERMARK` register, frozen `STREAM_STATUS`/`JOB_STATUS`/
`RING_STATUS` fields, `CAPABILITY0=0x00000018`, and the `apu_data` CDC
inventory. `CAPABILITY1`, `ABI_DIGEST`, format/stream/KWS/sequencer/resampler
capabilities, public start/doorbell, and public APU stream routes remain at the
specified fail-closed P1 values. No sequencer, primitive, codec, KWS, public
diagnostic operation, or synthesized diagnostic endpoint is added.

Validation:

```sh
make check-soc-topology check-clock-reset-domains
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-lint
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim
```

Completion: the production DMA and ring scheduler pass direct/ring directed and
random tests through the verification-only backend; the production router and
both 64-word FIFO directions pass standalone backpressure/watermark/xrun tests;
public start/doorbell and route value1 remain rejected; every bus fault,
timeout, coalescing epoch, writeback, and abort path is bounded; status/IRQ/C
parity passes; Gateway A fairness is demonstrated. No P3..P7 engine is required
for P2 completion.

### Phase 3 - Microcode Assembler, Loader, and Sequencer

ID: `APU-P3`.

Scope: `apu-mcasm`, reference interpreter, ISA tables, `APUMC` loader,
2048x64 control store, scalar/loop/call state, local-memory protection,
watchdog/traps, loader lock, ABI parity, co-simulation, and formal.

Dependencies: Phase2 and qualified 4 KiB SRAM abstraction.

Public changes: implements the frozen microcode loader/ISA/status ABI. It adds
no processor, system hart, new clock domain, or arbitrary code execution.

Validation:

```sh
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-lint
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
```

Completion: valid microcode runs deterministic dummy programs; all malformed
ISA/control-flow/range/CRC/capability/watchdog cases fail closed; control-store
mapping and size are reviewed.

### Phase 4 - Shared Bitstream, Entropy, and DSP Primitive Engines

ID: `APU-P4`.

Scope: reservoir, CRC, Huffman/Rice, scalar reconstruction, transform,
resampler/PCM packer, 112 KiB local SRAM arbitration, primitive scoreboard,
latency counters, extreme arithmetic tests, and formal bounds.

Dependencies: Phase3.

Public changes: implements existing capability bits and primitive manifest;
no new public register, opcode class, or format ID may be added.

Validation:

```sh
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-lint
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta
```

Completion: every primitive matches BAM over directed/random/extreme inputs,
meets latency bounds, reports faults, and closes the 48 MHz block target or
records a blocking failure.

### Phase 5 - WAV and FLAC Microprograms

ID: `APU-P5`.

Scope: WAV/FLAC microassembly, tables, metadata/frame parsing, PCM conversion,
Rice/fixed/LPC/decorrelation, resampling, memory/I2S output, interpreter/RTL
differential, conformance corpus, and HAL decode.

Dependencies: Phase4 and locked RFC/libFLAC/test inputs.

Public changes: enables format IDs0 and2 only; no ABI layout change.

Validation:

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk firmware
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim
```

Completion: supported WAV/FLAC matrices and malformed corpora pass; FLAC is
bit-exact; 44.1-to-48 and 24-bit/96 kHz playback meet xrun/counter gates.

### Phase 6 - MP3 Layer III Microprogram and Real-Time Closure

ID: `APU-P6`.

Scope: MP3 microassembly/tables, ID3/header/side-info/reservoir, scalefactors,
Huffman, requant/reorder/antialias/stereo, IMDCT/polyphase, conformance,
long-playback, instruction/control-store optimization, and real-time/PPA.

Dependencies: Phase5 and locked MP3 conformance/reference inputs.

Public changes: enables format ID1; no new opcode class or public ABI.

Validation:

```sh
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk firmware
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta
```

Completion: supported modes/conformance pass PSNR and accounting gates;
320 kbit/s stereo meets real-time; 2048-word store, SRAM, area, and timing
evidence is reviewed.

### Phase 7 - Independent Continuous KWS Engine

ID: `APU-P7`.

Scope: 16 kHz input, MFCC, `APUM` converter/loader/lock, fixed INT8 engine,
continuous scheduler, threshold/debounce, diagnostic operation1, IRQ, accuracy,
performance, and concurrent decode/KWS.

Dependencies: Phase6 and locked MLPerf Tiny model/data inputs.

Public changes: implements frozen KWS/model/descriptor-operation/IRQ/counter
ABI; no generic NPU interface.

Validation:

```sh
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta
```

Completion: MFCC/layer differential passes, official accuracy is at least
90 percent, continuous scheduling has no unexplained loss, and concurrent
MP3/KWS meets the xrun gate.

### Phase 8 - LP/HP Software, Contention, and Physical Evidence

ID: `APU-P8`.

Scope: complete HAL, LP-only startup load, HP ownership/jobs, cache maintenance,
Linux ASoC, handoff, USB2/SDIO0 contention, full regression, synthesis recipes,
netlist, OpenSTA, warnings/metrics, and commercial-gap report.

Dependencies: Phases1..7.

Public changes: completes frozen HAL/Linux surfaces; V1 register/descriptor/
microcode/model/address/IRQ/resource/clock allocation cannot change.

Validation:

```sh
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make regress-pr
make regress-nightly
```

Completion: every objective MVP item passes; IHP130 block/full-SoC evidence is
reviewed; unrun commercial gates remain explicit; no unsupported claim ships.

## Commercial Delivery Gaps

The following remain release blockers after MVP unless separately closed:

- full requirements-to-test traceability and functional/code coverage closure;
- reusable APB4/AXI4/AXI4-Stream/I2S/microcode/descriptor/fault VIP;
- licensed MPEG conformance, independent long-run decoder interoperability,
  fuzzing, vulnerability intake, and codec maintenance process;
- KWS false-positive/false-negative qualification across speakers, accents,
  noise, microphones, rooms, and target languages;
- authenticated/anti-rollback microcode/model update, confidential storage,
  secure debug, and protected-content architecture;
- CDC/RDC and reset/clock-gating signoff with unilateral-reset fault injection;
- qualified SRAM for every PDK, ECC decision, MBIST/repair, scan/ATPG, and DFT;
- PVT/MMMC, CTS, extracted STA, SI, IR/EM, power, thermal, package, and board;
- gate/SDF, FPGA prototype, silicon characterization, audio quality, sustained
  contention, and production soak;
- upstream-quality Linux ASoC, recovery/update policy, release notes, SBOM,
  notices, integration examples, and versioned artifacts; and
- every deferred codec, channel, low-power, coherency, safety, or security item.
