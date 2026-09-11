# Mini Audio Processing Unit

## Purpose and Research Boundary

This document is the authoritative architecture, interface, microcode, software,
and verification contract for the retroSoC Mini Audio Processing Unit (APU).
The stable feature slug is `apu`. The current release provides autonomous
WAV/PCM and native FLAC decode, fixed-point sample processing, private DMA,
direct I2S streaming, and continuous keyword spotting (KWS).

Current-release scope: APU-P6 MP3 decoding is explicitly DEFERRED. The stable
Phase 6 ID/title remain as an inactive placeholder; Phase 7 proceeds from
the reviewed Phase 5 baseline and Phase 8 does not require Phase 6 completion.
The retained P6 design/reference sections are historical, non-normative notes
for a future refreeze. They do not enable MP3 or require MP3 dependencies,
three-active-codec packing, PSNR or MP3 real-time evidence in this release.
This scope rule takes precedence over those deferred notes. All other active
WAV/FLAC, KWS, transport, ABI, ownership and physical-evidence requirements
remain in force.

APU-P7 is refrozen on 2026-09-11 by the P7 sections below. They fix the
reference inputs, APUM 1.0 wire format, numerical profile, capture settings,
HAL and acceptance rules; they do not assert that P7 is implemented. The
starting implementation remains reviewed P5 with `CAPABILITY0=0x000001bd`.
Only completed P7 qualification permits `0x000001fd`. No P6 work is reactivated.

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
| `APU-MVP-004` | WAV/PCM and native FLAC decode MUST execute entirely in the coreless APU. MP3 decoding is deferred and MUST NOT be advertised by this release. |
| `APU-MVP-005` | LP MUST load one bundle containing exactly three entry descriptors: active WAV and FLAC entries plus the existing unsupported-MP3 trap stub. Successful load MUST lock microcode until hard reset. |
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

The following work is DEFERRED outside the active implementation phases of
this release and MUST NOT be silently inserted into an MVP phase:

- APU-P6 MPEG-1/2/2.5 Layer III MP3 decoding, its production microprogram,
  reference/corpus setup, three-active-codec packing, PSNR and MP3 real-time
  qualification; the Phase 6 slot remains reserved for an explicit future
  refreeze and is not a release blocker;
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
    apu_control_store       (4096 x 64, 32 KiB from the P5 capacity refreeze)
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

From the P5 capacity refreeze, total image/data storage is 144 KiB instead of
the earlier 128 KiB target. P3/P4 implemented capacities remain as reported in
their capability profiles:

| Region | Capacity | Use |
| --- | ---: | --- |
| control store | 32 KiB | 4096 64-bit instructions containing codec programs and common subroutines; P3/P4 retain 2048 words / 16 KiB. |
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

Previously delivered P4 primitives remain implemented and tested even where
their names or research rationale mention MP3. Their presence does not enable
format ID 1. Deferring MP3 does not remove these engines, shrink the 4096-word
control store or 112 KiB data store, or change the P5 instruction/transport ABI.

### Independent KWS

I2S RX feeds a dedicated KWS input FIFO, mono/downmix, 16 kHz resampling,
512-point fixed FFT/MFCC, and a 16-lane INT8/INT32 DS-CNN engine. Supported
operators are Conv2D, depthwise 3 by 3, pointwise 1 by 1, bias,
requantization/ReLU, the pinned 25 by 5 average pool, fully connected, and
INT8 Softmax. The source model's shape-only reshape is folded by the converter.

KWS evaluates a 49 by 10 INT8 window every 100 ms. Score threshold and 1..255
consecutive-hit debounce are programmable. KWS does not use codec microcode or
codec MAC lanes, so it remains live during file decode. Only SRAM arbitration,
PCLK, stream routing, IRQ collection, and lifecycle control are shared.

### Control and data flow

1. LP programs read/write ACLs and the `APUMC` bundle address/size/CRC.
2. Private DMA loads the WAV/FLAC bundle with the retained MP3 trap entry.
   Hardware and the offline
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
| 4 | `OUTPUT_ADDRESS` | Aligned PCM destination for decode; zero for stream output or operation1. |
| 5 | `OUTPUT_CAPACITY` | Destination bytes for decode; zero for stream output or operation1. |
| 6 | `INPUT_CONFIG` | Expected rate `[16:0]`, channels `[18:17]`, source bits/sample `[25:20]`; zero fields mean derive. |
| 7 | `OUTPUT_CONFIG` | Rate `[16:0]`, channels `[18:17]`, PCM format `[20:19]`. |
| 8 | `JOB_FLAGS` | Strict decode bit 0; all other V1 bits zero. |
| 9 | `KWS_CONFIG` | Memory-window threshold `[7:0]`, debounce `[15:8]`; zero for decode. |
| 10 | `RESULT_INPUT_USED` | Bytes consumed. |
| 11 | `RESULT_OUTPUT_BYTES` | PCM bytes written or streamed. |
| 12 | `RESULT_FRAMES` | PCM sample frames produced by decode; input sample frames consumed by operation1. |
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

Format ID 1 remains allocated for compatibility but MP3 decode (operation 0,
format 1) is unsupported throughout this release, including after P7 KWS is
enabled. `RS_APU_MP3` remains declared and HAL decode/submission returns
`RS_ENOTSUP` for it. A raw direct start returns `PSLVERR` without payload DMA
or result mutation; an owned ring entry completes code 3/stage 2/detail
`0x01000001` at its CONTROL address and follows existing writeback/OWN-clear
rules. This does not defer KWS operation 1. No host MP3 fallback is allowed.
MP3 format ID 1, capability bit 1, and format-1 parser-detail reasons
`0x0100..0x0140` remain reserved for future MP3 reactivation and may not be
reassigned. Those deferred parser details are not emitted in this release;
the existing unsupported result/stub detail `0x01000001` is unchanged.

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
| `0x004` | `IP_VERSION` | RO | implementation | APB ABI V1.0 `0x00010000` for P1..P4 and pre-expansion P5; expanded P5 onward is V1.1 `0x00010001`. |
| `0x008` | `CAPABILITY0` | RO | implementation | Bits 0..2 WAV/MP3/FLAC, 3 private DMA, 4 ring, 5 streams, 6 KWS, 7 sequencer, 8 resampler. P1 is `0`; P2 is `0x00000018`; P3 is `0x00000098`; P4 is `0x00000198`; P5 is `0x000001bd`; P7/completed current MVP is `0x000001fd`. MP3 bit 1 stays zero; deferred P6 introduces no current capability value. |
| `0x00c` | `CAPABILITY1` | RO | implementation | Control-store KiB `[7:0]`, data SRAM KiB `[15:8]`, max channels `[17:16]`, max source-rate kHz `[25:18]`; P1/P2 are `0`; P3 is `0x00000010`; P4 is `0x01827010`; expanded P5 onward is `0x01827020` (32/112/2/96). |
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
| `0x058` | `SEQUENCER_STATUS` | RO | `0` | PC low `[10:0]`, class `[14:11]`, opcode `[18:15]`, wait 19, loop-active 20; APB V1.1 appends PC bit 11 at bit 21. |
| `0x05c` | `SEQUENCER_RETIRED` | RO | `0` | Saturating instructions retired in current frame/block. |
| `0x060` | `STREAM_WATERMARK` | RW idle | `0` | RX/input high `[7:0]`, TX/output low `[15:8]`, reserved `[31:16]=0`; zero disables, otherwise 1..64. Added in P2. |
| `0x080` | `MC_IMAGE_ADDRESS` | RW idle/LP | `0` | 64-byte-aligned `APUMC` address. |
| `0x084` | `MC_IMAGE_SIZE` | RW idle/LP | `0` | Exact nonzero bundle bytes. |
| `0x088` | `MC_EXPECTED_CRC` | RW idle/LP | `0` | Expected payload CRC32, equal to header. |
| `0x08c` | `MC_STATUS` | RO | `0` | Busy 0, valid 1, header error 2, range error 3, control-flow error 4, table error 5, CRC error 6, capability error 7; `[31:8]` reserved zero. |
| `0x090` | `MC_ABI` | RO | `0` | Loaded APUMC/ISA version: V1.0 `0x00010000` or V2.0 `0x00020000`, according to the validated image. Independent of APB IP_VERSION. |
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
| `0x23c` | `KWS_INPUT_CONFIG` | RW disabled/idle | `0x0104bb80` | P7 append: rate `[16:0]`, physical channels `[18:17]`, precision `[25:20]`; see P7 capture rules. |
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
the complete canonical APB V1 register/field/job-descriptor, supported
`APUMC` V1/V2, `APUM`, opcode,
format/IRQ/error tables only in the Phase8 supported MVP. For this release,
the digest includes reserved MP3 identifiers and the P5 rejection/stub contract
but excludes the inactive P6 design archive. A zero digest means
prototype/incomplete ABI and is not a compatibility hash for a subset.

Expanded P5 keeps `CAPABILITY0=0x000001bd` and primitive mask `0x001fffff`,
but advertises `CAPABILITY1=0x01827020` and `IP_VERSION=0x00010001` for the
32 KiB store and appended PC-high status bit. This hardware discovery is
constant even while a legacy V1 image is loaded. Format, TX/RX, KWS, data-SRAM,
channel, rate, IRQ, ownership, and job behavior are otherwise unchanged.

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

#### Versioned P5 control-store expansion

The selected P5 capacity remedy is a 4096-word, 64-bit control store. The
reported compacted 2437-word trial was already 389 words over the old limit
and still omitted cross-frame FLAC resampling and complete long-Rice paths.
That report is sizing evidence, not a complete-codec acceptance result. The
expanded store leaves 1659 words relative to that incomplete trial; the final
complete image must still demonstrate that it fits. No compact opcode,
dynamic-kernel operand, parser/CRC shortcut in RTL, host decode, overlay, or
runtime code replacement is authorized by this refreeze.

APB register ABI and APUMC binary ABI have independent versions. APB V1.1 is
an additive status/capacity extension. APUMC V2.0 versions the widened PC and
branch operands so legacy images retain their exact V1 validation rules.

| Target / image | APB `IP_VERSION` | `CAPABILITY1` | Header word 1 / loaded `MC_ABI` | Instruction count / PC width |
| --- | --- | --- | --- | --- |
| Historical P3 | `0x00010000` | `0x00000010` | `0x00010000` only | 1..2048 / 11 bits |
| Historical P4 | `0x00010000` | `0x01827010` | `0x00010000` only | 1..2048 / 11 bits |
| Pre-expansion P5 compatibility image | Historical hardware remains `0x00010000` | Historical hardware remains `0x01827010` | `0x00010000` | 1..2048 / 11 bits |
| Expanded P5, legacy image loaded | `0x00010001` | `0x01827020` | `0x00010000` | 1..2048 / 11-bit validation on the 12-bit engine |
| Expanded P5, V2 image loaded | `0x00010001` | `0x01827020` | `0x00020000` | 1..4096 / 12 bits |

Expanded P5 must load both exact header versions. Unknown versions fail with
the existing loader header-error tuple, locating header word 1 and reporting
its observed value. A V1 image with count 2049..4096, a high descriptor PC bit,
or branch immediate bit 11 set still fails V1 validation even on the expanded
hardware. A V2 image is legal with fewer than 2049 instructions too; image size
must never be used to infer the encoding. Older P3/P4/pre-expansion P5 loaders
reject V2 at the header before publishing valid or fetching its instructions.

Version-related loader failures keep code 9, stage 1, response/index zero:
unknown version sets MC_STATUS header-error and uses address
`MC_IMAGE_ADDRESS+4`, detail header word 1; invalid count sets range-error
and uses `MC_IMAGE_ADDRESS+12`, detail header word 3. Invalid PC/reserved bits
in entry word 0 or 1 set range-error and locate that entry word with its
observed 32-bit value. A branch's nonzero reserved immediate bits set
control-flow-error and use its full instruction source address plus the
existing `trap_detail(1)` encoding. These are the same category precedence
and locator rules as before; the selected version supplies only new bounds
and masks. V2 does not create a new error code or IRQ.

The 64-byte header, three 32-byte entry descriptors, 64-bit instruction format,
opcode/predicate IDs, primitive masks, scratch/table fields, CRC algorithm and
coverage, build ID, and MP3 stub contents are retained. Only the versioned
instruction-count, PC fields and branch immediates below expand. The 128-byte
public job/ring descriptor does not change. No image can switch ISA versions
while executing, and lock/reset/admission/publication semantics are unchanged.

All multibyte bundle fields and instructions are little-endian. The bundle
starts with this exact 64-byte header:

| Word | Field |
| ---: | --- |
| 0 | magic `0x41504d43` (`APMC`) |
| 1 | combined APUMC/ISA ABI: major `[31:16]`, minor `[15:0]`; V1.0 `0x00010000` or V2.0 `0x00020000` under the target matrix above |
| 2 | total bundle bytes |
| 3 | instruction count, 1..2048 for V1 or 1..4096 for V2 |
| 4 | 64-byte-aligned instruction offset |
| 5 | table-payload offset, 4-byte aligned |
| 6 | table-payload bytes |
| 7 | entry-descriptor offset, 32-byte aligned |
| 8 | entry count; V1 and V2 require exactly 3 |
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

The descriptor array contains three 32-byte, eight-word entries. Header word 1
selects exactly one of the following PC allocations; there is no mixed-layout
array. Unlisted fields below retain the same meaning in both versions.

| Word | Bit allocation and units |
| ---: | --- |
| 0 | format ID `[3:0]`; V1 entry PC `[14:4]`, reserved `[31:15]`; V2 entry PC `[15:4]`, reserved `[31:16]`; all reserved bits zero |
| 1 | V1 first PC `[10:0]`, last PC `[26:16]`, reserved `[15:11]` and `[31:27]`; V2 first PC `[11:0]`, last PC `[27:16]`, reserved `[15:12]` and `[31:28]`; all reserved bits zero |
| 2 | scratch base byte offset `[16:0]`; `[31:17]` reserved zero |
| 3 | scratch size in bytes `[16:0]`; `[31:17]` reserved zero |
| 4 | maximum loop count `[15:0]`; `[31:16]` reserved zero |
| 5 | maximum retired instructions per frame/block `[23:0]`; `[31:24]` reserved zero |
| 6 | required primitive mask `[31:0]` |
| 7 | table-relative byte offset `[15:0]`; table bytes `[31:16]` |

Word 0 reserved masks are `0xffff8000` (V1) and `0xffff0000` (V2).
Word 1 reserved masks are `0xf800f800` (V1) and `0xf000f000` (V2).
Words 2..7 retain masks `0xfffe0000`, `0xfffe0000`, `0xffff0000`,
`0xff000000`, `0xffe00000` (reserved primitive bits), and zero respectively;
implemented-mask checks are additional to the word-6 reserved mask. V2 word 0
is `format_id | (entry_pc<<4)` and word 1 is
`first_pc | (last_pc<<16)`, without truncating any of the 12 PC bits. Entry
format IDs/order remain 0/1/2. For PCs below 2048 these words have exactly
the same values in V1 and V2; the header version still governs all checks.

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
and unsigned `LT`), four return-stack entries, and four loop slots. Saved
return PCs and loop-start PCs are 11 bits in P3/P4 and 12 bits in expanded P5;
V1 execution still checks the 11-bit range. All
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
| `0.3 JUMP_FWD` | V1 uses `immediate[10:0]` in 1..2047; V2 uses `immediate[11:0]` in 1..4095; higher immediate bits and other operands are zero. Target is `PC+1+delta` and must be inside the entry program range. |
| `0.4 CALL_FWD` | same target rule as `JUMP_FWD`; pushes `PC+1`, then branches; a fifth nested call traps. |
| `0.5 RET` | all operands zero and predicate must be always; pops and branches; empty stack traps. |
| `0.6 LOOP_SETUP` | predicate always; `aux[1:0]` selects an inactive loop slot, `aux[7:2]=0`, count is `R[src0][15:0]`, and other fields are zero. Count must be nonzero and no greater than the descriptor maximum; the slot records count and `PC+1` as its loop-start PC. |
| `0.7 LOOP_BACK` | predicate always; `aux[1:0]` selects the active slot. V1 uses nonzero distance `immediate[10:0]` in 1..2047; V2 uses `immediate[11:0]` in 1..4095; higher immediate bits and other operands are zero. `PC+1-distance` must equal the slot's recorded loop-start. Count greater than one is decremented and branches there; count one clears the slot and falls through. Inactive slot, underflow, or target mismatch/range failure traps. |
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
word 2047 for V1, or word 4095 for V2, traps. Branch/call/loop/return targets
are checked before assignment to the PC: V2 arithmetic uses at least 13 bits
to detect underflow, overflow and a target of 4096 rather than wrapping it to
zero. The width change does not permit arbitrary backward branches, increase
call depth, add loop slots, alter loop counts, or change watchdog budgets.
`END`/`TRAP` may legally occupy the final loaded word, including V2 PC 4095.

An asynchronous P2 transport error is sampled at the next retirement boundary,
then fetch and new commands stop while accepted transfers drain. Trap reason
allocations are 1 illegal encoding, 2 PC/program range, 3 call stack, 4 loop,
5 local/table range, 6 unavailable/undeclared primitive, 7 no-retirement
watchdog, 8 per-frame retirement budget, 9 engine/transport fault, and 10
explicit `TRAP`; 0 and 11..255 are reserved. A trap sets sticky
`STATUS.SEQUENCER_TRAPPED` and IRQ bit 10. IRQ bit 10 clears only by its W1C or
reset. A trap leaves a previously loaded `MC_STATUS.VALID` and `MC_LOCK` set
because the bundle itself remains loaded.

For the table below, `PC` is the trapping control-store word index (11 bits
for V1, 12 for V2). The 32-bit `trap_detail(reason)` keeps its V1 allocation:
reason `[7:0]`, **PC low 11 bits** `[18:8]`, class `[22:19]`, opcode
`[26:23]`, and `aux[4:0]` `[31:27]`. Every primary non-AXI trap sets
`ERROR_STATUS.VALID=1`, AXI response `0`, descriptor index `0`, and
`ERROR_ADDRESS=zero_extend(PC)<<3`. APUMC entry indices are not job/ring
descriptor indices and therefore never enter `ERROR_STATUS.DESCRIPTOR_INDEX`.

`ERROR_ADDRESS` always uses the full PC, including V2 bit 11: PC 2048 reports
`0x00004000` and PC 4095 reports `0x00007ff8`, including explicit reason-10
TRAP. No bit of reason/class/opcode/aux is stolen to extend `ERROR_DETAIL`.
For loader instruction diagnostics, the address remains the absolute bundle
address `MC_IMAGE_ADDRESS + instruction_offset + 8*PC`, using the full PC;
`trap_detail` there also retains the low-11-bit PC field. Reason 9 still
preserves an existing causative AXI/engine tuple; its address must not be
reinterpreted as a PC. Software uses retained SEQUENCER_STATUS for that case.

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

Under APB V1.0, `SEQUENCER_STATUS` bits `[31:21]` remain reserved zero. APB
V1.1 appends `PC_HIGH` at bit 21 (reset zero), with `[31:22]` reserved zero;
PC-low, class, opcode, wait, and loop-active keep their original bit positions.
The V1.1 reserved mask is `0xffc00000`, versus V1.0 `0xffe00000`. Decode the
full PC as `(status & 0x7ff) | (((status >> 21) & 1) << 11)`; legacy V1
execution has PC_HIGH zero. While running, PC, class,
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

PC_HIGH participates in the same atomic running/terminal snapshot as PC-low:
END/trap/abort retain it; accepted launch initializes it from the new entry
PC; soft/resource/hard reset clears it; IRQ/error W1C and counter clear do not
alter it. `SEQUENCER_RETIRED`, all first-error precedence, trap reasons, and
terminal retention rules are otherwise unchanged. Readers requiring a stable
PC while running read the single 32-bit status word rather than combining
separately sampled status and ERROR_ADDRESS from different events.

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
`MC_ABI` from the accepted header word 1 (`0x00010000` for P3/P4/V1 or
`0x00020000` for an expanded-P5 V2 image), build ID and actual CRC,
saturating-increments
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

The P3/P4 control store is exactly 2048x64 (16 KiB), with the mapping below;
expanded P5 uses the separately frozen 4096x64 mapping. Both have synchronous
one-PCLK-cycle sequencer fetches, no architecturally visible reset contents,
and are fetchable only when valid. With `HAVE_SRAM_MACRO=YES`, the P3/P4 store
is implemented as four
`tc_sram_1024x32` instances: two depth banks by low/high 32-bit halves; loader
writes the halves and sequencer fetches the combined word, with mutually
exclusive loader/fetch ownership. If a selected PDK advertises the macro but
cannot elaborate that mapping, elaboration must fail.

For P3/P4 with `HAVE_SRAM_MACRO=NO`, including the supported ICS55 profile,
`apu_control_store` selects a portable inferred synchronous
`logic [63:0] mem [0:2047]` implementation with identical admission, latency,
byte/word ordering, and loader/fetch exclusion. It must not instantiate an
unconnected macro wrapper. This path is functional and synthesis-compatibility
evidence only; it is not an SRAM-macro, PPA, or tapeout claim.

Expanded P5 uses eight `tc_sram_1024x32` instances: four depth banks selected
by word-address `[11:10]`, each with low/high 32-bit halves, and row `[9:0]`.
Both halves form one 64-bit control word; loader writes, loader verification
reads, and sequencer fetch retain the same exclusive ownership and one-cycle
synchronous read behavior. The selected bank is registered with each read so
the 2047/2048 boundary cannot return the preceding bank's data. The no-macro
path is `logic [63:0] mem [0:4095]` with identical word ordering and latency.
Memory contents need not reset. Header version, loaded instruction count,
valid/lock state, and entry bounds gate every fetch: an accepted V1 image
cannot access the upper half or stale words from an earlier image.

Every loader/scanner/sequencer/fetch/return/loop PC path and saved verifier
state must carry 12 bits on expanded P5. An instruction count or end sentinel
must represent 4096 without truncation (at least 13 bits); the payload length
must represent 32768 instruction bytes. Loader proof storage scales from 2048
to 4096 pending path records for V2, retaining the V1 limit for V1 validation;
the offline verifier's maximum-instruction-count-times-64 bound becomes 262144 for
V2 versus 131072 for V1. Exceeding a proof bound remains a control-flow loader
failure, never a reason to skip paths. Internal proof-record layouts are not
APUMC fields, but all saved PCs must round-trip bit 11. Proof workspace is
implementation overhead and must be reported separately from the advertised
control/data capacities.

No local-data partition, primitive latency, PCLK frequency, reset ownership,
CDC/RDC crossing, DMA interface, or atomic table/control-store publication
rule changes. `MC_LOAD_COUNT` and loader IRQ count one complete publication,
not a bank or halfword. A late CRC/range/proof failure or an abort after an
upper-bank write still publishes neither code nor tables. Existing soft/
resource-reset lock retention and hard-reset invalidation apply to all banks.

`apu-mcasm` is the single assembler/verifier and produces the binary, symbols,
control-flow/loop report, primitive manifest, deterministic trace input, and
canonical ABI-input manifest. A separate Python interpreter executes the exact
enabled ISA for BAM and microcode/RTL differential tests. In P3 both tools
execute class 0/1 and reject class 2..6 under the P3 target capabilities; later
phases extend execution without changing these encodings. No partial tool-table
fingerprint is exposed as the public `ABI_DIGEST`, which remains zero through
P7. Neither tool accepts C, ELF, RV32, dynamic linking, or runtime code
generation.

For the capacity migration, `--target p3` and `--target p4` continue to emit
APUMC V1 and enforce 2048 words. `--target p5` emits APUMC V2 by default and
enforces 4096 words. The assembler adds an explicit `--mc-abi 1.0` or
`--mc-abi 2.0` selector; p3/p4 with 2.0 is rejected. `--target p5 --mc-abi 1.0`
is the retained legacy P5 build path, including its 2048-word rejection. Parser
and interpreter select the exact PC/operand limits from header word 1, then
check the requested target's allowed primitives. Python helpers must take the
version explicitly or derive it from this target default; no global widening
may silently relax V1 checks.

All generated reports record APB compatibility, APUMC version, actual/maximum
instruction words, byte size, free words, entry ranges, branch-delta maxima,
source/coefficient hashes, bundle SHA-256 and CRC, and proof high-water. The
canonical ABI manifest includes both descriptor/operand variants and the
additive PC_HIGH field. RTL/C definitions remain independently handwritten and
parity-tested; no generator is introduced. A source binary is rebuilt with the
selected version, not patched in place; header/size/CRC/build-ID provenance
must correspond to the exact resulting bytes. Existing legacy fixture bytes
remain fixed.

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
P5 bundles, or a future explicitly reactivated P6 bundle, without changing
the P4 arithmetic contract.

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
the active P5 bundle provides its codec-quality values while P4 BAM
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
| `CAPABILITY1` | Expanded P5: `0x01827020`, 32 KiB control, 112 KiB data, two channels, 96 kHz maximum source rate. |
| Implemented primitive mask | `0x001fffff`, bits 0..20; reserved bits 21..31 remain zero. |
| ISA target | Add `p5` to the assembler/parser/interpreter and hardware capability validation. Classes 0..6 and all six existing `WAIT` sources are admitted subject to entry masks. Existing `p3` and `p4` targets retain their masks and behavior. |
| Public job | Operation 0 with format 0 WAV or 2 FLAC; one active job, direct or ring. MP3, KWS operation 1, and model load remain unavailable. |
| Stream route | TX 0/1 legal; RX only 0 legal. Bit 5 means at least one implemented stream direction, not permission for RX/KWS. RX 1 and reserved direction values return `PSLVERR`. |
| ABI identity | Expanded P5 APB V1.1, `IP_VERSION=0x00010001`; new release bundles use APUMC V2.0 / `MC_ABI=0x00020000` and legacy V1 images remain loadable. Existing APB offsets, job descriptor, 64-bit instruction positions/opcodes, and topology stay fixed. `ABI_DIGEST=0` through P7. |

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

The released P5 APUMC uses V2.0 and still contains exactly three entries.
Instruction word 0 is always `0x0200000001000001` (unconditional class-0 TRAP, detail
`0x01000001`). The MP3 entry at descriptor index 1 has the exact eight words
`[0x00000001, 0, 0, 0, 1, 1, 0, 0]`: entry/first/last PC zero, zero scratch,
table and primitive mask, maximum loop/retired one. A verification-only
launch of it produces code 11/stage 11/response 0/index 0/address 0/detail
`0x01000001`, retired zero. Public MP3 requests are rejected with unsupported
format before reaching that trap. WAV and FLAC entries start after PC 0;
their masks contain the primitives they declare and may share read-only
tables and scratch as already allowed. The header mask is the OR of entries,
not forcibly `0x001fffff`; the implemented mask advertises hardware capacity.

<details>
<summary>Deferred APU-P6 design archive — not current-release requirements</summary>

#### P6 MP3 profile, compatibility, and capacity

Status: DEFERRED. Everything in this archive through the following closing
details marker, including its capability/target, active-MP3 entry, packing and
MP3 decode rules, is retained for future design reference only. It is not
normative for the current release and cannot authorize implementation or
advertising MP3. Reactivation requires an explicit refreeze. The current
release uses the P5 WAV/FLAC image and MP3 stub, with MP3 capability bit 1 zero.

This refreeze is grounded in code baseline
`836371663feff6554ee923bb63a6a42978f4d777`. Its P5 microassembly contains
4073 instructions, leaving 23 of the 4096 words unused. This establishes
that appending a decoder to the current layout is not a credible capacity
plan; it does not establish a size for a reorganized complete P6 bundle.

| P6 property | Archived proposal (inactive for this release) |
| --- | --- |
| Discovery | `CAPABILITY0=0x000001bf`, `CAPABILITY1=0x01827020`, `IP_VERSION=0x00010001`, `ABI_DIGEST=0`. MP3 bit 1 becomes implemented; KWS bit 6 remains zero. |
| Image and ISA | Add target `p6`, default APUMC V2 / `MC_ABI=0x00020000`, mask `0x001fffff`, existing classes 0..6 and 12-bit PC/branches. Preserve p3/p4/p5 targets and V1 rejection/compatibility rules. p6 may explicitly read/emit V1 within its 2048-word limit; the production P6 release is V2. |
| Job and route | Operation 0, formats 0 WAV, 1 MP3, 2 FLAC, direct/ring, memory or TX stream. RX route 1, KWS, model loading and other formats remain unavailable. No new register offset, IRQ, resource index, system master, pad, clock or CDC/RDC allocation. |
| Resident image | One boot-loaded, validated and hard-reset-locked three-entry bundle contains all three real decoder entries. It replaces the P5 release image as a whole; MP3 entry 1 is no longer the P5 trap stub. No per-job reload, overlay, host parsing/decoding, C/DSP core, or unlocked code bank is introduced. |
| Hard limits | 4096 total 64-bit words including every entry/common routine/padding; 32 KiB control store and 112 KiB data store. P4/P5 local partitions and published PCM/transport/HAL semantics are retained. No implicit 8192-word expansion or new ISA operand mode is authorized. |
| Allowed compaction | The P6 emitter may regenerate, relocate, share routines and tables, change register allocation, tile kernels, and remove provably unreachable/duplicate instructions. It may not delete supported P5 paths, weaken diagnostics, change P4 arithmetic, or move parser decisions into RTL. No fixed fraction of the store is reserved for MP3; the only code budget is the complete 4096-word image. |

Before changing production RTL or advertising P6 capability, implementation
must produce a complete three-format microassembly packing report and a local
table/scratch live-range report, covering MP3 and every P5 path. The current
4073-word layout is not immutable inside the new image; the committed P5 image
and its builder/fixtures remain reproducible compatibility artifacts. Passing
P6 means the new image also passes the P5 corpus with identical PCM, parsed
input/output/frame accounting, acceptance/rejection, and semantic error tuple.
Build IDs, code PCs, retired counts and cycle measurements naturally describe
the new image; their definitions and PC-to-symbol diagnostics stay unchanged.
Packing is the first bounded implementation milestone, not an artifact this
documentation-only refreeze claims to have produced. Preflight must distinguish
a decision-complete contract from an unproven packing result and make the
packing gate visible before authorizing downstream production changes.

The packing gate must include all MP3 parsing, reservoir/Huffman/scalefactor,
requantization/reorder/antialias/stereo, long/start/short/stop IMDCT, overlap,
polyphase synthesis, output/resampling and error paths. P5 coefficient banks
and its FLAC workspace cannot simply be displaced by MP3 tables. MP3 may
reuse scratch between nonoverlapping lifetimes, generate coefficients there
with the existing arithmetic, and use explicit table/bit-reader routines;
it cannot reinterpret the P4 canonical-Huffman, REQUANT, or DCT32_POLY opcode
semantics as a different hardwired MP3 operation. The report must show the
actual lowering to existing primitives and its numerical/latency evidence.
The existing 24 KiB combined codec table/scratch ceiling applies to the
complete bundle, not independently to each static table image.

If those complete packing reports exceed code or data limits, return
`SPEC_CONFLICT` before downstream implementation; do not claim that this
refreeze proves the three decoders fit. Increasing capacity or changing the
ISA requires a separate explicit architectural refreeze. This is an evidence
gate with an exact budget, not permission to omit unimplemented branches.

P6 hardware continues to accept supported legacy images. It must recognize
the exact P5 entry-1 trap descriptor/body already specified and reject a public
MP3 job against that stub before executing it: direct start returns PSLVERR
with no job mutation; an owned ring entry completes code 3/stage 2/detail
`0x01000001` at its CONTROL address. WAV/FLAC jobs remain legal. Release
software uses the manifest of the loaded image when selecting formats;
CAPABILITY0 describes hardware and alone does not certify arbitrary loaded
microcode. The P5 verification-only stub launch keeps its original trap tuple.

##### P6 file, header, and metadata rules

P6 accepts finite elementary Layer III streams, at most `0x7fffffff` input
bytes, with the following exact subset. Bitstream constants are cross-checked
against the pinned independent decoder sources in the P6 reference section;
ID3 framing follows [ID3v2.3](https://id3.org/id3v2.3.0) and
[ID3v2.4](https://id3.org/id3v2.4.0-structure). Reference decoder tolerance does
not override the rejection rules here.

| Field or structure | Accepted values and required handling |
| --- | --- |
| Leading ID3 | Zero to four consecutive ID3v2.2/2.3/2.4 tags at byte zero, revision 0. Each has a complete 10-byte header and four synchsafe size bytes with high bits zero. Total skipped tag bodies, headers and footers must be at most 1 MiB. There is no arbitrary junk search before the first audio frame. |
| ID3 flags | v2.2 allowed mask `0xc0`; v2.3 `0xe0`; v2.4 `0xf0`. Other flag bits fail. Tag body is an opaque skip of the declared on-disk bytes, including unsynchronisation, compression and any extended header; no ID3 text/CRC/decryption semantics are claimed. v2.4 footer bit `0x10` adds 10 bytes beyond header+body and requires `3DI` plus identical version/flags/size fields. Other versions have no footer. Checked range arithmetic precedes the skip. |
| MPEG version | Header version bits 3 MPEG-1, 2 MPEG-2, 0 MPEG-2.5; value 1 is reserved and fails. Layer bits must be 1 (Layer III); Layers I/II are unsupported. |
| Bitrate | Indices 1..14 use the exact tables below. Index 0 (free format) is always unsupported, even if a reference can infer its frame length; index 15 is malformed. No scan-ahead free-format heuristic. |
| Sample rate | Index 0/1/2 uses the exact table below; index 3 is malformed. Version and rate are constant for the entire job. |
| Channels/mode | Modes 0 stereo, 1 joint stereo, 2 dual channel produce two channels; mode 3 produces one. Stereo/dual/joint may switch without changing channel count. A mono/stereo transition is rejected. Both joint-stereo extension bits (intensity and MS) are supported; extension bits are ignored outside joint mode. |
| Other header bits | Padding 0/1 and bitrate may change per frame (CBR/VBR/ABR accepted). Protection may change; zero means the two-byte CRC is present. Private/copyright/original bits are accepted without affecting output. Emphasis 0 is supported, 1/3 are unsupported, and reserved 2 is malformed. |
| Frame byte count | MPEG-1: `floor(144000*bitrate_kbps/rate_hz)+padding`; MPEG-2/2.5: `floor(72000*bitrate_kbps/rate_hz)+padding`. The count includes header/CRC/side-info and must fit the input and be at least their sum. Maximum supported frame length is 1441 bytes. |
| Side-info size | MPEG-1: 17 bytes mono, 32 stereo; MPEG-2/2.5: 9 mono, 17 stereo. Two granules/frame for MPEG-1, one for MPEG-2/2.5; every granule/channel represents 576 samples. |
| Geometry changes | Reject version/rate/channel-count changes at the first differing header field. Expected nonzero INPUT_CONFIG rate/channels must match. MP3 has no encoded PCM bit depth: P6 reports decoded source precision 24; expected bits is zero or 24, otherwise unsupported. |
| End tags | One final 128-byte ID3v1 block beginning `TAG` is accepted and consumed in either strict mode. No APE or midstream ID3 parsing. Other trailing bytes are rejected in strict mode and ignored only after at least one complete audio frame in relaxed mode. A partial sync/header or a valid next header whose frame is truncated is always an error, not relaxed trailing junk. |
| VBR metadata | Xing/Info/VBRI/LAME ancillary bytes do not supply authoritative duration, seek points, gain, encoder delay, padding, or frame count. Their containing MPEG frames are decoded/count normally. No gapless trim or ReplayGain is applied; actual validated frame headers determine accounting. |

| MPEG family | Bitrate indices 1..14, kbit/s | Rate indices 0,1,2, Hz | Samples/channel/frame |
| --- | --- | --- | ---: |
| MPEG-1 | 32,40,48,56,64,80,96,112,128,160,192,224,256,320 | 44100,48000,32000 | 1152 |
| MPEG-2 | 8,16,24,32,40,48,56,64,80,96,112,128,144,160 | 22050,24000,16000 | 576 |
| MPEG-2.5 | 8,16,24,32,40,48,56,64,80,96,112,128,144,160 | 11025,12000,8000 | 576 |

At least one complete audio frame is required; a tag-only or empty MP3 input
returns malformed/no-audio. Frame boundaries follow the computed byte count.
There is no silent resynchronization, concealment, skipped bad frame, or
property-dependent restart inside a job.
At an expected initial audio header, a nonempty remainder shorter than four
bytes is truncated input. After a valid frame, a short suffix beginning with
`0xff` and matching the available MPEG sync/version/layer bits is a truncated
header; other short suffixes follow the strict/relaxed trailing-byte rule.
A recognized `ID3` or `TAG` prefix with insufficient bytes for its required
header/block is truncated in both modes. These checks precede a relaxed skip.

##### P6 side-info, reservoir, and integrity rules

Let `P` be the cumulative number of main-data slot bytes in all preceding
frames, excluding their header, optional CRC and side-info. Let `M` be the
current frame's main-data slot count and `B=main_data_begin`. MPEG-1 B is a
9-bit value 0..511; MPEG-2/2.5 B is 8 bits 0..255. The current coded data
starts at byte `P-B` of that main-data-only stream. At job start history and
overlap are zero/empty, so the first frame requires B=0. Retain the last 511
main-data slot bytes plus current frame slots, at most 1952 bytes. Headers,
ID3 and CRC bytes never become reservoir bytes. Reset/abort or the next job
clears this history; it is never shared between ring jobs.

Require B no larger than actual retained history. The start bit must not
precede the previous frame's consumed main-data end bit, and the sum of all
`part2_3_length` values must end no later than `8*(P+M)`. Ancillary gaps and
byte-alignment stuffing between coded frame payloads are allowed. A reference
decoder that substitutes silence on reservoir underflow does not define P6
behavior: P6 terminates without PCM from the affected frame.

Side-info is parsed in transmitted granule/channel order. Each big_values is
0..288; each part2_3 length is a 12-bit bit budget, not a byte count. Reject
reserved codebook selections 4/14 and region boundaries outside 576 lines.
Table 0 produces zero pairs without consuming Huffman bits. Window switching
requires block_type 1/2/3; mixed_block is legal only with short block type 2.
Support long/start/short/stop and mixed blocks, MPEG-1 scfsi/preflag,
MPEG-2/2.5 scalefactor-compress and intensity rules, scalefac_scale,
subblock_gain, both count1 tables, all nonreserved pair codebooks and linbits.
Scalefactor bits are charged against part2_3 before Huffman data. Pair/quad
decoding cannot publish past line 575 or consume another part's bit budget;
remaining uncoded lines are zero and legal count1 termination/stuffing is
handled without reading beyond that budget. Truncated physical input and a
budget violation are distinct errors.

When protection is zero, read the stored big-endian CRC16 immediately after
the four-byte header. Compute MSB-first CRC with initial `0xffff`, polynomial
`0x8005`, no final XOR, over the header's final 16 bits (bitrate index through
emphasis), followed by all side-info bits in transmitted order. Exclude the
stored CRC and main-data bytes. CRC checking is mandatory in strict and
relaxed modes. It is MPEG error protection, not a whole-audio checksum.
The existing CRC16 primitive can use this nonzero initial accumulator;
its opcode behavior does not change.

No PCM from a frame is issued until its complete physical byte range,
side-info, CRC (when present), reservoir range and compressed-sample decode
have passed. Earlier valid output remains on later failure. Synthesis history
may be updated speculatively only if it cannot affect another job after an
error. Source bit extraction may use bounded scalar/table routines on the
saved reservoir; the original input FIFO is not rewound or fed duplicate
header bytes. The P5 explicit refill/cursor/EOF contract remains unchanged.

##### P6 PCM, counts, and first-offender diagnostics

MP3 decoding includes requantization, short-block reorder, alias reduction,
joint-stereo reconstruction, windowed IMDCT/overlap-add, frequency inversion
and synthesis polyphase filtering, in MPEG order. Intermediate representations
and coefficient realization must lower to the existing fixed-point primitives
and are qualified by the bit-accurate lowering report and the numerical gates
below. No synthesis stage or frequency band may be dropped to meet capacity.
Decoded samples enter the P5 post-processing path as signed Q1.31. Native
S24_32 output is the arithmetic right shift by 8 with saturation; S16 is the
right shift by 16. P5 downmix, duplication, resampling, capacity, TLAST, and
whole-output-frame rules are inherited exactly.
The reported precision 24 describes the canonical decoded PCM representation;
already normalized MP3 Q1.31 samples must not be shifted left again as if they
were raw 24-bit input samples.

Count every decoded MPEG frame including Xing/Info/VBRI-containing frames.
Native source sample-frame count is 1152 per MPEG-1 frame or 576 per lower
rate frame. No leading synthesis delay, encoder padding, or final samples
are trimmed, and no extra overlap tail is flushed beyond that count.
`JOB_FRAMES`/descriptor RESULT_FRAMES count destination PCM sample frames
after P5 rate conversion, not MPEG frames or channel samples. SOURCE_INFO
contains rate, 1/2 channels, and precision 24. INPUT_USED is the parsed physical
file prefix including accepted ID3 tags and frame bytes, never reservoir
rereads or prefetched bytes. Relaxed ignored trailing junk is excluded. Output
bytes/partial output and all direct/ring completion ordering remain P5 rules.

For MP3 parser failures, DETAIL `[31:24]=1`, `[23:16]` is warnings, and
`[15:0]` is the reason below. Warning bit 1 means relaxed trailing bytes were
ignored; other MP3 warning bits are zero. On success reason is zero. Each row
sets ERROR_STATUS valid=1, response=0, direct index=0 or owning ring index,
with the specified code/stage. Addresses below are absolute input addresses:
`F` is the current four-byte MPEG header address, `S=F+4+crc_bytes`, and a
field address is the byte containing the first transmitted bit of that field.
For reservoir-derived entropy bits, retain their original physical-byte
provenance across frames; do not report a scratch pointer as an input address.

| Reason | Failure | Code / stage | First-offender address |
| --- | --- | --- | --- |
| `0x0100` | Unsupported ID3 major/revision | 3 / 4 | Tag start + 3 |
| `0x0101` | Reserved ID3 flags | 4 / 4 | Tag start + 5 |
| `0x0102` | Nonsynchsafe ID3 size | 4 / 4 | First size byte with bit 7 set |
| `0x0103` | ID3 count/1 MiB limit or extent arithmetic overflow | 3 / 4 for limit, 4 / 4 for overflow | Offending tag start |
| `0x0104` | ID3v2.4 footer mismatch | 4 / 4 | First differing footer byte |
| `0x0110` | Missing sync/no audio/invalid reserved version | 4 / 4 | F (no audio: parsed tag end) |
| `0x0111` | Unsupported layer | 3 / 4 | F + 1 |
| `0x0112` | Free-format bitrate index 0 | 3 / 4 | F + 2 |
| `0x0113` | Bitrate index 15 or rate index 3 | 4 / 4 | F + 2 |
| `0x0114` | Unsupported/reserved emphasis | 3 / 4 for 1/3, 4 / 4 for 2 | F + 3 |
| `0x0115` | Frame shorter than its mandatory structures | 4 / 4 | F + 2 |
| `0x0116` | Version/rate/channel-count change | 4 / 4 | First changed field in header byte order |
| `0x0117` | Expected source-geometry mismatch | 3 / 4 | First offending version/rate/mode field; expected precision mismatch uses F |
| `0x0120` | Mandatory ID3/header/side-info/frame bytes missing | 5 / 4 | INPUT_ADDRESS + INPUT_LENGTH |
| `0x0121` | Strict unrecognized trailing bytes | 4 / 4 | First trailing byte |
| `0x0130` | Side-info big_values/window/codebook/region invalid | 7 / 5 | First invalid transmitted field |
| `0x0131` | Reservoir history underflow | 7 / 5 | S (main_data_begin field) |
| `0x0132` | Reservoir overlap or summed part2_3 range violation | 7 / 5 | S for overlap; first part2_3_length field making the sum exceed available bits otherwise |
| `0x0133` | Scalefactor/entropy part budget invalid | 7 / 5 | Start of that part's first undecodable code, mapped to physical input |
| `0x0134` | Illegal Huffman prefix/line count | 7 / 5 | First offending code's original physical byte |
| `0x0140` | Stored MPEG CRC mismatch | 6 / 4 | F + 4 |

Within a frame, validate complete header and its range, then side-info field
legality, then MPEG CRC, then reservoir bounds, then scalefactors/entropy. A
missing mandatory byte outranks checks that require that missing structure;
an already invalid earlier header is reported without reading later bytes.
Within side-info use transmitted bit order and granule/channel order. Global
AXI/DMA/xrun/trap/abort precedence and immutable-first-error capture remain
unchanged. Primitive/kernel overflow, sequencer faults, and output-capacity
errors retain P4/P5 tuples and PC_HIGH handling; they are not relabeled as
one of these parser reasons. HAL status mapping treats format 1 explicitly:
MP3 uses CAPABILITY0 bit 1 and these codes, not the previous non-WAV-to-FLAC
fallback. Existing job/result structures and API signatures are retained.

</details>

### `APUM` KWS model ABI

This is the first byte-level definition of APUM 1.0; no P1..P5 implementation
accepts an APUM image. All multibyte fields are little-endian, offsets are byte
offsets, signed integers are two's complement, and padding/reserved bytes MUST
be zero. APUM is not a TFLite FlatBuffer and is independent of APUMC and APB
versions. P7 accepts only the graph/quantization below, not a general NPU graph.

#### APUM header and layout

The image base is 64-byte aligned. The header is exactly 64 bytes. The image
is exactly 32768 bytes: 12 operator records at `0x0040`, 13 tensor records at
`0x0340`, zero padding at `0x04e0..0x04ff`, parameters at `0x0500..0x768f`,
and zero tail padding at `0x7690..0x7fff`. There are no external pointers,
compressed parameters, optional sections, alias records, or variable shapes.

| Header byte | Type | Field / required P7 value |
| ---: | --- | --- |
| `0x00` | u32 | Magic `0x4d555041` (bytes `APUM`). |
| `0x04` | u32 | APUM ABI `0x00010000`. |
| `0x08` | u32 | Total image bytes `32768`. |
| `0x0c` | u32 | Operator-set ID `1`. |
| `0x10` | u32 | MFCC rows `[15:0]=49`, coefficients `[31:16]=10`. |
| `0x14` | u32 | Classes `[15:0]=12`, operator count `[31:16]=12`. |
| `0x18` | u32 | Parameter bytes `29072`, starting at fixed offset `0x0500`. |
| `0x1c` | u32 | Scratch reservation `32768` bytes, separate from image bytes. |
| `0x20` | u32 | Quantization profile ID `1`, defined below. |
| `0x24` | u32 | CRC-32/ISO-HDLC over bytes `[64,32768)`, including padding. |
| `0x28` | u64 | Model ID `0xce4f70006843eaae`; first eight SHA-256 digest bytes of the pinned TFLite, interpreted little-endian. |
| `0x30` | u32 | Default threshold `[7:0]=128`, debounce `[15:8]=3`, upper bits zero. |
| `0x34` | u32 | Tensor count `13`. |
| `0x38` | u32 | Scratch-layout ID `1`. |
| `0x3c` | u32 | Reserved zero. |

CRC uses reflected polynomial `0xedb88320`, initial state `0xffffffff`, bytes
in increasing address order, and final XOR `0xffffffff` (`123456789` gives
`0xcbf43926`). The header CRC word and `KWS_MODEL_EXPECTED_CRC` MUST both equal
the observed payload CRC. Header fields are validated separately; neither CRC
nor the truncated model ID authenticates an image. The complete upstream SHA
and generated-image SHA belong in the host release manifest.

An independent freeze-time in-memory packing of the pinned model under these
rules gives the following golden values. The implementation converter MUST
reproduce them; these are computed bytes, not a claimed RTL/converter test.

| Golden object | Required value |
| --- | --- |
| Payload CRC / production expected CRC | `0xb9034b22` |
| Complete 32768-byte APUM SHA-256 | `87861b5f866182969e34917b4bf57cab61cd2245c3ab9b933797209322e3ce63` |
| Parameters `[0x0500,0x7690)` SHA-256 | `0e4eb210d247a45747049ef9602bbd7e90868e9cb1c04fb2a02f128db44e241e` |
| Weighted operators' multiplier then shift arrays, graph order, no delimiters, SHA-256 | `222e05821695f3fdd47be682b2cc75e0e735aa106436bf941cdda3ef8cb03b59` |

The corresponding 64-byte header, consecutive hexadecimal bytes, is:

```text
4150554d00000100008000000100000031000a000c000c009071000000800000
01000000224b03b9aeea436800704fce800300000d0000000100000000000000
```

The runtime CRC check compares observed/header/register values as specified;
it is not a SHA validator or authorization for a differently trained release
model. The release flow additionally requires the complete golden APUM hash.

Each operator record is 64 bytes:

| Byte in record | Type | Meaning |
| ---: | --- | --- |
| `0x00` | u16 | Opcode: 1 Conv2D (also pointwise), 2 depthwise, 3 average pool, 4 fully connected, 5 Softmax. |
| `0x02` | u16 | Flags: bit 0 fused ReLU; all others zero. |
| `0x04`, `0x06` | u16 each | Input and output tensor IDs. |
| `0x08`, `0x0c` | u32 each | Image-relative weight and bias offsets. |
| `0x10`, `0x14` | u32 each | Image-relative Q31 multiplier and signed-shift array offsets. |
| `0x18`, `0x1c` | u32 each | Weight byte count; output channel count. |
| `0x20`, `0x22` | u16 each | Kernel height and width. |
| `0x24`, `0x26` | u16 each | Height and width stride. |
| `0x28..0x2b` | u8 each | Top, bottom, left, right zero-point padding. |
| `0x2c`, `0x30` | i32 each | Input and output zero points. |
| `0x34`, `0x38` | i32 each | Inclusive output clamp minimum and maximum. |
| `0x3c` | u32 | Reserved zero. |

Convolution weights are signed INT8 in `[out,h,w,in]` order; depthwise weights
are `[1,h,w,channel]`, depth multiplier one; FC weights are `[out,in]`. All
weight zero points are zero. Bias, multiplier and shift arrays contain one
signed-32 word per output channel. FC's single source scale is broadcast to
12 output channels. For each weighted operator in graph order, append weights,
biases, multipliers, then shifts, each 16-byte aligned. These arrays total
22016 + 2352 + 2352 + 2352 = 29072 bytes; no array is deduplicated. Pool and
Softmax have zero in all four parameter offsets and weight-byte count. FC and
Softmax use kernel/stride 1 by 1 and zero padding. Pool uses kernel/stride
25 by 5, VALID padding. Pool/FC/Softmax have no ReLU; clamp is -128..127.

Each tensor record is 32 bytes: u16 `N,H,W,C` at bytes 0,2,4,6; u32
scratch-relative offset at 8; u32 byte count at 12; u32 element type `1=INT8`
at 16; u32 IEEE-754 binary32 scale bits at 20; i32 zero point at 24; u32 zero
at 28. Scale bits are immutable metadata checked against the pinned tensor
table, not permission to execute floating-point arithmetic in hardware.
Byte count equals `N*H*W*C`, checked without overflow. All tensors are NHWC,
batch one. Pool/FC tensors use the four-dimensional shapes below; the upstream
reshape changes no bytes and creates no APUM operator or additional buffer.

#### P7 fixed graph and quantization profile 1

The immutable source is TFLite SHA-256
`aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae`.
The binary, not a freshly trained Keras graph or its prose README, is the
authority for every weight, bias and per-channel scale. It contains 13 TFLite
operators and 35 tensors; folding only reshape yields the 12 operators and
13 activation tensors below. Batch normalization and ReLU are already fused.

| APUM tensor | Producer / source TFLite output | Shape N,H,W,C | Scale bits / zero point | Scratch offset |
| ---: | --- | --- | --- | ---: |
| 0 | MFCC / 0 | 1,49,10,1 | `0x3f15af17` / 83 | `0x4000` |
| 1 | Conv 10x4, stride 2x2 / 22 | 1,25,5,64 | `0x3da13ac8` / -128 | `0x0000` |
| 2 | Depthwise 3x3 / 23 | 1,25,5,64 | `0x3da99aea` / -128 | `0x2000` |
| 3 | Pointwise 1x1 / 24 | 1,25,5,64 | `0x3d75dd81` / -128 | `0x0000` |
| 4 | Depthwise 3x3 / 25 | 1,25,5,64 | `0x3d808854` / -128 | `0x2000` |
| 5 | Pointwise 1x1 / 26 | 1,25,5,64 | `0x3d19329e` / -128 | `0x0000` |
| 6 | Depthwise 3x3 / 27 | 1,25,5,64 | `0x3d3c02c1` / -128 | `0x2000` |
| 7 | Pointwise 1x1 / 28 | 1,25,5,64 | `0x3d070c5a` / -128 | `0x0000` |
| 8 | Depthwise 3x3 / 29 | 1,25,5,64 | `0x3d3fdf8a` / -128 | `0x2000` |
| 9 | Pointwise 1x1 / 30 | 1,25,5,64 | `0x3da452db` / -128 | `0x0000` |
| 10 | Average pool 25x5 / 31 (32 aliases 31) | 1,1,1,64 | `0x3da452db` / -128 | `0x2000` |
| 11 | FC 64 to 12 / 33 | 1,1,1,12 | `0x3e142a46` / 14 | `0x0000` |
| 12 | Softmax beta 1 / 34 | 1,1,1,12 | `0x3b800000` / -128 | `0x2000` |

Operator `i` consumes tensor `i` and produces `i+1`. First-convolution padding
is top 4, bottom 5, left 1, right 1. Depthwise padding is one on every side;
pointwise has zero padding. All other convolution strides are one, dilation
is one, and all nine convolution operators fuse ReLU. The source weight/bias
tensor pairs in weighted-operator order are `(17,3)`, `(5,4)`, `(18,6)`,
`(8,7)`, `(19,9)`, `(11,10)`, `(20,12)`, `(14,13)`, `(21,15)`, `(16,1)`.
Per-channel scales use the source quantized dimension (Conv axis 0, depthwise
axis 3); FC is per-tensor. No recalibration, retraining, bias re-rounding,
channel permutation, pruning, or alternative model is part of P7.

For output channel c, accumulate `bias[c] + sum((input-zin)*weight[c])` in
signed INT32 with checked wider intermediates, in h,w,input-channel order.
Padding contributes `input=zin`. Overflow is an arithmetic fault, not wrap or
silent accumulator saturation. Convert the effective multiplier
`double(input_scale)*double(weight_scale[c])/double(output_scale)` with the
pinned TFLite `QuantizeMultiplier`: binary64 operations without contraction,
frexp, positive nearest/ties-away Q31 rounding, carry renormalization, and
the upstream shift-below-minus-31 flush. Record the resulting Q31 word and
shift, not a decimal approximation. Runtime requantization uses the pinned
`MultiplyByQuantizedMultiplier` double-rounding behavior: checked left shift,
`SaturatingRoundingDoublingHighMul`, then `RoundingDivideByPOT`. Add zout and
clamp to `[max(-128,zout),127]` for ReLU, otherwise `[-128,127]`. Do not
replace these rules with nearest-even rounding or single-rounding DSP modes.

Average pool sums the 125 signed input bytes in INT32 and divides by 125
with nearest rounding, ties away from zero, retaining the same scale/zero
point; it is not the 24x5 pool suggested by the training source's shape
calculation. Softmax is the pinned
`tflite::reference_ops::Softmax<int8_t,int8_t>` with
`input_multiplier=1242899200`, `input_left_shift=24`, `diff_min=-124`,
Q5.26 scaled differences and Q12 accumulation, using the pinned gemmlowp
fixed-point exp/reciprocal routines. The host oracle and RTL must agree on
all twelve output bytes, including underflow, saturation and tied maxima.
No float exp, alternative LUT approximation, omitted Softmax, or CMSIS-NN
rounding substitution is permitted in the inference reference path.

#### P7 memory and loader validation

The existing KWS partition remains banks 10..25, local `0x0a000..0x19fff`,
64 KiB total. Banks 10..17 hold the 32 KiB APUM; banks 18..25 are the 32 KiB
scratch reservation. Codec/control-store banks, Gateway A identity, IRQ and
resource allocations do not change. A new independently arbitrated KWS client
may access only these KWS banks; it cannot borrow codec buffers or MAC lanes.

Scratch layout 1 has A at `0x0000..0x1fff`, B at `0x2000..0x3fff`, MFCC at
`0x4000..0x41ff`, a 50x40 u32 raw-mel ring at `0x4200..0x61ff`, complex FFT
workspace at `0x6200..0x71ff`, 768 S16 ingress samples at `0x7200..0x77ff`,
and metadata at `0x7800..0x7fff` (peak ring, FIR state, counters, pending
stereo word and reduction state). A/B lifetimes alternate exactly as in the
tensor table. Scratch range checking cannot treat the entire 112 KiB local
store as available. The one-second history is retained as raw mel bands plus
peak metadata, not an additional unbudgeted 32000-byte PCM buffer. Immutable
frontend coefficients are fixed engine ROM constants generated from the
numerical recipe; report their separate ROM/logic footprint in P8.

MODEL_LOAD is LP-only, globally idle and quiesced, KWS disabled, ACL-valid and
model unlocked. Fetch/validate header first, then exact-size payload and CRC,
then records, ranges and quantization. Validate every fixed field, zero byte,
opcode, tensor ID, shape, scale/zero point, array length/alignment, graph edge,
padding/stride, scratch lifetime and parameter region before publishing valid.
Unsupported major/minor/quantization/operator-set/layout versions fail closed.
The loader MUST compare the records and requantization arrays with the frozen
profile; arbitrary parameters with internally consistent but different shapes
or arithmetic do not become a second supported model. All address additions
are checked; no DMA may escape the inclusive read ACL or image range.

An accepted load clears previous unlocked loader diagnostics and actual CRC,
sets busy and keeps valid clear. Success atomically publishes valid/locked and
the observed CRC, applies the header defaults to KWS_CONFIG and raises IRQ 4.
Any failure leaves valid/locked clear and execution disabled, records the
specified error and raises terminal IRQ 4 plus first-error IRQ 8. A retry is
allowed only after draining and clearing/recovering the error. A successful
lock cannot be cleared or reloaded by software, HP, abort, soft reset or
resource reset; only hard/PCLK reset invalidates it. An aborted partial load
never publishes valid or raises a successful-load indication.

### P7 frontend numerical profile 1

This profile closes the former 10 ms/49-row contradiction: a one-second,
16000-sample mono window uses 480-sample (30 ms) frames, 320-sample (20 ms)
hop, and a 512-point FFT. Frame r uses samples `320*r .. 320*r+479`, r=0..48;
the last 160 samples contribute to the normalization peak but not to a frame.
Inference windows end after samples 16000,17600,19200,... in continuous mode.
There is no pre-emphasis, DC removal, noise augmentation, AGC, dither, lifter,
center padding or trailing STFT padding. The frozen floating reference is the
pinned `get_dataset.py` MFCC branch, not its LFBE/microfrontend branch.

Let RNE denote exact nearest integer with ties to even and TZ truncation
toward zero. All constant generation uses increased precision with interval
bounds until rounding is unambiguous; independently generate and compare the
ROM words, and put their SHA-256 and profile ID in every release report.
Host math-library defaults are not the numerical specification.

1. Input is signed S16 after the capture conversion below. Use the positive
   peak `P=max(1,max(x[0..15999]))`, not max absolute value. The `max(1,...)`
   rule explicitly defines silence/all-nonpositive inputs where the upstream
   division would otherwise be invalid or unsuitable. On the official corpus
   the positive-peak rule is unchanged. Retain maxima for 100 successive
   160-sample blocks so each rolling window has its own exact P.
2. Hann coefficients are `H[n]=RNE(2^30*(1-cos(2*pi*n/480))/2)`, n=0..479.
   Build a 512-element complex input with real part
   `RNE(x[n]*H[n]/2^15)` and imaginary zero; n=480..511 is zero. This carries
   15 fractional bits of the unnormalized S16 value. Do not normalize each
   frame with a different peak.
3. Use radix-2 decimation-in-time FFT, bit-reversed input, stages of length
   2,4,...,512 and ascending butterfly indices. Twiddles are independently
   RNE-quantized Q2.30 cos and negative sin. For each complex multiply, form
   both signed-64 sums of products before one RNE divide by `2^30`; butterfly
   sum/difference is then RNE divided by two at every stage. Components are
   signed-32; overflow faults rather than wrapping. Thus final components
   represent the unscaled DFT times 64. Keep bins 0..256 and use nearest
   integer square root of the unsigned-64 sum of component squares (ties
   even); no magnitude-squared/power substitution or log10 is allowed.
4. Define `mel(f)=1127*ln(1+f/700)`. Forty triangular filters have 42 evenly
   spaced mel edges from mel(20) to mel(4000). Evaluate triangles at
   `f[k]=16000*k/512`; clamp each to [0,1], force DC-bin weights to zero,
   and quantize weights to Q2.30 using RNE. For each band store
   `M=RNE(sum(magnitude[k]*weight[k])/2^32)` as unsigned UQ28.4. This is
   raw, unnormalized magnitude, not power. Products/reduction use unsigned
   64-bit checked arithmetic. A 50-row ring holds these 40-word frames.
5. At a window endpoint, capture P and the 49 corresponding mel rows. For
   each band form the positive rational
   `z=(1000000*M+16*P)/(16000000*P)`; this is `M/(16*P)+1e-6`.
   Normalize z exactly as `2^e*m`, 1<=m<2. The fixed log ROM contains
   `L[i]=RNE(2^24*ln(1+i/1024))`, i=0..1024, and
   `LN2=RNE(2^24*ln(2))`. Set i=floor(1024*(m-1)) and
   `f=RNE(65536*(1024*(m-1)-i))`, allowing f=65536. Output signed Q8.24
   `e*LN2+L[i]+RNE((L[i+1]-L[i])*f/65536)`. Integer divisions and exponent
   selection must use the exact rational; no intermediate float is implied.
6. DCT coefficients are
   `D[j,b]=RNE(2^30*sqrt(2/40)*cos(pi*(b+1/2)*j/40))`, j=0..9,b=0..39.
   Compute `C[j]=RNE(sum(log[b]*D[j,b])/2^30)` in signed Q8.24 using signed-64
   checked reduction. Coefficient zero has the same scaling as the other
   coefficients, matching TensorFlow MFCC rather than an orthonormal DCT-II.
7. Quantize with `q=TZ(C[j]/(2^24*S)+83)` using the exact binary32 scale
   `S=0x3f15af17`. Store the low eight bits, interpreted signed INT8.
   This intentional modulo-256 conversion matches upstream NumPy INT8
   export; it is NOT saturation. The published corpus includes 15 features
   in `tst_000563_Go_1.bin` for which saturation gives different bytes.
   This compatibility exception applies only at the MFCC boundary; inference
   requantization and PCM conversion retain their own saturation rules.

For the independently evaluated floating recipe on all 1000 reconstructed
waveforms, 1381 of 490000 feature bytes differed from the published bytes when
using saturation: 15 were the export-wrap case and the others were within one
LSB. This 2026-09-11 host cross-check supports the corpus mapping and exposes
the quantizer distinction; it is NOT fixed-point RTL accuracy evidence.
P7 MUST implement a bit-accurate model (BAM) of the integer profile above and
compare every frontend stage and every inference tensor against RTL. Report
wrapped INT8 feature distance, per-stage error versus the floating reference,
and end-to-end top-1 separately. No feature-distance tolerance waives the
900/1000 hardware top-1 gate, and no implementation may change the formulas
or constants merely to improve that score without another refreeze.

### P7 capture, scheduling, status and diagnostic operation

P7 appends one register; existing offsets and reserved masks are unchanged:

| Offset | Name | Access / reset | Meaning |
| ---: | --- | --- | --- |
| `0x23c` | `KWS_INPUT_CONFIG` | RW disabled/idle; `0x0104bb80` | Rate `[16:0]`, physical channels `[18:17]`, precision `[25:20]`; all other bits zero. Reset is stereo S16 at 48000 Hz. |

This register is needed because AXI4-Stream audio has no rate/precision tag.
It does not cause APU to read or write I2S APB registers. Legal continuous
values are two physical channels, 16 or 24 bits, and 16000/48000/96000 Hz.
The caller must configure matching I2S master/dividers/stream RX while I2S is
disabled, then select RX route 1. The current I2S HAL's exact divider checks
remain authoritative; programmable 16 kHz capture is a P7 integration test.
Memory-window operation ignores KWS_INPUT_CONFIG and is always mono S16/16 kHz.
Unsupported rates, mono physical I2S, or reserved fields return PSLVERR before
state changes. P1..P5 continue returning PSLVERR at the new offset. Software
must test KWS capability before access; IP_VERSION remains `0x00010001`.
KWS_INPUT_CONFIG uses byte-strobe merge and validates the merged full value,
like KWS_CONFIG. KWS_CONTROL pulses/transitions require a full-word strobe.

S16 RX consumes the older low half then newer high half of each full 32-bit
beat. S24 RX pairs consecutive beats using signed bits 23:0; upper bits are
ignored. The mono pair is defined by wire order, not a nonexistent LRCK/channel
tag: after flush, its first member is the first complete accepted sample,
then the next sample. Do not infer left/right identity from a paused 24-bit
stream. Downmix is arithmetic floor((older+newer)/2) in a widened signed
accumulator. S24 is then arithmetic-shifted right eight
and saturated to S16. `TKEEP=TSTRB=0xf`, no RX TLAST; malformed sidebands or
unrecoverable half-pairs cause code 19/stage 9, clear history and stop KWS.

P7 exports the I2S wrapper's existing synchronized PCLK `s_rx_flush_busy`
as a same-domain `rx_flush_busy_o`, connected to APU
`i2s_rx_flush_busy_i`. This is an internal integration status wire, not an
AXI sideband, APB register, pad or new CDC. It reuses the existing Common
warm-flush detection, including unilateral audio reset. While asserted, APU
must not accept RX data and must invalidate any pending half-pair/history;
a live unplanned epoch loss counts one overrun and requires explicit restart.
For planned quiesce/reset, use the existing non-error/forced-loss distinction.
No new complete inference may contain samples from both sides of a flush.

At 16 kHz conversion is exact bypass. At 48/96 kHz use a dedicated 63-tap
causal FIR and decimation D=3/6. With input indices starting at zero, emit
at n=D-1,2D-1,... using `sum(t=0..62,H_D[t]*x[n-t])`, zero history for n<t.
Let c=1/D, x=t-31, w=(1-cos(2*pi*t/62))/2 and
`a=c*sinc(c*x)*w`, sinc(z)=sin(pi*z)/(pi*z), sinc(0)=1. Quantize normalized
coefficients to Q2.30 by RNE and add the unity-sum residual to tap 31.
Use signed-64 reduction, RNE divide by `2^30`, then S16 saturation. These
126 fixed ROM words are independent of P5 codec resampler profiles/state.
Record the 31-input-sample filter delay; do not trim it or silently resample
the official mono16k diagnostic corpus. Neither this FIR nor the FFT may use
codec microcode, codec scratch or codec MAC lanes.

KWS_CONTROL bits remain ENABLE 0, MEMORY_WINDOW 1 and CLEAR_HISTORY pulse 2.
An enable rising edge latches continuous input/config, requires valid locked model and
starts empty history. ENABLE=1/MEMORY_WINDOW=0 is continuous RX; value 3 arms
memory-window operation without listening. Mode may change only disabled.
Configuration/clear-history writes require KWS disabled and global idle,
except KWS_CONFIG may be changed while memory mode is armed and no finite job
is active. The full-word write that clears ENABLE while retaining mode and
writing no pulse is additionally legal while KWS is active: stop admitting
new work, finish the current feature/inference, drain accepted input/DMA,
then become disabled. It does not abort a concurrent codec job. Mode/config
changes during this drain are rejected. CLEAR_HISTORY resets feature/peak/FIR
history, debounce and result-valid, but not the model, counters or IRQ state.

Global STATUS.IDLE and the resource idle output still require every client
idle; continuous listening counts as busy until disabled or quiesced. P7
separates that global lifecycle condition from finite-job admission: job/ring
configuration and codec START/RING_KICK may proceed when the finite-job path
is idle even while continuous KWS runs. This narrow admission exception does
not permit ACL/model/microcode/route/reset changes during listening. Configure
and enable continuous KWS before starting concurrent decode. Quiesce drains
the current KWS work, suppresses new windows and preserves enable/mode/model;
release resumes with fresh history and a one-second warm-up. If a nonempty
history was discarded, count one abandoned window, without first-error IRQ.
Do not combine samples across the gap. Abort disables KWS; soft/resource reset
clears enable/mode, capture/config registers to reset values, history, results,
IRQs and counters while preserving valid locked model bytes and actual CRC.
Forced loss and unilateral resets follow the existing error/CDC precedence.

Continuous inference begins only with a complete history, then every 1600
accepted 16 kHz samples. The deadline is the next such endpoint. The 49-row
MFCC snapshot must be consumed before its oldest raw-mel row is overwritten;
no partially updated input tensor may reach inference. A missed deadline,
mel-ring overwrite or RX overrun abandons that window, increments overrun
once, clears history/debounce, records code19/stage9 and stops KWS. Recovery
is bounded disable/drain, RX flush, error/IRQ clear, history clear and enable;
the validated model is retained. No silent catch-up, sample duplication or
completion of a corrupted window is allowed. Frontend/inference watchdogs
use the existing nonzero SEQUENCER_TIMEOUT as a maximum consecutive
no-progress PCLK-cycle count independently per KWS work item. Progress means
an accepted PCM sample, completed butterfly/band/feature, completed MAC
reduction step or committed output tensor element, not merely an active
state machine. Expiry is code14 at stage9/10 and quiesces the APU. Slow
PCLK correctness tests may increase that timeout but may not claim 48 MHz
real-time performance. DMA stalls continue to use DMA_TIMEOUT.

| KWS_STATUS bit | Meaning |
| ---: | --- |
| 0 | Listening, live continuous capture (not quiesced/draining). |
| 1 | Inference busy, including preparation of its immutable MFCC snapshot. |
| 2 | History full, belonging to the current uninterrupted capture epoch. |
| 3 | Current published result is a stable hit (same as KWS_RESULT bit16). |
| 4 | Sticky overrun, cleared with the existing stream-xrun IRQ_STATE bit9 W1C or soft/resource/hard reset. A new overrun also raises IRQ9; hardware set wins clear. |
| 5, 6 | Model valid, model locked. |
| 7 | Result valid; at least one result has been published since history/reset clear. |
| 31:8 | Reserved zero. |

KWS_MODEL_STATUS bits 0,1,2 are busy, valid, locked. Bits 8,9,10,11,12 are
header, range, size, CRC and operator/quantization failure respectively;
all other bits read zero. They are sticky until the next accepted unlocked
load or reset, with exactly one semantic failure bit selected. Validation
order is size, header fields in byte order, payload DMA/CRC, then records in
byte order; range is checked before dereferencing each field. Failures use
code12/stage1, except CRC uses code13/stage1. ERROR_ADDRESS is the first bad
field's external byte address (size uses KWS_MODEL_SIZE's APB address; CRC
uses model base+0x24), and ERROR_DETAIL is `0x07000000 | reason`, reason
1=size, 2=header, 3=range, 4=CRC, 5=operator/quantization. AXI/timeout/abort
faults retain their existing codes and precedence. Internal KWS arithmetic
uses code14/stage9 or10, address equal to the failing local byte address,
detail `0x07000100 | operator_index` (frontend index 0xff).
If new KWS and existing codec semantic faults coincide, the pre-existing
global AXI/lifecycle/xrun precedence still wins; otherwise retain the codec
fault, then KWS frontend, then KWS inference in that order. Model loading is
globally exclusive. Collect every applicable sticky event/counter without
overwriting the first error. Actual model CRC remains zero until the entire
payload has been received, then reports the observed finalized CRC even if
subsequent CRC/record validation fails.

Choose the lowest class ID on tied final INT8 scores. Class order is Down,
Go, Left, No, Off, On, Right, Stop, Up, Yes, Silence, Unknown (0..11).
Unsigned confidence is `int32(softmax[class])+128` (0..255); threshold is an
inclusive comparison. Only classes 0..9 can be hits. A run increments only
for the same above-threshold keyword on consecutive completed windows; a
different class starts at one, and silence/unknown/below-threshold/gap resets
the run. Emit one stable-hit event when run count first reaches debounce
(1..255), saturating the run count at debounce, not emitting on later matching
windows. Hold hit for that uninterrupted
run; re-arm on the first nonmatching/below-threshold result or explicit clear.
KWS_RESULT holds every latest completed top-1 result, including non-hits;
IRQ2 and HIT_COUNT change only on the event edge. IRQ W1C does not re-arm or
clear the classifier history. Hardware set wins W1C.

The timestamp is the 64-bit PCLK timestamp of the accepted last sample of
the evaluated one-second window, not the time software services the IRQ.
Reading KWS_RESULT atomically latches its timestamp for subsequent LO/HI
reads; a later inference cannot tear that pair. A read does not acknowledge
IRQ or consume the result. Frame, inference, hit and overrun counters are
unsigned-32 saturating: completed raw-mel frames, completed inferences,
stable-hit edges and abandoned windows respectively. CLEAR_COUNTERS is
globally idle-only and clears these without clearing model/history/IRQ.

Diagnostic operation 1 uses the existing direct/ring slot, not a second
concurrent finite job. It requires valid locked microcode (compatibility
admission only; no codec entry executes), valid locked model and memory mode
armed; it is rejected while continuous KWS is enabled. CONTROL operation=1,
format=0, output-mode=0, downmix/resample=0; INPUT_ADDRESS is four-byte aligned,
INPUT_LENGTH=32000, INPUT_CONFIG explicitly mono/16000/16. OUTPUT_ADDRESS,
OUTPUT_CAPACITY, OUTPUT_CONFIG and JOB_FLAGS are zero. This is the sole
operation-1 exception to the decode rule requiring a nonzero memory output.
All other reserved fields remain zero; OWN/IOC/cookie/ring ordering are
unchanged. KWS_CONFIG is descriptor word9 for ring jobs and the KWS_CONFIG
register latched at START for direct jobs. Each independent memory window
clears debounce history and RESULT_VALID at acceptance, so debounce>1 returns hit=0 even when top-1 is a
keyword. Accuracy uses top-1, not hit; use debounce=1 for standalone hit tests.

Success returns INPUT_USED=32000, OUTPUT_BYTES=0, FRAMES=16000,
SOURCE_INFO=mono/16000/16, DETAIL=0 and the normal done/cycles/timestamps/cookie;
descriptor word22 and KWS_RESULT contain the result. No PCM output DMA is
issued. Direct reads use existing job result registers plus KWS_RESULT;
ring reads use word22 before slot reuse. A failed/aborted operation sets
word22=0, does not publish a fresh KWS result or inference/hit count, and
uses existing terminal writeback/OWN-clear rules. Input-used is the contiguous
number of successfully consumed bytes, a multiple of two, at failure.
RESULT_FRAMES on failure is INPUT_USED/2; OUTPUT_BYTES stays zero. A ring may
mix decode and operation1 entries while memory mode is armed, but cannot
silently switch a running continuous listener into memory mode.
Invalid raw direct requests return PSLVERR without payload DMA/result change;
invalid owned ring requests use code2/stage2 at the first invalid descriptor
word, DETAIL=`0x07000200 | word_index`, then normal error writeback.

### HAL and compatibility

`<retrosoc/hal/apu.h>` owns discovery, ACL, microcode/model load, direct/ring
submit, stream routing, KWS, interrupt, error, statistics, bounded wait, abort,
and reset. Fallible functions return `rs_status_t` and waits take a timeout.
`<retrosoc/hal/apu_regs.h>` independently mirrors every public constant.

The APB/job ABI is append-only within major version 1. Existing offsets,
job-descriptor size, opcode/format/error/IRQ IDs, ownership, and lock semantics
retain their meaning. APB V1.1 adds PC_HIGH and capacity discovery without
moving an existing field. APUMC has its own binary/ISA version: legacy V1 is
immutable, and the approved V2 widens its entry-PC and branch fields with
explicit version negotiation. `APUM` model ABI does not change. Software fails
closed on unknown major versions in the relevant namespace, not by equating
APB `IP_VERSION` to `MC_ABI`.

The updated P5 HAL accepts APB major 1, minor 0 or 1 for the supported legacy
and expanded profiles, comparing the extracted major against 1 rather than
against the full V1.1 word. It reads actual control-store KiB from CAPABILITY1.
Release software targeting APUMC V2 requires APB V1.1 with 32 KiB before
submitting that image. The existing microcode-load API and image structure
remain unchanged; the hardware validates header word 1, and successful HAL
load accepts/readbacks the corresponding MC_ABI 1.0 or 2.0. It must not require
MC_ABI to be 1.0 on a valid V2 load or infer it from image size. Unknown image
versions retain the existing header-failure/RS_EIO path. Existing legacy
software can submit V1 images to expanded hardware; software displaying full
PCs must use PC_HIGH or the full trap address. Functional PCM/job/error rules
and every public HAL function signature remain unchanged.

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

### P7 HAL additions

These declarations are frozen additions to `<retrosoc/hal/apu.h>` for
implementation in `crt/src/hal/apu.c`. Existing P5 structures/functions and
the 128-byte descriptor retain their layout and signatures. The new structs
are host-side objects, not DMA wire layouts; all flags/enumerated integers
must be range checked. No dynamic allocation or hosted-library dependency is
permitted. Independently extend `apu_regs.h` and `apu_define.svh`, and maintain
handwritten Python APUM constants and deterministic parity tests.

```c
typedef struct {
    uint32_t threshold;       /* 0..255, inclusive */
    uint32_t debounce;        /* 1..255 */
    uint32_t input_rate;      /* 16000, 48000 or 96000 */
    uint32_t input_bits;      /* 16 or 24; physical I2S channels fixed at two */
} rs_apu_kws_config_t;

typedef struct {
    uint32_t input_address;   /* exactly 32000 mono S16_LE bytes */
    uint32_t threshold;
    uint32_t debounce;
    uint32_t cookie[2];
} rs_apu_kws_job_t;

typedef struct {
    uint32_t class_id;
    uint32_t score;
    uint32_t hit;
    uint32_t timestamp[2];   /* low, high; evaluated-window endpoint */
} rs_apu_kws_result_t;

typedef struct {
    uint32_t status;
    uint32_t model_status;
    uint32_t model_crc;
    uint32_t frame_count;
    uint32_t inference_count;
    uint32_t hit_count;
    uint32_t overrun_count;
} rs_apu_kws_status_t;

typedef struct {
    rs_apu_result_t job;
    uint32_t class_id;
    uint32_t score;
    uint32_t hit;
} rs_apu_kws_completion_t;

rs_status_t rs_apu_kws_model_load(const rs_apu_image_t *image, rs_timeout_t timeout);
rs_status_t rs_apu_kws_configure(const rs_apu_kws_config_t *config);
rs_status_t rs_apu_kws_enable(uint32_t memory_window);
rs_status_t rs_apu_kws_disable(rs_timeout_t timeout);
rs_status_t rs_apu_kws_clear_history(void);
rs_status_t rs_apu_kws_status_read(rs_apu_kws_status_t *status);
rs_status_t rs_apu_kws_result_read(rs_apu_kws_result_t *result);
rs_status_t rs_apu_kws_validate_job(const rs_apu_kws_job_t *job);
rs_status_t rs_apu_kws_submit_direct(const rs_apu_kws_job_t *job);
rs_status_t rs_apu_kws_wait_direct(rs_apu_kws_completion_t *result, rs_timeout_t timeout);
rs_status_t rs_apu_kws_ring_submit(rs_apu_ring_t *ring, const rs_apu_kws_job_t *job,
                                    uint32_t ioc, uint32_t *slot);
rs_status_t rs_apu_kws_ring_result(const rs_apu_ring_t *ring, uint32_t slot,
                                    rs_apu_kws_completion_t *result, rs_timeout_t timeout);
```

- `model_load` is blocking and reuses rs_apu_image_t's DMA address, exact byte
  size and expected payload CRC. Validate size=32768, alignment, checked
  inclusive ACL range, LP ownership, quiesce/global idle, disabled KWS and
  unlocked model; perform the same CBO/fence discipline as microcode load.
  Program the three existing model registers, issue COMMAND bit5, and poll
  KWS_MODEL_STATUS. Success requires valid AND locked and matching actual CRC.
  No unlock, implicit hard reset, IRQ acknowledgement or retry is hidden.
- `configure` requires disabled/global idle, packs the two fields of
  KWS_CONFIG and the appended KWS_INPUT_CONFIG, and preserves all other
  settings. It does not configure I2S, change route or clear history/errors.
  `enable(memory_window)` accepts only 0/1, validates capability/model/owner
  and nonquiesced admission, and writes control 1 or 3. Continuous mode also
  requires RX route1; the caller is responsible for matching I2S settings.
  No codec microcode executes in either KWS mode.
- `disable` initiates the KWS-only bounded drain, preserving mode. Poll until
  ENABLE reads zero and both listening/inference-busy clear; hardware keeps
  ENABLE readback one until drain completes. Already-disabled is RS_OK. Do
  not abort a concurrent codec job or silently reroute RX to central DMA.
  `clear_history` issues only bit2 while disabled/global idle, preserving
  mode and model lock. Neither call clears unrelated IRQ or first-error state.
- `status_read` returns the raw status/model words, actual CRC and individual
  monotonic counters. These live counter reads are not a multi-register
  atomic snapshot; use the existing PERF snapshot for cycle comparisons.
  `result_read` checks RESULT_VALID, reads KWS_RESULT (latching its timestamp),
  then timestamp LO/HI, and decodes class/score/hit. It returns the latest
  valid result without consuming it; no-result returns RS_ETIMEOUT immediately.
- `validate_job` is pure, performs no MMIO and validates nonnull pointer,
  four-byte alignment, checked 32000-byte range and threshold/debounce.
  Submit functions additionally check capability, model/microcode locks,
  owner/quiesce/ACL state and armed memory mode. They are nonblocking:
  pack operation1 exactly as above and either issue START or publish the
  owned ring entry with the existing cache/fence/doorbell discipline. Ring
  submission preserves caller cookie and sets IOC from exactly 0/1. Do not
  call the P5 WAV decoder to process these raw PCM bytes.
- `wait_direct` and `ring_result` are bounded completion readers with normal
  P5 job/result/error semantics. Read descriptor word22 only after completed
  OWN-clear and cache invalidation, before the caller reuses that slot; ring
  results use that word, not the newest global result. Both completion APIs
  return the unchanged job START/FINISH timestamps in `job`; they do not
  claim a per-descriptor capture-endpoint timestamp. On a failed job, zero
  the returned class_id/score/hit fields and return its error;
  a previous successful global result is never presented as the failed job.

The global KWS result reports a capture endpoint, whereas the immutable
descriptor records job start/finish. All START/FINISH fields keep their
original meanings, including operation1. A per-descriptor capture-endpoint
timestamp is explicitly deferred because it requires a new descriptor ABI.

All fallible APIs use existing rs_status_t values: RS_EINVAL for null/range/
state/ownership/mode errors; RS_ENOTSUP for missing KWS or unsupported APB
major version (test discovery before touching the P7-only offset); RS_EFORMAT
for model size/header/range/operator rejection (code12); RS_EIO for CRC,
AXI, arithmetic and other hardware terminal failures; RS_ETIMEOUT for an
exhausted poll budget; RS_OK only on the specified successful state/result.
Waits use the existing rs_timeout_t poll budget `max(1,timeout)`, not
milliseconds and never an infinite wait. Timeout does not transfer ownership,
clear OWN, unlock the model, acknowledge IRQs or cancel outstanding DMA.
The caller retains input storage until bounded disable/abort/drain confirms
completion; global abort/reset is an explicit caller decision. Existing
rs_apu_irq_* and error APIs manage IRQ2/4/8/9 without new interrupt allocation.
The owner driver serializes register configuration, submission and result
reads; these freestanding APIs add no OS lock and are not implicitly reentrant.

Deterministic host tests cover exact packing/offsets and model CRC, every
rejection and return mapping, zero/one/max timeouts, no-MMIO pure validation,
no writes after failed validation, result freshness, ring slot reuse, cache
ordering, and P5 discovery fail-closed behavior. The implementation must review
applicable MISRA rules and add a reviewed deviation only if actually needed;
this documentation freeze grants no new MISRA deviation.

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
- MP3 is not part of this release. Format ID 1 and the three-descriptor APUMC
  layout are retained with the P5 unsupported-MP3 trap stub; MP3 requests
  continue to fail closed.
- Native FLAC: mono/stereo, 16/24-bit, 8..96 kHz, constant/verbatim/fixed/LPC
  order0..32, Rice/Rice2, independent/left-side/side-right/mid-side, CRC8/16,
  and bounded metadata skip. Ogg mapping is unsupported.
- S16_LE or S24_32LE memory/I2S output; fixed-point resampling to 48/96 kHz,
  including 44.1-to-48 kHz.
- Continuous KWS: 16 kHz mono S16, one-second history, 20 ms feature stride,
  49 by 10 INT8 MFCC, 12 classes, inference each 100 ms, configurable threshold
  and debounce.
- One decode job plus concurrent KWS, direct/ring DMA, APB4, LP/HP ownership,
  interrupts, ACL, timeout, abort/reset, first error, and counters.

### MVP acceptance

1. WAV and FLAC produce bit-exact approved PCM with the P5
   frame/sample/channel accounting and deterministic output-conversion rules.
   MP3 unsupported-request and trap-stub compatibility tests pass; positive
   MP3 decode, PSNR and three-active-codec packing are not acceptance gates.
2. The official MLPerf Tiny KWS 1000-utterance set reaches at least 90 percent
   top-1 through the hardware MFCC/inference path.
3. At 48 MHz PCLK, the P5 supported WAV/FLAC playback workloads run concurrently
   with continuous KWS with zero I2S underrun and zero KWS overrun under the
   active P5 ready-memory qualification conditions. MP3 performance workloads
   and the archived P6 service-envelope gate are not prerequisites.
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
- The minimp3/mpg123 pins and MP3 numerical/performance rules below are
  archived P6 research only. This release does not require installing those
  inputs, adding target p6, or running positive MP3 qualification. Existing
  generic P4 primitive tests and P5 unsupported-MP3 tests remain required.
- FLAC uses RFC 9639, locked Xiph libFLAC, and the official
  [FLAC test files](https://github.com/ietf-wg-cellar/flac-test-files).
- MLPerf Tiny inputs/model/converter revision and generated `APUM` are locked
  and reproducible.

All new external corpora or reference packages require exact revisions or
archive checksums in the dependency lock. Managed source retains notices and
does not become evidence of self-owned MISRA conformance.

### P7 locked reference inputs and corpus provenance

The following revisions and complete archive SHA-256 values were verified
from upstream bytes on 2026-09-11. Register them in the executable dependency
lock during P7 implementation, using the existing shared dependency helpers
and `scripts/setup_apu_reference.py`; this refreeze changes documentation only.
No floating branch, newly trained model, arbitrary first-1000 selection,
unverified cache hit or direct CI download is an equivalent input.

| Source lock key | Repository / full revision | License and retained notice |
| --- | --- | --- |
| `sources.apu_mlperf_tiny` | `https://github.com/mlcommons/tiny.git` at `4addd0fa08d216e20637637874e084895f289da4` | Apache-2.0; LICENSE.md and source/model notices. |
| `sources.apu_kws_mfcc` | `https://github.com/eembc/benchmark-runner-ml.git` at `cf7c2f2634608a7c0ea7458ab7cb3379f2863424` | Mixed tree: lock NOASSERTION, consume only datasets/kws01; retain source README and Speech Commands CC-BY-4.0 attribution. Do not package the runner or unrelated datasets. |
| `sources.apu_tfds` | `https://github.com/tensorflow/datasets.git` at `8997c4140cd4fc145f0693787b1da78691930459` (v4.3.0) | Apache-2.0; LICENSE and per-file notices; ordering reference only. |
| `sources.apu_tensorflow` | `https://github.com/tensorflow/tensorflow.git` at `fcc4b966f1265f466e82617020af93670141b009` (v2.3.1) | Apache-2.0; LICENSE and per-file notices; host numerical reference only. |
| `sources.apu_gemmlowp` | `https://github.com/google/gemmlowp.git` at `fda83bdc38b118cc6b56753bd540caa49e570745` | Apache-2.0; LICENSE and per-file notices; scalar fixed-point oracle only. |

Source destinations are `.cache/retrosoc/sources/<source-key-with-underscores-replaced-by-hyphens>`
(for example `.cache/retrosoc/sources/apu-mlperf-tiny`). Archive keys below
match source keys where applicable. Archive download destinations are
`.cache/retrosoc/downloads/apu/<key>-<revision>.<tar.gz-or-zip>`; the Google
corpus uses `speech_commands_test_set_v0.02.tar.gz`. These are managed inputs,
not installed Python runtime versions or code permitted in freestanding CRT.

| Archive key | Immutable URL | SHA-256 |
| --- | --- | --- |
| `archives.apu_mlperf_tiny` | `https://codeload.github.com/mlcommons/tiny/tar.gz/4addd0fa08d216e20637637874e084895f289da4` | `70012ee5a8fc3367b466854b1840fb0246e0525744262631a98c5fc0971a04b0` |
| `archives.apu_kws_mfcc` | `https://codeload.github.com/eembc/benchmark-runner-ml/tar.gz/cf7c2f2634608a7c0ea7458ab7cb3379f2863424` | `87e431a6b4d3f011d672180a3fb1f08856d8074310f37653d5388ec2affc5209` |
| `archives.apu_tfds` | `https://codeload.github.com/tensorflow/datasets/tar.gz/8997c4140cd4fc145f0693787b1da78691930459` | `e300258c247fe8607f3c0200a34343c6a28efb69f0d2b822606a8a66cccea651` |
| `archives.apu_tensorflow` | `https://codeload.github.com/tensorflow/tensorflow/tar.gz/fcc4b966f1265f466e82617020af93670141b009` | `ad41490904b0313c00f3729c7e2ba931b2b8d1e54ea1a859a4bcea3054d4fdc0` |
| `archives.apu_gemmlowp` | `https://storage.googleapis.com/mirror.tensorflow.org/github.com/google/gemmlowp/archive/fda83bdc38b118cc6b56753bd540caa49e570745.zip` | `43146e6f56cb5218a8caaab6b5d1601a083f1f31c06ff474a4378a7d35be9cfb` |
| `archives.apu_kws_pcm` | `https://storage.googleapis.com/download.tensorflow.org/data/speech_commands_test_set_v0.02.tar.gz` | `cc2a00c1147c2254e9be3fa0f779d8c17421dc349b86366567a8edfa9acd51df` |

The PCM archive is exactly 112563277 bytes and contains 4890 WAV files. Extract
it to `.cache/retrosoc/sources/apu-kws-pcm` with the shared safe extractor.
License is CC-BY-4.0; retain its LICENSE and README.md, attribute Pete Warden /
Google Speech Commands Data Set Test Files v0.02, and identify padding and
feature extraction as modifications in redistributed derivatives. Managed
reference code/data is excluded from self-owned MISRA claims. P7 release
notices must cover any derived model/ROM/data actually shipped; benchmark
inputs themselves are host-only unless explicitly included as test fixtures.

The model path under apu-mlperf-tiny is
`benchmark/training/keyword_spotting/trained_models/kws_ref_model.tflite`,
53936 bytes, SHA-256
`aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae`.
Do not substitute the README's obsolete `aww_ref_model` name, the float32
model, or a newly generated `kws_model.tflite`. Source preprocessing/converter
reference files are `benchmark/training/keyword_spotting/{get_dataset.py,kws_util.py,make_bin_files.py}`
at that same full revision. The scalar inference reference is
`tensorflow/lite/kernels/internal/{common.h,quantization_util.cc,reference/softmax.h,reference/integer_ops/conv.h,reference/integer_ops/depthwise_conv.h,reference/integer_ops/pooling.h,reference/integer_ops/fully_connected.h}`
at the pinned TensorFlow
revision, with scalar `fixedpoint/fixedpoint.h` from pinned gemmlowp. No
TensorFlow wheel, network-accessing training script or TFDS runtime is needed
to reconstruct the frozen PCM manifest.

#### Exact 1000-window selection

[apu-kws-corpus.tsv](apu-kws-corpus.tsv) is a normative input manifest, not a
build report. It has no header, UTF-8/ASCII text, six tab-separated columns
and LF terminators including the last line: six-digit index, official binary
name, relative source WAV path, decimal class ID, source WAV SHA-256, padded
PCM SHA-256. Its canonical-text SHA-256 is
`57fa600948ef7a19ed5eb0d0e73c7d09fef7d0dbb12bc8833a0a8caad1d6845e`.
When checkout line endings differ, normalize CRLF to LF only before checking
this text hash. Binary WAV/PCM/MFCC hashes never normalize bytes.

The verified selection reproduces TFDS speech_commands 0.0.2 ordering as
used by the upstream test exporter: take each WAV's key `<directory>_<filename>`,
sort by the unsigned 128-bit MD5 of UTF-8 `test` followed by that key, divide
the 4890 sorted records into four contiguous shards of 1222,1223,1223,1222
records (round-to-nearest-even boundaries 0,1222,2445,3668,4890), then read
16 records from each shard in order, repeatedly. Take the first 1000.
The MD5 here is an ordering algorithm, not an integrity/security checksum.
All 1000 labels match the official list. No filename remapping based only on
class labels, nearest-feature search or host-dependent TFDS iteration is used.

Read each selected RIFF WAV as mono 16000 Hz signed S16, preserve sample bits,
right-pad with signed-zero samples to exactly 16000 samples, and emit exactly
32000 little-endian bytes. Reject a longer file or different rate/precision.
The first source is `stop/563aa4e6_nohash_3.wav`; the last is
`up/c22d3f18_nohash_2.wav`. The PCM manifest is independently reproducible from
the public Google archive; an unavailable/deleted EEMBC td_samples package
or user-supplied licensed download is not a prerequisite.

| Object / byte-order of concatenation | Required SHA-256 |
| --- | --- |
| 1000 padded PCM files, index 0..999, no delimiters (32000000 bytes) | `abd1ff2c988ac168dd68c29f934d95114d1094d7818d79fe73adb166ac009bee` |
| Official `datasets/kws01/y_labels.csv`; identical to Tiny `benchmark/evaluation/datasets/kws01/y_labels.csv` | `6cb3709762d53fe64eb00eaf4a75796248bb3c1386f1d1f93ccdb07b071e9698` |
| Official 1000 `datasets/kws01/tst_*.bin`, index order, 490 bytes each, no delimiters | `c2e5f02def82726f5c49dfe85c311c52f295ad68561f6bae89931fdadaaedc73` |

The future self-owned converter is `scripts/apu_kws_convert.py`, contract
revision `apu-kws-convert/1.0.0`, target `p7`, APUM ABI 1.0 and frontend
profile 1. It performs the specified static import/packing, not training or
quantization calibration. Its source commit/hash cannot exist before
implementation: each P7 artifact MUST record the exact implemented converter
Git revision, dirty status, source-file SHA-256 and contract revision. A dirty
or missing converter identity cannot qualify a release. Two independent
imports of the pinned source must give identical APUM bytes, CRC, ROM words
and manifest. Check the generated APUM CRC/SHA and parameter/requantization
hashes against the independent freeze-time golden values above, and record
the actual results. The production converter is still an implementation
deliverable; its existence or correctness is not implied by that byte-layout
cross-check.

#### P7 qualification artifacts and gates

The implementation extends the existing APU reference setup flow with target
P7 and offline doctor checks. Its generated corpus, model, coefficients,
per-layer tensors and JSON reports belong below the selected committed
profile's `build/<profile>-<date>-<hash>/apu-kws/`. Setup/doctor must check all
archive, source model, label, manifest, per-file and aggregate hashes above.
It must fail for missing input rather than downloading outside the shared
dependency helpers or replacing the corpus with synthetic stimuli.

Required report names are `provenance.json`, `apum-layout.json`,
`frontend-differential.json`, `layer-differential.json`, `accuracy.json`,
`concurrent.json`, and `lifecycle.json`. They record input/converter/BAM/RTL
revisions, model/ROM hashes, profile, simulator/tool versions, seed, exact
command, success/failure, counts and artifact paths. Layout includes every
image interval, scratch lifetime, bank access and high-water, not just the
53 KiB source TFLite size. That source file must never be copied verbatim
into the 32 KiB APUM model reservation.

- Official feature-input inference is a separate host/verification-only
  layer differential on all 1000 MFCC files; it exposes no new public
  operation or bypass bit. Each INT8 layer and final result is bit-exact
  against the pinned scalar inference reference.
- End-to-end accuracy feeds all 1000 padded PCM windows through operation 1
  and the real hardware frontend/inference path, resets history per input,
  threshold=128/debounce=1, and requires at least 900 correct top-1 labels
  out of exactly 1000. Silence/unknown remain part of the denominator. No
  skipped/duplicated utterance, CPU MFCC or precomputed-input substitution
  is allowed. Report per-class counts and every incorrect index.
- Continuous tests cover the initial one-second warm-up, 20 ms feature hop,
  100 ms inference cadence, every tie/threshold/debounce edge, snapshot
  coherency, counter saturation, planned gaps and stale-result prevention.
  Raw-mel reuse must equal recomputing the same window's integer frontend.
- Mutate every APUM header/record/range/CRC/reserved field, per-channel
  scaling, sign/rounding extrema and scratch boundary. Test partial load,
  retry, lock, HP denial, no payload DMA before admission and no valid on
  failure. Independently handwritten RTL/C/Python constants and wire
  fixtures must agree; a register generator is still prohibited.
- Concurrent WAV and every qualified P5 FLAC performance workload run with
  continuous RX KWS for at least 60 simulated seconds at 48 MHz, at both
  48 and 96 kHz I2S and both precisions, with the active P5 ready-memory
  qualification. Require zero codec underrun and KWS overrun, every full
  uninterrupted scheduled window completed before its successor, and
  matching byte/frame/cycle/stall scoreboards. Do not promote archived P6
  memory-service envelopes to new P7 prerequisites.
- Separately inject AXI stalls/errors, RX/TX xrun, abort/reset/quiesce/handoff
  at each loader/frontend/layer/writeback state, descriptor wrap/ownership,
  half stereo pairs and unilateral clock-domain resets. These stress cases
  require the bounded specified recovery, not an impossible zero-xrun claim
  under arbitrary starvation. KWS failure must not corrupt codec SRAM,
  model lock or previously published descriptor completions.

IHP130 synthesis/netlist/OpenSTA and final commercial physical evidence remain
P8 work, as for P5. P7 records cycle/memory/ROM/CDC integration evidence but
does not claim area/timing/power closure or an official MLPerf submission.
The current release still advertises no MP3 support.

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

<details>
<summary>Deferred APU-P6 references and qualification — inactive for this release</summary>

### P6 locked MP3 inputs and numerical evidence

Status: DEFERRED. This section and its PSNR, real-time and physical-evidence
subsections are historical notes, not current-release requirements. No MP3
dependency setup, decoder/corpus build, PSNR run, 320 kbit/s workload or
three-active-codec report is required by this release. Current P8 physical
requirements are stated in the active Synthesis, Timing, and Physical Evidence
section; archiving these P6 notes does not remove those P8 requirements.

These fixed revisions and archive SHA-256 values were read and computed from
the complete upstream archive bytes on 2026-09-11. P6 implementation extends
`scripts/setup_apu_reference.py` and the executable dependency lock with these
exact keys. This refreeze changes documentation only. Existing FLAC lock keys,
setup and qualification remain intact.

| Source lock key | URL / full revision | Source destination | License record |
| --- | --- | --- | --- |
| `apu_minimp3` | `https://github.com/lieff/minimp3.git` / `ea99364f61c14656440e8d77e9c233ccf3124633` | `.cache/retrosoc/sources/apu-minimp3` | `CC0-1.0`, retain LICENSE and upstream attribution. |
| `apu_mpg123` | `https://github.com/madebr/mpg123.git` / `f6c19f46031088efc8d0e5b83305a6f36ceceb65` | `.cache/retrosoc/sources/apu-mpg123` | `LGPL-2.1-only` as the default COPYING terms; retain COPYING, AUTHORS and any per-file exceptions. |
| `apu_mp3_corpus` | Same minimp3 URL / `ea99364f61c14656440e8d77e9c233ccf3124633`; select `vectors/` | `.cache/retrosoc/sources/apu-mp3-corpus` | Record upstream `CC0-1.0` declaration and retain LICENSE; preserve vector provenance and any per-file notices. Host-only test material, not a claim of ISO certification or a new license grant over third-party vectors. |

| Archive key | URL | SHA-256 | Download destination |
| --- | --- | --- | --- |
| `apu_minimp3` | `https://codeload.github.com/lieff/minimp3/tar.gz/ea99364f61c14656440e8d77e9c233ccf3124633` | `5628166eb82a9bb581317918a334c317a2c0a30278bb14a20381307976768f34` | `.cache/retrosoc/downloads/apu/minimp3-ea99364f61c14656440e8d77e9c233ccf3124633.tar.gz` |
| `apu_mpg123` | `https://codeload.github.com/madebr/mpg123/tar.gz/f6c19f46031088efc8d0e5b83305a6f36ceceb65` | `1b42d961c56ec0e47510e69768277dd6726316a3063116bfd8264f19b9e1c218` | `.cache/retrosoc/downloads/apu/mpg123-f6c19f46031088efc8d0e5b83305a6f36ceceb65.tar.gz` |
| `apu_mp3_corpus` | Same fixed minimp3 archive URL | `5628166eb82a9bb581317918a334c317a2c0a30278bb14a20381307976768f34` | Same minimp3 download destination, verified once and reused for extraction. |

The mpg123 mirror is linked by the project's
[download page](https://www.mpg123.de/download.shtml). The two decoders have
independent implementations; one decoder executed with two configurations is
not sufficient. All reference programs and corpus files are host-only, outside
firmware, RTL and APUMC release outputs. Use shared checksum/download/extraction
helpers; there is no floating HEAD/tag fallback. Retain notices with cached
sources and any redistributed reference artifacts. Product microassembly and
numerical tables must have independently recorded provenance; copying GPL/LGPL
decoder code into the product is not authorized by these test-input pins.

Setup keeps the existing `--build-dir` interface and adds `--phase p5|p6`
(default p5). P6 installs all P5 inputs plus the three keys above. It checks
CMake at least 3.27, Ninja, and a C compiler before building the pinned mpg123
tree at `ports/cmake`; use `BUILD_PROGRAMS=OFF`, `BUILD_LIBOUT123=OFF`,
`BUILD_SHARED_LIBS=OFF`, `GAPLESS=OFF`, `NO_LAYER1=ON`, `NO_LAYER2=ON`,
`NO_NTOM=ON`, `NO_EQUALIZER=ON`, `NETWORK=OFF`, `NO_REAL=OFF`, and `HAVE_FPU=ON`.
Select the library's `generic` decoder explicitly. Build minimp3 with
`MINIMP3_IMPLEMENTATION`, `MINIMP3_ONLY_MP3`, `MINIMP3_NO_SIMD`, and
`MINIMP3_FLOAT_OUTPUT`. Both host wrappers disable fast-math and FP contraction,
use native source rate/channels and float32 output, and record compiler,
configuration and binary hashes. Missing build tools are explicit setup
prerequisites, not skipped evidence or direct unpinned installer downloads.

mpg123 uses feeder decoding with GAPLESS removed, IGNORE_INFOFRAME set, unity
scale, ReplayGain disabled and no forced resampling or mono mode. minimp3
uses the frame decoder with persistent state, not the extended whole-file
helper's automatic gapless trimming. Both receive the same exact MPEG frame
bytes after this specification's metadata classification. Assert frame count,
sample count, rate and channels before comparing PCM. A reference that silently
resynchronizes or omits an Info frame is a harness failure. Neither reference's
CRC/underflow tolerance is the oracle for malformed files: a separate bounded
header/reservoir/CRC model implements the P6 rejection rules.

Every pinned `vectors/**/*.bit` and `vectors/**/*.mp3` is classified in a
committed deterministic manifest by path and SHA-256. Unsupported layer/free-
format/geometry/emphasis cases are rejection tests, not silently excluded
tests. Every valid in-profile file is a numerical test. Paired upstream `.pcm`
files are supplementary evidence with their byte order/count recorded; the
primary normalized oracle is the pinned mpg123 wrapper. Required stress
families include `l3-compl.bit`, `l3-he_32khz.bit`, `l3-he_44khz.bit`,
`l3-he_48khz.bit`, `l3-he_mode.bit`, `l3-si.bit`, `l3-si_block.bit`,
`l3-si_huff.bit`, `l3-sin1k0db.bit`, `M2L3_bitrate_16_all.bit`,
`M2L3_bitrate_22_all.bit`, `M2L3_bitrate_24_all.bit`, `M2L3_compl24.bit`, and
the performance vectors below. A named file may fail the P6 profile; its exact
first-offender result is then tested instead of treating tolerant reference
decoding as evidence of support.

Self-owned deterministic vectors supplement missing corners: all nine rates,
both channel counts, all supported bitrate indices, MPEG-2.5, protected frames,
all block/mixed modes and joint-stereo combinations, maximum reservoir, VBR,
zero main-data, every ID3 flag/size/footer boundary, and truncated headers,
side-info and entropy. Generate exact coded frames from documented literal
headers/side-info/Huffman symbols and pair every valid frame sequence with both
decoders; no new encoder dependency or opaque Internet audio sample is needed.
No coverage item is waived merely because the pinned corpus lacks it.

#### P6 PSNR calculation and comparison windows

Compare native-rate, source-channel MP3 PCM before P5 downmix/resampling.
Promote each reference float32 `x` to float64 before normalization. Clamp it
to `[-1,1-2^-31]`, round `x*2^31` to nearest-even, then arithmetic-shift right
eight bits to obtain signed 24-bit `r`. Obtain APU `a` from S24_32 output
using the same native geometry and no optional processing. Full-scale peak is fixed at
`P=8388607`, not the measured signal peak. For N samples,
`SSE=sum((a-r)^2)`, `MSE=SSE/N`, and `PSNR=10*log10(P^2/MSE)`; SSE zero means
positive infinity. NaN/infinite reference samples fail the harness before
quantization. Accumulate integer SSE in at least 128 bits or arbitrary-precision
integers without overflow. The acceptance
comparison is strictly `SSE < N*P^2/10^9.6` (>96 dB), evaluated with enough
precision to resolve the boundary; printed rounded dB is never the verdict.

Require >96 dB against each independent reference on the full file, on each
individual channel, and on consecutive 1152-source-sample-frame windows
(including the final nonempty short window). Also compare the two references
to each other with the same threshold; disagreement blocks qualification and
must be investigated, not resolved by choosing the easier oracle. Report
SSE, N, maximum absolute error and worst-window PSNR. Do not optimize delay,
gain, sample offset, or channel permutation to raise PSNR. Start all decoder
histories empty, include encoder/synthesis delay and padding samples, include
Info frames, and require exactly 1152/576 frames per MPEG frame; there is no
trimmed warmup window. Empty/tag-only inputs are error tests, not infinite-
PSNR successes.

Separate S16, downmix and resampling tests compare against applying the frozen
P5 integer post-processing model to the APU's native decoded sequence. This
isolates post-processing correctness from MP3 approximation error; the native
PSNR gates still apply. Run the unchanged WAV/FLAC bit-exact corpus against
both the legacy P5 image and the rewritten P6 image. Code relocation may change
build IDs and cycle/PC measurements, but not PCM, accounting or semantic errors.

#### P6 real-time envelope and physical-evidence boundary

The mandatory 320 kbit/s, 48 kHz joint-stereo workloads come from the pinned
corpus. Their file hashes are:

| Relative path under vectors | SHA-256 |
| --- | --- |
| `performance/MIPSTest.mp3` | `197265fa09d1b6777b71269d986055035f3e9e1f4d74e4cbaa0e55034447a9ca` |
| `performance/MEANDR_PHASE90.mp3` | `b8a8f2b38e2cacc42849af754a926552b87478003738a9f40c86ff0e22f555a1` |
| `performance/noise_meandr.mp3` | `423a97ef5b01c8253940d04bf93ee0d9508b77ef17608c69a1b3c09ae8667c0d` |

Run each as a finite job and in a descriptor ring for at least 60 simulated
seconds, restarting decoder history at each job boundary as specified. Test
S16 and S24_32, at 48 MHz PCLK, 48 kHz I2S; test 48-to-96 kHz output separately
using the P5 resampler. KWS is disabled in P6; simultaneous KWS qualification
is still a P7/P8 requirement. Do not label a clock divider slower than 48 MHz
or a different source corpus as the qualified run.

The qualified AXI service envelope is measured at the APU PCLK master and
includes Gateway A/CDC/target delay: AR or AW handshake within 64 PCLK cycles
of continuously asserted VALID; first RVALID within 32 cycles after AR; at
most four cycles between available R beats when the APU is ready; WREADY at
least once every four cycles after AW; BVALID within 16 cycles after the last
W handshake. Bursts are the existing 1..16 beats/4 KiB subset, responses OKAY.
The BFM must cover both zero-delay and maximum-delay schedules and randomized
legal schedules. APU-generated backpressure and local-SRAM stalls are not
subtracted from execution time. This is a qualified environment assumption,
not a new QoS guarantee imposed on the entire SoC or on slow serial memories.

Start I2S consumption after 64 APU-router words are prefetched, or the whole
output for a shorter job; initial prefill must finish within 2400000 PCLK
cycles from the first MPEG header after ID3. Per job, the steady interval from
the first consumed PCM sample through the last must show zero I2S underrun,
zero dropped/reordered/duplicated PCM frames, exactly one final TLAST for a
nonempty output, and exact P5 byte/frame counters. Queue gaps between jobs
are excluded only if explicitly recorded; they are not a gapless-playback
claim. Clear xrun state before the window and check both sticky state and
event scoreboard during it. Report effective clocks, per-frame/granule cycles,
minimum FIFO occupancy, refill stalls, last-sample time and the full service
trace. An average faster-than-real-time result cannot excuse an underrun.

Randomized tests beyond the service envelope verify the existing timeout,
first-error and drain behavior; uninterrupted playback is not required under
unbounded stalls. Physical signoff remains deferred to P8 as in the approved
APU execution policy. P6 completion requires functional/cycle/formal evidence,
not a claim that an RTL cycle model closes physical timing.

P8 must synthesize this exact P6/P7 hierarchy and compare with the reviewed P5
baseline under the same committed IHP130 profile and locked tools. Static
acceptance is max-delay WNS >= 0 ns and TNS = 0 at the 20.833 ns PCLK target,
no unconstrained active APU clock/data paths, no inferred latch or unresolved
non-PDK black box, and all macro/clock/reset views accounted for. Report hold
analysis separately; pre-layout STA is not post-layout signoff. Area acceptance
requires the unchanged eight control plus 28 data SRAM wrappers, complete
cell/macro accounting and reviewed per-block/total deltas versus P5. There is
no approved absolute standard-cell mm2 or power ceiling before measurement:
those metrics remain explicitly report-only under repository policy, and a
missing area report is not an area pass. No global warning or metric policy
is changed by these feature evidence requirements.

</details>

### Required evidence matrix

| Area | Required evidence |
| --- | --- |
| APB/register | Decode, waits, strobes, RO/WO, busy protection, W1C/set priority, reset, capability, and RTL/C parity. |
| DMA/ring | Native AXI BFM plus the P2 verification-only backend cover internal direct/ring ownership, writeback, wrap, coalescing epochs/IOC, 4 KiB split, tails, ACL overflow, faults, abort, and timeout without a public diagnostic operation. |
| Streams | P2 verification-only endpoints cover both production router/FIFO directions, random backpressure, watermark/xrun, active detection, and route protection; later phases add S16/S24/TLAST and concurrent codec/KWS product endpoints. |
| Assembler/loader | Syntax and semantic rejection, deterministic binary, all control-flow/loop/stack/range checks, CRC, capability, atomic valid/lock, mutation/fuzz. |
| Sequencer/formal | PC/control-store bounds, only bounded loop-back, counter decrement, call depth, watchdog, no system/APB access, descriptor-only DMA handles, legal traps. |
| Primitives | Bitstream/CRC, every Huffman/Rice mode, arithmetic extremes, saturation, transform/LPC/resampler differential, latency bounds. |
| Codecs | WAV/FLAC complete-file differential, sample/rate/channel counts, malformed/truncated/adversarial corpus, metadata limits, FLAC predictor/Rice extremes, and long playlists; MP3 is tested only for unsupported-request/stub compatibility. |
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

Current P8 physical acceptance covers the active P5 WAV/FLAC and P7 KWS
hierarchy, compared with the reviewed P5 baseline under the same IHP130
profile and locked tools. Max-delay WNS must be >= 0 ns and TNS = 0 at the
20.833 ns PCLK target, with no unconstrained active APU path, inferred latch,
or unresolved non-PDK black box; all macro/clock/reset views must be accounted
for and hold analysis reported separately. Retain the eight control-store
plus 28 data-store SRAM wrappers and complete per-block cell/macro/delta
accounting. Standard-cell area and power remain report-only with no approved
absolute ceiling, and missing reports do not count as passes. Pre-layout STA
does not replace physical signoff. No MP3 hierarchy, decoder quality or MP3
performance result is required for this release's P8 acceptance.

Evidence includes:

- control-store and local-SRAM macro count/utilization; expanded P5 uses eight
  4 KiB control-store wrappers plus the unchanged 28 local-data wrappers
  (36 logical wrappers total versus 32 before expansion). Control storage
  increases 16 KiB and combined image/data storage increases from 128 to
  144 KiB. These are capacity counts, not measured area/power; report verifier
  workspace, additional PC/branch flops, muxing, and fetch paths separately;
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

The current active order is P0..P5, then P7, then P8. P6 is a deferred
placeholder, not an implementation task or a prerequisite for P7/P8. Record
it as DEFERRED, not completed or verified. Resuming MP3 requires a later
explicit scope refreeze; the retained reference material is not authorization
to start it automatically.

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
The capacity refreeze adds the 4096x64 store, 12-bit PC/branch datapaths,
APUMC V2 plus legacy V1 decoding, and APB V1.1 PC_HIGH/capacity discovery to
this phase. Previously completed transport, HAL, formal, and corpus work is
the implementation base and is preserved except for the required version/
capacity/width integration.

Dependencies: reviewed Phase4 and the exact RFC/libFLAC/corpus inputs above.
Implement their dependency-lock/setup entries before reference tests. No host
decoder enters the product path.

Public changes: `CAPABILITY0=0x000001bd`, `CAPABILITY1=0x01827020`, implemented
primitive mask `0x001fffff`, classes 0..6, format IDs 0/2, TX route 1, and the
documented HAL. `IP_VERSION=0x00010001`; new release images are APUMC V2.0,
with widened entry PC/branch operands and PC_HIGH at SEQUENCER_STATUS bit 21.
MP3/KWS/RX route 1 remain unavailable and `ABI_DIGEST=0`. No existing APB
offset, job-descriptor layout, legacy APUMC V1 encoding, P1..P4 target behavior,
Resource7, APB group23, IRQ31/PLIC10, Gateway A identity, or clock/CDC allocation
changes.

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

Capacity-migration verification is mandatory in those same test/formal flows:

- V1 accepts 2048 words and rejects 2049; V2 accepts complete 2049/2437/4096-
  word fixtures and rejects 4097. A count of zero is rejected in both. Test
  V1 high descriptor bits and immediate bit 11, V2 reserved bits and immediate
  bit 12, unknown ABI, bad CRC, and field/region overflow with exact loader
  error tuples and no valid/lock publication.
- Round-trip entry/first/last PCs 0, 2047, 2048, and 4095 in handwritten SV/C
  and Python tables. Exercise jump/call/return/loop crossings in both directions
  across 2047/2048, zero/maximum deltas, underflow and a target of 4096; call
  and loop depth/budgets retain their existing limits. No high bit may alias.
- Verify loader writes, proof-state save/restore and fetches across all four
  depth banks with distinct low/high words. Verify eight-macro and inferred
  mappings in behavioral tests, including the no-macro profile. Abort/reset/
  CRC failure after upper-bank writes must leave stale code unexecutable;
  legacy images cannot execute it. Run the complete existing V1 P3/P4/P5
  fixtures, retaining their original binary bytes and terminal tuples.
- At PCs 2048 and 4095, verify SEQUENCER_STATUS PC_HIGH and all existing
  class/opcode/wait/loop fields, full ERROR_ADDRESS, unchanged low-PC detail
  packing, explicit-TRAP immediate, and END/trap/abort/reset retention. Include
  an aux value with bit 4 set so no diagnostic bit is silently lost.
- Rebuild the shared production WAV/FLAC bundle with every previously frozen
  parser/output/error path, cross-frame FLAC resampling, and complete supported
  long-Rice handling. Count every control-store word including the MP3 stub,
  common subroutines and padding. The complete bundle must use at most 4096
  words and publish exact size, free words, CRC/build/SHA-256 and source hashes.
  A larger capacity alone, the incomplete 2437-word trial, or passing only
  already-delivered transport tests cannot establish P5 completion. If the
  complete image still exceeds 4096, report a capacity conflict; do not remove
  required paths or move parsing into RTL/LP/HP.

Completion: the exact supported/rejected matrices, malformed corpus, published
error/count rules, HAL host tests, and production direct/ring/TX paths pass.
Matching-precision/rate/channel FLAC is bit-exact; 44.1-to-48 and 24-bit/96 kHz
playback meet the cycle-counted xrun gate. Larger FLAC blocks, whole-file MD5,
unlisted conversion ratios, MP3 and KWS are outside P5. Synthesis/STA/netlist/
PPA remain deferred to Phase8; functional cycle evidence is not timing signoff.

### Phase 6 - MP3 Layer III Microprogram and Real-Time Closure

ID: `APU-P6`.

Status: DEFERRED for the current release. The ID and title are retained for
traceability; this phase must not be reported as implemented, passed or merged
merely because it has been excluded.

Scope: no MP3 implementation in this release. Do not add an active p6 target,
MP3 microprogram, three-real-codec bundle, MP3 reference/corpus setup, or MP3
PSNR/real-time qualification on behalf of this phase. Retain the existing
format ID, enum, reserved diagnostic IDs and unsupported-MP3 trap entry.
Previously implemented P4 primitives, 4096-word control store, APUMC V1/V2
compatibility, and all P5 functionality remain unchanged.

Dependencies: none for the current active release path. A future MP3 effort
requires an explicit refreeze and a fresh capacity/behavior/evidence review;
the archived P6 notes do not activate it.

Public changes: none from this deferred phase. MP3 CAPABILITY0 bit 1 stays
zero. Discovery remains `0x000001bd` before KWS and becomes `0x000001fd`
only when P7's KWS capabilities are actually implemented and qualified.
`CAPABILITY1=0x01827020` and `IP_VERSION=0x00010001` are retained;
`ABI_DIGEST=0` through P7. P5 direct/ring MP3 rejection and the exact
verification-only trap-stub result remain required.

Validation: no positive MP3, dual-decoder, MP3 dependency, 320 kbit/s, >96 dB
or three-active-codec packing gate applies. Continue the existing P5
unsupported-request, legacy image, ABI parity, and primitive regressions.

Exit status for release planning: DEFERRED, not COMPLETE. The next active
phase is P7 from reviewed P5; P8 reviews the active WAV/FLAC/KWS release and
does not wait for P6.

### Phase 7 - Independent Continuous KWS Engine

ID: `APU-P7`.

Scope: 16 kHz input, MFCC, `APUM` converter/loader/lock, fixed INT8 engine,
continuous scheduler, threshold/debounce, diagnostic operation1, IRQ, accuracy,
performance, and concurrent decode/KWS.

Dependencies: reviewed Phase5; the P7 source/model/corpus/converter contracts
above are frozen inputs. Registering their exact dependency entries and
installing them through the shared setup flow is P7 implementation work,
not an open choice of model/dataset or a missing-user-data prerequisite.
Deferred Phase6 is not a prerequisite and its MP3 reports are not required.

Public changes: implements frozen KWS/model/descriptor-operation/IRQ/counter
ABI, the additive KWS HAL and KWS_INPUT_CONFIG at `0x23c`, and RX route 1.
The I2S wrapper also exports its existing synchronized RX flush-busy state
to APU over the specified same-PCLK internal wire.
Existing offsets/reserved masks, 128-byte descriptor, APUMC V1/V2, 4096-word
control store, bank count, Gateway/IRQ/resource/pad/clock/CDC allocations are
unchanged. `CAPABILITY1=0x01827020`, `IP_VERSION=0x00010001` and `ABI_DIGEST=0`
remain required. Only after every P7 gate passes does the release capability
change from P5 `0x000001bd` to `0x000001fd`; MP3 bit1 remains zero. No generic
NPU interface, CPU MFCC, host inference or shared-codec-lane fallback.

Implementation order within this single phase:

1. Add exact dependency inputs, offline verification and the fixed corpus
   manifest import; implement converter contract 1.0.0 and independent BAM.
2. Add handwritten RTL/C/Python APUM/register parity, wire fixtures and
   deterministic HAL packing tests before enabling public commands.
3. Implement bounded model DMA/CRC/validation/atomic lock and failure tests.
4. Add the independent banks10..25 client, capture/FIR/MFCC/16-lane inference,
   fixed graph, scheduler, snapshot/status/counters and lifecycle integration.
5. Activate RX route1 and direct/ring operation1 with HAL, firmware and
   fault/ownership tests; retain all reviewed P5 and MP3-stub behavior.
6. Produce the complete P7 differential, 1000-window accuracy, concurrency
   and lifecycle reports, then promote only the KWS capability bit.

Validation after implementation (these commands are not evidence of results
from this documentation-only refreeze):

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
ruff check .
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk formal
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim
git diff --check
```

P7 must additionally register and run directed KWS model/frontend/inference,
HAL and full qualification tests under Pytest and the affected formal/firmware
flow; a green generic smoke is not a substitute for the seven named reports.
Extend `scripts/setup_apu_reference.py` with `--target p7` and `--doctor`,
preserving its current `--build-dir` and P5 default behavior. The future
converter accepts `--target p7 --model <verified-tflite> --output <apum>` and
`--manifest <json>`; all paths resolve inside the active build directory except
read-only managed model input. These options are implementation deliverables,
not commands assumed to exist before P7.

Completion: every byte/schema/loader/HAL/lifecycle gate above passes, every
layer is bit-exact, all 1000 windows execute through hardware with top-1
>=900/1000, and concurrent WAV/FLAC plus KWS meets the stated zero-xrun gate.
The source manifest and generation hashes must be reported, not inferred
from a successful simulator exit. Synthesis, netlist, OpenSTA, full LP/HP
contention and commercial physical closure remain P8; P6 remains deferred.

### Phase 8 - LP/HP Software, Contention, and Physical Evidence

ID: `APU-P8`.

Scope: complete HAL, LP-only startup load, HP ownership/jobs, cache maintenance,
Linux ASoC, handoff, USB2/SDIO0 contention, full regression, synthesis recipes,
netlist, OpenSTA, warnings/metrics, and commercial-gap report.

Dependencies: Phases1..5 and Phase7. Phase6 remains DEFERRED and is not a
release prerequisite.

Public changes: completes frozen HAL/Linux surfaces; V1 register/descriptor/
microcode/model/address/IRQ/resource/clock allocation cannot change.

Validation:

```sh
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make regress-pr
make regress-nightly
```

Completion: every active WAV/FLAC/KWS MVP item passes; IHP130 block/full-SoC
evidence is reviewed; unrun commercial gates remain explicit; no unsupported
claim ships. MP3 remains unadvertised and its absence does not block this
release. The current-release capability word stays `0x000001fd`; P8's ABI
digest covers the released contract including reserved MP3 IDs/stub and
excludes inactive P6 proposals.

## Commercial Delivery Gaps

The following remain release blockers after MVP unless separately closed:

These gaps apply to capabilities claimed by the delivered release. MP3/MPEG
decoder qualification is deferred with P6 and is not a blocker for the current
WAV/FLAC/KWS release.

- full requirements-to-test traceability and functional/code coverage closure;
- reusable APB4/AXI4/AXI4-Stream/I2S/microcode/descriptor/fault VIP;
- independent long-run WAV/FLAC interoperability, fuzzing, vulnerability
  intake, and codec maintenance process; licensed MPEG conformance applies
  only if MP3 is explicitly reactivated in a future release;
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
- qualification of deferred codec, channel, low-power, coherency, safety or
  security capabilities when they are later included in an advertised release.
