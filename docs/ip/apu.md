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
| `0x008` | `CAPABILITY0` | RO | implementation | Bits 0..2 WAV/MP3/FLAC, 3 private DMA, 4 ring, 5 streams, 6 KWS, 7 sequencer, 8 resampler. P1 is `0`; P2 is `0x00000018`; P3 is `0x00000098`; P4 is `0x00000198`; P5 is `0x000001bd`; MVP has 0..8 set. |
| `0x00c` | `CAPABILITY1` | RO | implementation | Control-store KiB `[7:0]`, data SRAM KiB `[15:8]`, max channels `[17:16]`, max source-rate kHz `[25:18]`; P1/P2 are `0`; P3 is `0x00000010`; P4/P5 are `0x01827010`; MVP is 16/112/2/96. |
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
| `0x08c` | `MC_STATUS` | RO | `0` | Busy 0, valid 1, header error 2, range error 3, control-flow error 4, table error 5, CRC error 6, capability error 7; `[31:8]` reserved zero. |
| `0x090` | `MC_ABI` | RO | `0` | Loaded combined major/minor microcode ABI; V1.0 is `0x00010000`. |
| `0x094` | `MC_BUILD_ID_LO` | RO | `0` | Build ID low. |
| `0x098` | `MC_BUILD_ID_HI` | RO | `0` | Build ID high. |
| `0x09c` | `MC_LOCK` | RO | `0` | Lock bit 0 sets automatically after successful load; `[31:1]` reserved zero; hard reset clears. |
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
`CAPABILITY1=0`. P3 reports `CAPABILITY0=0x00000098` for private DMA, ring, and
the sequencer, and `CAPABILITY1=0x00000010` for the 16 KiB control store. P3
continues to report zero for every format, stream, KWS, resampler, data-SRAM,
channel, and sample-rate field. P4 reports `CAPABILITY0=0x00000198` for private
DMA, ring, sequencer, and the implemented resampler primitive, and
`CAPABILITY1=0x01827010` for 16 KiB control store, 112 KiB local data SRAM,
two-channel primitive capacity, and 96 kHz maximum source-rate capacity. P4
format bits 0..2, streams bit 5, and KWS bit 6 remain zero because no public
codec or stream session exists. A caller must require both the requested
format/KWS bit and the necessary engine/model state before submitting. The P2
stream router remains unadvertised through P4 because its production endpoints
remain unavailable. `ABI_DIGEST`
is zero for every partial Phase1..7 build and becomes the nonzero CRC32 over
the complete canonical V1 register/field/descriptor/`APUMC`/`APUM`/opcode/
format/IRQ/error tables only in the Phase8 supported MVP. A zero digest means
prototype/incomplete ABI and is not a compatibility hash for a subset.

Hardware set wins same-cycle W1C. Snapshot captures all 64-bit counters
atomically; software reads low then high.

`MICROCODE_LOAD` and `MODEL_LOAD` require LP owner, quiesced/idle state,
valid ACLs, and a clear corresponding lock; KWS must also be disabled for model
load. P3 makes `MICROCODE_LOAD` legal under those conditions, but does not make
any decode or stream transport public; `MODEL_LOAD` remains rejected until its
later phase. `START_DIRECT` requires valid locked
microcode and a validated direct job whose requested format/KWS capability is
set. `RING_KICK` requires an enabled valid ring plus valid locked microcode and
a supported operation at head. `ABORT` requires active work. `SOFT_RESET` and
`CLEAR_COUNTERS` require idle. Therefore P2 and P3 reject public start and
doorbell, and reject `STREAM_ROUTE` value 1 in either direction, while accepting
and validating their configuration registers. The P3 dummy-program sequencer
launch path is verification-only and creates no public command, descriptor
operation, route, capability, or ABI. Violations return `PSLVERR` without
changing state.

### `APUMC` microcode bundle ABI

All multibyte bundle fields and instructions are little-endian. The bundle
starts with this exact 64-byte header:

| Word | Field |
| ---: | --- |
| 0 | magic `0x41504d43` (`APMC`) |
| 1 | combined APUMC/ISA ABI: major `[31:16]`, minor `[15:0]`; P3 accepts exactly V1.0, `0x00010000` |
| 2 | total bundle bytes |
| 3 | instruction count, 1..2048 |
| 4 | 64-byte-aligned instruction offset |
| 5 | table-payload offset, 4-byte aligned |
| 6 | table-payload bytes |
| 7 | entry-descriptor offset, 32-byte aligned |
| 8 | entry count; V1 requires exactly 3 |
| 9 | required primitive mask, equal to the OR of all entry primitive masks |
| 10 | maximum declared local scratch bytes |
| 11 | CRC32/ISO-HDLC over all bytes after the header |
| 12 | build ID bits `[31:0]` |
| 13 | build ID bits `[63:32]` |
| 14-15 | reserved zero |

The header total must equal `MC_IMAGE_SIZE` and be at least 160 bytes. The
instruction byte count is exactly instruction count multiplied by eight. The
header, descriptor array, instruction array, and table payload must lie wholly
inside the total, must not overlap, and address arithmetic must not wrap. A
zero-byte table payload is represented by word 6 equal to zero; word 5 remains
range checked and aligned but is otherwise ignored. Bytes not occupied by one
of those regions are padding and must be zero. `MC_EXPECTED_CRC`, header
word 11, and the CRC32/ISO-HDLC calculated over bundle bytes 64 through the end
in increasing byte-address order must all agree. CRC parameters are reflected
polynomial `0xedb88320` (normal form `0x04c11db7`), initial value
`0xffffffff`, and final XOR `0xffffffff`. Any other word-1 value, reserved bit,
entry count, alignment, size, range, overlap, or CRC relation is invalid.

The descriptor array contains these exact three 32-byte, eight-word entries:

| Word | Bit allocation and units |
| ---: | --- |
| 0 | format ID `[3:0]`; entry PC `[14:4]`; `[31:15]` reserved zero |
| 1 | program-first PC `[10:0]`; `[15:11]` reserved zero; program-last PC `[26:16]`; `[31:27]` reserved zero |
| 2 | scratch base byte offset `[16:0]`; `[31:17]` reserved zero |
| 3 | scratch size in bytes `[16:0]`; `[31:17]` reserved zero |
| 4 | maximum loop count `[15:0]`; `[31:16]` reserved zero |
| 5 | maximum retired instructions per frame/block `[23:0]`; `[31:24]` reserved zero |
| 6 | required primitive mask `[31:0]` |
| 7 | table-relative byte offset `[15:0]`; table bytes `[31:16]` |

PC fields are 64-bit instruction indices, not byte addresses. Descriptor array
indices 0, 1, and 2 have format IDs 0, 1, and 2 for WAV, MP3, and FLAC
respectively. For each entry, first PC is less than or equal to entry PC, entry
PC is less than or equal to last PC, and last PC is less than the header
instruction count. Scratch base and size are four-byte aligned, do not wrap,
and lie within the advertised local data SRAM. Maximum
loop count is 1..65535 and maximum retired count is nonzero. Table offset and
size are four-byte aligned and select a non-wrapping range inside the global
table payload. Word 10 of the header equals the greatest scratch end declared
by any entry.

P3 has no local data SRAM or primitive engine. It therefore accepts only
scratch base/size zero, table offset/size zero, header table bytes zero, and
header/entry primitive masks zero. Its required three entries may contain only
class-0 control and class-1 scalar instructions. A nonzero scratch/table field,
primitive mask, or class-2 through class-6 instruction fails load validation;
P3 never publishes table bytes. P4 adds the local table/SRAM and primitive
capabilities needed to admit those already frozen encodings. This restriction
does not pull a codec, table engine, or P4 storage into P3.

Primitive mask bits are fixed as follows. Bits 21..31 are reserved zero. Every
instruction's listed primitive must appear in its entry mask, every entry mask
must be a subset of the implemented mask, and the header mask is exactly the
OR of the three entry masks.

| Bit | Primitive | Bit | Primitive |
| ---: | --- | ---: | --- |
| 0 | bitstream reservoir | 11 | fixed predictor |
| 1 | CRC | 12 | LPC |
| 2 | Huffman | 13 | channel decorrelate |
| 3 | Rice | 14 | resampler |
| 4 | local memory/table | 15 | PCM pack |
| 5 | local FIFO | 16 | DMA input |
| 6 | requantize | 17 | DMA output |
| 7 | stereo processing | 18 | stream output |
| 8 | IMDCT6 | 19 | frame commit/job result |
| 9 | IMDCT18 | 20 | event |
| 10 | DCT32/polyphase |  |  |

Instructions are little-endian 64-bit words:

```text
63     60 59     56 55     52 51     48 47     44 43     40 39      32 31       0
+---------+---------+---------+---------+---------+---------+----------+-----------+
| class   | opcode  | pred    | dst     | src0    | src1    | aux      | immediate |
+---------+---------+---------+---------+---------+---------+----------+-----------+
```

The sequencer has 16 32-bit GPRs, three comparison flags (`EQ`, signed `LT`,
and unsigned `LT`), four 11-bit return-stack entries, and four loop slots. All
are cleared at entry launch and on soft, resource, or hard reset. Every GPR is
writable. GPR writes become visible to the next retired instruction. `CMP` is
the only instruction that changes comparison flags. Arithmetic `ADD` and `SUB`
wrap modulo 2^32; only `SAT` saturates. Variable shifts use the low five bits
of `src1`. Default next PC is current PC plus one.

Predicate encodings are exact:

| `pred` | Condition |
| ---: | --- |
| 0 | always |
| 1 | comparison `EQ` |
| 2 | not comparison `EQ` |
| 3 | comparison signed `LT` |
| 4 | not comparison signed `LT` |
| 5 | comparison unsigned `LT` |
| 6 | not comparison unsigned `LT` |
| 7 | descriptor input exhausted and bit reservoir empty |
| 8 | input FIFO nonempty |
| 9 | output FIFO not full |
| 10 | fixed-kernel completion latch set |
| 11 | no transport outstanding and the last transport command succeeded |
| 12-15 | invalid |

A false predicate is a one-cycle semantic NOP: it retires, increments the
per-frame retired count, and advances PC by one without other side effects.
Encoding and operand legality are still checked by the loader regardless of
the predicate. Unless an opcode says otherwise, reserved operand fields must
be zero. Register fields required by an opcode are 0..15; an opcode that
produces multiple registers states the tighter `dst` limit.

Opcode classes are:

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
`dst`, `src0`, `src1`, `aux`, and `immediate` is frozen below. A use not listed
is rejected rather than ignored.

#### Control and scalar semantics

| Class.op | Operands and execution |
| --- | --- |
| `0.0 NOP` | `dst/src0/src1/aux/immediate=0`; no effect. |
| `0.1 END` | all operand fields zero; when true, stalls until accepted kernel/transport/writeback work has drained, then terminates and commits the latched `JOB_RESULT`; code zero is success and a nonzero code is terminal error. If none was latched, the committed result is zero/success. A drained engine/transport fault traps instead. |
| `0.2 TRAP` | `dst/src0/src1/aux=0`; when true, traps with `immediate` as `ERROR_DETAIL`. |
| `0.3 JUMP_FWD` | only `immediate[10:0]` is used and is 1..2047; target is `PC+1+delta` and must be inside the entry program range. |
| `0.4 CALL_FWD` | same target rule as `JUMP_FWD`; pushes `PC+1`, then branches; a fifth nested call traps. |
| `0.5 RET` | all operands zero and predicate must be always; pops and branches; empty stack traps. |
| `0.6 LOOP_SETUP` | predicate always; `aux[1:0]` selects an inactive loop slot, `aux[7:2]=0`, count is `R[src0][15:0]`, and other fields are zero. Count must be nonzero and no greater than the descriptor maximum; the slot records count and `PC+1` as its loop-start PC. |
| `0.7 LOOP_BACK` | predicate always; `aux[1:0]` selects the active slot, `immediate[10:0]` is a nonzero backward distance, and other fields are zero. `PC+1-distance` must equal the slot's recorded loop-start. Count greater than one is decremented and branches there; count one clears the slot and falls through. Inactive slot, underflow, or target mismatch/range failure traps. |
| `0.8 WAIT` | predicate always; `aux` source 0 DMA, 1 kernel, 2 input-FIFO ready, 3 output-FIFO ready, 4 TX-stream accepted/idle, or 5 ring writeback complete; all other operands zero. It stalls without retiring until true. Other sources are invalid. |
| `1.0 MOV` | `R[dst]=R[src0]`; `src1/aux/immediate=0`. |
| `1.1 MOVI` | `R[dst]=immediate`; `src0/src1/aux=0`. |
| `1.2 ADD` | `R[dst]=R[src0]+R[src1]` modulo 2^32; `aux/immediate=0`. |
| `1.3 SUB` | `R[dst]=R[src0]-R[src1]` modulo 2^32; `aux/immediate=0`. |
| `1.4 AND` | `R[dst]=R[src0]&R[src1]`; `aux/immediate=0`. |
| `1.5 OR` | `R[dst]=R[src0]|R[src1]`; `aux/immediate=0`. |
| `1.6 XOR` | `R[dst]=R[src0]^R[src1]`; `aux/immediate=0`. |
| `1.7 SHL` | `R[dst]=R[src0]<<R[src1][4:0]`; `aux/immediate=0`. |
| `1.8 SHR` | logical right shift by `R[src1][4:0]`; `aux/immediate=0`. |
| `1.9 SAR` | signed arithmetic right shift by `R[src1][4:0]`; `aux/immediate=0`. |
| `1.10 CMP` | sets `EQ`, signed `LT`, and unsigned `LT` from `R[src0]` versus `R[src1]`; `dst/aux/immediate=0`. |
| `1.11 MIN` | `aux[0]` selects unsigned 0 or signed 1 minimum of `R[src0]` and `R[src1]`; `aux[7:1]=0`, `immediate=0`. |
| `1.12 MAX` | `aux[0]` selects unsigned 0 or signed 1 maximum; `aux[7:1]=0`, `immediate=0`. |
| `1.13 SAT` | saturates `R[src0]` to a width selected by `aux[4:0]`: 0 means 32, or literal 8, 16, or 24; `aux[5]` selects unsigned 0 or signed 1, `aux[7:6]=0`, `src1/immediate=0`; result is zero- or sign-extended into `R[dst]`. |

`WAIT` source 0 is true when no private AXI command/beat/response is pending and
the last DMA command succeeded; a latched DMA error traps instead. Source 1 is
true when the kernel completion latch is set, source 2 when the input FIFO is
nonempty, source 3 when the output FIFO is not full, source 4 when no
microcode-issued stream payload remains unaccepted, and source 5 when no ring
writeback remains pending. Source 0 or 5 requires the relevant DMA primitive,
source 1 requires the entry's kernel primitive, sources 2/3 require local FIFO,
and source 4 requires stream output. P3 zero-mask dummy programs therefore
cannot contain `WAIT`.

#### Bitstream, entropy, and local-data semantics

| Class.op | Operands and execution |
| --- | --- |
| `2.0 REFILL` | `immediate[5:0]` is 1..32 required valid bits; stalls until present or descriptor EOF and writes the valid-bit count to `R[dst]`; EOF itself does not trap. Other operands are zero. |
| `2.1 PEEK` | width is `immediate[5:0]`, 1..32; writes the next bits to `R[dst]` without consuming. Insufficient bits at EOF trap as truncated stream. Other operands are zero. |
| `2.2 GET` | same as `PEEK`, then consumes the bits. |
| `2.3 SKIP` | width is `immediate[5:0]`, 1..32; consumes without a result; insufficient bits trap. Other operands are zero. |
| `2.4 ALIGN` | all operands zero; consumes 0..7 bits to reach the next input byte. |
| `2.5 FRAME_SYNC` | byte-aligned scan for a masked 8..16-bit value: pattern `R[src0][15:0]`, mask `R[src1][15:0]`, width `aux[4:0]`, maximum scan bytes `immediate[15:0]` 1..65535; `R[dst]` receives skipped bytes and the matching byte remains at the head. No match before limit/EOF traps. Upper aux/immediate bits are zero. |
| `2.6 CRC8` | updates accumulator `R[src0][7:0]` with byte `R[src1][7:0]` using the MSB-first polynomial `0x07`, initial/final XOR zero, and writes the eight-bit result to `R[dst]`; no reservoir side effect; `aux/immediate=0`. |
| `2.7 CRC16` | updates accumulator `R[src0][15:0]` with byte `R[src1][7:0]` using the MSB-first polynomial `0x8005`, initial/final XOR zero, and writes the 16-bit result to `R[dst]`; no reservoir side effect; `aux/immediate=0`. |
| `3.0 HUFF_SYMBOL` | canonical table starts at entry-table byte offset `R[src0]`, contains `R[src1]` entries, and has maximum code length `aux[4:0]` 1..24; consumes a code and writes its 16-bit symbol to `R[dst]`; `immediate=0`. |
| `3.1 HUFF_PAIR` | same lookup fields as `HUFF_SYMBOL`; decoded symbol nibbles are written to `R[dst]` and `R[dst+1]`, so `dst<=14`. |
| `3.2 HUFF_QUAD` | same lookup fields; four decoded one-bit values are written to `R[dst..dst+3]`, so `dst<=12`. |
| `3.3 UNARY` | `aux[0]` selects zeros-until-one 0 or ones-until-zero 1; `immediate[15:0]` is a nonzero maximum; consumes the terminator and writes the run length to `R[dst]`; source fields and upper bits are zero. |
| `3.4 RICE4` | parameter `k=R[src0][3:0]`; for `k<15`, reads zero-run quotient `q`, its one terminator, and `k` remainder bits, then maps `u=(q<<k)|remainder` to signed `(u>>1) ^ -(u&1)` in `R[dst]`. For `k=15`, reads `R[src1][5:0]` bits (1..32) as a two's-complement residual. `aux/immediate=0`. |
| `3.5 RICE5` | as `RICE4`, with `k=R[src0][4:0]`, escape value 31, and the same 1..32-bit raw width. |
| `3.6 SIGN_RESTORE` | base magnitude is `R[src0]` and linbits count is `R[src1][4:0]`; nonzero magnitude consumes linbits to form `magnitude+extra`, then one sign bit and writes its positive value for sign 0 or two's-complement negative for sign 1 to `R[dst]`. Zero magnitude consumes neither and returns zero; `aux/immediate=0`. |
| `4.0 LD32` | loads `R[dst]` from descriptor scratch base plus `R[src0]+sign_extend(immediate[15:0])`; `src1/aux` and upper immediate bits are zero. |
| `4.1 ST32` | stores `R[src1]` to the same scratch address calculation; `dst/aux` and upper immediate bits are zero. |
| `4.2 TABLE8` | loads and zero-extends table element at entry table base plus `R[src0]+R[src1]`; `aux/immediate=0`. |
| `4.3 TABLE16` | as `TABLE8`, with index `R[src1]*2`; address must be two-byte aligned. |
| `4.4 TABLE32` | as `TABLE8`, with index `R[src1]*4`; address must be four-byte aligned. |
| `4.5 FIFO_POP` | `aux=0` selects the input-byte FIFO; stalls while empty, writes a little-endian 32-bit word to `R[dst]` and literal valid-byte count 1..4 `[2:0]` plus last flag bit 8 to `R[dst+1]`; `dst<=14`, sources/immediate zero, and all other sideband bits are zero. |
| `4.6 FIFO_PUSH` | `aux=0` selects the PCM-output FIFO; stalls while full, pushes little-endian `R[src0]` with literal valid-byte count 1..4 `[2:0]` and last flag bit 8 from `R[src1]`; other sideband bits must be zero and trap before push otherwise; `dst/immediate=0`. |

A `PEEK` or `GET` result is right-aligned in the destination; the earliest bit
in the MSB-first reservoir becomes result bit `width-1`. CRC results and Huffman
symbols are zero-extended to 32 bits. A canonical Huffman table entry is one 32-bit word with symbol `[15:0]`, code
length `[20:16]` in 1..24, and `[31:21]` zero, in canonical-code order. All
entries are ordered first by increasing length and then increasing canonical
code; the first code of each length is derived by the canonical prefix rule.
An invalid prefix or exhausted bounded table traps as entropy/decode failure.
All reservoir reads use the codec-defined most-significant-bit-first order.
Local loads/stores are little-endian, must be naturally aligned, stay within
the active entry scratch range, and must not access the read-only table range.
Table reads must stay
inside the active entry table slice. Range checks include the complete access
and trap before any partial side effect.

#### Kernel and transport semantics

Only one fixed-kernel request may be outstanding. For class 5, the values in
`R[src0]`, `R[src1]`, and pre-issue `R[dst]` are input, coefficient/state, and
output byte offsets relative to the descriptor scratch base. The low 16 bits
of `immediate` are a nonzero element/block count and upper bits are zero. Issue
stalls until accepted, retires on acceptance, clears the kernel-done latch, and
completion sets that latch and replaces `R[dst]` with the produced element
count. `dst` is pending between acceptance and completion; any instruction
that would read or overwrite a pending GPR stalls. An unsuccessful kernel
completion traps at the next retirement boundary with error code 8, or code 22
for reported FIFO/local/arithmetic overflow. A dynamic range/alignment failure
traps before issue.

| Class.op | `aux` and operation |
| --- | --- |
| `5.0 REQUANT` | shift `[4:0]`, round-to-nearest bit 5, output width `[7:6]`: 0 S16, 1 S24, 2 S32, 3 invalid. |
| `5.1 STEREO` | mode `[1:0]`: independent, left-side, side-right, or mid-side; `[7:2]=0`. |
| `5.2 IMDCT6` | six-point transform blocks; `aux=0`. |
| `5.3 IMDCT18` | eighteen-point transform blocks; `aux=0`. |
| `5.4 DCT32_POLY` | 32-point/polyphase subband blocks; `aux=0`. |
| `5.5 FIXED` | predictor order `aux[2:0]` 0..4; `[7:3]=0`. |
| `5.6 LPC` | predictor order `aux[5:0]` 1..32; `[7:6]=0`. |
| `5.7 DECORRELATE` | channel mode `[1:0]` as `STEREO`; `[7:2]=0`. |
| `5.8 RESAMPLE` | coefficient profile `aux[3:0]` 0..15; `[7:4]=0`; count is input frames. |
| `5.9 PCM_PACK` | format `[1:0]`: 0 S16_LE, 1 S24_32LE, 2..3 invalid; mono-duplicate bit 2; `[7:3]=0`. |

The class-5 opcode requires its correspondingly named primitive bit, except
`STEREO` requires bit 7 and `DECORRELATE` requires bit 13. Class-2 operations
require bitstream bit 0, with CRC operations additionally requiring bit 1.
Huffman operations require bits 0 and 2; unary/Rice/sign operations require
bits 0 and 3. Local accesses require bit 4 and FIFO accesses require bit 5.

| Class.op | Operands and execution |
| --- | --- |
| `6.0 INPUT_REFILL` | scratch-relative destination byte offset `R[src0]`, nonzero requested bytes `R[src1]`, returned transferred bytes `R[dst]`; `aux/immediate=0`; uses only the active descriptor input cursor and requires primitive bit 16. |
| `6.1 OUTPUT_COMMIT` | scratch-relative source byte offset `R[src0]`, nonzero bytes `R[src1]`, returned committed bytes `R[dst]`; `aux/immediate=0`; uses only the active descriptor memory-output cursor and requires bit 17. |
| `6.2 OUTPUT_STREAM` | same operands as `OUTPUT_COMMIT`, through the active TX stream, and requires bit 18. |
| `6.3 DMA_WAIT` | all operands except `dst` zero; waits for transport quiescence, writes zero on success, and traps on the latched transport error. The entry must declare every DMA/stream primitive that may be outstanding. |
| `6.4 FRAME_COMMIT` | saturating-adds input-used `R[src0]` and output-produced `R[src1]` to job counters, saturating-increments frame count, then resets the per-frame retired counter; `dst/aux/immediate=0`; requires bit 19. |
| `6.5 JOB_RESULT` | latches terminal code `R[src0][5:0]`, detail `R[src1]`, and stage `aux[3:0]` without terminating; `R[src0][31:6]`, `dst`, `immediate`, and `aux[7:4]` must be zero, and codes 23..63 trap as an illegal runtime value; requires bit 19. |
| `6.6 EVENT` | sets sticky IRQ state selected by nonzero `immediate[10:0]`; only bits 6 and 7 may be one; all register/aux fields and upper immediate bits are zero; requires bit 20. |

Transport operations never accept a raw system address from microcode. They
advance only the active validated descriptor cursor and inherit its ACL,
4 KiB-boundary, burst, timeout, abort, and first-error rules. At most one
microcode read command and one write/stream command may be outstanding. An
input/output opcode stalls until its command is admitted, retires on admission,
marks `dst` pending, and writes the completed byte count on successful
completion. A read or overwrite of that pending GPR stalls. `DMA_WAIT` and
`FRAME_COMMIT` stall until every applicable pending command has completed; a
latched failure traps instead. All these stalls count toward the no-retirement
watchdog.

#### Control-flow, watchdog, and trap rules

Only `LOOP_BACK` may branch backward. The loader proves all direct targets,
fall-throughs, returns, and loop-back targets remain inside the entry's
inclusive program range; call depth never exceeds four; each loop slot has one
setup and one matching back edge; loop intervals are disjoint or properly
nested rather than crossing; and every reachable path reaches `END` or `TRAP`.
Runtime rechecks dynamic return, loop, local, table, and transport ranges before
side effects.

The no-retirement counter clears on entry launch and each retired instruction,
increments once per running cycle with no retirement, and traps after exactly
`SEQUENCER_TIMEOUT` consecutive such cycles. A legal timeout value is nonzero.
The per-frame counter starts at zero and counts every retired instruction,
including predicate-false instructions. If the next instruction would exceed
the descriptor maximum, it traps before instruction side effects; `END` may be
the last allowed retirement. `FRAME_COMMIT` resets the counter only after its
counter/result update commits. Falling through program-last PC or control-store
word 2047 traps.

An asynchronous P2 transport error is sampled at the next retirement boundary,
then fetch and new commands stop while accepted transfers drain. Trap reason
allocations are 1 illegal encoding, 2 PC/program range, 3 call stack, 4 loop,
5 local/table range, 6 unavailable/undeclared primitive, 7 no-retirement
watchdog, 8 per-frame retirement budget, 9 engine/transport fault, and 10
explicit `TRAP`; 0 and 11..255 are reserved. A trap sets sticky
`STATUS.SEQUENCER_TRAPPED` and IRQ bit 10. IRQ bit 10 clears only by its W1C or
reset. A trap leaves a previously loaded `MC_STATUS.VALID` and `MC_LOCK` set
because the bundle itself remains loaded.

For the table below, `PC` is the trapping 11-bit control-store word index and
`trap_detail(reason)` is reason `[7:0]`, PC `[18:8]`, class `[22:19]`, opcode
`[26:23]`, and `aux[4:0]` `[31:27]`. Every primary non-AXI trap sets
`ERROR_STATUS.VALID=1`, AXI response `0`, descriptor index `0`, and
`ERROR_ADDRESS=zero_extend(PC)<<3`. APUMC entry indices are not job/ring
descriptor indices and therefore never enter `ERROR_STATUS.DESCRIPTOR_INDEX`.

| Trap reason | `ERROR_STATUS` code | Stage | AXI response | Descriptor index | `ERROR_ADDRESS` | `ERROR_DETAIL` |
| ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 illegal encoding | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(1)` |
| 2 PC/program range | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(2)` |
| 3 call stack | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(3)` |
| 4 loop | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(4)` |
| 5 local/table range | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(5)` |
| 6 unavailable/undeclared primitive | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(6)` |
| 7 no-retirement watchdog | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(7)` |
| 8 per-frame retirement budget | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(8)` |
| 9 non-AXI engine semantic failure | 8 | 6 for reconstruction/transform; 7 for resampler/PCM | 0 | 0 | `PC<<3` | `trap_detail(9)` |
| 9 non-AXI FIFO/local/arithmetic overflow | 22 | stage of the failing engine, 6 or 7 | 0 | 0 | `PC<<3` | `trap_detail(9)` |
| 9 AXI/DMA/stream cause | unchanged causative code 15..19 | unchanged causative stage | unchanged causative value | unchanged causative value | unchanged causative address | unchanged causative detail |
| 9 without a valid causative error | 11 | 11 | 0 | 0 | `PC<<3` | `trap_detail(9)` |
| 10 explicit `TRAP` | 11 | 11 | 0 | 0 | `PC<<3` | the instruction's 32-bit immediate |

Reason 9 is secondary when an AXI/DMA/stream first-error tuple has already
been captured: it sets sequencer trap status and IRQ bit 10 but does not alter
that tuple. A reason-9 assertion without a causative error is an internal
sequencer trap and uses the fail-closed row above. If another global terminal
condition and a sequencer trap coincide, hard reset, forced resource reset,
AXI write, AXI read, DMA timeout, RX overrun, and TX underrun retain their
existing order above the trap; the trap outranks forced abort. Every applicable
sticky event still sets.

`SEQUENCER_STATUS` bits `[31:21]` are reserved zero. While running, PC, class,
opcode, wait, and loop-active are live for the current instruction. Wait is one
for any current-instruction stall, including explicit wait, pending-GPR,
kernel, DMA, FIFO, or backpressure stall. The terminal readback rules are:

| Event | `SEQUENCER_STATUS` after the event | `SEQUENCER_RETIRED` after the event |
| --- | --- | --- |
| `END`, with either a zero or nonzero latched terminal result | Retains the terminal `END` PC/class/opcode and the wait/loop-active values sampled immediately before retirement. | Retains the saturating current-frame count including the retired `END`. |
| Trap, including watchdog | Retains the trapping current-instruction PC/class/opcode and its wait/loop-active values when the trap was recognized. | Retains the count before the non-retired trapping instruction or stall. |
| Accepted abort with an active sequencer | Further retirement stops; retains the current-instruction tuple sampled when abort was accepted through terminal abort completion. | Retains the count sampled when abort was accepted. |
| Accepted abort without an active sequencer | Remains unchanged. | Remains unchanged. |
| Soft reset | Clears to zero when the reset is applied. | Clears to zero. |
| Normally drained or forced resource reset | Clears to zero when resource-reset state is applied after drain. | Clears to zero. |
| Hard/PCLK reset | Clears immediately to reset value zero. | Clears immediately to reset value zero. |

`END`, trap, and abort snapshots persist through status reads,
`ERROR_STATUS`/IRQ W1C, `CLEAR_COUNTERS`, and microcode load. The next accepted
entry launch clears `SEQUENCER_RETIRED` to zero and initializes
`SEQUENCER_STATUS` to entry PC with class/opcode/wait/loop-active zero until the
first instruction fetch updates it. `STATUS.SEQUENCER_TRAPPED` clears on that
launch or on soft/resource/hard reset; `END` and abort do not set it. The P3
verification-only launch follows the same rules and creates no public launch
mechanism.

#### P3 loader, status, and control store

`MC_STATUS` reset is zero. `BUSY` bit 0 is live, `VALID` bit 1 is retained
state, bits 2..7 are sticky terminal validation errors, and bits 8..31 are
reserved zero. `STATUS.MICROCODE_VALID` is an exact mirror of
`MC_STATUS.VALID`. A legal load start clears `VALID`, bits 2..7, `MC_ABI`,
build ID, and `MC_ACTUAL_CRC`, then sets `BUSY`. A prior successful load has
automatically set `MC_LOCK`, so the clear-lock admission rule prevents it from
being overwritten. Busy, valid, and terminal-error states are mutually
exclusive.

The loader first validates header/ranges sufficiently to bound DMA, may then
write the private control store while the sequencer is held idle and `VALID=0`,
and publishes the new image atomically only after full validation and CRC.
Success in one PCLK edge clears `BUSY`, sets `VALID` and `MC_LOCK`, writes
`MC_ABI=0x00010000`, build ID and actual CRC, saturating-increments
`MC_LOAD_COUNT`, and sets sticky IRQ bit 3. Load-done IRQ and count occur only
on successful publication; the count saturates at `0xffffffff`. A failed
attempt clears `BUSY`, keeps `VALID` and lock clear, does not increment the
count, does not set IRQ bit 3, and makes any partially written store
inaccessible; the next attempt overwrites it.

Load admission also requires 64-byte-aligned `MC_IMAGE_ADDRESS`, nonzero
`MC_IMAGE_SIZE`, and a non-wrapping complete source range inside the local read
ACL. Admission failure returns `PSLVERR` without setting `BUSY` or changing
loader state. Once admitted, validation-error categories are exact: header is
bad magic/ABI/header reserved/total/entry count; range is offset, alignment,
overlap, instruction-count, PC, scratch, or arithmetic range; control-flow is
instruction encoding, predicate, operand-reserved, branch/call/loop, or
termination proof; table is global/entry table layout or content, including
any nonzero P3 table field; capability is an unsupported primitive mask,
class-2..6 instruction in P3, or header/entry mask mismatch; CRC is the final
three-way CRC mismatch. A nonzero P3 scratch field is a range error.

Every non-AXI loader validation failure sets `ERROR_STATUS.VALID=1`, stage 1,
AXI response 0, descriptor index 0, and the code/address/detail tuple below,
subject to the global immutable-first-error rule. Loader diagnostics use an
absolute DMA source byte address, `MC_IMAGE_ADDRESS + bundle byte offset`.
APUMC entry indices do not use the job/ring descriptor-index field.

| Loader category | `MC_STATUS` bit | Error code | `ERROR_ADDRESS` | `ERROR_DETAIL` |
| --- | ---: | ---: | --- | --- |
| Header | 2 | 9 | Address of the first offending header word, or the aligned 32-bit word containing the first nonzero padding byte. | Observed little-endian 32-bit word at `ERROR_ADDRESS`. |
| Range | 3 | 9 | Address of the first header/entry field participating in the failed range relation. | Observed little-endian 32-bit field value. |
| Control flow | 4 | 9 | Address of the first offending 64-bit instruction: `MC_IMAGE_ADDRESS + instruction_offset + (PC<<3)`. | `trap_detail(1)` for encoding/predicate/reserved-operand failure, `trap_detail(2)` for target/fall-through/termination failure, `trap_detail(3)` for call/return proof failure, or `trap_detail(4)` for loop proof failure. |
| Table | 5 | 9 | Address of the first nonzero P3 table field: header word 5, header word 6, then entry-descriptor word 7 in entry-index order. | Observed little-endian 32-bit field value. |
| Capability | 7 | 10 | Address of header word 9, an entry word 6, or an instruction, whichever is the first offending item under the order below. | `header_mask XOR (entry0_mask OR entry1_mask OR entry2_mask)` for a mask mismatch; `observed_mask AND NOT implemented_mask` for an unsupported-mask failure; `trap_detail(6)` for a class-2..6 instruction rejected by P3. |
| CRC | 6 | 10 | Address of header word 11, `MC_IMAGE_ADDRESS+0x2c`. | `MC_ACTUAL_CRC`. |

For header, range, and table categories, “first” means lowest bundle byte
offset. For a range relation with more than one participating field, the
lowest-addressed participant owns the diagnostic. Control-flow instructions
are checked by entry index 0, 1, 2 and then increasing PC; a proof failure
without a unique instruction uses that entry's entry PC, and the lower entry
index wins a tie. For capability checking, header-mask mismatch precedes
unsupported header-mask bits; header word 9 then precedes entry word 6 in entry
order, which precedes instructions in that same entry/PC order. These locator
rules apply after the already frozen category precedence and do not change
which `MC_STATUS` bit wins.

Exactly one validation-error bit is set on failure using precedence header,
range, control-flow, table, capability, then CRC. Header/range/control-flow/
table failures use code 9; capability/CRC failures use code 10. An AXI
read/protocol failure records code 15 and sets no validation-error bit. All
failure classes set sticky first-error IRQ bit 8 under the global first-error
rules. `MC_ACTUAL_CRC` is zero on early-validation or AXI failure;
header/range failures are early. For an admitted range-safe image, the loader
continues through the complete payload before reporting control-flow, table,
capability, or CRC failure, and `MC_ACTUAL_CRC` contains the computed value,
including on CRC mismatch.
A later legal load start clears the loader error bits. Clearing `ERROR_STATUS`
or IRQ state does not clear `MC_STATUS`. Idle `CLEAR_COUNTERS` clears
`MC_LOAD_COUNT` but not valid, lock, ABI/build/CRC, or loader errors. Hardware
terminal updates win any same-cycle software clear elsewhere.

Hard/PCLK reset has highest precedence and clears all loader state, valid,
lock, ABI/build/CRC, and load count without an IRQ. Resource reset is next: if
a load is active, it blocks new DMA, drains accepted traffic, cancels the load,
clears all `MC_STATUS` bits plus lock/ABI/build/CRC, leaves the count unchanged,
suppresses load-done IRQ, and records forced lifecycle error 21 because the
accepted load was canceled. Idle-only soft reset cannot be accepted while
loader `BUSY`. A software abort accepted during a load uses the existing P2
block-new-and-drain behavior, then cancels publication, clears all `MC_STATUS`
bits plus lock/ABI/build/CRC, leaves the count unchanged, suppresses IRQ bit 3,
and sets abort-done IRQ bit 5. A successfully drained abort records no first
error; a drain fault or timeout uses the existing global error and precedence
rules. When no load is active, soft or normally drained resource reset clears
loader error bits while preserving valid, lock, ABI/build/CRC, and load count.
Terminal precedence is hard reset, resource reset, accepted abort, load
failure, then load success.

The control store is exactly 2048x64 (16 KiB), has synchronous one-PCLK-cycle
sequencer fetches, no architecturally visible reset contents, and is readable
only when valid. With `HAVE_SRAM_MACRO=YES`, it is implemented as four
`tc_sram_1024x32` instances: two depth banks by low/high 32-bit halves; loader
writes the halves and sequencer fetches the combined word, with mutually
exclusive loader/fetch ownership. If a selected PDK advertises the macro but
cannot elaborate that mapping, elaboration must fail.

With `HAVE_SRAM_MACRO=NO`, including the supported ICS55 profile,
`apu_control_store` selects a portable inferred synchronous
`logic [63:0] mem [0:2047]` implementation with identical admission, latency,
byte/word ordering, and loader/fetch exclusion. It must not instantiate an
unconnected macro wrapper. This path is functional and synthesis-compatibility
evidence only; it is not an SRAM-macro, PPA, or tapeout claim.

`apu-mcasm` is the single assembler/verifier and produces the binary, symbols,
control-flow/loop report, primitive manifest, deterministic trace input, and
canonical ABI-input manifest. A separate Python interpreter executes the exact
enabled ISA for BAM and microcode/RTL differential tests. In P3 both tools
execute class 0/1 and reject class 2..6 under the P3 target capabilities; later
phases extend execution without changing these encodings. No partial tool-table
fingerprint is exposed as the public `ABI_DIGEST`, which remains zero through
P7. Neither tool accepts C, ELF, RV32, dynamic linking, or runtime code
generation.

#### P4 primitive and local-SRAM profile

P4 implements primitive-mask bits 0..15, so its implemented primitive mask is
exactly `0x0000ffff`. It admits classes 0..5 and rejects class 6 and classes
7..15 at load time. Within class 0, `WAIT` sources 1 (kernel), 2 (input FIFO),
and 3 (output FIFO) are admitted; sources 0, 4, and 5 remain unavailable.
Primitive bits 16..20, every class-6 transport opcode, and public
transport-driven entry launch remain deferred. Each entry mask may be any
subset of `0x0000ffff`, but every admitted instruction must have all of its
required bits in that entry mask and the header mask remains the exact OR of
the three entry masks.

The assembler, parser, reference interpreter, RTL package, and handwritten C
mirror expose a separate P4 target with this mask and class admission. The P3
target remains mask zero/class 0..1 and is not widened retroactively. P4 adds
no opcode, predicate, primitive-bit number, descriptor field, or APUMC header
field.

P4 reports `CAPABILITY0=0x00000198` and `CAPABILITY1=0x01827010` as defined in
the register table. Format bits, streams, and KWS stay zero; `ABI_DIGEST` stays
zero. Consequently `START_DIRECT`, `RING_DOORBELL`, and `STREAM_ROUTE` value 1
remain fail-closed. P4 exercises primitive programs only through the
verification-only launch and data-injection path, which adds no public command,
operation, address, interrupt, or route.

The P4 112 KiB local-data address space is byte addressed and fixed:

| Local byte range | Size | P4 ownership and access |
| --- | ---: | --- |
| `0x00000..0x05fff` | 24 KiB | Active-bundle table followed by per-entry codec scratch. |
| `0x06000..0x07fff` | 8 KiB | Input staging, internal and verification-only until class 6 is enabled. |
| `0x08000..0x09fff` | 8 KiB | Output staging, internal and verification-only until class 6 is enabled. |
| `0x0a000..0x19fff` | 64 KiB | Reserved for P7 KWS; inaccessible in P4. |
| `0x1a000..0x1bfff` | 8 KiB | Primitive scoreboard, FIFO metadata, and bounded internal result state; not microcode addressable. |

Let `T` be header word 6, the table-payload byte count. P4 requires
`0<=T<=0x6000` and four-byte alignment, and copies
`bundle[header_word5+i]` exactly to local byte address `i` for `0<=i<T`.
Entry table slices may overlap because they are read-only, but each must be
wholly inside `[0,T)`. Each nonempty entry
scratch range must be wholly inside `[T,0x6000)`, must not wrap, and must not
overlap its table slice; scratch ranges belonging to different entries may
overlap because only one codec entry can execute. Header word 10 remains the
greatest declared scratch end and must be at most `0x6000`. A zero-table,
zero-scratch P3-compatible bundle remains legal in P4.

For P4 load diagnostics, `T` or entry-table-slice failure sets
`MC_STATUS.TABLE_ERROR`, code 9/stage 1, and locates header word 6 or the first
failing entry word 7. Scratch/base/end/header-word-10 failure sets
`MC_STATUS.RANGE_ERROR`, code 9/stage 1, and locates the first participating
field. A mask bit above 15, class-6 instruction, or unavailable `WAIT` source
sets `MC_STATUS.CAPABILITY_ERROR`, code 10/stage 1, using the already frozen
mask/instruction locator and detail. Classes 7..15 remain illegal V1 encodings
and use `MC_STATUS.CONTROL_FLOW_ERROR`. All are non-AXI loader tuples with
response/index zero and retain the existing category precedence.

The loader owns the local-data port while loading and writes only `[0,T)`.
Control-store words and table bytes are a single publication unit: both remain
inaccessible while `MC_STATUS.VALID=0`, and the existing successful-load edge
publishes both before setting lock/IRQ/count. Header, descriptor, instruction,
table, or CRC failure; load abort; hard reset; or forced resource reset during
load leaves both unpublished. Physical SRAM contents need not be cleared.
After successful publication, the table is read-only and survives sequencer
trap, job abort, soft reset, and normally drained resource reset exactly with
the locked control store. Only hard reset invalidates that retained bundle.

Scratch, staging, FIFO, and internal-result contents have no architectural
reset value. Each accepted entry launch starts a new mutable-data epoch: its
scratch range, both staging ranges, both primitive FIFOs, and internal result
state are logically invalid until written in that epoch. A read of an invalid
word traps with reason 5 before data is consumed; a successful `ST32`, injector
write, or kernel write marks only the written SRAM words valid, while FIFO
push marks only its new entry valid. Abort and soft, resource, or hard reset
invalidate all mutable epochs and flush both FIFOs. This may use validity
metadata rather than physically clearing SRAM, but stale
bits must never affect a result or become externally visible. The P4
verification-only injector may initialize scratch/FIFO data and validity for a
test launch; it is excluded from product filelists and public ABI.

`apu_local_sram` presents one active codec-side 32-bit, byte-write-enabled port
with a one-PCLK-cycle synchronous read. With `HAVE_SRAM_MACRO=YES`, local
address bits select 28 existing `tc_sram_1024x32` instances: banks 0..9 are
codec table/scratch/staging, banks 10..25 are the disabled P4 KWS partition,
and banks 26..27 are internal common/result state. With
`HAVE_SRAM_MACRO=NO`, it selects an inferred synchronous
`logic [31:0] mem [0:28671]` implementation with identical ordering, latency,
and byte masks; it must not instantiate an unavailable macro wrapper. Loader
access is exclusive. Outside loading, the one outstanding fixed kernel owns
the SRAM port until completion; otherwise class-4 sequencer access owns it.
This makes arbitration bounded and prevents a scalar/local instruction from
perturbing an accepted kernel's latency. The inferred path is compatibility
evidence, not SRAM-macro, PPA, or tapeout evidence. P7 may enable a separate
KWS client on banks 10..25 without sharing codec banks or changing this P4
address/latency contract; common-bank contention remains governed by its later
phase.

P4 implements two 64-entry, 41-bit primitive FIFOs using the existing Common
`stream_fifo`: payload is data `[31:0]`, valid-byte count `[34:32]`, reserved
`[39:35]=0`, and last `[40]`. They implement class-4 `FIFO_POP/PUSH` and remain
separate from the already frozen P2 stream-router FIFOs. They run in PCLK, add
no CDC/RDC boundary, and have only the verification producer/consumer in P4;
class 6 later connects production transport.

##### P4 bit-accurate numerical contract

Scratch samples are little-endian signed two's-complement 32-bit integers.
Fractional coefficients are signed Q2.30 words. A signed multiply produces the
exact 64-bit product; a dot product accumulates in signed 72 bits. Exceeding
the signed 72-bit range traps as code 22 before the affected output is made
valid. `RNE(x,s)` divides signed integer `x` by `2^s` and rounds the magnitude
to nearest with an exact half going to an even quotient, then restores the
sign; `RNE(x,0)=x`. An unrounded right shift is a two's-complement arithmetic
shift, rounding toward negative infinity. `SATb(x)` clamps to
`[-2^(b-1),2^(b-1)-1]`. All formulas below use these operations and contain no
floating-point or implementation-dependent intermediate.

`R[src1]` points to an opcode-specific parameter block in entry scratch. A
32-bit reference word in such a block uses bit 31 as table select: zero means
scratch-relative byte offset `[16:0]` with `[30:17]=0`, and one means
entry-table-relative byte offset `[15:0]` with `[30:16]=0`. References are
four-byte aligned, the complete referenced range is checked before issue, and
table-selected ranges are read-only. State and history references must select
scratch; input/output array references must also select scratch. Coefficient
and scale references may select table or scratch. Coefficients are therefore
explicit operands rather than hidden RTL constants. Static coefficient banks
originate in CRC-covered APUMC data; dynamic scales or predictors may be
written to scratch by microcode. Hardware, assembler, interpreter, and BAM
consume identical words. Codec-specific static values are selected with the
P5/P6 bundles without changing the P4 arithmetic contract.

For the class-5 table, `N=immediate[15:0]`, `P` is the transform or predictor
order defined by the opcode, and the pre-issue value of `R[dst]` is the
scratch-relative output base:

| Opcode | Parameter block and exact output |
| --- | --- |
| `REQUANT` | Word 0 references `N` Q2.30 scales. For element `i`, `product=input[i]*scale[i]`; aux bit 5 selects `RNE(product,30+shift)` or arithmetic shift by `30+shift`, where shift is aux `[4:0]`. Apply `SAT16`, `SAT24`, or `SAT32` from aux `[7:6]`, sign-extend to 32 bits, and write `N` outputs. |
| `STEREO` | Word 0 references the second `N`-sample input. Inputs are planar `A` and `B`; output is planar left then right. Modes produce `(A,B)`, `(A,A-B)`, `(A+B,B)`, or `mid=(A*2)+(B&1); ((mid+B)>>1,(mid-B)>>1)` for independent, left-side, side-right, or mid-side. Signed 64-bit intermediates are clamped with `SAT32`; result count is `2N`. |
| `IMDCT6` / `IMDCT18` | Word 0 references a row-major Q2.30 matrix `C[2P][P]`, with `P=6` or 18. For every block and `0<=n<2P`, output `SAT32(RNE(sum(k=0..P-1,input[k]*C[n][k]),30))`. There is no hidden scale; results contain `12N` or `36N` samples. |
| `DCT32_POLY` | Words 0/1 reference Q2.30 `C[32][32]` and `W[16][32]`; word 2 references signed-32 `history[16][32]`; word 3 holds phase `[3:0]` and has other bits zero. Compute `v[n]=SAT32(RNE(sum(k=0..31,input[k]*C[n][k]),30))`, replace `history[phase][n]`, then output `SAT32(RNE(sum(m=0..15,history[(phase-m)&15][j]*W[m][j]),30))` for `j=0..31`; advance phase modulo 16 and write it back to word 3 per block. Result count is `32N`. |
| `FIXED` | Word 0 references a newest-first signed-32 history with `P=aux[2:0]` in 0..4. Predictor is 0, `s1`, `2s1-s2`, `3s1-3s2+s3`, or `4s1-6s2+4s3-s4`. Add each signed-32 residual, require the exact signed-64 result to fit signed 32 bits, write it, and update history. Result count is `N`. |
| `LPC` | Word 0 references `P=aux[5:0]` signed-32 coefficients, word 1 references newest-first signed-32 history, and word 2 is a sign-extended predictor shift in -31..31. Accumulate `sum(j=0..P-1,coeff[j]*history[j])` in signed 72 bits; arithmetic-shift right for nonnegative shift or exact-shift left for negative shift, add the residual, require signed-32 range, write, and update history. Result count is `N`. |
| `DECORRELATE` | Word 0 references the second planar input and uses the four `STEREO` equations, but any result outside signed 32 bits traps rather than saturates. Result count is `2N`. |
| `RESAMPLE` | Words 0/1/2 reference the full-band, two-thirds-band, and half-band coefficient banks; each bank is Q2.30 `H[32][16]`. Mutable words 3/4 hold 64-bit `next_output_num`, words 5/6 hold 64-bit `input_base_index`, and word 7 is channel count 1 or 2. The exact rational/phase/filter rules below produce interleaved signed-32 frames and update both 64-bit state values. Result count is produced frames. |
| `PCM_PACK` | Word 0 is signed Q2.30 gain and word 1 is input channels 1 or 2; `N` counts input frames. For each input sample use `RNE(sample*gain,30)`, then `SAT16` or `SAT24`. S16_LE emits two little-endian bytes; S24_32LE emits the sign-extended 24-bit result in a four-byte little-endian word. Mono-duplicate is legal only for one input channel and emits two equal channels. Result count is emitted bytes. |

The 16 `RESAMPLE` profile ratios are output/input in lowest terms:

| Profile | Ratio `L/M` | Coefficient bank | Profile | Ratio `L/M` | Coefficient bank |
| ---: | ---: | --- | ---: | ---: | --- |
| 0 | `1/1` exact bypass | none | 8 | `6/1` | full-band |
| 1 | `1/2` | half-band | 9 | `8/1` | full-band |
| 2 | `80/147` | half-band | 10 | `12/1` | full-band |
| 3 | `160/147` | full-band | 11 | `320/147` | full-band |
| 4 | `3/2` | full-band | 12 | `640/147` | full-band |
| 5 | `2/1` | full-band | 13 | `1280/147` | full-band |
| 6 | `3/1` | full-band | 14 | `2/3` | two-thirds-band |
| 7 | `4/1` | full-band | 15 | `4/3` | full-band |

Profile 0 copies exactly `N` interleaved frames, adds `N` to both
`next_output_num` and `input_base_index`, and reports `N` frames. For profiles
1..15, source frame indices are absolute. At invocation, `R[src0]` addresses
frame `input_base_index` and its buffer must also contain seven valid history
frames before it and nine valid look-ahead frames after the `N` frames. While
`floor(next_output_num/L)<input_base_index+N`, let
`i=floor(next_output_num/L)` and remainder `r=next_output_num mod L`. Phase is
the nearest-even integer to `32*r/L`; phase 32 is represented as phase 0 with
`i` incremented. For every channel, output
`SAT32(RNE(sum(t=0..15,sample[i+t-7]*H[phase][t]),30))`, then add `M` to
`next_output_num`. After the invocation add `N` to `input_base_index`.
Both state values start at zero; the first seven history frames and final nine
look-ahead frames are explicit valid zeros supplied by microcode. A profile
cannot change within a job; a new job reinitializes both state values. The three
coefficient banks are APUMC data and have no hidden normalization or scale;
the P5/P6 approved bundles provide their codec-quality values while P4 BAM
compares the exact supplied Q2.30 words.

##### P4 latency and fault bounds

Latency is counted in PCLK cycles from accepted execute/issue through retire or
kernel-done, inclusive. The bounds assume required local words are valid and a
required FIFO word/space is present. Time waiting for external FIFO data or
space is instead covered by `SEQUENCER_TIMEOUT`. `B` is scanned bytes, `E` is
Huffman entries (1..4096), `q` is a Rice quotient limited to 65535, `k` is the
Rice parameter/raw width, `maximum_run` is the `UNARY` immediate, `S` is
emitted PCM samples, and `O`/`C` are resampler output frames/channels.

An entropy request with `E` outside 1..4096, a unary run beyond its declared
maximum, or a Rice quotient above 65535 traps as invalid entropy before a
result is written. EOF before the required entropy bits is a truncated-stream
fault rather than a latency-bound exception.

| Primitive/opcode | Maximum PCLK cycles |
| --- | ---: |
| `REFILL` | 3 |
| `PEEK`, `GET`, `SKIP`, `ALIGN`, `CRC8`, `CRC16` | 1 |
| `FRAME_SYNC` | `2+2B` |
| `HUFF_SYMBOL`, `HUFF_PAIR`, `HUFF_QUAD` | `2+24+E` |
| `UNARY` | `2+maximum_run` |
| `RICE4`, `RICE5` | `4+q+k`; escape path `4+raw_width` |
| `SIGN_RESTORE` | `3+linbits` |
| `LD32`, `TABLE8`, `TABLE16`, `TABLE32` | 2 |
| `ST32`, ready `FIFO_POP`, ready `FIFO_PUSH` | 1 |
| `REQUANT` | `8+4N` |
| `STEREO`, `DECORRELATE` | `8+4N` |
| `IMDCT6` | `8+94N` |
| `IMDCT18` | `8+706N` |
| `DCT32_POLY` | `8+2304N` |
| `FIXED` | `8+(P+4)N` |
| `LPC` | `8+(2P+5)N` |
| `RESAMPLE` profile 0 | `8+2NC` |
| `RESAMPLE` profiles 1..15 | `8+2NC+36OC` |
| `PCM_PACK` | `8+5S` |

`N`, output size, every referenced array, and each latency expression must fit
32-bit unsigned arithmetic and the active scratch range before issue. A bound
violation traps before a write. A conforming implementation may complete
earlier but never later under the stated ready-data conditions. The interpreter
and RTL expose identical completion cycles in the P4 latency corpus.

P4 extends reason-9 causative errors without changing P3 behavior: frame-sync
failure captures code 4/stage 4; required-bit exhaustion captures code 5 with
stage 4 for class 2 or stage 5 for class 3; and invalid Huffman/unary/Rice
content or a frozen entropy bound violation captures code 7/stage 5. These
non-AXI tuples use response/index zero, `ERROR_ADDRESS=PC<<3`, and
`ERROR_DETAIL=trap_detail(9)` before setting the existing secondary reason-9
trap. CRC opcodes only calculate values; codec checksum policy remains in the
codec phases. Local range/validity faults use reason 5. Class-5 semantic and
overflow faults retain the already frozen code 8 or 22 and stage 6/7 mapping.

#### P5 public codec and transport profile

This section freezes P5 against the reviewed P4 interfaces present at
`57ffd03216502804f1108041184fdd6e6a328217`. It specifies the production
controller that replaces the tied-off job, FIFO, and TX-session connections;
it does not declare that controller already implemented.

| P5 discovery/admission | Exact value or rule |
| --- | --- |
| `CAPABILITY0` | `0x000001bd`: WAV 0, FLAC 2, DMA 3, ring 4, TX streams 5, sequencer 7, resampler 8. MP3 1 and KWS 6 remain zero. |
| `CAPABILITY1` | `0x01827010`: 16 KiB control, 112 KiB data, two channels, 96 kHz maximum source rate. |
| Implemented primitive mask | `0x001fffff`, bits 0..20; reserved bits 21..31 remain zero. |
| ISA target | Add `p5` to the assembler/parser/interpreter and hardware capability validation. Classes 0..6 and all six existing `WAIT` sources are admitted subject to entry masks. Existing `p3` and `p4` targets retain their masks and behavior. |
| Public job | Operation 0 with format 0 WAV or 2 FLAC; one active job, direct or ring. MP3, KWS operation 1, and model load remain unavailable. |
| Stream route | TX 0/1 legal; RX only 0 legal. Bit 5 means at least one implemented stream direction, not permission for RX/KWS. RX 1 and reserved direction values return `PSLVERR`. |
| ABI identity | Existing offsets, descriptor size, instruction encoding, `MC_ABI=0x00010000`, and topology stay fixed. `ABI_DIGEST=0` through P7. |

Direct acceptance snapshots all job fields, requires owner/unblocked/idle,
locked valid microcode, a supported format, valid ranges and output geometry,
and no enabled active ring. Rejected direct starts cause no payload DMA and
leave result state unchanged. Ring doorbell requires an enabled valid ring,
owner/unblocked state, locked microcode, and no direct job; it does not inspect
the head format during the APB transfer. Each invalid owned descriptor,
including MP3/KWS, completes with the existing P2 error/writeback/OWN-clear
sequence. Thus an unsupported ring head cannot prevent its own rejection
writeback. Direct and ring configuration words retain their existing layouts.
Buffers and the complete 128-byte descriptor must fit the relevant ACL;
input/output and descriptor/result memory may not overlap. Shared storage must
remain immutable/non-cacheable or explicitly cache-maintained while owned.

##### Production entry context and class-6 movement

GPRs still start at zero. Before the first instruction, after the P4 mutable
epoch clear, the controller writes the following 64-byte context into the
last 64 bytes of the active entry's scratch range. This is a microprogram ABI
inside existing scratch, not a new APB register window. The P5 WAV/FLAC bundle
reserves it; kernels and transport data buffers may not overlap it. `LD32` and
`ST32` use the existing scratch-relative addressing to access it.

| Word | Value/owner |
| ---: | --- |
| 0..3 | Controller writes descriptor `CONTROL` without OWN/IOC, `INPUT_CONFIG`, `OUTPUT_CONFIG`, and `JOB_FLAGS`; microcode reads only. |
| 4 | Microcode's cumulative parsed input bytes, initially zero; monotonically increasing and at most `INPUT_LENGTH`. |
| 5 | Microcode's diagnostic byte offset from input start, initially zero; may equal `INPUT_LENGTH` for EOF. |
| 6 | Microcode's detected `SOURCE_INFO` in the existing result layout, initially zero; written after header validation and constant thereafter. |
| 7 | Microcode final-output marker, bit 0 only; initially zero. It marks the next output command as the final one and is consumed/cleared when that command is accepted. |
| 8 | Controller writes `INPUT_LENGTH`; microcode reads only. |
| 9 | Controller writes `OUTPUT_CAPACITY`; microcode reads only. |
| 10 | Controller writes current private-DMA input cursor after each refill completion; microcode reads only. |
| 11 | Controller writes completed transport output bytes after each output completion; microcode reads only. |
| 12..15 | Reserved zero. |

The controller owns transport cursors and checks context bounds when consumed.
APUMC loader validation retains all P4 table/scratch range rules. Job dispatch
additionally requires a WAV/FLAC entry with at least 64 scratch bytes; a
generic primitive-only bundle may still load but cannot run a public codec
job without this space. Only released, verified P5 microprograms define codec
semantics; load CRC/lock is not authentication of an arbitrary program.

`INPUT_REFILL` has exactly one source: the active descriptor input cursor. Its
requested count is a multiple of four in 4..256, and its scratch destination
is four-byte aligned and has space for the request. Actual bytes are
`min(request, INPUT_LENGTH-cursor)`. The controller buffers an entire request
in the P4 input staging region at `0x06000` before publishing it; on success
it copies the actual bytes to scratch, zeroes unused lanes of the final local
word, and queues the same bytes in the primitive input FIFO. Completion and
cursor increment occur once both copies have been accepted. Source bytes are
not reread or decoded by LP/HP. Zero actual bytes completes with zero without
issuing AXI; it sets the EOF state and emits no zero-byte FIFO item.

Refill admission reserves enough free FIFO entries for the entire actual
request, as well as the read-command slot, and waits for an active fixed
kernel to complete before claiming SRAM. A reservation need not wait for the
reservoir to empty. The primitive FIFO's `last` is set only on the item ending
the descriptor input, not on each 256-byte refill. Valid-byte counts remain
literal 1..4 and byte order is increasing address. `FIFO_POP` and bitstream
refill consume one shared FIFO; the microprogram must not use `FIFO_POP`
while the bitstream reservoir holds unconsumed bits. Scratch copies are for
CRC/header inspection and do not implicitly consume the reservoir.
The parser tracks available bits and schedules explicit refills before an
operation would exhaust queued input. Long unary/Rice tokens spanning refill
boundaries are decoded with bounded bit-read/refill microcode loops; issuing
an entropy primitive that stalls waiting for its own not-yet-issued refill
is forbidden in the released bundle. This needs no autonomous host refill.

`OUTPUT_COMMIT` and `OUTPUT_STREAM` both take authoritative bytes from the
specified scratch range; their byte count is 1..256 and a multiple of a
complete destination PCM sample frame. The scratch base is four-byte aligned.
They first copy those bytes into output staging at `0x08000`, then enqueue
them into the primitive output FIFO, then drain that FIFO to private AXI DMA
or to the P2 TX router respectively. Output-command admission requires this
FIFO empty. `FIFO_PUSH` remains executable for primitive programs, but an
output command with older manually pushed entries is a reason-5 contract
fault; it may not discard or substitute those entries. During transport's
FIFO ownership, manual pushes stall. SRAM and FIFO payloads are not two
alternative public output modes.

Only one read and one output command may be pending. Local SRAM ownership is
loader exclusive, then an already accepted fixed kernel, then a transport
copy, then a class-4 request; newly eligible kernel/transport/local requests
use round robin and cannot preempt an accepted operation. Each transport copy
is at most 64 words. Transport waits outside a running kernel do not change
P4's accepted-kernel latency guarantee. The DMA owner remains held until done
through the P2 channel/response drain, including ring fetch and writeback.

Output-memory cursor advances only by bytes from bursts with successful B
responses. `OUTPUT_COMMIT` returns its requested count only after all B
responses succeed. `OUTPUT_STREAM` returns only after the last word of that
command crosses the router-to-I2S handshake, not merely the primitive FIFO
or router enqueue. Source/context data cannot be modified while its command
is pending; unrelated mutable words may still be used. Existing GPR-pending,
`DMA_WAIT`, and `WAIT` semantics apply.
`WAIT 4` includes the router FIFO and unaccepted TX word; `WAIT 5` observes
ring result/OWN writeback. It is initially true before a writeback begins and
is not a prerequisite for the running entry's own future writeback.

The final-output context marker asserts `TLAST` only on the final I2S word of
the marked command. Memory output consumes the marker without an external
`TLAST`. A marked command forbids later output commands in that job. Empty
audio emits no word or `TLAST`. A nonempty successful stream job must have
exactly one final marker. The microprogram checks EOF/container end using
look-ahead before releasing the final PCM frame. There is no fabricated
`TLAST` on a previously accepted word when a job aborts or fails.

`FRAME_COMMIT` retires once per destination PCM sample frame, never once per
compressed FLAC frame or DMA command. Its source0/source1 values add logical
input-used/output-produced deltas and it increments the existing frame counter
by one. Source1 equals destination bytes per frame, including mono-to-stereo
duplication for I2S; input deltas may be zero during upsampling. Hardware
also tracks physical successful bytes independently, so commits cannot exceed
transported bytes. On normal `END`, logical output bytes/frames must equal
physical bytes/complete PCM frames; mismatch is a contract failure. Parsed
input context word 4 supplies final input-used, including header/trailing
chunks not associated with the last PCM frame, and must not be less than the
committed input-used. `FRAME_COMMIT` continues to reset the per-frame retired
watchdog budget. `EVENT` retains IRQ bits 6/7 semantics; it does not replace
the router's watermark detectors.

On failure or abort, results report parsed input context word 4, the physical
successful output prefix, and complete PCM frames in that prefix. A burst
with failing B is excluded from that prefix even though some destination
bytes may physically have changed. No rollback of AXI or accepted audio is
promised. Successful DMA byte counters count each wire transfer once;
sequencer commits and local staging copies do not double-count them. Loader
and ring traffic retain their existing counter attribution. `JOB_CYCLES`
saturates from job acceptance through terminal drain/result construction;
ring finish timestamp precedes OWN clear, as in the P2 scheduler.

Abort/resource block-new stops instruction retirement and new transfers.
An output command is not issued to AXI until its complete payload is in
staging; its accepted W/B work drains even if mutable epochs are invalidated.
A presented unaccepted stream word remains stable and drains, as do already
queued router words. Unpresented staging/primitive-FIFO data may be discarded
after the command's outstanding obligations are tracked. Resource reset is
applied only after drain; hard/PCLK reset retains the P2 warm-flush rules.
If the sink/fabric never responds, idle/abort-done must not falsely assert.
AXI response/protocol and DMA-timeout precedence remains unchanged. New
codec errors enter below the existing AXI/DMA/xrun causes, below a sequencer
trap, and above forced abort on the same cycle; otherwise the first captured
error remains immutable. Empty/full primitive FIFOs alone are backpressure,
not audio xrun. The P2 router's real I2S xrun events retain codes 18/19.
On successful END, any prefetched-but-unparsed input tail is discarded after
all read responses drain; it is not counted as parsed input and cannot carry
into the next entry epoch. This includes relaxed trailing bytes.

##### P5 WAV and native-FLAC file profiles

Files are finite, contiguous DMA inputs of at most `0x7fffffff` bytes. These
limits are the P5 acceptance subset; a valid file outside them is unsupported,
not malformed. WAV syntax uses the Microsoft
[RIFF rules](https://learn.microsoft.com/en-us/windows/win32/xaudio2/resource-interchange-file-format--riff-)
and [PCM/extensible format definitions](https://learn.microsoft.com/en-us/windows/win32/api/mmreg/ns-mmreg-waveformatextensible).
Native FLAC syntax is [RFC 9639](https://datatracker.ietf.org/doc/html/rfc9639);
the bounded profile and error policy below override any freedom it gives a
decoder. LP/HP neither parse these files for the APU nor provide decoded PCM.

| WAV property | P5 rule |
| --- | --- |
| Container | Exactly little-endian `RIFF`, 32-bit size, `WAVE`; no RF64, RIFX, WAVE64, compressed WAVE, or leading tags. Compute `riff_end=8+size` with checked wide arithmetic. It must be at least 12 and not exceed input length. |
| Required chunks | Exactly one `fmt ` before exactly one `data`. Chunk headers are eight bytes; every chunk payload and its odd-size pad must fit `riff_end`. `data` before `fmt `, duplicate required chunks, overlapping/wrapped sizes, or a partial final chunk header fail. |
| PCM `fmt ` | Tag 1; length 16, or length 18 with `cbSize=0`. Channels 1/2, integer rate 8000..96000 Hz, bits 8/16/24/32. `blockAlign=channels*(bits/8)` and `avgBytesPerSec=rate*blockAlign` must match exactly. |
| Extensible `fmt ` | Tag `0xfffe`; length 40, `cbSize=22`, PCM subtype GUID `00000001-0000-0010-8000-00aa00389b71`. Valid bits must equal container bits, both from 8/16/24/32. Mono channel mask is 0 or `0x4`; stereo is 0 or `0x3`. Float subtype, other masks, and padded-valid-bit variants are unsupported. |
| Unknown chunks | Skip bounded payloads by consuming input; do not interpret `LIST`, `JUNK`, `fact`, `bext`, or embedded metadata. At most 1024 chunks and 1 MiB total skipped payload plus padding, including chunks after `data`. |
| Alignment/padding | Odd chunk lengths have exactly one pad byte; strict mode requires zero, relaxed mode accepts any value. Missing required pad is truncated input. `data` size must be a multiple of blockAlign, including a valid zero-length data chunk. |
| End | Parse remaining chunks through `riff_end`. Strict requires `riff_end==INPUT_LENGTH`; relaxed ignores bytes beyond riff_end and sets warning bit 1. `RESULT_INPUT_USED=riff_end` on success. |
| Sample representation | Eight-bit samples are unsigned with bias 128; 16/24/32-bit samples are signed little-endian two's complement. No host conversion or dither. |

| Native FLAC property | P5 rule |
| --- | --- |
| Signature/metadata | `fLaC` at byte zero; first metadata block is exactly one 34-byte STREAMINFO. At most 128 metadata blocks and 1 MiB total metadata payload. A terminating last-metadata flag is mandatory. Types 1..6 are bounded opaque skips; reserved types 7..126 are unsupported; type 127 and duplicate STREAMINFO are malformed. |
| Geometry | 1/2 channels, 16/24 bits/sample, rate 8000..96000 Hz. Nonzero total-samples is a required exact end count; zero means unknown until EOF. Nonzero min/max frame-byte hints must be ordered; STREAMINFO min/max block sizes must be legal and contain each nonfinal frame's block size. |
| Workspace bound | Maximum coded block is 4096 samples for mono or 2048 for stereo. Maximum encoded frame is 65536 bytes. A larger advertised maximum or frame/block is unsupported before PCM from that frame is released. This explicitly excludes common 4096-sample stereo files in P5; broader block support needs a later memory/streaming design. |
| Frame header | Accept fixed- and variable-blocking strategies, all RFC block-size codes 1..15 and sample-rate codes 0..14 when the decoded values fit the profile. Code 0 block size, code 15 sample rate, reserved bits/bit-depth codes, and invalid UTF-8-style frame/sample numbers fail. A file keeps one blocking strategy. Numbers start at zero and advance contiguously; final short blocks, including 1..15 samples, are allowed. |
| Property changes | Rate, bit depth, and channel count must match STREAMINFO and stay constant. Channel assignment may vary per frame among independent/left-side/side-right/mid-side; mono uses independent only. All expected nonzero `INPUT_CONFIG` fields must match the detected source. |
| Subframes | Constant, verbatim, fixed order 0..4, LPC order 1..32; predictor order is no larger than block size. LPC coefficient precision 1..15 and signed shift -16..15 are accepted. Restore predictor warmups and residuals exactly; side subframes use the required extra bit. |
| Wasted bits | Accept any legal wasted-bit count leaving at least one coded bit. Restore wasted bits before stereo decorrelation and check the final nominal sample range. Invalid counts or reconstruction overflow fail. |
| Residuals | Rice and Rice2 with legal partition order 0..15, block divisibility, first-partition warmup subtraction, and exact sample count. Honor P4's quotient limit 65535; a legal larger quotient is unsupported. Escape raw width 0 represents an all-zero residual partition and is synthesized by microcode without issuing the P4 raw-width primitive; raw widths 1..31 use sign extension. |
| Integrity | Mandatory header CRC8 and frame CRC16, initialized zero with the existing P4 polynomials, in both strict modes. All subframe-to-footer pad bits must be zero. Decode and validate the full frame before releasing any of its PCM. No resynchronization, concealment, or checksum bypass. |
| MD5 | STREAMINFO MD5 is retained as metadata but not computed by P5. Zero and nonzero MD5 fields are accepted; success always sets warning bit 0, MD5 unchecked. Strict does not turn on an absent MD5 engine. External reference tests may verify MD5; APU success does not assert whole-file MD5 verification. |
| End/truncation | With a known sample count, stop at exactly that count; a final frame may not exceed it. Strict rejects trailing bytes; relaxed ignores trailing bytes and sets warning bit 1. With unknown count, only exact EOF after a valid frame is success; incomplete next headers/frames fail in either mode. Empty streams are accepted only at the metadata end with total-samples zero. |

The P5 released bundle uses at most 6144 table bytes and reserves at least
18432 scratch bytes for each supported entry, wholly within the existing
`0x00000..0x05fff` workspace. Up to 16384 scratch bytes hold one full decoded
FLAC frame; at least 2048 remain for input copies, predictor state, parameter
blocks, resampling tiles, CRC and job context. Process resampling in tiles of
at most eight source frames so expansion up to 12:1 fits that remainder.
Predictor reconstruction uses at most 64 residual samples per kernel request,
preserving history across requests. Required P5 bundles bound each kernel's
ready-data latency below the existing default `SEQUENCER_TIMEOUT=0xffff` and
prove their maximum retired count between commits (including metadata skip)
fits the entry's 24-bit budget. No artificial FRAME_COMMIT may be used to
reset a watchdog before producing an output PCM frame.
This is a release-bundle packing requirement, not a reduction of P4 loader
capacity. The staging regions and P7 KWS reservation retain their P4 addresses.
WAV processes at most 256 source PCM frames per validation block, using a
smaller tile when needed. A terminal container/metadata error can occur after
earlier valid audio has already been emitted; its prefix is retained.
For resampling across FLAC frames, retain only the bounded history and pending
end tile while decoding the next full frame into the main planar buffer; do
not allocate a second full-frame buffer or read unverified next-frame samples.
On a next-frame CRC error, pending unissued output may be discarded. Accumulate
small packed tiles until an output command can carry 256 bytes, except at
final output or remaining capacity, so I2S startup prefill can complete without
waiting on a shorter nonfinal command's sink handshake.

##### P5 PCM, rate, and completion policy

For source precision `b`, normalize signed source integer `s` to signed Q1.31
with the exact integer `s*2^(32-b)` (WAV unsigned eight-bit first subtracts
128). Stereo-to-mono is `RNE(left+right,1)` using a signed 33-bit sum in that
domain, followed by signed-32 saturation. Bit 10 in CONTROL authorizes this
reduction; it is illegal when not doing stereo-to-mono. Mono-to-stereo is exact
duplication and does not use bit 10. Output channel zero means derive from
source for memory, and two for I2S. Memory permits 1/2 output channels; I2S
requires two physical slots. To request downmixed audio on I2S, select one
logical output channel with bit 10, then duplicate it into the two slots.

CONTROL bit 11 zero requires output rate zero (derive) or exactly source
rate. With bit 11 one, rate must explicitly be 48000 or 96000 Hz and the
reduced output/source ratio must match a P4 profile, including profile 0 for
equal rates. Other ratios are unsupported; no nearest-rate choice is made.
Memory pass-through accepts every source rate in the file profile; I2S output
must resolve to 48 or 96 kHz. Its width/rate are configured through the existing
I2S HAL before submission. The APU does not write I2S registers; the driver
requires matching I2S format and stream-TX configuration and an idle central
DMA TX path before enabling APU TX route.

The shipped P5 resampler tables are three fixed 32-phase/16-tap Q2.30 banks.
Their values are uniquely defined by the following offline formula, not by
host floating-point defaults. For cutoff `c=1,2/3,1/2`, phase `p=0..31`, and
tap `t=0..15`, let `x=t-7-p/32`, `sinc(z)=sin(pi*z)/(pi*z)` with sinc(0)=1,
`w(t)=(1-cos(2*pi*(t+1/2)/16))/2`, and `a(t)=c*sinc(c*x)*w(t)`.
Round `2^30*a(t)/sum(a)` to nearest-even to obtain each coefficient; add the
integer residual `2^30-sum(coefficients)` to tap 7. Coefficient generation
must resolve rounding using increased precision/interval bounds, emit all
1536 little-endian signed words, and compare independently generated words
before shipping. The binary is covered by the APUMC CRC/build manifest. P4
arithmetic, profile mapping, phase rounding, history/look-ahead, and saturation
are unchanged. Identity bypass is exact; nonidentity conversion is not a
lossless-output claim.

After downmix/resampling, convert Q1.31 to signed output precision by
arithmetic right shift 16 for S16 or 8 for S24, then saturation. There is no
dither or implicit gain. Before using `PCM_PACK`, microcode has already made
that shift and sets packer gain to `0x40000000`. Thus native 16/24-bit FLAC
pass-through at matching precision/rate/channels is bit-exact, and changing
precision has a deterministic amplitude-preserving result. Stereo S16 uses
one full 32-bit I2S word per frame; stereo S24 uses two sign-extended words.
`TKEEP=TSTRB=0xf`; all other I2S sidebands are zero except final `TLAST`.

Output capacity is enforced before issuing each command, with checked
`cursor+bytes` arithmetic; only whole destination PCM frames may be issued.
Memory output requires nonzero capacity and four-byte-aligned address. Stream
output uses address/capacity zero. In either mode total output bytes must fit
32 bits; detect a prospective overflow as code 22/stage 8 before issue rather
than allowing a cursor to wrap.
If the entire next command cannot fit, issue no byte from it and terminate
with code 8/capacity detail. The released microprogram must shorten a tile to
the remaining whole-frame capacity first, then report exhaustion if more
audio remains. A known too-small capacity need not prevent earlier valid
frames from being returned. Input format errors never publish a partly
decoded or CRC-unverified FLAC frame; transport faults may leave partial
output from an already verified frame. Success is distinct from partial
prefix plus terminal error.

Memory success waits for every output B response. Stream success waits for
the final router-to-I2S handshake and an empty APU TX router, not for the last
sample to leave the DAC pin. The stream session remains active until that
drain, so route changes still use the P2 active-direction rule. Software that
needs audible completion must separately drain I2S before disabling it.
Empty jobs need no final beat. IRQ, ring coalescing/IOC, result writeback and
OWN-last release follow P2; direct completion uses IRQ bit 0, ring uses bit 1.
`JOB_FLAGS[0]` affects only the explicitly stated padding/trailing-byte checks;
it never disables bounds, codec CRC, overflow, or output-capacity checks.

##### P5 format diagnostics and unsupported MP3 entry

Codec `RESULT_DETAIL`, `JOB_DETAIL`, and codec `ERROR_DETAIL` use format ID
`[31:24]`, warnings `[23:16]`, and reason `[15:0]`. Warnings are bit 0 MD5
unchecked (FLAC only), bit 1 relaxed trailing bytes ignored, bit 2 relaxed
nonzero WAV pad accepted; bits 3..7 are zero. Warnings describe checks actually
skipped, including on a later failure. All unspecified reason values are
reserved. On success reason/code are zero. On a codec error the tuple has
VALID=1, AXI response=0, direct descriptor index=0 or the owning ring index,
and `ERROR_ADDRESS=INPUT_ADDRESS+context_word5`, with checked arithmetic.
The location is the first byte of the failing field/chunk/frame, or exactly
one-past-input for truncation. W1C, existing first-error preservation and P3
loader/trap tuples remain unchanged.

| Reason | Meaning | Code / stage |
| ---: | --- | --- |
| `0x0001` | Unsupported operation/format | 3 / 2 |
| `0x0002` | Unsupported rate/channels/precision or expected-input mismatch | 3 / 4 |
| `0x0003` | Unsupported valid encoding/container/metadata type | 3 / 4 |
| `0x0004` | File/chunk/metadata/block/frame/Rice quotient profile limit | 3 / 4 (container/block) or 5 (Rice) |
| `0x0010` | Bad file signature | 4 / 4 |
| `0x0011` | RIFF size/wrap or malformed container extent | 4 / 4 |
| `0x0012` | Missing/duplicate/misordered required chunk | 4 / 4 |
| `0x0013` | Chunk data length not frame-aligned or invalid chunk extent | 4 / 4 |
| `0x0014` | Invalid PCM format fields/alignment/byte rate | 4 / 4 |
| `0x0015` | Invalid STREAMINFO | 4 / 4 |
| `0x0016` | Invalid FLAC metadata structure | 4 / 4 |
| `0x0017` | Invalid/reserved frame header | 4 / 4 |
| `0x0018` | Midstream geometry/blocking-strategy change | 4 / 4 |
| `0x0019` | Forbidden nonzero pad bits/strict pad byte | 4 / 4 |
| `0x001a` | Invalid/noncontiguous frame or sample number | 4 / 4 |
| `0x001b` | Strict trailing bytes | 4 / 4 |
| `0x0020` | Required bytes/bits missing | 5 / 4 for class 2/parser; 5 / 5 for entropy |
| `0x0030`, `0x0031` | Header CRC8, frame CRC16 mismatch | 6 / 4 |
| `0x0032` | Nonzero STREAMINFO total differs at complete-frame EOF or is exceeded | 4 / 4 |
| `0x0040` | Malformed entropy/partition encoding | 7 / 5 |
| `0x0041` | Invalid wasted-bit count | 7 / 5 |
| `0x0042` | Invalid Rice escape/partition sample count | 7 / 5 |
| `0x0043` | Reconstruction or restored sample out of range | 22 / 6 |
| `0x0050` | Unsupported output rate/channel/flag combination | 3 / 0 |
| `0x0051` | Destination capacity exhausted | 8 / 8 |
| `0x0052` | Invalid context/cursor/commit/final-marker contract | 11 / 11; uses existing sequencer reason-9 trap detail, not codec detail |

Structural APB rejections still return `PSLVERR` without inventing a new
codec result. For unsupported ring descriptors, reason 1 uses descriptor
CONTROL address rather than an input-file address. Transport/primitive/trap
errors keep their existing P2/P3/P4 tuple (including PC addresses), and the
job result copies that detail. The format table applies to microcode parser
`JOB_RESULT` failures, not a reinterpretation of those lower-level failures.
For output capacity reason `0x0051`, use `OUTPUT_ADDRESS+output_cursor` for
memory (response zero, stage 8, owning job index). A total-byte overflow on
stream uses address zero and code 22/stage 8 with `trap_detail(9)`; on memory
it uses the checked next destination address, saturating at `0xffffffff` if
that address itself overflows. Invalid context reason `0x0052` uses the
existing reason-9 fallback code 11/stage 11/index zero/PC address.
When multiple parser checks at the same position fail, structural extent and
reserved-bit errors precede unsupported-profile checks, then CRC checks;
the first check in field order otherwise wins.

The released P5 APUMC still contains exactly three entries. Instruction word
0 is always `0x0200000001000001` (unconditional class-0 TRAP, detail
`0x01000001`). The MP3 entry at descriptor index 1 has the exact eight words
`[0x00000001, 0, 0, 0, 1, 1, 0, 0]`: entry/first/last PC zero, zero scratch,
table and primitive mask, maximum loop/retired one. A verification-only
launch of it produces code 11/stage 11/response 0/index 0/address 0/detail
`0x01000001`, retired zero. Public MP3 requests are rejected with unsupported
format before reaching that trap. WAV and FLAC entries start after PC 0;
their masks contain the primitives they declare and may share read-only
tables and scratch as already allowed. The header mask is the OR of entries,
not forcibly `0x001fffff`; the implemented mask advertises hardware capacity.

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

### P5 HAL contract

The following declarations are the required P5 additions to
`<retrosoc/hal/apu.h>`, implemented in `crt/src/hal/apu.c` with deterministic
packing/validation tests. They describe software interfaces to implement in
P5; this freeze does not add code. Existing `rs_apu_probe`, `rs_apu_info_t`,
`rs_apu_descriptor_t`, and every 128-byte descriptor member offset are retained.
Enums use the already frozen integer encodings. These host-side structures
are not DMA wire formats; only `rs_apu_descriptor_t` is the shared layout.

```c
typedef enum { RS_APU_WAV = 0, RS_APU_MP3 = 1, RS_APU_FLAC = 2 } rs_apu_format_t;
typedef enum { RS_APU_MEMORY = 0, RS_APU_I2S = 1 } rs_apu_output_t;
typedef enum { RS_APU_S16 = 0, RS_APU_S24_32 = 1 } rs_apu_pcm_t;

typedef struct {
    rs_apu_format_t format;
    rs_apu_output_t output;
    rs_apu_pcm_t pcm;
    uint32_t input_address, input_bytes;
    uint32_t output_address, output_capacity;
    uint32_t expected_rate, expected_channels, expected_bits;
    uint32_t output_rate, output_channels;
    uint32_t downmix, resample, strict; /* each exactly zero or one */
    uint32_t cookie[2];
} rs_apu_job_t;

typedef struct { uint32_t address, bytes, expected_crc; } rs_apu_image_t;
typedef struct { uint32_t status, address, detail; } rs_apu_error_t;
typedef struct {
    uint32_t status; /* descriptor RESULT_STATUS encoding, including direct */
    uint32_t input_used, output_bytes, frames, source_info, cycles, detail;
    uint32_t cookie[2], start_timestamp[2], finish_timestamp[2];
    uint32_t microcode_build_id;
    rs_apu_error_t first_error;
} rs_apu_result_t;

typedef struct {
    rs_apu_descriptor_t *descriptors; /* aligned CPU mapping, caller-owned */
    uint32_t dma_address, entries, tail;
} rs_apu_ring_t;

rs_status_t rs_apu_set_acl(uint32_t read_base, uint32_t read_limit,
                           uint32_t write_base, uint32_t write_limit);
rs_status_t rs_apu_microcode_load(const rs_apu_image_t *image, rs_timeout_t timeout);
rs_status_t rs_apu_validate_job(const rs_apu_job_t *job);
rs_status_t rs_apu_submit_direct(const rs_apu_job_t *job);
rs_status_t rs_apu_wait_direct(rs_apu_result_t *result, rs_timeout_t timeout);
rs_status_t rs_apu_decode(const rs_apu_job_t *job, rs_apu_result_t *result,
                          rs_timeout_t timeout);
rs_status_t rs_apu_ring_configure(rs_apu_ring_t *ring, uint32_t stop_on_error,
                                 uint32_t coalesce_count, uint32_t coalesce_timeout);
rs_status_t rs_apu_ring_submit(rs_apu_ring_t *ring, const rs_apu_job_t *job,
                              uint32_t ioc, uint32_t *slot);
rs_status_t rs_apu_ring_result(const rs_apu_ring_t *ring, uint32_t slot,
                              rs_apu_result_t *result, rs_timeout_t timeout);
rs_status_t rs_apu_ring_disable(rs_timeout_t timeout);
rs_status_t rs_apu_stream_route(uint32_t tx_route, uint32_t rx_route);
rs_status_t rs_apu_abort(rs_timeout_t timeout);
rs_status_t rs_apu_soft_reset(void);
rs_status_t rs_apu_error_read(rs_apu_error_t *error);
rs_status_t rs_apu_error_clear(void);
rs_status_t rs_apu_irq_read(uint32_t *state);
rs_status_t rs_apu_irq_enable(uint32_t mask);
rs_status_t rs_apu_irq_ack(uint32_t mask);
```

All pointers are mandatory; addresses are 32-bit DMA addresses, never silently
truncated CPU pointers. Validation rejects unknown enums, nonboolean flags,
reserved fields, misalignment, overflow, overlap, unsupported capabilities,
and invalid capacity/route combinations before any job-register mutation.
Header-dependent checks are performed by APU microcode after submission, not
by reading the file on LP/HP. Direct submission packs the same descriptor
words into `JOB_*`, fences, and issues START once; it is asynchronous.
`rs_apu_decode` is exactly submit-direct followed by wait-direct. Direct
results normalize `JOB_STATUS` into descriptor-result bit positions; direct
cookie is the saved submitted cookie, and direct start/finish timestamps are
zero because no corresponding APB registers exist. The direct build ID is
read from the locked MC build ID. `first_error` is a raw snapshot of the global
first-error tuple and may belong to an earlier fault; per-job status/detail
are authoritative for the returned job. No API implicitly clears first error.

`rs_timeout_t` uses the existing unsigned poll-budget convention here: timeout
`n` permits at most `max(1,n)` status observations; zero is a nonblocking
single observation, not infinite. `RS_TIMEOUT_DEFAULT` is the existing SDK
default. A poll has no assumed wall-clock duration. Exhaustion returns
`RS_ETIMEOUT`, leaves the output result structure untouched, and does not
abort, reset, release buffers, or retry a command. An admitted operation can
still be active; buffers remain owned until a later successful terminal wait
or drained abort. A successful poll populates the complete result even when
its terminal status maps to a nonzero `rs_status_t`.

Return mapping: `RS_EINVAL` for invalid arguments, range/packing violations,
or illegal idle/owner conditions; `RS_ENOTSUP` for a clear required capability
or error code 3; `RS_ENOSPC` for full software ring or reason `0x0051` capacity
exhaustion; `RS_ETIMEOUT` for poll exhaustion; `RS_EFORMAT` for codec codes
4..7; `RS_EIO` for hardware DMA, trap, overflow, abort, or other terminal
failures. Successful operation is `RS_OK`. Busy is not encoded as success;
terminal DMA timeout is `RS_EIO` with hardware code 17, distinct from a HAL
poll budget expiring while hardware is still running.

The caller owns resource acquisition/quiesce, I2S setup, cache maintenance,
and serialization between LP/HP/interrupt contexts. APU HAL calls never
transfer resource ownership, decode on the host, allocate memory, or load a
replacement image automatically. ACL programming and microcode load are
LP-only and quiesced/idle; a locked image returns `RS_EINVAL` without trying
to unlock it. Load waits for busy to clear, then checks MC valid/lock/CRC and
returns the frozen loader result. Timeout does not cancel the load.

Ring configure requires idle with ring disabled, 2..256 power-of-two entries,
128-byte-aligned CPU/DMA bases, a non-cacheable descriptor mapping, boolean
stop-on-error, count 1..255, and timeout 1..65535. It programs
base/size/coalescing, tail zero, then enables;
software must have cleared every OWN bit before configuring. At most
`entries-1` slots are queued to disambiguate head==tail. Submit fills a free
slot, zeros result/reserved/KWS words, preserves the requested cookie, writes
OWN last, fences, advances tail, and rings the doorbell. The P5 ring helper
requires non-cacheable descriptor storage so no cache-maintenance callback is
needed between its payload stores and OWN publication. Payload-buffer cache
clean/invalidate remains the caller's responsibility before submit and after
completion; manual cached-descriptor operation still follows the existing P2
CBO contract. Submit does not wait. Result polling observes OWN clear with
an acquire fence and then copies the immutable descriptor
result. A slot with OWN clear and no terminal result is not a completed job
and returns `RS_EINVAL`; callers must collect a slot before resubmitting it.
Result polling never recycles or advances a producer slot. Ring disable uses abort
when active, waits for idle, then clears enable. Abort on an idle APU is a HAL
no-op returning OK; otherwise it issues ABORT once and waits for idle/abort
completion. Soft reset requires idle and preserves the locked bundle.

`rs_apu_stream_route` changes the requested directions only after checking
their active state and P5 directional capabilities; it preserves the P2
same-value write rule. IRQ enable replaces the enable mask, IRQ ack W1C-clears
only requested implemented bits, and reads never clear. Invalid mask bits are
`RS_EINVAL`. Error clear writes only ERROR_STATUS valid/W1C and cannot clear a
same-cycle hardware fault. None of these calls changes existing IRQ routing.

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
frontend 9, KWS inference 10, and sequencer-control/lifecycle 11.

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

### P5 locked reference inputs and qualification

The following pins were read from upstream and both archive SHA-256 values
were computed from the complete fixed-revision archive bytes on 2026-09-05.
They are authoritative P5 setup inputs, not floating branch/tag selections.
This documentation freeze does not modify the executable dependency lock.
Adding the exact entries and setup/test integration below is the first P5
implementation step; missing installed inputs are setup work, not an open
architecture choice. No direct download is added to CI or firmware flows.

| Lock key / use | Upstream and full revision | Destination | License handling |
| --- | --- | --- | --- |
| `sources.apu_libflac` / host-only reference | `https://github.com/xiph/flac.git`, release 1.5.0 commit `1507800de4b70e21be71f38caa0d9079d0bc6e45` | `.cache/retrosoc/sources/apu-libflac` | Lock license `NOASSERTION` for the mixed source tree; libFLAC/libFLAC++ are BSD-3-Clause (`COPYING.Xiph`), CLI code is GPL-2.0-or-later. Retain COPYING.Xiph, COPYING.GPL, COPYING.LGPL, COPYING.FDL and per-file notices. |
| `sources.apu_flac_corpus` / host-only corpus | `https://github.com/ietf-wg-cellar/flac-test-files.git`, commit `aa7b0c6cf32994c106ae517a08134c28a96ff5b2` | `.cache/retrosoc/sources/apu-flac-corpus` | `CC0-1.0`; retain LICENSE.txt and root/per-group README.txt attribution. |

| Archive lock key | URL | SHA-256 | Download destination |
| --- | --- | --- | --- |
| `archives.apu_libflac` | `https://codeload.github.com/xiph/flac/tar.gz/1507800de4b70e21be71f38caa0d9079d0bc6e45` | `d80ef5facdb21972efe91774da03d6b9abf216aa17093d740fcc411cd8afbb41` | `.cache/retrosoc/downloads/apu/libflac-1507800de4b70e21be71f38caa0d9079d0bc6e45.tar.gz` |
| `archives.apu_flac_corpus` | `https://codeload.github.com/ietf-wg-cellar/flac-test-files/tar.gz/aa7b0c6cf32994c106ae517a08134c28a96ff5b2` | `36de2310155b4084011fbd56f24603dfef91a26c5433e3f92bd21995b45089c3` | `.cache/retrosoc/downloads/apu/flac-corpus-aa7b0c6cf32994c106ae517a08134c28a96ff5b2.tar.gz` |

Archive license fields match the corresponding source entries. Git checkout
and verified archive extraction are two encodings of the same pinned source;
setup selects one explicitly and must not silently fall back to a newer
revision after a checksum failure. Build the host reference with Ogg disabled,
and keep its binaries/build products in the variant build tree. No libFLAC,
GPL CLI, or corpus code is linked into `crt/`, LP/HP firmware, RTL, or shipped
APUMC; comparison is through host test processes. If reference tools are
redistributed, retain their applicable source/license obligations. `NOASSERTION`
is not a relicensing or compliance claim. P5's self-owned HAL and microassembly
are independent artifacts; any copied upstream material needs explicit notice
review before inclusion.

P5 delivers deterministic WAV/FLAC microassembly, the three-entry APUMC bundle,
1536-word resampler coefficient file, symbols, instruction/control-store and
scratch high-water reports, and a per-file corpus manifest. The manifest records
each pinned corpus relative path and SHA-256, its expected supported/rejected/
malformed result, profile reason, PCM geometry, and reference-output hash.
Every official corpus file is classified, including files above P5 block limits;
unsupported files must be tested for clean rejection, not silently omitted.
Generated valid/malformed vectors supplement the official corpus for every
WAV chunk boundary, FLAC escape width zero, wasted-bit count, predictor order,
CRC fault, strict/relaxed case, and 2048/4096 block boundary. Host libFLAC
supplies PCM truth; the independent integer post-processing model supplies
downmix/resample/packing truth. CRC-only success with MD5 unchecked must be
visible in expected results.
The host harness obtains PCM even for an MD5-only mismatch and records that
reference integrity failure separately; it must not mislabel the P5 documented
MD5-unchecked acceptance as a PCM decoding mismatch.

Directed tests must exercise production direct and ring submission, invalid
owned MP3/KWS entries, class-6 cursor/FIFO backpressure, all three required
bundle entries, every format error tuple, exact output capacity and one-frame
short capacity, I2S final TLAST/drain, abort/reset during every transport stage,
and cross-format ring sequences. Differential Icarus and Verilator runs use
the same fixtures and result scoreboard; no verification injector may appear
in product behavioral or synthesis filelists. Formal covers exclusive DMA/SRAM
ownership, range checks, stable stream payload under stalls, accepted-transfer
drain, OWN-clear ordering, and no public MP3/KWS/RX execution. P3/P4 target and
observability regressions remain required.

At 48 MHz PCLK, a ready memory target must sustain the P5 supported WAV/FLAC
rates and 44.1-to-48 kHz conversion in cycle-counted simulation. The I2S test
starts consumption after a 64-word APU prefill (or the whole output for a
shorter job), then supplies ready memory without injected stalls; between
first and last samples it must record zero xrun. Separate random-stall tests
verify bounded error/drain rather than claim uninterrupted playback under
unbounded stalls. Measured maximum tolerable AXI stalls, source properties,
instruction budget, and occupancy must accompany results. Static timing,
area, power, netlist, and physical 48 MHz closure remain Phase8 evidence.

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
2048x64 control store, scalar/loop/call state, load-time local/table protection,
watchdog/traps, loader lock/atomic publication, ABI parity, co-simulation, and
formal. Class-2 through class-6 execution, codec tables, and data SRAM remain
outside this phase.

Dependencies: Phase2, the Common `tc_sram_1024x32` wrapper for macro profiles,
and the frozen inferred-control-store fallback for `HAVE_SRAM_MACRO=NO`.

Public changes: implements the frozen microcode loader, class-0/class-1
sequencer, `MC_STATUS`, `MC_ABI`, build/CRC/lock/count, IRQ bit 3, and exact
P3 values `CAPABILITY0=0x00000098` and `CAPABILITY1=0x00000010`.
`ABI_DIGEST` remains zero. Public direct/ring commands and APU stream routes
remain fail-closed, and the verification-only dummy launch adds no public ABI.
It adds no processor, system hart, new clock domain, or arbitrary code
execution.

Validation:

```sh
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-lint
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke LINK_TYPE=ld2_all_sram SOC_SIM_TIME=360 VERILATOR_SIM_ARGS=--fast-flash SIMU=VERILATOR HAVE_SVA=YES firmware sim
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ics55.mk SYNTH=YOSYS synth
```

The 360-second command with `--fast-flash` is the supported P3 SoC-level
Verilator acceptance command; fast flash changes only boot/XPI timing and does
not bypass APU logic. Directed loader/sequencer tests remain the functional
evidence for the P3 paths.

Completion: all three required zero-table/zero-primitive entries load
atomically and deterministic class-0/class-1 dummy programs execute through
the verification-only launch. Every malformed header/descriptor/ISA/control-
flow/range/table/CRC/capability/watchdog case fails closed with the frozen
status, IRQ, count, and reset result. Macro and inferred control-store mappings,
including ICS55 elaboration/synthesis, are reviewed. No P4..P7 engine is
required for P3 completion.

### Phase 4 - Shared Bitstream, Entropy, and DSP Primitive Engines

ID: `APU-P4`.

Scope: reservoir, CRC, Huffman/Rice, scalar reconstruction, transform,
resampler/PCM packer, 112 KiB local SRAM arbitration, primitive scoreboard,
latency counters, extreme arithmetic tests, and formal bounds. The implemented
primitive mask is `0x0000ffff`; class 6 and primitive bits 16..20 remain
outside this phase.

Dependencies: Phase3, Common `tc_sram_1024x32`, and Common `stream_fifo`.

Public changes: reports exact P4 values `CAPABILITY0=0x00000198` and
`CAPABILITY1=0x01827010`, admits the frozen class-2..5 ISA and APUMC table/
scratch fields, and retains `ABI_DIGEST=0`. Format, stream, and KWS capabilities
remain zero, while primitive channel/rate discovery becomes 2/96 kHz; public
direct/ring/stream behavior stays fail-closed. No new public register, opcode
class, format ID, IRQ, resource, address, clock/reset boundary, or CDC/RDC entry
is added.

Validation:

```sh
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal-apu
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR HAVE_SVA=YES rtl-lint
```

`tests/test_apu_primitives.py` is a required P4 deliverable and runs the same
golden corpus through the Python BAM/interpreter plus focused Icarus and
Verilator primitive testbenches. `formal-apu` must include the P4 dispatcher,
local-range/validity, single-kernel, and latency-counter properties.

Completion: every primitive matches BAM over directed/random/extreme inputs,
meets the frozen ready-data latency bound, reports the frozen fault tuple,
proves local/table/FIFO bounds, and preserves all fail-closed public paths.
Yosys synthesis, OpenSTA, netlist simulation, macro PPA, and 48 MHz closure are
explicitly deferred to Phase8 and are not P4 completion gates.

### Phase 5 - WAV and FLAC Microprograms

ID: `APU-P5`.

Scope: WAV/FLAC microassembly, tables, metadata/frame parsing, PCM conversion,
Rice/fixed/LPC/decorrelation, resampling, memory/I2S output, interpreter/RTL
differential, conformance corpus, and the frozen P5 HAL. Includes production
class-6 transport, controller entry context, direct/ring backend connection,
TX stream routing, and exact codec/result policies in the P5 sections above.

Dependencies: reviewed Phase4 and the exact RFC/libFLAC/corpus inputs above.
Implement their dependency-lock/setup entries before reference tests. No host
decoder enters the product path.

Public changes: `CAPABILITY0=0x000001bd`, `CAPABILITY1=0x01827010`, implemented
primitive mask `0x001fffff`, classes 0..6, format IDs 0/2, TX route 1, and the
documented HAL. MP3/KWS/RX route 1 remain unavailable and `ABI_DIGEST=0`.
No existing APB offset, descriptor layout, P1..P4 target behavior, Resource7,
APB group23, IRQ31/PLIC10, Gateway A identity, or clock/CDC allocation changes.

Validation:

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk firmware
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR HAVE_SVA=YES rtl-lint
make CONFIG=configs/ci/ihp130.mk formal-apu formal-apu-loader formal-apu-sequencer
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke LINK_TYPE=ld2_all_sram SOC_SIM_TIME=360 VERILATOR_SIM_ARGS=--fast-flash SIMU=VERILATOR HAVE_SVA=YES firmware sim
```

`tests/test_apu_codecs.py` and `tests/test_apu_codec_transport.py` are P5
deliverables included by the full Pytest command; missing required EDA/reference
tools are reported as unrun, never counted as passing skipped tests. The
ci_smoke command proves SoC integration and does not replace the directed
codec corpus or long-playback evidence.

Completion: the exact supported/rejected matrices, malformed corpus, published
error/count rules, HAL host tests, and production direct/ring/TX paths pass.
Matching-precision/rate/channel FLAC is bit-exact; 44.1-to-48 and 24-bit/96 kHz
playback meet the cycle-counted xrun gate. Larger FLAC blocks, whole-file MD5,
unlisted conversion ratios, MP3 and KWS are outside P5. Synthesis/STA/netlist/
PPA remain deferred to Phase8; functional cycle evidence is not timing signoff.

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
