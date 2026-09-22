# Mini Neural Processing Unit

## Purpose and Research Boundary

This is the authoritative, design-frozen specification for feature `npu`,
approved on 2026-09-16. It defines an independently designed integer inference
accelerator for retroSoC Mini PRODUCT, its deployment ABI, and Phases 0-6.
Design freeze is not RTL freeze: none of the NPU implementation, performance,
or physical evidence is claimed by this document. Phase execution requires
the matching implementation preflight and approval.

The qualification contract was refrozen on 2026-09-21 to remove FPGA hardware
as an NPU-P6 dependency. Full-corpus functional and performance qualification
now runs on the complete PRODUCT Verilator model using architecturally counted
cycles for the same modeled 72 MHz HP configuration. This refreeze does not
change the NPU architecture, hardware or software ABI, workload, 2.0-times
target, synthesis, timing, formal, netlist, or regression requirements. FPGA
and board execution remain useful post-MVP evidence but are not P6 exit gates.

The selected MVP has 64 MAC lanes, 64 KiB of private banked SRAM, a private
AXI4 master with 64-bit data, APB4 configuration, and an independently compiled
bare-metal deployment path. It accelerates small visual and keyword models.
It does not implement or execute the Ethos-U55 register, instruction, weight,
driver, or binary ABI.

Authoritative repository inputs are:

- [LP/HP architecture](../lp-hp-architecture.md), [AXI4 interconnect](../axi4-interconnect.md),
  [DMA](dma.md), [streams](../axi4-stream.md), and [resources](resource-controller.md);
- [address map](../../rtl/mini/address_map/memory_map.json),
  [topology](../../rtl/mini/integration/soc_topology.json),
  [clock/reset inventory](../../rtl/mini/integration/clock_reset_domains.json),
  and the [IHP130 profile](../../configs/ci/ihp130.mk);
- [RTL policy](../rtl-coding-style.md), [engineering policy](../engineering.md),
  and [dependency lock](../../dependencies/dependencies.lock.json);
- the [verification contract](npu-verification.md), which is normative for
  qualification but cannot change the architecture or ABI below.

CONFIRMED FROM REPOSITORY: the current product has nine AXI64 masters,
seven-bit global IDs, 32 KiB system SRAM, a 72 MHz initial HP fabric clock,
and no hardware cache coherence. SDRAM already has a burst-capable frontend.
The private NPU store is additional to system SRAM. The earlier
[Mini NPU survey](mini-npu.md) remains historical research; its AXI32 and
128 KiB baseline and stream-first recommendation do not govern this feature.

## Commercial References

The following CONFIRMED FROM EXTERNAL REFERENCE material was inspected on
2026-09-16. It supports the rationale, not normative encodings or PPA claims.

| Reference | Functions, interfaces, and dependencies | Evidence and selected lessons |
| --- | --- | --- |
| [Arm Ethos-U55 TRM r2p0](https://documentation-service.arm.com/static/60b5e972e022752339b44b4c), Issue 02, 2021-05-12 | Configurable 32/64/128/256 MAC inference; APB4 control, AXI data ports, autonomous command/data DMA, completion IRQ, NPU clock and reset. The reference also has Q-channel and security-dependent behavior. | [Current support](https://support.arm.com/compute-ip/ethos-u55) includes evaluation/model infrastructure. Reuse explicit working storage, offline scheduling, and completion accounting as concepts. Do not inherit its microblocks, compressed weights, encodings, security, or power interfaces. |
| [STM32N6](https://www.st.com/en/microcontrollers-microprocessors/stm32n6-series.html) and [Neural-ART programming model](https://stedgeai-dc.st.com/assets/embedded-docs/stneuralart_programming_model.html) | MCU NPU with dual 64-bit AXI, stream half-DMAs, convolution/vector units, epoch execution, interrupt/poll completion, AHB control, multiple clocks and an asynchronous bridge. Memory is noncoherent. | Active product introduced in December 2024; vendor headline 600 GOPS and 4.2 MB MCU SRAM describe a larger platform. Reuse static allocation and transport/compute separation. Exclude its stream-switch fabric, encryption and clock controls; Mini control is APB4. |
| [MIPS ARC NPX6](https://mips.com/processor-solutions/arc-npx6/) and [2022 vendor architecture presentation](https://www.synopsys.com/content/dam/synopsys/designware-ip/documents/presentations/arc-summit/2022/arc22-et-heterogeneous-multicore-design-nn-pat-harmon.pdf) | Current product successor to Synopsys NPX6, with local/shared memory hierarchy and compiler/virtual-model support. Historical material describes DMA and AXI attachment. | Even entry configurations exceed this MVP. Reuse memory-hierarchy and tensor/vector separation concepts. Current public material does not establish the required APB, IRQ, reset, CDC or coherency contract; none is inferred. Multicore and virtualization are excluded. |

[Vela 5.2.0](https://pypi.org/project/ethos-u-vela/) was released on 2026-09-03.
Its [official documentation](https://arm-software.github.io/CMSIS-Ethos-U/main/vela/index.html)
describes Ethos-U-specific scheduling and output and a deprecated external API.
The approved baseline is an independent TFLite backend; successful Vela/Regor
retargeting is not a prerequisite. [Gemmini](https://github.com/ucb-bar/gemmini)
and [NVDLA](https://nvdla.org/hw/v1/hwarch.html) inform storage and scheduling
analysis only. Their RTL, CPU coupling, and qualification are not dependencies.

No inspected source supplies transferable IHP130 area, power, SRAM timing,
CDC/RDC, or verification results for this architecture. Peak vendor throughput,
model estimates, and licensed functional models are not measured Mini results.

## Requirements and Non-goals

MUST and MUST NOT are normative. The approved Common preference is selected
where exact reset, latency, and handshake semantics fit. Deferred work cannot
silently expand an implementation phase.

| ID | Normative requirement |
| --- | --- |
| NPU-001 | The NPU MUST implement its own architecture and ABI, with 64 dense MAC lanes and 64 KiB private SRAM in the qualified MVP. |
| NPU-002 | Payload and descriptors MUST use a private AXI4/64-bit-data master; configuration MUST use 32-bit APB4. |
| NPU-003 | DMA, sticky completion/error interrupts, bounded software waits, abort, and safe recovery MUST be supported. |
| NPU-004 | NPU low-power modes, Q-channel, power gating, retention, and NPU-controlled clock gating or frequency scaling MUST NOT be added. |
| NPU-005 | NPU security domains, encryption, authentication, virtualization, IOMMU, and security/safety certification claims MUST NOT be added. Existing SoC policy and lifecycle MUST remain intact. |
| NPU-006 | Master/resource 9, the APB window, and IRQ assignments below MUST be added without renumbering existing identities or consuming EXT-H. |
| NPU-007 | Compute/DMA/SRAM MUST use the HP fabric clock; APB MUST use PCLK with atomic approved CDC transactions. |
| NPU-008 | INT8 tensors, signed-nine-bit centered inputs, checked INT32 accumulation, and numerical profile 1 MUST be implemented exactly. |
| NPU-009 | Private memory, reduction slices, buffer lifetimes, parameter streaming, and all DMA accesses MUST stay within their documented bounds. |
| NPU-010 | Only the specified static operators and explicit CPU Softmax/preprocessing path MUST be accepted; unsupported work MUST fail visibly. |
| NPU-011 | The compiler MUST produce independent deterministic artifacts, allocation/traffic reports, and an explicit CPU/NPU execution plan. |
| NPU-012 | The HAL MUST remain freestanding, use `rs_` and `rs_status_t`, and use caller-owned storage. SVH/C registers MUST be handwritten with parity tests. |
| NPU-013 | Common registers, compatible FIFOs, CDC and bus interfaces MUST be reused; managed sources MUST NOT be edited as project RTL. |
| NPU-014 | Clock pause, abort, resource reset, unilateral reset and coordinated transport flush MUST have distinct behavior; no local timeout may discard an outstanding AXI transaction. |
| NPU-015 | KWS and VWW MUST pass the fixed-asset numerical and hardware qualification in the verification companion; missing inputs MUST NOT count as passing skips. |
| NPU-016 | Capability, first-fault, coherent snapshots, traffic, packing, useful-MAC and stall observations MUST report actual implemented behavior. |
| NPU-017 | IHP130 synthesis, 72 MHz timing, macro mapping and NPU-executing netlist tests MUST precede an MVP qualification claim. |
| NPU-018 | Both model workloads MUST meet the companion's 2x performance-qualification target against the fixed same-frequency HP C baseline; a shortfall MUST be reported, not hidden by peak GOPS. |

Explicit DEFER items are Linux/UAPI, ONNX/TOSA import, Vela reuse, training and
calibration, dynamic shapes, batches above one, general grouped/dilated
convolution, broadcast Add, nonconstant weights, float/INT16/INT4, sparsity,
weight compression, queue/ring submission, preemption, cross-layer streaming,
external AXI4-Stream ports, and larger arrays/stores. Existing APU KWS, camera,
audio capture, and central DMA behavior are not replaced or rearchitected.
FPGA prototype and board qualification are post-MVP evidence and MUST NOT be
required for, or inferred from, an NPU-P6 verdict.

## Selected Architecture

### Module and ownership boundary

The owned implementation belongs under `rtl/ip/multimedia`, with technology
storage supplied by the existing `tc_sram_1024x32` wrapper. The intended
hierarchy is:

```text
apb4_npu
  npu_reg                  PCLK registers, launch slot, result/IRQ mirror
  npu_control_cdc          launch/result mailboxes and epoch reconciliation
  npu_core                 HP-domain lifecycle and job controller
    npu_job_decoder        bounded immutable descriptor execution
    npu_scheduler          load/pack/execute/requantize/store ownership
    npu_dma                AXI4 address, burst, byte-edge, response accounting
    npu_local_sram         sixteen technology banks and ownership arbitration
    npu_patch_packer       bounded NHWC gather and local transpose
    npu_mac_array          8 output positions x 8 output channels
    npu_accumulator        two contexts, each 64 checked INT32 sums
    npu_vector             eight-lane depthwise and scalar auxiliary work
    npu_requantizer        one pipelined scalar numerical-profile-1 path
```

No internal instruction-set CPU, general stream switch, or arbitrary program
execution is introduced. A layer descriptor selects bounded hardware loops.
The scheduler overlaps independent load, pack, compute and store activity,
using explicit valid/ready handshakes and buffer ownership. Backpressure can
stall any producer without overwriting a live tile. A layer retires only after
all its output writes receive successful B responses; the next layer then
starts. A model may require several NPU submissions separated by explicit CPU
work in the generated static plan.

Each accumulator context retains its output coordinates, valid lanes, partial
sums, and eight-channel parameter slice until its final quantized byte is
accepted by owned output staging. Only then may that context be reused;
output staging remains owned until its contents are consumed by DMA, and
accepted transport obligations still retire only on B responses.
Bias is added once before the first reduction element, not once per K slice.
Compute stalls if both contexts are occupied. Only initialized lanes are read.

### Private storage and packing

These offsets are internal implementation layout, not CPU-addressable SRAM
or a second bus aperture. No APB bulk-memory access is provided.

| Local range | Bytes | Role |
| --- | ---: | --- |
| `0x0000..0x3fff` | 16384 | Raw IFM gather staging, two 8192-byte halves |
| `0x4000..0x7fff` | 16384 | Packed A, two 8192-byte halves |
| `0x8000..0xbfff` | 16384 | Packed W, two 8192-byte halves |
| `0xc000..0xdfff` | 8192 | Output staging, two 4096-byte halves |
| `0xe000..0xffff` | 8192 | Bounded descriptor/parameter and auxiliary staging |

Two 32-bit single-port banks form each 64-bit-wide 8 KiB A/W half. Active A
and W therefore consume four independent 32-bit reads per compute cycle.
Packing/DMA write inactive halves. The two accumulator contexts occupy
512 bytes of registers outside the 64 KiB SRAM budget; FIFO/register/control
storage and their synthesis cost MUST also be reported separately.

For dense Conv/FC, local A is `[k_in_slice][spatial_lane:0..7]` and local W is
`[k_in_slice][output_channel_lane:0..7]`, raw INT8 bytes in increasing lane
order. `K_SLICE` is 1..1024. Invalid A lanes are filled with input zero point;
invalid W lanes are zero and never become output writes. Centering A to
signed nine bits occurs after the SRAM read, not in an expanded stored format.

The raw gather half holds at most `M * slice_length <= 8192` needed bytes in
`[spatial_lane][k_in_slice]` order. DMA gathers contiguous input-channel runs
within each kernel position, synthesizes padding bytes locally, and refills
bounded segments. It does not require the entire rectangular receptive-field
bounding box to fit a half, and it does not write an external im2col tensor.
The packer transposes these bytes into A. Redundant gathers of overlapping
windows are permitted and MUST appear in traffic estimates.

One spatial tile contains `TILE_H*TILE_W <= 8` output positions, in row-major
order; edge tiles shorten these dimensions. The full reduction order is
kernel height, kernel width, input channel, with contiguous K slices retaining
that order. Reductions greater than 1024 remain supported within operator
dimension limits. Each output-channel group completes all its K slices before
its sums are requantized. When the full reduction fits one A half, its tag
permits reuse across output-channel groups. Larger reductions may reload A;
they MUST NOT assume storage for additional partial-sum contexts.

Depthwise uses eight channel lanes at one output position at a time. Its
local A is `[spatial_lane][kernel_k][channel_lane]`, and W is
`[kernel_k][channel_lane]`; only eight products per cycle are useful. FC has
one spatial position and similarly cannot claim full dense-array utilization.
Parameters are fetched by eight-channel slices, not as a whole-layer array.

### Operator and numerical profile 1

All tensors have static batch one, NHWC storage, contiguous channels, and
positive byte row strides. H, W, OH, OW, input C and output C are each 1..4096;
allocated byte ranges and every computed address must fit unsigned 32 bits
without wrap. Operand weights are constants. The following opcode numbers
are part of descriptor ABI 1.0:

| Opcode | Operation | Additional limits |
| ---: | --- | --- |
| 1 | CONV2D | Kh/Kw 1..16; Sh/Sw 1 or 2; dilation 1; groups 1; per-channel weights |
| 2 | DEPTHWISE3X3 | Kh=Kw=3; Sh/Sw 1 or 2; multiplier 1; Cout=Cin; per-channel weights |
| 3 | FULLY_CONNECTED | H=W=OH=OW=1; reduction Cin; kernel/stride 1; per-tensor or per-output-channel scale |
| 4 | ADD | Two identically shaped NHWC inputs, no broadcasting; independent input scales/zero points |
| 5 | MAX_POOL | Kh/Kw 1..16; Sh/Sw 1 or 2; Cout=Cin; equal input/output scale and zero point |
| 6 | AVERAGE_POOL | Same geometry/quantization limits as MAX_POOL |
| 7 | GLOBAL_AVERAGE_POOL | OH=OW=1, Cout=Cin; whole HxW input; equal scale and zero point |
| 8 | CLAMP | Identical input/output geometry and quantization; covers standalone ReLU/ReLU6 |

Conv/pool output size is `floor((input + pad_before + pad_after - kernel) /
stride) + 1`, independently for H and W. Pads are nonnegative and strictly
less than the corresponding kernel dimension. Every output must have at
least one in-range input position; a zero/negative output extent is invalid.
Conv padding is the raw input zero point. Pooling excludes padding entirely;
MaxPool starts from -128 and AveragePool divides by the valid-position count.
GlobalAveragePool lowers the KWS 25x5 whole-input pool exactly without a
25-row generic pooling kernel. Compiler-only reshape is legal only if it
preserves the contiguous storage interpretation and supported consumer shape.

Activations cover -128..127; symmetric weights cover -127..127 with zero
point zero. Conv/DW/FC accumulate
`bias[c] + sum((input - input_zero_point) * weight)` in signed INT32, checking
each ordered update with wider arithmetic. Overflow traps rather than wraps
or silently saturates. Raw input centering is signed nine bits and the
physical product is signed 9x8, despite the external tensor precision being
INT8. Masked lanes do not raise arithmetic faults.

The effective scale is converted offline using the pinned TFLite
`QuantizeMultiplier` semantics: binary64 arithmetic without contraction,
`frexp`, positive nearest/ties-away Q31 rounding, carry renormalization, and
flush of shifts below -31. Emit the exact nonnegative INT32 multiplier and
signed shift, not a decimal approximation. Accepted runtime shifts are
-31..30; a flushed multiplier is represented by multiplier=0, shift=0.

Define `QM(x,m,s)` as checked INT32 multiplication by `2^max(s,0)`, followed
by `SaturatingRoundingDoublingHighMul` with m, then `RoundingDivideByPOT` with
`max(-s,0)`. For the high multiply, form signed INT64 product p, add
`2^30` if p>=0 or `1-2^30` otherwise, divide by `2^31` truncating toward zero,
with the INT32_MIN-times-INT32_MIN saturation special case. For right shift r,
let mask=`2^r-1`, remainder=`x & mask`, threshold=`(mask>>1)+(x<0)`;
return arithmetic-shifted x plus `(remainder>threshold)`. r=0 returns x.
This is double rounding; nearest-even and single-rounding replacements are
not permitted. A checked left-shift overflow is an arithmetic fault.

Conv/DW/FC output is `clamp(QM(acc,m[c],s[c]) + zout, ACT_MIN, ACT_MAX)`,
with a widened zero-point addition. Bounds are -128..127 and min<=max. The
compiler derives ReLU/ReLU6 limits using the pinned reference quantization.
Plain INT8 saturation uses -128/127. Weight/bias packing does not change the
numerical order or recompute trained bias values.

ADD follows the pinned INT8 reference path: form
`x0=(a-z0)*2^20`, `x1=(b-z1)*2^20`; apply the respective input QM functions,
sum with checked INT32 arithmetic, apply output QM, add zout and clamp. The
offline real multipliers are `scale0/(2*max(scale0,scale1))`,
`scale1/(2*max(scale0,scale1))`, and
`2*max(scale0,scale1)/(2^20*output_scale)`. They use the same Q31 conversion.

Average pooling sums raw signed bytes in checked INT32 and divides by the
positive valid count with nearest/ties-away-from-zero rounding, then clamps.
Global averaging uses count=H*W with the same rule and no padding. MaxPool
returns the maximum valid raw input followed by clamp. CLAMP applies only
the bounds. The compiler MUST verify equal quantization for these operations;
the hardware additionally verifies equal descriptor zero points.

Final Softmax executes through the explicitly pinned scalar C integer
reference and is reported as CPU work. Float exponential, approximate LUT
substitution, or omitted Softmax is not numerical acceptance. Image/audio
preprocessing is outside the NPU graph and is separately accounted. Existing
[APU KWS numerical rules](apu.md#p7-fixed-graph-and-quantization-profile-1)
provide a reference boundary, not shared hardware or an APUM-compatible ABI.

## Interfaces

### Mini allocations and capability integration

These are frozen allocations. Phase 2 wires them exactly as specified; the
integration advertises no execution readiness, DMA, or operator capability.

| Allocation | Value |
| --- | --- |
| APB region | `APB4_NPU`, `0x1001b000..0x1001bfff`, peripheral slot 29 |
| AXI master | Index/prefix 9, following GA2D 8; ten masters total |
| Global AXI ID | Existing 4-bit prefix plus 3-bit local ID, still seven bits |
| Resource | Index 9; count 10; append-only Resource Controller ABI 1.2 |
| LP IRQ | APB peripheral group bit 25, vector 33, external ordinal 31 |
| HP IRQ | PLIC source 12 |

The peripheral IRQ group expands 25 to 26 bits; the existing 64-bit LP vector
and 32-source PLIC container need no width increase. Preserve the separate
MPW compatibility path and all existing harts, resources and interrupts.
Phase 2 MUST update topology generator names/policies, hardcoded master
credit/priority functions, 9x6 assertions, resource vectors, monitor banks,
HAL counts/version and tests together. Adding a port with zero credit is not
integration. Existing bank-addressed monitor registers remain stable.

### AXI4 data plane

The master uses 32-bit addresses, 64-bit data, ID width 3 fixed to zero, and
the existing one-bit USER fixed to zero. There is at most one outstanding
read and one outstanding write; they may overlap. No AXI exclusives, locks,
instruction access, FIXED/WRAP burst, or coherent transaction is emitted.
AxCACHE=0, AxLOCK=0, AxQOS=0 and AxPROT=0; these are ordinary data-transaction
attributes, not a claim to an NPU security mode. Normal arbitration class is
8 with the existing starvation promotion and no programmable QoS elevation.

Read targets are SRAM, SDRAM, active QPI/OPI, and mapped XPI; write targets
exclude XPI. MMIO is not a DMA target. Existing admission checks, inactive-pad
errors, target guards and error responses remain authoritative. This policy
is enforced by the SoC rather than a new NPU firewall.

INCR bursts contain 1..16 beats, use aligned sizes of 1/2/4/8 bytes, and never
cross a 4 KiB page, row segment, allocation or target boundary. Bulk transfers
use full 64-bit beats. Leading/trailing edges use naturally aligned narrow
transfers and byte strobes; WSTRB outside the addressed transfer is never set.
Reads MUST NOT overfetch outside a declared allocation to simplify alignment.
All addresses, strides, lengths and ends use widened checked arithmetic.

Reserve receive storage for a complete read burst before ARVALID. Reserve the
complete write payload before AWVALID. WVALID is asserted only after its AW
handshake; this NPU deliberately does not issue W before AW. Once VALID is
asserted, payload remains stable until accepted or an explicit coordinated
fabric transport flush invalidates the entire transaction. R/B receivers and
AW-accepted W draining remain live during pause and abort.

### APB4 configuration and streams

APB data/address width is 32. Registers require word alignment and writes
with PSTRB=0xf; a zero/partial strobe, unknown offset, reserved-bit write, or
read/write permission violation completes with PSLVERR and no side effect.
Invalid reads return zero with PSLVERR; defined WO reads likewise fail.
Accepted transfers complete once locally in PCLK with a registered response,
held through any wait state. START never holds PREADY awaiting a CDC round
trip or job completion. PPROT is not interpreted as authenticated ownership.

The MVP exposes no extra pads or AXI4-Stream ports. Camera and audio software
can use existing capture/DMA paths to prepare memory inputs. Central DMA
channels, including the reserved channel, are not allocated to NPU execution.

## DMA and Interrupt Contract

### Job submission and ordering

The PCLK shell contains one launch slot. START atomically latches JOB_BASE,
JOB_COUNT, JOB_ID and timeout settings, sets shell BUSY immediately, and sends
one complete launch payload. The source mailbox becoming ready again does not
release the shell BUSY lock. A second START while BUSY, unreconciled, paused,
quiesced, reset-requested, or with a pending terminal IRQ fails with PSLVERR.

JOB_BASE is a physical 64-byte-aligned address to 1..65535 contiguous 128-byte
descriptors. The descriptor region is immutable until safe terminal recovery.
There is no linked-list pointer, ring, hardware queue, or self-modifying job.
Hardware fetches each record into private staging and validates all of its
fields, sizes and operand spans before issuing its operand transactions.
Records execute in order. A later invalid record may leave earlier layer
outputs written; neither error nor abort rolls memory back.

No CPU, DMA or other accelerator may modify descriptors, constants or active
input/output allocations until completion or confirmed recovery. Different
operand allocations must be disjoint from the current descriptor array,
weights and parameters. Output must not overlap either input; input0/input1
may alias only for read-only ADD. Separate job records may reuse an arena
after the previous record's stores have retired. In-place transforms are
deferred. Range checks prevent programming errors; they do not authenticate
untrusted software or provide memory isolation.

DONE requires every descriptor retired, no active compute/pack/store work,
and all final output B responses successful. ERROR/ABORTED become terminal
only after transport drains or the SoC explicitly invalidates it by flush.
Before that point BUSY and DRAINING remain set and output buffers are unsafe.
The result snapshot carries JOB_ID, internal epoch, fault, descriptor index,
completed descriptor count and counters. Stalled delivery cannot overwrite it.

### Interrupt events

IRQ_STATE bits are DONE=0, ERROR=1 and ABORTED=2; bits 31:3 are reserved.
IRQ_ENABLE gates delivery only, not event collection. IRQ_STATE is W1C and
hardware set wins a same-cycle clear. IRQ_TEST injects any implemented bits
without changing BUSY, RESULT_CODE or completed job identity. Test IRQ alone
is not successful completion. Status reads have no clearing side effects.

`irq_o = |(IRQ_STATE & IRQ_ENABLE)` is routed by Resource Controller 9 to
LP vector 33 for owner 0 or HP PLIC source 12 for owner 1, never both.
Resource reset masks both destinations. APB carries no authenticated hart
identity: software serializes submissions and uses the existing resource
handoff protocol; the NPU does not claim to reject a non-owner CPU's MMIO.
Owner changes do not clear sticky events: an uncleared IRQ follows the new
owner under the existing routing rule. The HAL acknowledges the old terminal
job before handoff; intentionally retained events remain visible to the new
owner and are never delivered to both. Pending terminal IRQ means any of
IRQ_STATE bits2:0 is set, regardless of IRQ_ENABLE.

ABORT on an active job requests terminal cancellation; ABORT on an idle NPU
is a successful no-op. Ordinary cancellation produces ABORTED only. A hardware
fault produces ERROR only; if cancellation races a fault, ERROR wins. Successful
completion already published before ABORT remains DONE. Acceptance of ABORT
before terminal publication prevents DONE, even if some output was written.
The launch slot is released only after terminal delivery or epoch recovery.

## Register and Software ABI

### Register map

Version is 1.0 (`0x00010000`). The following offsets are normative; all
unlisted offsets are invalid. Reset means PCLK shell reset or completed local
software reset unless a row specifies a constant/live value. Resource reset
retains its cancellation diagnostic until acknowledgement or local reset.

| Offset | Register | Access | Reset / behavior |
| --- | --- | --- | --- |
| `0x000` | IP_ID | RO | `0x4e505531` (`NPU1`) |
| `0x004` | IP_VERSION | RO | `0x00010000` |
| `0x008` | CAPABILITY | RO | Implemented feature flags below |
| `0x00c` | STATUS | RO | Live/link and terminal status below |
| `0x010` | CONTROL | WO | One of START bit0, ABORT bit1, SOFT_RESET bit2 |
| `0x014` | IRQ_STATE | RW1C | 0; three sticky events |
| `0x018` | IRQ_ENABLE | RW | 0; bits2:0 |
| `0x01c` | IRQ_TEST | WO | Implemented event mask |
| `0x020` | JOB_BASE | RW idle | 0; physical descriptor address |
| `0x024` | JOB_COUNT | RW idle | 0; count in bits15:0 |
| `0x028` | JOB_ID | RW idle | 0; opaque software token |
| `0x02c` | TIMEOUT_CYCLES | RW idle | 72000000 HP active cycles without progress; zero is illegal |
| `0x030` | RESULT_JOB_ID | RO | 0; last terminal or recovery token |
| `0x034` | RESULT_CODE | RO | 0; result enumeration below |
| `0x038` | COMPLETED_DESCRIPTORS | RO | 0; complete stores only |
| `0x03c` | FAULT_DESCRIPTOR | RO | `0xffffffff`; zero-based index, or all ones for job-level fault |
| `0x040` | FAULT_CODE | RO | 0; first fault/error code |
| `0x044` | FAULT_ADDRESS | RO | 0; first relevant external byte address, otherwise 0 |
| `0x048` | FAULT_INFO | RO | 0; direction/AXI response/lane details below |
| `0x04c` | NUMERIC_PROFILE | RO | 1 |
| `0x050` | LOCAL_BYTES | RO | 65536 when implemented; otherwise 0 |
| `0x054` | MAC_CONFIG | RO | dense lanes bits15:0=64, depthwise lanes bits31:16=8 when implemented |
| `0x058` | MAX_K_SLICE | RO | 1024 when implemented; otherwise 0 |
| `0x05c` | MAX_DIMENSION | RO | 4096 when implemented; otherwise 0 |
| `0x060` | OP_CAPABILITY | RO | Bit n advertises implemented opcode n; full MVP `0x000001fe` |
| `0x064` | OWNER_STATUS | RO | Resource owner bits1:0, lock bit8, quiesce bit9, reset request bit10 |
| `0x068` | RECOVERY_GENERATION | RO | PCLK-visible epoch-generation counter; see lifecycle |
| `0x06c` | PERF_CONTROL | WO | SNAPSHOT bit0 only |
| `0x070` | PERF_STATUS | RO | SNAP_BUSY bit0, SNAP_VALID bit1 |
| `0x074` | PERF_JOB_ID | RO | Job token associated with snapshot |
| `0x078` | PERF_GENERATION | RO | Generation associated with snapshot |
| `0x07c` | DESCRIPTOR_BYTES | RO | 128 |
| `0x080..0x0cf` | PERF counters | RO | Ten low/high pairs, 8-byte stride; reset 0 |

CONTROL requires exactly one implemented bit, no reserved bits. START performs
the job checks above. SOFT_RESET is accepted only with no active launch/job,
no accepted/presented AXI work and no snapshot transfer; otherwise PSLVERR.
It clears programmable registers, IRQ and result state, then reconciles CDC
before READY returns. It does not clear physical SRAM contents. Configuration
writes require shell idle and no pending START, but IRQ mask/W1C/test and
snapshot commands remain legal while BUSY. An unavailable START is a local
APB error, not a newly collected job fault.

CAPABILITY bits: 0 PRESENT (register shell integrated); 1 EXECUTION_READY
(complete supported MVP implementation compiled in); 2 PRIVATE_AXI64_DMA;
3 INTERRUPTS; 4 DOUBLE_ROUNDING; 5 NATIVE_HP_CLOCK; 6 SOFTWARE_ABORT.
Reserved bits are zero. Interim phases expose only tested implemented bits
and operator capabilities; P2 does not advertise inference or accept real jobs.
Software checks EXECUTION_READY and required OP_CAPABILITY before deployment.
MAC_CONFIG and LOCAL_BYTES reflect instantiated storage/compute, not a future
constant accidentally advertised by a shell-only implementation.

STATUS bits: 0 READY, 1 BUSY, 2 DRAINING, 3 CLOCK_PAUSED, 4 RECOVERING,
5 RESULT_VALID; 31:6 zero. READY means links reconciled, complete executable
implementation available, no resource/reset/pause request, no busy launch,
no pending terminal IRQ, and no active snapshot handshake. RESULT_VALID clears
on an accepted START or reset, not on IRQ W1C. RESULT_CODE is NONE=0, DONE=1,
ERROR=2, ABORTED=3, RESET_CANCELLED=4. Tests/IRQs never create RESULT_VALID.

RECOVERY_GENERATION is a 32-bit wrapping shell counter incremented after each
completed link/transport recovery; shell reset resets it to zero. It is an
observable generation, not the sole stale-message filter. Internal reset
handshakes invalidate both mailboxes and hold launches off until both endpoints
acknowledge a fresh epoch, including at counter wrap or unilateral reset.

### Descriptor ABI 1.0

Each record is 32 little-endian unsigned words. Signed byte/halfword fields
are two's complement; reserved bits and unused operation fields must be zero.
No compiler-native C bitfield or packed-struct layout is used as a wire ABI.

| Word | Field | Meaning |
| ---: | --- | --- |
| 0 | VERSION_OPCODE | Bits31:16=`0x0100` (1.0); bits15:8=0; bits7:0 opcode |
| 1 | RESERVED | 0 |
| 2 | INPUT0_BASE | Physical byte address |
| 3 | INPUT1_BASE | ADD input; otherwise 0 |
| 4 | OUTPUT_BASE | Physical byte address |
| 5 | PARAM_BASE | Physical 64-byte-aligned parameter slice-array base, or 0 |
| 6 | INPUT_HW | H bits15:0, W bits31:16 |
| 7 | CHANNELS | Cin bits15:0, Cout bits31:16 |
| 8 | OUTPUT_HW | OH bits15:0, OW bits31:16 |
| 9 | INPUT0_ROW_BYTES | Positive byte row stride, at least W*Cin |
| 10 | OUTPUT_ROW_BYTES | Positive byte row stride, at least OW*Cout |
| 11 | INPUT1_ROW_BYTES | ADD row stride, at least W*Cin; otherwise 0 |
| 12 | KERNEL_STRIDE | Kh, Kw, Sh, Sw in ascending byte lanes |
| 13 | PADDING | Top, bottom, left, right in ascending byte lanes |
| 14 | TILE_HW | TILE_H bits7:0, TILE_W bits15:8; upper half zero |
| 15 | K_SLICE | 1..1024; last slice is shortened |
| 16 | INPUT0_BYTES | Nonzero accessible allocation length |
| 17 | INPUT1_BYTES | ADD accessible allocation length; otherwise 0 |
| 18 | OUTPUT_BYTES | Nonzero accessible allocation length |
| 19 | PARAM_BYTES | Exact parameter-array byte count, or 0 |
| 20 | INPUT0_ZERO | Signed low byte; upper 24 bits zero |
| 21 | INPUT1_ZERO | ADD signed low byte; upper 24 bits zero; otherwise entire word 0 |
| 22 | OUTPUT_ZERO | Signed low byte; upper 24 bits zero |
| 23 | ACTIVATION_BOUNDS | Signed ACT_MIN low byte, ACT_MAX next byte; upper half zero |
| 24 | WEIGHT_BASE | Conv/DW/FC 64-byte-aligned packed weights; otherwise 0 |
| 25 | WEIGHT_BYTES | Exact packed-weight length; otherwise 0 |
| 26..31 | RESERVED | 0 |

For nonconvolutional elementwise operations (ADD/CLAMP), input/output geometry
is identical, kernel/stride word is `0x01010101`, padding is zero and K_SLICE=1.
FC has the same kernel/stride word, zero padding and TILE_H=TILE_W=1.
GLOBAL_AVERAGE_POOL has kernel/stride and padding zero, TILE_H=TILE_W=1;
its reduction is H*W. Pool/DW K_SLICE cannot exceed their full reduction;
other reductions also require K_SLICE<=full K. TILE_H/TILE_W are each 1..8,
their product is at most 8, and neither exceeds the corresponding output
dimension. ADD/CLAMP and pool require Cout=Cin. FULLY_CONNECTED input row
stride is at least Cin, output row stride at least Cout.

Full K is Kh*Kw*Cin for Conv, Cin for FC, 9 for Depthwise, Kh*Kw for local
pooling, H*W for GlobalAveragePool, and 1 for ADD/CLAMP. Pool slice boundaries
do not change the valid-element count or average rounding point; round only
after the complete output reduction.

For each operand, the used span is `(H-1)*row_stride + W*C`; it must not exceed
the declared allocation. INPUT1 uses input geometry. Byte-addressed activation
bases need no artificial 64-byte alignment; the DMA handles legal edges.
Compiler arenas and host cache maintenance use 64-byte-separated allocations
to prevent unrelated dirty data sharing boundary cache lines.

Dense weights are `[ceil(Cout/8)][Kh*Kw*Cin][8]`; FC uses Kh=Kw=1. Reduction
indices run kh, kw, cin. WEIGHT_BYTES equals `ceil(Cout/8)*K*8`. The lane for
channel c is c%8, its group is c/8. Padding output-channel weights are zero.
Depthwise weights are `[ceil(Cin/8)][9][8]` in kh/kw order, with zero channel
tails. Hardware validates each fetched weight is not -128 and masks tail
lanes; the offline validator also verifies tail bytes are zero.

Conv/DW/FC parameters comprise exactly Cout records of 16 bytes:
`{int32 bias, int32 nonnegative_q31_multiplier, int32 shift, uint32 reserved0}`.
Records have natural 16-byte stride; only the array base is 64-byte aligned.
The final eight-channel fetch is shortened rather than overreading padding.
ADD parameters are exactly 32 bytes:
`{uint32 left_shift=20, int32 m0, int32 s0, int32 m1, int32 s1,
int32 mout, int32 sout, uint32 reserved0}`. Pool/CLAMP have PARAM_BASE/BYTES=0.
Unknown versions, opcode/reserved fields, dimensions, scales, bounds,
overlap, unsupported capabilities and overflowed span arithmetic are errors.

### Compiler artifacts and C HAL

The version-1 deployment package is a directory containing `npu.json`,
`descriptors.bin`, `weights.bin`, `params.bin` and generated static C plan/data.
It is not an Ethos-U binary and requires no firmware filesystem loader.
The host manifest records schema=1, source-model SHA-256, compiler revision,
numeric_profile=1, required capability/opcode masks, each file's byte count
and SHA-256, arena bytes, and ordered execution steps. NPU steps give first
descriptor/count; the only runtime CPU neural operator in v1 is terminal
integer Softmax with pinned parameters. Preprocessing is an explicitly
separate application step. Storage-preserving reshape emits no runtime work.

The host descriptor templates use region-relative offsets in address words.
The manifest contains relocations `{descriptor_index, word_index, region,
offset}` for words 2/3/4/5/24 as applicable, with region in `arena`, `weights`,
or `params`. Each nonzero semantic pointer has exactly one relocation, even
when its relative offset is zero. Generated C adds caller-provided physical
region bases using checked arithmetic into a caller-owned aligned descriptor
copy before submission; templates are never submitted directly. The manifest
and C plan retain tensor quantization metadata for offline validation.
SHA-256 records provenance/integrity during development, not authentication.

No runtime heap allocation, training, calibration, silent precision change,
or hidden CPU fallback is allowed. Compiler reports list every operator's
placement, full/sliced K, packed sizes, allocation/lifetime, DMA bytes,
packing cycles, reloads, tail utilization and estimated cycles. Inference
estimates are distinct from measured counters. The final application may
place generated constant arrays in mapped flash, and its arena/descriptors
in admitted writable memory using an existing committed profile/link layout.

Public headers are `<retrosoc/hal/npu.h>` and
`<retrosoc/hal/npu_regs.h>`, with implementation in the matching HAL source
layer. Owned RTL uses `npu_define.svh` and `npu_pkg.sv`; a dedicated parity test
compares handwritten offsets, masks, opcodes, errors and descriptor word
positions. Do not introduce a register generator. Generated model artifacts
do not replace those handwritten interface definitions.

The HAL surface MUST include these operations using normal project argument
validation and public typed structs:

- `rs_npu_get_capability()` returns identity, numeric profile, memory, lanes,
  dimension/slice limits and operator mask.
- `rs_npu_submit()` accepts descriptor physical address/count, job token and
  timeout cycles; it validates readiness and writes START once.
- `rs_npu_wait()` polls the real terminal status for the submitted token with
  `rs_timeout_t`; zero timeout means one poll. IRQ mode uses the same result
  rules and never treats an injected IRQ as a completed job.
- `rs_npu_abort_wait()` requests cancellation and waits for transport-safe
  terminal/recovery; `rs_npu_reset()` is idle-only.
- `rs_npu_get_status()`, `rs_npu_get_error()` and
  `rs_npu_snapshot_counters()` provide non-destructive typed observations.
- IRQ enable/pending/ack APIs operate on the three implemented event bits.

The exact v1 signatures are:

```c
rs_status_t rs_npu_get_capability(rs_npu_capability_t *capability);
rs_status_t rs_npu_submit(const rs_npu_job_t *job);
rs_status_t rs_npu_wait(uint32_t job_id, rs_timeout_t timeout,
                        rs_npu_status_t *status);
rs_status_t rs_npu_abort_wait(uint32_t job_id, rs_timeout_t timeout,
                              rs_npu_status_t *status);
rs_status_t rs_npu_reset(rs_timeout_t timeout);
rs_status_t rs_npu_get_status(rs_npu_status_t *status);
rs_status_t rs_npu_get_error(rs_npu_error_t *error);
rs_status_t rs_npu_snapshot_counters(rs_timeout_t timeout,
                                     rs_npu_counters_t *counters);
rs_status_t rs_npu_irq_enable(uint32_t events);
rs_status_t rs_npu_irq_pending(uint32_t *events);
rs_status_t rs_npu_irq_ack(uint32_t events);
```

Public structs contain named `uint32_t` fields unless specified otherwise:
`rs_npu_job_t` has `descriptor_address`, `descriptor_count`, `job_id`,
`timeout_cycles`; `rs_npu_capability_t` has `ip_id`, `ip_version`, `flags`,
`numeric_profile`, `local_bytes`, `dense_macs`, `depthwise_macs`,
`max_k_slice`, `max_dimension`, `op_mask`. `rs_npu_status_t` has `flags`,
`job_id`, `result_code`, `completed_descriptors`, `recovery_generation`;
`rs_npu_error_t` has `code`, `address`, `descriptor_index`, `info`.
`rs_npu_counters_t` has `job_id`, `recovery_generation` and ten `uint64_t`
fields matching the lower-case counter names in the counter table. These
structs are source APIs, not memory-mapped wire layouts. Null required output
pointers are RS_EINVAL. IRQ enable replaces the mask; pending returns raw
implemented sticky events. Wait/abort reject a token that does not identify
the active or retained result rather than cancelling an unrelated task.

Status mapping is RS_EINVAL for invalid arguments, busy/not-ready or invalid
state; RS_ENOTSUP for missing capability; RS_EFORMAT for malformed deployment
or descriptor; RS_EIO for hardware/arithmetic fault or cancellation; and
RS_ETIMEOUT for a bounded software wait. No new RS_EBUSY value is invented.
A timeout does not transfer buffer ownership back to the caller. The caller
must complete abort/drain or observe coordinated recovery before reuse.

LP is the default owner; HP bare-metal submission is included in qualification.
Software serializes one submitter and acquires resource ownership before use.
Before START it cleans input/constants/descriptors and cleans/invalidates
output lines as applicable, then fences. After terminal successful output
completion it invalidates output and fences before CPU access. Use the
existing 64-byte HP Zicbom boundary and avoid sharing cache lines with
unrelated allocations. LP still executes ordering fences despite no D-cache.
Cache ownership of an active NPU job remains the application's responsibility
during HP lifecycle operations; automatic coherence is not implied.

## Clock, Reset, CDC/RDC, and Lifecycle

### Domains and Common reuse

The NPU compute, scheduler, SRAM, counters and DMA use `clk_hp_i` and shared
`rst_hp_n_i`. They MUST NOT use the gated HP-hart `clk_hp_core_i` or its
hart-only reset. The shell uses PCLK and its reset. Initial qualification is
at HP=72 MHz; PCLK ratios/phases follow the existing clock inventory and its
constraints rather than an assumed 72 MHz APB clock.

Use Common `async_reqack` for complete launch/result/snapshot payloads and
approved `cdc_sync`/reset primitives for stable scalar lifecycle requests.
The active Common lock is revision
`964a54d70cb78e394ba9a25c05f2aa2b02941fb7`. Its one-entry mailboxes flush on
either endpoint reset; this is explicitly accounted for below. Use the
existing Common interfaces, compatible FIFO wrappers and register primitives.
FIFO depth/latency must meet their actual power-of-two/minimum-depth contract.
The HP-native master needs no NPU payload AXI CDC or width upsizer.

Every new crossing, domain reset and instance is added to the canonical
clock/reset inventory in Phase 2. Functional asynchronous tests do not
constitute physical CDC/RDC signoff.

### Clock pause is not task cancellation

Global `block_new_i` can close AR/AW acceptance before an NPU task finishes.
On this request, stop starting new internal work at a bounded register-safe
micro-operation boundary, preserve SRAM/accumulators/job state, and drain
accepted reads and AW-accepted writes. Do not wait for the current tile or
job to finish if doing so needs a new blocked address.

An already asserted but unaccepted ARVALID/AWVALID remains stable through the
pause and resumes after unblock. Such a request is not an outstanding
accepted transaction. `clock_pause_ack` means paused internal state and zero
accepted read/write obligations; it does not require master-idle or BUSY=0.
The global HP-idle contribution is
`!clock_pause_requested || clock_pause_ack`, combined with existing accepted
fabric-transaction drain. A paused job must not permanently hold global idle
low. Receivers remain ready as required by reserved burst storage.
Pause ACK is also independent of PCLK accepting a completion or counter
mailbox; its stable payload may wait through the clock transition.

Ordinary clock switching preserves the task; unblocking resumes it. Pause
cycles are excluded from the job no-progress watchdog, but a software
wall-clock wait may still expire. No NPU clock/power-management feature is
introduced by participation in this platform protocol.

### Abort, quiesce, reset and flush

| Event | Required action |
| --- | --- |
| Software ABORT / resource QUIESCE | Stop new scheduling; finish presented addresses, drain accepted responses and accepted writes; discard incomplete compute/output tiles; publish ABORTED if a job was active. Idle quiesce produces no job event. |
| Resource RESET | Perform stop/drain before local functional reset. Retain RESET_CANCELLED diagnostic for an active job; IRQ routing remains masked while reset requested. READY stays low until actual completion and fresh epoch reconciliation. |
| Idle SOFT_RESET | Clear programmable/result/IRQ state and all local validity; reconcile endpoints before READY. No SRAM content clearing. |
| PCLK unilateral reset | Do not reset HP AXI state directly. Detect link loss, stop new work, drain, discard old result, and reconcile a fresh epoch. Software must regard pre-reset jobs as invalid. |
| Shared HP domain hard reset | Resets NPU with the fabric under its existing reset contract; shell reconciles link loss and reports RESET_CANCELLED for its active token after recovery. |
| Coordinated fabric flush | This explicit transport invalidation may discard presented/accepted requests together with the fabric; cancel an active job, advance epoch, suppress DONE, and do not resume that job. No job means no artificial cancellation event. |

Resource quiesce/reset closes master-9 admission only after a fresh
source-quiesced acknowledgement: no presented VALID, no accepted obligations,
no memory/compute writer, and terminal result safely latched for delivery.
The handshake MUST also account for every PCLK-shell-accepted launch in the
current epoch, including one still in flight to HP. Cancel or retire that
token and latch its terminal record before handoff/reset ACK; an empty HP
engine alone cannot acknowledge an unseen launch. Shell BUSY/launch-pending
state participates in the round-trip quiesce reconciliation.
Do not use a stale synchronized idle sample. If resource abort overlaps global
clock block with an unaccepted address, resource ACK waits for unblock or an
explicit coordinated flush; a local timeout may not withdraw VALID.

The Resource Controller reset-request bit is not proof that downstream reset
has completed. NPU READY/RECOVERING and the fresh source ACK provide that
evidence. Following coordinated flush, rearm only after flush deasserts,
fabric `flush_busy` clears, resource reset/quiesce releases and both mailboxes
complete epoch reconciliation. Late responses/results from an old epoch
cannot complete a new launch. Existing target timeout isolation until hard
reset remains in effect; NPU software reset cannot repair an isolated target.

Physical SRAM contents are never reset as a bulk array. Clear occupancy,
tags, context ownership and validity so no stale content is consumed. New
operands, padding and masked-lane definitions initialize all values actually
read. This is functional reset behavior, not secure zeroization.

## Errors, Recovery, Security, and Observability

First fault is retained until the next accepted START or completed software
reset; IRQ W1C never clears its detail. The core stops issuing new work after
a fault but continues necessary transport draining. The shell receives a
stable fault notice promptly while BUSY/DRAINING remains true; terminal ERROR
and its IRQ are published only when buffers are safe or coordinated recovery
has invalidated transport. An APB programming error does not replace the job
first-fault record.

| Code | Name | Condition |
| ---: | --- | --- |
| 0 | NONE | No fault |
| 1 | DESCRIPTOR | Version, reserved field, malformed record or parameter encoding |
| 2 | UNSUPPORTED | Opcode/capability or unsupported operator constraint |
| 3 | RANGE | Address/span overflow, target/allocation crossing, illegal overlap, bad geometry |
| 4 | AXI_READ | Non-OKAY read response |
| 5 | AXI_WRITE | Non-OKAY write response |
| 6 | AXI_PROTOCOL | Unexpected ID/beat count/RLAST or impossible response sequencing |
| 7 | ARITHMETIC | Checked accumulation, scaling or reduction overflow |
| 8 | NO_PROGRESS | Active watchdog expired |
| 9 | LOCAL_STATE | FIFO bounds, illegal internal state or ownership violation |
| 10 | RESET_CANCELLED | Active task invalidated by reset/transport epoch recovery |

FAULT_INFO bits1:0 are AXI response where applicable; bits3:2 direction
(0 internal, 1 read, 2 write); bits15:8 failing output lane 0..63 or 255 when
not applicable; other bits zero. FAULT_ADDRESS identifies the failing beat
or offending operand base; internal arithmetic uses zero. Deterministic
same-cycle first-fault priority is AXI_PROTOCOL, AXI_READ, AXI_WRITE,
LOCAL_STATE, ARITHMETIC, DESCRIPTOR, UNSUPPORTED, RANGE, NO_PROGRESS. Reset
cancellation does not overwrite a captured earlier fault. A fault during
ordinary abort converts the result to ERROR.

Reset or coordinated-flush cancellation with no earlier fault produces
RESULT_CODE=RESET_CANCELLED, FAULT_CODE=RESET_CANCELLED and the ERROR event
after safe transport recovery; an earlier fault instead retains ERROR and its
detail. Resource reset continues masking delivery until released. When PCLK
itself resets, the old shell result/token is lost: recovery generation/READY
reconciliation invalidates the software job, without inventing an old-token
IRQ in the new shell. Idle recovery never creates a failed job.

The watchdog counts HP active cycles without useful progress: descriptor or
operand bytes accepted, a pack/compute/requantization item retired, or a
response obligation completed. It resets on such progress and excludes global
administrative pause and terminal mailbox waiting. TIMEOUT_CYCLES is a
nonzero per-job snapshot. Expiry initiates fault/drain; it cannot invent R/B
responses or force independent DMA reset. A permanently stuck transport is
resolved by the existing SoC target guard or coordinated lifecycle recovery.

Ten 64-bit saturating per-job counters reset at accepted core launch:
ACTIVE_CYCLES, CLOCK_PAUSE_CYCLES, USEFUL_MACS, PACK_CYCLES,
LOCAL_BANK_STALL_CYCLES, DMA_READ_BYTES, DMA_WRITE_BYTES,
DMA_STALL_CYCLES, REQUANT_STALL_CYCLES and RETIRED_DESCRIPTORS, in that order
at offsets `0x080 + 8*i` (low then high). ACTIVE excludes clock pause and
includes normal scheduling/bus stalls. DMA bytes count actual transferred
lanes, including descriptors/parameters on reads and successful strobe bytes
on writes; erroneous transactions remain visible as traffic. USEFUL_MACS
counts unmasked mathematical MACs, including zero-valued operands. Stall
counters measure cycles with a ready work item blocked by that named
resource; categories may overlap and must not be summed as total latency.

PERF_CONTROL.SNAPSHOT requests an atomic HP capture while a job is active, or
copies the retained terminal counters while idle. One request may be pending;
another returns PSLVERR. PERF reads return the previous bank while SNAP_BUSY;
capture completion replaces all pairs and job/generation together, sets
SNAP_VALID and clears SNAP_BUSY. A new request clears VALID until completed.
Terminal completion latches final counters separately and MUST NOT overwrite
the publicly readable PERF bank. That bank changes only on an explicit
snapshot or reset, preventing a low/high tear at terminal publication.
Terminal transfer waits behind an already accepted snapshot transaction.
Reset cancels a pending capture and invalidates it. Snapshot payload is held
stable; independent synchronizers for counter bits are prohibited. The
single-submitter HAL serializes snapshot requests and reads only after VALID
with BUSY clear, checking job/generation. Before any job, an idle snapshot
returns zero counters with RESULT_VALID=0 and is not execution evidence.

NPU admission/bounds checks and SoC owner routing provide programming and
recovery discipline, not security isolation. There is no security promise
for hostile descriptors, arbitrary MMIO writers, external-memory contents,
confidential model weights, fault attacks, or safety-critical inference.
No security features are added as a commercial roadmap requirement.

## MVP and Commercial-grade Roadmap

The complete MVP consists of Phases 0-6 below: all specified operators,
independent TFLite compilation, static bare-metal deployment, private DMA,
IRQ/lifecycle, local storage and the evidence in the companion. The fixed KWS
graph includes Conv10x4/stride2, four DW3x3/PW1x1 pairs, whole-input average,
FC64-to-12 and CPU integer Softmax. It reuses the frozen source model and
1000-input corpus definitions without changing APU. VWW uses the MLCommons
Tiny MobileNetV1 alpha0.25, 96x96x3, two-class model.

P0 resolves immutable VWW binary/evaluation-corpus hashes and the missing local
KWS checkout through the repository dependency setup flow. The current lock
already selects MLCommons Tiny revision
`4addd0fa08d216e20637637874e084895f289da4`; inspect its assets before adding
any further lock entry. No hash, source checkout, trained model or successful
acceptance result is invented by this freeze. This is an explicit P0 evidence
task, not an open architectural alternative. Its completion gates P0 exit and
full-model claims. Microarchitecture unit feasibility does not require a
downloaded evaluation corpus.

At 72 MHz, 64 MAC/cycle gives a theoretical 4.608 GMAC/s or 9.216 GOPS when
multiply/add count separately. Scalar requantization, eight-lane depthwise,
small FC, gather transpose, memory traffic and tails reduce utilization.
Neither continuous 64-MAC activity nor a vendor-equivalent model rate is
promised. Qualification requires architecturally counted traffic and cycles,
cycle-derived modeled latency, the two-model 2x target, bit-exact supported
semantics and IHP130 synthesis/timing evidence. If an approved target is
missed, report it and return an architecture/performance change for approval;
do not silently change array/store size, the model, baseline, precision or
acceptance corpus.

The post-MVP target preserves this separation of an independent compiler,
versioned jobs, local tensor storage and autonomous memory transfers. Future
separately frozen increments may add cross-layer fusion, more efficient
depthwise execution, multiple outstanding IDs, 128/256-lane variants with
larger SRAM, Linux deployment, ONNX, and optional AXI4-Stream ingestion.
They require measured bottleneck evidence and their own compatibility and
validation scope. No future variant is advertised by MVP capability bits.
Low-power/Q-channel and security features remain non-goals.

## Verification and Software Validation

[npu-verification.md](npu-verification.md) supplies the normative matrix,
asset gates, representative cases, baseline timing definition and commands.
All requirements above need linked evidence before qualification. Simulation
must execute production datapath and DMA, not a verification-only neural
backend hidden behind a production shell.

P0 provides an independent scalar numerical oracle and compiled-job executor.
Compare every supported intermediate tensor, not merely top-1 labels. Host
runs use the full qualified corpora; the P5 dual-simulator RTL runs use ten
deterministic samples per model plus directed numerical/tiling cases. P6 runs
both complete corpora on the full PRODUCT Verilator model through the real HP
software, private DMA and production datapath. Missing assets or tools cannot
become passing skips in an acceptance invocation. Ordinary optional repository
tests may retain their existing behavior without being cited as model
acceptance.

New host C follows the current MISRA C:2012 Amendment 2 policy and approved
deviation procedure; this freeze adds no deviations. Host logic, HAL errors,
wire parsing, finite waits and cache ownership are tested separately from
device timing. Formal proves bounded protocol/state properties with explicit
environment assumptions, not universal neural arithmetic or unbounded AXI
liveness. The smallest appropriate unit checks precede SoC/full-regression
checks. Warning baselines and observe-mode metric policy remain unchanged.

## Synthesis, Timing, and Physical Evidence

Use committed `configs/ci/ihp130.mk` as the initial PRODUCT integration
baseline, with EXT_CLK_HZ=72000000, 32 KiB system SRAM and HP enabled. The NPU
adds sixteen IHP130 `RM_IHPSG13_1P_1024x32_c2_bm_bist` macros through the
existing technology wrapper. Do not infer a flip-flop substitute or count
the system's SRAM as NPU storage. No new profile is necessary for the initial
phases; when integrated, the MVP feature is present in PRODUCT with truthful
capability. A shell-only phase must remain unable to claim executable NPU.

The HP target period is `1000000000/72000000` ns (approximately 13.888889 ns).
PCLK remains independently constrained by the platform clock inventory,
including its existing 48 MHz STA requirement. Add the HP native compute and
PCLK/HP CDC boundaries to generated timing/CDC inputs; do not reuse a
PCLK-clocked accelerator constraint for the MAC array. Actual macro, library,
clock uncertainty and slow-corner reports determine feasibility.

Report standalone NPU and integrated PRODUCT area/cells, all SRAM macro
counts, WNS/TNS, unconstrained endpoints, synthesis warnings and actual
mapped storage. Required timing qualification has no negative setup slack
or negative total setup slack at the approved core corner and no unexpected
unconstrained paths, latches or black boxes. A missed target blocks the
corresponding qualification; no IHP130 area budget is fabricated in advance.

Run firmware, Verilator/Icarus directed/product simulations, dedicated formal
targets, Yosys synthesis, OpenSTA and actual NPU-executing netlist tests.
Boot-only netlist output is not NPU execution evidence. Hosted
`_regression.yml` currently uses `--behavioral-only` and `formal-doctor`;
local/full flows must supply missing synthesis, netlist, STA and proof results.
The frozen current CI policy is not changed by this document.

Generic macro simulation and core STA are not package/board, extracted timing,
clock-tree, DFT, memory BIST, silicon, power or PVT signoff. SRAM BIST pins in
the current wrapper do not themselves implement a qualified MBIST system.
Other PDK regressions retain their actual macro/model availability and report
gaps, particularly ICS55 commercial models, instead of claiming equivalent
physical qualification. Power/activity reports may characterize consumption;
they do not authorize adding excluded power-management features.

## Development Order

Phase identifiers and the exact `Phase N - Title` headings below are stable.
Do not rename, renumber, or reuse them; append a newly approved phase if work
must be inserted later. P0-P6 form the approved MVP, not permission to execute
all phases in one implementation request. Every phase starts with its own
preflight. The future filenames below identify delivery ownership, not files
claimed to exist at freeze.

### Phase 0 - Workload and Numerical Contract

ID: `NPU-P0`. Dependency: this approved design freeze.

- Create the host numerical reference, descriptor/parameter validator,
  compiled-job functional executor and deterministic model/corpus manifests.
  Resolve asset/source hashes through the locked setup flow and reuse existing
  KWS definitions without modifying APU semantics.
- Extract operator/quantization data for both binary models; prove lowering
  including Conv10x4, global pool and CPU Softmax. Report K slices, raw/packed
  memory peaks, lane tails, traffic and reference intermediate hashes.
- Add host/Python tests and necessary reviewed dependency-lock/setup changes
  only. No production RTL, topology, register, clock or IRQ changes occur.
- Run Python lint/Pytest and affected dependency/setup checks; host C numerical
  helpers also require C format/policy/host tests. Exit only with all required
  assets fixed, supported intermediate outputs exact, and legal bounded
  allocations for both graphs. Missing model/corpus is BLOCKED, not replaced.

### Phase 1 - Banked Memory and Compute Feasibility

ID: `NPU-P1`. Dependency: P0 numerical and packing contracts.

- Implement isolated production-intent memory, patch packer, array,
  accumulator contexts, depthwise/vector and requantizer modules under owned
  RTL, plus standalone test/filelist/synthesis harnesses.
- Verify numerical profile, synchronous single-port storage, ownership,
  reductions/tails, scalar-drain pressure and actual sixteen-macro mapping.
  Complete isolated IHP130 synthesis and 72 MHz STA before platform expansion.
- No SoC address/resource/IRQ or public register behavior changes. Run
  affected RTL format/style/lint, two-simulator unit cases, host oracle tests,
  isolated synthesis/STA and their warning review. Exit with bit-exact modules
  and measured macro/timing feasibility; a failure returns to design review.

### Phase 2 - SoC Control and Resource Integration

ID: `NPU-P2`. Dependency: P1 feasibility acceptance.

- Add APB shell, CDC/epoch/lifecycle, source-9 interface, resource/IRQ routing,
  monitor/topology/HAL metadata and handwritten register parity. Inactive
  production DMA is tied safely idle until P3; test masters remain test-only.
- Extend generator credit/priority/policy and fixed-width assertions together;
  record clock/reset crossings and distinguish clock pause from resource
  quiesce. Preserve all prior identities and MPW compatibility.
- This phase changes APB/address/resource/IRQ and clock/reset/CDC integration;
  these changes require the normal human preflight gate. It does not advertise
  EXECUTION_READY or model inference.
- Run topology/extension/clock inventory checks, register/HAL tests,
  resource/IRQ/fabric regressions, affected firmware/RTL simulations and CDC
  adversarial cases. Exit with correct source credit/routing, no prior-ABI
  regression, atomic shell behavior and no false readiness.

### Phase 3 - Private DMA and Job Execution

ID: `NPU-P3`. Dependency: P2 integration and P1 compute modules.

- Implement production descriptor fetch/validation, byte-edge and 2D gather
  DMA, scheduler transport ownership, errors, watchdog, cancel/drain/flush
  and snapshots. Integrate the HP-native master with no payload width/CDC
  bridge and no central-DMA channel allocation.
- Exercise transport and already implemented numerical blocks through the
  real descriptor path; model-wide EXECUTION_READY stays zero until P4.
  Test-only sinks may check transport but are not inference evidence.
- Run dedicated AXI randomized/error/lifecycle tests and bounded formal
  targets, RTL/software checks, integration firmware/simulation and updated
  synthesis/STA. Exit with no lost beats, no pre-B completion, no orphan
  transactions and correct clock-pause/resource-reset collision behavior.

### Phase 4 - Complete MVP Operator Pipeline

ID: `NPU-P4`. Dependency: P3 transport acceptance.

- Complete all opcodes, checked K-slice accumulation, scalar/vector numerics,
  parameter streaming, packing reuse and load/compute/store overlap on the
  production datapath. Enable only fully verified capability bits.
- Run descriptor-level differential tests, randomized shapes and numeric
  edges, both RTL simulators, resource/CDC regressions and updated synthesis,
  timing and formal checks. All opcode/record/numeric ABIs remain unchanged.
- Exit with the complete supported operator mask, executable capability,
  truthful counters and bit-exact supported intermediate tensors, including
  the fixed models' operator shapes.

### Phase 5 - Offline Compiler and Bare-Metal Deployment

ID: `NPU-P5`. Dependency: P4 and P0 locked inputs/oracle.

- Implement deterministic TFLite import, target IR, allocation, bounded tile
  choice, independent packing/artifacts and static C execution plan. Complete
  the public HAL, CPU Softmax and bare-metal integration for both harts.
- Extend existing supported application composition for NPU acceptance; do
  not silently add an unsupported APP or Linux ABI. Unsupported models fail
  with placement/constraint diagnostics, never hidden CPU fallback.
- Run host compiler/HAL/parity tests, C quality gates, affected firmware and
  complete production-DMA model simulations against intermediate references.
  Exit with both reproducible deployments and explicit preprocessing/CPU
  costs. Hardware/wire ABI and resource allocation remain fixed.

### Phase 6 - MVP Qualification and Delivery

ID: `NPU-P6`. Dependency: P5 functional deployment.

- Complete the companion matrix, fixed corpora, competing-master performance,
  full-corpus PRODUCT Verilator runs, NPU and PRODUCT synthesis/STA, actual NPU
  netlist workloads, warning review, formal results and release/readiness
  traceability.
- Run supported PR/nightly matrices without treating hosted behavioral-only
  results as physical evidence. Publish per-model architectural cycles,
  cycle-derived modeled latency, traffic and stalls, both >=2x qualifications,
  and remaining PDK/board gaps. Simulator host runtime is not model latency.
- Exit with linked evidence for every MVP requirement, no acceptance skips,
  correct release manifests and an honest maturity label. Unmet functional,
  performance or timing criteria leave P6 incomplete; commercial physical
  signoff below is not implied by MVP completion.

## Commercial Delivery Gaps

All implementation evidence is pending at this design freeze. Following MVP,
reusable protocol VIP/coverage closure, production CDC/RDC review, DFT and
memory-test integration, SRAM repair strategy if needed, extracted MMMC,
clock-tree/hold closure, floorplan/package/board constraints, FPGA prototype
and board execution, PVT power/activity, release reproducibility and silicon
characterization still require evidence.
No safety/security, coherent-memory or low-power claim follows from these
functional phases. Future architecture changes and Linux/framework deployment
require separate approved specifications or appended phases.

This refreeze does not reopen P0-P5 or change their evidence contracts. The
next implementation preflight is exactly
`NPU-P6 / Phase 6 - MVP Qualification and Delivery`, using this document and
the verification companion. It must not add FPGA as a hidden prerequisite or
weaken the full-corpus, 2.0-times, formal, netlist, synthesis, timing, or
regression gates.
