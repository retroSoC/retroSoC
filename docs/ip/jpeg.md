# Baseline JPEG Codec

## Scope and Sources of Truth

The Mini SoC JPEG block is an 8-bit Baseline Sequential encoder/decoder with a
handwritten APB4 ABI, a private 64-bit AXI4 DMA master, direct jobs, a
scatter-gather ring, interrupts, and LP/HP transferable resource ownership. It
is mapped at `0x1001a000..0x1001afff` and supports images up to 2048 x 2048.
Encode and decode are mutually exclusive in one instance.

The executable sources of truth are:

- `rtl/ip/multimedia/jpeg_*.sv`, `apb4_jpeg.sv`, and `jpeg_define.svh`;
- `crt/include/retrosoc/hal/jpeg_regs.h`, `jpeg.h`, and
  `crt/src/hal/jpeg*.c`;
- `rtl/mini/address_map/memory_map.json` and
  `rtl/mini/integration/soc_topology.json`;
- `tests/jpeg_reference.py`, `tests/test_jpeg*.py`, and
  `tests/rtl/jpeg_*_tb.sv`.

There is intentionally no register generator. The aligned SystemVerilog macro
table and C header are maintained manually. The parity test compares offsets,
field bits, shifts, and the fixed 128-byte descriptor size.

## Commercial Reference Survey

This survey was refreshed on 2026-08-31 from vendor, upstream Linux, and
standards material. "Active" means a current product or maintained upstream
driver was visible at review time. Public sources do not expose vendor RTL or
confidential PPA and verification reports.

| Reference | Problem and architecture | Dependencies | Activity | Reuse / avoid |
| --- | --- | --- | --- | --- |
| NXP i.MX 8QuadMax/8QuadXPlus JPEG-E-X/JPEG-D-X | Standalone CAST encode/decode cores sit behind wrappers. Configuration streams and pixels are fetched from memory, and chained descriptors feed four independently enabled bitstream slots. The Linux interface is V4L2 memory-to-memory. | AXI memory, coherent descriptor/configuration buffers, IRQs, V4L2 driver, CAST core integration. | Active: NXP still publishes the [i.MX 8 family documentation](https://www.nxp.com/products/i.MX8), and the [upstream driver](https://github.com/torvalds/linux/blob/master/drivers/media/platform/nxp/imx-jpeg/mxc-jpeg.c) supports 8/12-bit raw formats, descriptor slots, IRQ recovery, NV12, YUYV, RGB, and grayscale. | Reuse separate configuration/data phases, memory descriptors, format negotiation, and interrupt recovery. Avoid fixed slot count as the public queue ABI, silent alignment padding, and driver assumptions that hide hardware limits. |
| CAST JPEG-E-S/JPEG-D-S and companion DMA | Autonomous Baseline JPEG cores use AXI4-Stream data and APB control. Optional raster-to-block conversion, metadata input, rate control, and AXI4 SGDMA form a complete subsystem. The encoder is specified at one sample/cycle and about 70k gates. | Streaming buffers, raster line/block conversion, optional DMA and rate-control products, licensed BAM and integration kit. | Active: the current [CAST JPEG family](https://www.cast-inc.com/compression/jpeg-image-compression) and [JPEG-E-S page](https://www.cast-inc.com/compression/jpeg-image-compression/jpeg-e-s) list current interfaces and deliverables. | Reuse APB plus AXI4-Stream partitioning, autonomous program-once operation, metadata side stream, BAM, self-checking testbench, and explicit DMA option. Avoid claiming optional rate control or one-sample/cycle performance without the matching implementation and measurement. |
| Alma Technologies JPEG-E-X/JPEG-D-X/UHT | A self-contained pipeline includes DCT, zig-zag/quantization, RLE/Huffman, syntax, tables, and optional video rate control. Standard cores expose flow-controlled streaming; UHT variants scale lanes for 4K/8K. | Streaming I/O, table/configuration interface, optional rate controller, vendor BAM and target scripts. | Active: Alma lists a current [JPEG IP portfolio](https://www.alma-technologies.com/ip-core.JPEG-IP) and an [AXI4-Stream JPEG-E-X](https://www.alma-technologies.com/ip-core.JPEG-E-X) with BAM, testbench, and ASIC scripts. | Reuse stage boundaries, independent table memories, flow control, positive-edge-only implementation, and versioned delivery artifacts. Avoid coupling the baseline MVP to 10/12-bit, multi-scan, DICOM, or rate control before baseline coverage closes. |
| VeriSilicon Hantro VC9000/VC9800 and Nano | A firmware-driven multi-format VPU shares scalable encode/decode infrastructure across modern video formats and JPEG. Nano variants target battery-powered products; larger variants scale cores and streams. | Embedded VPU processor/firmware, frame buffers, scheduler, driver stack, and often proprietary validation tools. | Active: the current [Hantro VPU portfolio](https://verisilicon.com/en/IPPortfolio/HantroVPUIP) lists JPEG in encode/decode products from Nano through 8K/multi-stream variants. | Reuse product variants, clock/power isolation, robust multi-context scheduling, and firmware/driver release discipline. Avoid importing a firmware CPU and multi-codec control plane into a small standalone JPEG accelerator. |
| Chips&Media CODA/WAVE-J class | CODA combines JPEG with video codecs behind job scheduling and memory buffers; the current product family separates JPEG/CODA from WAVE generations. Linux exposes CODA as V4L2 memory-to-memory. | Codec firmware on some variants, DMA memory, V4L2, shared VPU scheduling and recovery. | Active: Chips&Media retains a [JPEG/CODA product category](https://chipsnmedia.com/en/products/index), and current Linux contains maintained CODA/WAVE drivers. | Reuse memory-to-memory software semantics, context ownership, timeout/reset recovery, and buffer completion rules. Avoid making JPEG availability implicit in a broader VPU product name or requiring opaque firmware for a baseline-only block. |
| ASPEED AST video JPEG | A capture-oriented JPEG engine serves BMC remote-display workloads. The upstream driver prebuilds several quality tables and supports standard and ASPEED-specific JPEG, 4:2:0/4:4:4 selection, and up to 1920 x 1200 at 60 Hz input timing. | Display capture engine, reserved/coherent buffers, fixed quality presets, V4L2 and BMC display pipeline. | Active in the current [upstream ASPEED video driver](https://github.com/torvalds/linux/blob/master/drivers/media/platform/aspeed/aspeed-video.c). | Reuse precomputed table contexts and encode-many operation. Avoid binding a general JPEG IP to one capture source, vendor-specific stream headers, or a small fixed quality set. |

The highest-value combination for retroSoC is the CAST/Alma streaming core
boundary plus the NXP descriptor wrapper: keep the codec stages independently
testable, then add a native AXI4 raster/bitstream DMA and a queue. Hantro's
firmware VPU is deliberately not selected because its multi-codec flexibility
costs more area, software, and verification than this product needs.

## Selected Architecture

```text
                     APB4 @ 0x1001a000
                              |
       +---------------- register / IRQ / first-error ----------------+
       |                         |                                    |
 table portal             direct job context                 SG ring context
 4 contexts             raster/stream addresses          128-byte descriptors
       |                         |                                    |
       +-------------------------+------------------+-----------------+
                                                    |
  raster memory <-> 64-bit AXI4 DMA <-> MCU build/reconstruct
                                      |
               +----------------------+----------------------+
               |                                             |
 encode: RGB/YCbCr -> FDCT -> quant -> RLE/Huffman -> pack/syntax
 decode: marker parser -> Huffman/RLE -> dequant -> IDCT -> RGB/YCbCr
               |                                             |
               +--------------- JPEG bitstream ---------------+
```

The control block and codec run on PCLK. A Common `axi4_async_bridge` crosses
the JPEG master into the HP AXI64 data plane. The master can read and write
independently, uses incrementing bursts of up to 16 beats, splits at 4 KiB,
honors byte strobes on tails, and drains accepted traffic on abort. It uses
data-master index 6 and can access SRAM, SDRAM, QPI, OPI, and XPI for reads;
writes exclude XPI. All JPEG buffers are non-cacheable/shared or explicitly
cleaned/invalidated by the owner.

The Resource Controller exposes JPEG as resource 6. Ownership can move between
LP and HP only after quiesce, DMA drain, and idle acknowledgement. The LP
aggregate source is peripheral group bit 22/core IRQ30; HP PLIC source 9 is
used while HP owns the resource. Reset aborts the codec and drains the AXI
master before idle is reported.

## Implemented MVP

| Area | Implemented behavior | Current limit |
| --- | --- | --- |
| JPEG syntax | 8-bit SOF0 Baseline Sequential, JFIF header generation, DQT, DHT, DRI, SOS, EOI, byte stuffing, and RST0..RST7. | No progressive, arithmetic, lossless, hierarchical, 10/12-bit, multi-scan, or abbreviated-table stream. |
| Encode | Grayscale, 4:4:4, 4:2:2, and 4:2:0; programmable quant/Huffman contexts and restart interval. | Hardware always produces a complete JFIF stream. APP/COM metadata and rate control are rejected, not ignored. |
| Decode | Strict marker parser, in-stream DQT/DHT table expansion, restart checking, edge replication, and complete raster output. | One to three components using the supported sampling patterns; malformed/unsupported streams fail closed. |
| Raster formats | `GRAY8`, `RGB565`, `RGB888`, `YUYV422`, and two-plane `NV12`, with independent byte strides. | 8-bit samples only; no planar I420/YV12, BGR/ARGB, tiled, compressed, or 10/12-bit surfaces. |
| Scheduling | Direct job and 2..256-entry power-of-two SG ring; descriptor OWN/IOC, result writeback, stop-on-error, coalescing, head/tail and doorbell. | One active codec job. No preemption, priority queue, virtual contexts, IOMMU, or hardware cache snoop. |
| Tables | Four encoder contexts in six 1024 x 32 technology SRAMs. Decoder tables come from the input JPEG. Portal writes auto-increment and commit atomically marks a context valid. | Software must load expanded canonical Huffman tables. `TABLE_DEFAULT` is reserved and marks the context erroneous; quality is realized by the loaded quant tables. |
| Faults | APB alignment/access errors, validation errors, first AXI fault address/response, malformed JPEG codes, abort, resource reset, sticky W1C IRQ and first-error state. | Error recovery is job/ring level; no ECC/MBIST on table storage and no duplicated safety controller. |

The locked libjpeg-turbo 3.2.0 archive is a host-verification input, not linked
into freestanding firmware. `tests/jpeg_reference.py` is the deterministic BAM
used for byte-exact RTL vectors; libjpeg-turbo/Pillow interoperability provides
an independent ecosystem check. The archive URL and SHA-256 are controlled by
`dependencies/dependencies.lock.json`.

## Data Contract

- Images are 1..2048 pixels in each dimension. Partial edge MCUs replicate
  the final valid row/column; callers do not pad the image.
- DMA addresses are 8-byte aligned. Stride is bytes and must cover one logical
  raster line. NV12 plane 1 contains interleaved Cb/Cr pairs.
- RGB565 words are little-endian `rrrrrggg gggbbbbb`. RGB888 byte order is R,
  G, B. YUYV is Y0, Cb, Y1, Cr. AXI lane 0 is the earliest byte.
- Encode uses table IDs 0 and 1 from `JOB_CONFIG.TABLE_CONTEXT`. Table kinds
  0..3 are 64-entry quant tables, 4..7 are 12-entry DC code/length tables, and
  8..11 are 256-entry AC code/length tables. Huffman words contain code
  `[15:0]` and length `[20:16]`.
- Descriptor and raster memory must not be modified while hardware owns it.
  Software writes descriptor payload, sets OWN last, executes `fence rw,rw`,
  advances tail, and rings the doorbell. Hardware writes results and clears
  OWN before advancing head and raising the event.
- `ABORT` and resource reset stop new work but never withdraw an accepted AXI
  transfer. Completion is reported only after read/write channels drain.

## Register ABI

All registers are 32-bit, word aligned, and byte-strobe aware. Configuration
writes are rejected while busy, except `RING_TAIL` and the doorbell so a
producer can extend a running queue.

| Offset | Register | Access | Purpose |
| ---: | --- | --- | --- |
| `0x000..0x00c` | `IP_ID`, `IP_VERSION`, `CAPABILITY0/1` | RO | Identification and implemented feature geometry |
| `0x010` | `COMMAND` | WO | Start, abort, soft reset, or ring kick |
| `0x014` | `STATUS` | RO | Busy, ring active, encode, idle |
| `0x018..0x020` | `IRQ_STATE/ENABLE/TEST` | RO/W1C, RW, WO | Job, ring, header, abort, and error IRQs |
| `0x024..0x02c` | `ERROR_STATUS/ADDRESS/DETAIL` | RO/W1C | Sticky first error, stage, AXI response, and address |
| `0x030..0x04c` | performance registers | RW/RO | Enable/clear, cycles, pixels, bytes, read/write stalls |
| `0x080..0x094` | job/image/format/encode/restart | RW idle | Direct-mode operation and image geometry |
| `0x098..0x0bc` | bitstream, plane, metadata addresses | RW idle | DMA addresses, sizes, and strides; metadata is reserved |
| `0x0c0..0x0cc` | result registers | RO | Byte count, decoded image size/format, parsed markers |
| `0x100..0x11c` | ring registers | RW/RO | Base, size, head, tail, enable/stop, status, coalescing, doorbell |
| `0x200..0x214` | table portal | RW/RO | Context, kind, index, data, command, status |

`IRQ_STATE` bits 0..4 are job done, ring event, header ready, abort done,
and error. `ERROR_STATUS` packs valid bit 0, error code `[5:1]`, stage `[9:6]`,
and AXI response `[11:10]`. Defined codes include invalid job 1, invalid ring
2, table context 3, marker 4, unsupported process 5, precision 6, sampling 7,
length 8, Huffman 9, truncated stream 10, restart 11, AXI read 13, AXI write
14, and datapath/overflow 18. Unknown codes must be treated as fatal for the
current job.

## Descriptor ABI

Each descriptor is 128-byte aligned and exactly 128 bytes. Ring size is a
power of two from 2 through 256. Head is hardware owned; tail is software
owned.

| Word | Field | Direction |
| ---: | --- | --- |
| 0 | OWN, IOC, encode, auto-header, strict, metadata, table/input/output/sampling | SW -> HW; HW clears OWN |
| 1 | done/error/abort and error code | HW -> SW |
| 2..6 | image, encode config, restart, bitstream address/size | SW -> HW |
| 7 | compressed/output result size | HW -> SW |
| 8..15 | three plane addresses/strides and metadata address/length | SW -> HW |
| 16..17 | opaque 64-bit cookie | Preserved |
| 18..23 | result image/format, cycles, input/output bytes | HW -> SW |
| 24..31 | reserved, write zero | Reserved |

An invalid owned descriptor is completed with error, written back, and head
advances. An unowned descriptor stalls the ring without consuming it. IOC
overrides coalescing. `STOP_ERROR` prevents fetching the next descriptor after
an error writeback.

## Performance Target and Optimization Plan

The product target is 1920 x 1080 4:2:0 at 60 frames/s on a 72 MHz codec
clock. This is 124.416 Mpixel/s and 186.624 M color samples/s, so a sustained
implementation needs at least 1.728 pixels/cycle or 2.592 color samples/cycle,
before blanking and memory stalls.

The current functional pipeline does not meet that target. The deterministic
Icarus benchmark measured 979 busy cycles for one 16 x 16 4:2:0 MCU and 1347
for two, or about 368 steady-state cycles/MCU. Excluding DMA stalls, that
projects to about 3.00 million cycles for 1080p, approximately 24 fps at
72 MHz. This is an optimization baseline, not a 1080p60 claim.

The commercial-performance revision is ordered as follows:

1. Add two ping-pong MCU raster buffers so DMA captures MCU N+1 while N is
   transformed. Coalesce compressed output into 16-beat writes instead of one
   AXI transaction per output beat.
2. Split transform, quantize, and entropy into independently backpressured
   block stages. Bank block storage and carry component/DC metadata beside the
   data so at least one block enters every eight cycles.
3. Use four transform lanes and two entropy lanes for the 4:2:0 profile. Compute
   quantized DC values before entropy issue so luma predictor dependencies do
   not serialize DCT/quant work. Preserve token order through per-block FIFOs.
4. Convert RGB/YUYV/NV12 with at least two pixels/cycle and bank the raster
   buffer to supply four color samples/cycle. Register multiplier outputs and
   fanout-heavy table selects before physical synthesis.
5. Mirror the pipeline on decode: speculative Huffman lookahead, four
   coefficients/cycle inverse RLE, overlapped dequant/IDCT, and ping-pong
   reconstruction. Invalid codes still retire in order and fail closed.
6. Gate the claim with a 1080p frame simulation using randomized AXI
   backpressure, `CYCLES <= 1,200,000` at zero memory stall, sustained SDRAM
   bandwidth evidence, and post-layout timing/power. A frequency-only result
   cannot satisfy this gate.

## Verification and Commercial Delivery Alignment

| Delivery area | Current evidence | Commercial release gate |
| --- | --- | --- |
| Standards and BAM | T.81-derived deterministic model; byte-exact complete-file encode; decoded pixels match BAM; Pillow interoperability. | Full libjpeg-turbo encode/decode differential matrix, JPEG conformance corpus, malformed/adversarial corpus, all restart positions and marker permutations. |
| Block/datapath | FDCT/IDCT, quant/dequant, Huffman, stuffing, marker, MCU format, edge and complete-file directed tests. | Randomized coefficient extremes, saturation proof, PSNR/error bounds by quality, functional coverage and long randomized images. |
| APB/AXI/ring | APB error/IRQ/table tests, 2D DMA burst/4 KiB/tail test, and APB+AXI descriptor fetch/error-writeback/head/IRQ test. | Constrained-random AXI VIP, simultaneous read/write backpressure, all response faults, ring wrap/full/producer races, abort/reset at every state, coherency tests. |
| SoC lifecycle | Generated address/IRQ/resource topology, dedicated AXI64 CDC bridge, quiesce/reset drain, RTL/C parity. | LP/HP live ownership transfer with cache maintenance, clock-stop/reset matrix, CDC/RDC signoff and isolation fault injection. |
| PPA/performance | Cycle counters, reproducible 1/2-MCU baseline, IHP130 synthesis/STA hooks. | Implement the multi-lane revision, 1080p60 frame gate, PVT/MMMC closure, power/activity report and post-layout memory bandwidth. |
| Release package | Synthesizable RTL, handwritten HAL/ABI, Python BAM, directed tests, dependency lock, architecture document. | Versioned requirements traceability, UVM/VIP environment, coverage reports, SVA/formal pack, lint/CDC/RDC/DFT reports, gate/SDF tests, release notes and integration example. |

Current formal gaps are explicit: there is no end-to-end equivalence proof,
CDC/RDC signoff, fault-injection campaign, SDF test, ECC/MBIST, or ISO
conformance certification. Metadata insertion, rate control, 10/12-bit data,
progressive decode, and multi-instance scaling are feature expansions after
the 1080p60 baseline closes. APP/COM insertion should use a bounded metadata
AXI4-Stream side input and marker allowlist; it must not let software splice
unvalidated bytes into entropy data.

## Development Order

The MVP implementation order is the required order for future changes:

1. Freeze syntax, raster ordering, APB fields, descriptor ownership, error and
   abort semantics.
2. Extend the BAM and independent library differential tests before RTL.
3. Verify transform, quantization, entropy and marker primitives separately.
4. Integrate complete encode/decode streams, then raster conversion and edge
   handling.
5. Add 2D AXI DMA, direct operation, ring fetch/writeback, IRQ and resource
   lifecycle tests.
6. Integrate the SoC address, AXI CDC, ACL, resource and PLIC routing.
7. Run style, software policy, host/Python tests, firmware, behavioral
   simulation, IHP130 synthesis, netlist simulation, STA, warning and metric
   gates. Optimize only after a measured failing stage is identified.

## Standards and Golden Model

- [ITU-T T.81 / ISO/IEC 10918-1](https://www.itu.int/ITU-T/recommendations/rec.aspx?id=2633)
  is the normative JPEG-1 baseline.
- The public [T.81 common text](https://www.w3.org/Graphics/JPEG/itu-t81.pdf)
  is used for marker, entropy, restart and DCT behavior.
- [libjpeg-turbo 3.2.0](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/tag/3.2.0)
  is the locked active independent implementation. Its known restart-marker
  slow path is a software implementation detail, not a reason to omit restart
  verification in hardware.
