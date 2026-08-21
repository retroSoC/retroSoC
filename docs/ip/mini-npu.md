# Mini NPU Commercial Reference Survey

## Status and Scope

This document evaluates commercial SoCs as system-level references for an
optional retroSoC Mini AI accelerator. It is a roadmap study, not an
implemented RTL, register ABI, performance claim, or supported build profile.
The base Mini product does not require an NPU. Any derivative that adopts this
study should be identified separately, for example as `Mini-AI`, so that the
base product remains below Std in memory bandwidth, area, power, and software
complexity.

The executable Mini baseline remains defined by the committed configuration,
address map, topology, and RTL. In particular:

- the system fabric has 32-bit address and data paths;
- each master may own at most one read and one write transaction;
- the committed system clock is 72 MHz, giving a theoretical 288 MB/s fabric
  payload rate before arbitration, protocol overhead, and target stalls;
- external-memory front ends currently serialize accepted AXI4 bursts into
  ordered scalar engine operations; and
- the current address map exposes 128 KiB of on-chip SRAM and a 64 MiB SDRAM
  window, while the planned Linux product target is 64-128 MiB of main memory.

These constraints make local data reuse more important than peak arithmetic
throughput. A large MAC array without banked local SRAM, layer fusion, and
native external-memory bursts would spend most of its time waiting for data.

## Evaluation Criteria

Commercial devices were selected for similarity along one or more of these
axes:

- one lightweight Linux application processor plus a separately controlled
  MCU or management processor;
- 64-256 MiB-class product memory rather than desktop-class DDR capacity;
- approximately 0.5-1 TOPS of advertised INT8 inference performance;
- low-cost packaging and embedded vision, audio, gateway, or HMI use cases;
- a documented local-buffer, DMA, streaming, compiler, or Linux-driver model;
  and
- enough public material to separate verified features from inference.

Vendor TOPS figures are not directly comparable. They may count one multiply
and one addition as two operations, assume a particular precision, sparsity,
clock, or layer shape, and exclude memory stalls. End-to-end model latency,
external-memory traffic, MAC utilization, accuracy after quantization, and
energy per inference are more useful acceptance metrics.

## Commercial References

| Priority | Commercial SoC | Publicly documented characteristics | Relevant lesson for Mini | Important mismatch |
| --- | --- | --- | --- | --- |
| 1 | Rockchip RV1106B | One Cortex-A7 application core, an MCU, a 0.5 TOPS INT8 NPU, 512 Mbit to 2 Gbit embedded DDR, and an 88-pin QFN package. See the [RV1106B product page](https://www.rock-chips.com/a/en/products/RV11_Series/2025/1208/2122.html). | Closest product-scale reference for a low-memory Linux processor, management MCU, small NPU, and compact package. | The ISP, codec, CPU frequency, memory subsystem, and proprietary fourth-generation NPU are substantially stronger than the current Mini baseline. |
| 2 | Allwinner V851S / V853 | V853 combines a Cortex-A7 Linux core, a RISC-V XuanTie E907 MCU, and a 1 TOPS INT8 NPU. Its public NPU guide identifies a 128 KiB internal cache. See the [V853 product page](https://www.allwinnertech.com/index.php?a=index&c=product&id=117) and [NPU guide](https://docs.aw-ol.com/v853/en/npu/dev_npu/). Public V851S ecosystem material describes a lower 0.5 TOPS, 64 MiB DDR2 variant. | Best heterogeneous lifecycle reference: the MCU handles low-power and control work while Linux uses a separately accelerated application domain. The 128 KiB NPU-local storage point is especially relevant. | Detailed NPU microarchitecture is not public, and the integrated camera and video pipeline is outside the defining Mini scope. Public V851S evidence is less authoritative than the V853 vendor material. |
| 3 | CVITEK CV1800B | RISC-V application and real-time cores, 64 MiB SiP DRAM, and an advertised 0.5 TOPS INT8 TPU. See the [CV1800B overview](https://milkv.io/chips/cv1800b), [SOPHGO CV180x/CV181x software documentation](https://doc.sophgo.com/cvitek-develop-docs/master/docs_latest_release/CV180x_CV181x/en/), and [Milk-V Buildroot SDK](https://github.com/milkv-duo/duo-buildroot-sdk-v2). | Closest RISC-V Linux, low-memory, low-cost TPU reference. Its separate TPU/TDMA software model and public Linux integration are useful for driver, reserved-memory, and model-deployment work. | The CPU is RV64, the multimedia subsystem is larger, and public compiler/runtime sources do not disclose a reusable TPU RTL implementation. |
| 4 | Kendryte K210 | A fixed-function KPU for convolution, batch normalization, activation, and pooling; DMA and direct camera input; 6 MiB general SRAM plus 2 MiB AI SRAM. See the [K210 functional description](https://github.com/kendryte/kendryte-doc-datasheet/blob/master/en/003.md) and [K210 product page](https://www.kendryte.com/product/kendryteai). | Strong reference for a simple first-generation accelerator in which dedicated local SRAM and a direct sensor data path matter more than a sophisticated coherent fabric. The associated [nncase compiler](https://github.com/kendryte/nncase) also demonstrates static allocation and quantized model lowering. | It is an older MCU-oriented design, its KPU has restrictive operator and model rules, and it is not a modern MMU-Linux reference. Its 28 nm memory budget must not be projected onto IHP130 or GF180 without physical evidence. |
| 5 | ST STM32N6 | A 600 GOPS Neural-ART accelerator, about 300 configurable MAC units, 4.2 MiB contiguous SRAM, streaming execution, an internal cache, and two 64-bit AXI memory ports. See the [STM32N6 overview](https://www.st.com/en/microcontrollers-microprocessors/stm32n6-series.html), [NPU introduction](https://www.st.com/resource/en/product_presentation/st-neural-art-accelerator-introduction.pdf), and [ST architecture discussion](https://blog.st.com/stm32n6/). | Useful upper reference for stream processing, layer fusion, local caching, camera-to-NPU integration, and the importance of memory bandwidth even in an MCU-class product. | Its RAM capacity, dual 64-bit interfaces, CPU frequency, process, and multimedia blocks are well beyond Mini. It should guide dataflow, not set Mini's throughput target. |
| 6 | NXP i.MX 93 | Linux Cortex-A55 application cores, a Cortex-M33 real-time processor, and a 0.5 TOPS Arm Ethos-U65 microNPU. See the [i.MX 93 product page](https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/i-mx-applications-processors/i-mx-9-processors/i-mx-93-applications-processor-family-arm-cortex-a55-ml-acceleration-power-efficient-mpu%3Ai.MX93) and [family fact sheet](https://www.nxp.com/docs/en/fact-sheet/iMX93FAMFS.pdf). | Best higher-end reference for Linux driver integration, management-processor ownership, low-power wake-word use, security domains, product lifecycle, and a stable microNPU software contract. | Its coherent 64-bit application platform and DDR subsystem are not physical or performance peers for Mini. |

The recommended product reference combination is therefore:

- RV1106B for package, memory, and product-scale constraints;
- V851S/V853 for Linux-plus-management-MCU ownership;
- CV1800B for low-memory RISC-V Linux deployment and TPU/TDMA software
  organization;
- K210 for explicit AI SRAM and sensor-to-accelerator dataflow;
- STM32N6 for streaming, fusion, and local-cache bandwidth reduction; and
- i.MX 93 for driver, isolation, recovery, and long-lived software contracts.

BL808 is relevant to the wider Mini heterogeneous architecture, but the public
NPU information and tooling are too incomplete to make it a primary NPU design
reference. Multi-TOPS devices such as K230, RK3568-class application
processors, and desktop-oriented accelerators assume memory bandwidth and
software complexity that belong in retroSoC Std or Pro.

## Recommended Mini-AI V1 Direction

The first implementation should be a small, parameterized integer inference
engine rather than an attempt to match the commercial devices' headline TOPS.
The following values are design-exploration starting points, not frozen
requirements:

| Area | Initial direction | Rationale |
| --- | --- | --- |
| Arithmetic | INT8/UINT8 operands with INT32 accumulation; no FP16 in V1 | Matches the useful precision of the closest commercial references while containing area and verification scope. |
| Array | Parameterized 8 by 8 MAC array; evaluate 16 by 16 only for a qualified denser process | Sixty-four MACs are a tractable IHP130 exploration point. Array size must remain independent of the software ABI. |
| Local memory | At least 128 KiB of banked SRAM, with weight, activation, and accumulator allocation selected per layer | A 32-bit system bus cannot feed the MAC array every cycle. Banked SRAM and tiling are mandatory architectural components, not optional optimizations. |
| Scheduling | Decoupled load, compute, and store engines with double buffering | Allows central DMA traffic to overlap computation and matches the reusable lesson from commercial streaming NPUs. |
| Operators | 1 by 1 and 3 by 3 convolution, depthwise convolution, GEMM/fully connected, add, ReLU-class activation, pooling, and requantization | Covers a useful quantized CNN subset while leaving uncommon operations to the CPU. Winograd, sparsity, and dynamic shapes should wait for workload evidence. |
| Control | APB4 configuration, capability discovery, versioned command descriptors, aggregate interrupt, timeout, abort, and reset | Fits the existing Mini control plane and permits a stable Linux and firmware contract. |
| Data | One framed 32-bit AXI4-Stream input and output, initially fed by central DMA; optional direct DVP input after arbitration and backpressure are verified | Reuses the existing non-coherent DMA and stream infrastructure without immediately adding another fabric master. A later native AXI4 master requires a deliberate interconnect revision. |
| Coherency | Explicit CPU cache clean/invalidate and owned-buffer transitions | The planned Linux configuration has no hardware I/O coherency. The driver must not hide this limitation. |
| Lifecycle | Hazard3 owns NPU clock, reset, bus admission, fault capture, and forced recovery; Linux owns job submission only | Preserves Mini's defining trusted-management model and prevents a failed Linux or NPU job from taking final lifecycle control. |

At 72 MHz, an 8 by 8 array has a 9.216 GOPS arithmetic ceiling if one MAC is
counted as two operations. This is intentionally far below commercial
marketing figures. A useful V1 result is sustained end-to-end acceleration of
selected models with bounded memory traffic, not a nominal TOPS target that
the existing memory system cannot sustain.

## Integration Prerequisites

Before an NPU becomes a supported Mini feature, the project should complete
all of the following:

1. Implement and verify native cache-line bursts in the selected external
   memory controller. Measure sustained bandwidth under CPU, display, storage,
   and NPU contention.
2. Select qualified SRAM macros and characterize the bank count, port width,
   area, timing, leakage, and test strategy independently for every target
   PDK.
3. Extend the canonical address map, interrupt topology, DMA request ownership,
   SYSCTRL lifecycle controls, firewall rules, performance counters, and fault
   records from their generated sources of truth.
4. Define a versioned command format and Linux UAPI before freezing the RTL.
   Buffer ownership, cancellation, timeout, cache maintenance, and recovery
   must be explicit.
5. Provide an offline model compiler that imports at least ONNX or TFLite,
   performs calibration and INT8 quantization, tiles tensors into local SRAM,
   fuses supported operators, emits a versioned binary, and reports every CPU
   fallback.
6. Validate representative vision and audio models in a cycle-accurate model,
   FPGA prototype, RTL simulation, synthesis, and post-layout memory-bandwidth
   analysis before publishing performance or energy claims.

## Open Microarchitecture References

Commercial SoCs establish product expectations but do not provide reusable
NPU RTL. Microarchitecture work should therefore also study transparent
implementations:

- [Gemmini](https://github.com/ucb-bar/gemmini) for decoupled
  load/execute/store control, a parameterized systolic array, private
  scratchpad SRAM, and a separate accumulator;
- [NVDLA](https://nvdla.org/hw/v1/hwarch.html) for a configurable small
  convolution pipeline, banked convolution buffer, fused activation/pooling,
  and explicit memory-bandwidth tradeoffs; and
- [VTA](https://tvm.apache.org/2018/07/12/vta-release-announcement.html) for a
  compact tensor instruction stream and end-to-end compiler/runtime
  co-design.

These are reference starting points, not drop-in Mini IP. Their native CPU
coupling, bus protocol, generated RTL, verification assumptions, SRAM ports,
licenses, and toolchains require separate review before reuse.
