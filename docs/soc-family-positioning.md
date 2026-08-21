# retroSoC Family Product Positioning

## Status and Scope

This document defines the intended Tiny, Mini, Std, and Pro product ladder.
It is a product roadmap, not a statement of implemented repository support.
The current build system accepts only `SOC=MINI`, and the committed Mini
profiles remain the executable source of truth.

Mini is the family anchor. It establishes the common product model: an open
RISC-V SoC in which a small, always-available Hazard3 management core owns
trusted boot, reset, bus admission, shutdown, and fault recovery. Higher tiers
add application processors and accelerators without transferring final
lifecycle control to Linux. Tiny reduces this model to an MCU-class device and
does not require a separate application processor.

All frequencies, memory sizes, bus widths, accelerator rates, and software
features below are product targets. They require separate RTL integration,
driver enablement, verification, and physical qualification before they can be
advertised for a device or PDK.

## Product Ladder

| Tier | Product role | Compute topology | Primary software | Defining boundary |
| --- | --- | --- | --- | --- |
| Tiny | Low-power MCU and edge-connectivity endpoint | One Hazard3 MCU core | Bare metal or RTOS | No MMU or external DRAM dependency |
| Mini | Low-cost heterogeneous RV32 Linux control SoC | Hazard3 management core plus one RV32 VexiiRiscv Linux core | Embedded Linux plus management firmware | Lightweight Linux and basic HMI, without a desktop-class accelerator requirement |
| Std | Heterogeneous RV32 graphical Linux edge SoC | Hazard3 management core plus VexiiRiscv performance and efficiency cores | Graphical Linux plus RTOS firmware | Full AXI4 memory fabric, GPU, audio, and AI acceleration |
| Pro | Highest-performance and only RV64 family tier | Hazard3 management core plus four coherent RV64 VexiiRiscv Linux cores | RV64 graphical Linux | Coherent SMP, high-bandwidth memory, GPU, NPU, and video codecs |

The VexiiRiscv targets rely on the upstream core's documented RV32/RV64,
single/dual-issue, cache, Sv32/Sv39, AXI4, and Linux capabilities. The exact
[VexiiRiscv](https://github.com/SpinalHDL/VexiiRiscv) revision and generated
configuration must be locked and verified before integration.

The names describe capability tiers, not die-size derivatives. In particular,
Tiny is not a Mini with features disabled, and Std is not a Mini that merely
adds a GPU. Their memory systems, power targets, software contracts, and
verification requirements differ materially.

## Tiny: Low-Power MCU and Edge Connectivity

### Position

Tiny serves battery-powered sensors, actuators, metering, low-power industrial
nodes, protocol bridges, and smart-home edge endpoints. It is MCU-first: boot
latency, sleep behavior, deterministic I/O, security, package cost, and usable
energy per event take precedence over Linux compatibility.

Tiny has two productization profiles:

- **Tiny-MCU** contains no radio and targets wired control or products that do
  not need connectivity on every unit.
- **Tiny-Connect** provides Bluetooth Low Energy and IEEE 802.15.4 capability.
  The open digital-RTL baseline should expose a qualified SPI or SDIO host,
  interrupt, reset, wake, and power-sequencing interface to a certified radio.
  On-die or co-packaged RF becomes a product option only after suitable RF IP,
  analog integration, PDK support, and regulatory qualification exist.

Wi-Fi 6 is an optional upper Tiny-Connect SKU rather than a baseline
requirement. This avoids imposing its RF, memory, and active-power costs on
802.15.4 and Bluetooth endpoint products.

### Recommended Architecture

| Area | Product target |
| --- | --- |
| CPU | One Hazard3 RV32IMAC core at 64-160 MHz, subject to PDK qualification |
| On-chip memory | 256-512 KiB banked SRAM, boot ROM, and 8-32 KiB retention SRAM |
| Code storage | QSPI flash with execute-in-place and authenticated recovery boot |
| Memory model | No MMU and no external DRAM dependency |
| Interconnect | 32-bit RIB; bounded `INCR4` support for DMA and XIP, without a full AXI4 fabric |
| Software | Freestanding SDK, bare metal, and Zephyr- or FreeRTOS-class RTOS ports |
| Low power | Clock gating, switchable SRAM banks, RTC/event wake, retention, and a separately measured deep-sleep state |
| Security | Immutable boot root, signed boot, OTP key material, PMP, TRNG, and symmetric/hash acceleration |
| Edge I/O | UART, SPI, I2C, PWM, ADC, I2S/PDM, USB full speed, and CAN FD selected by package profile |

No power-current number should be published until it is measured on a
qualified physical implementation with the wake sources and retention state
specified. Tiny's acceptance criteria should include sleep-to-active latency,
energy per sensing/reporting cycle, and certified-radio interoperability, not
only CPU benchmarks.

### Commercial Reference Points

| Commercial SoC | Relevant axis | Position relative to Tiny |
| --- | --- | --- |
| [Espressif ESP32-H2](https://www.espressif.com/en/products/socs/esp32-h2) | Low-power RV32 MCU with Bluetooth LE and IEEE 802.15.4 | Primary Tiny-Connect endpoint and Thread/Zigbee market reference |
| [Espressif ESP32-C6](https://www.espressif.com/en/products/socs/esp32-c6) | RV32 high- and low-power cores with Wi-Fi 6, Bluetooth LE, and IEEE 802.15.4 | Upper connectivity reference; RF and protocol integration are well beyond a radio-companion Tiny baseline |
| [Raspberry Pi RP2350](https://www.raspberrypi.com/products/rp2350/) | Dual Hazard3 option, 520 KiB SRAM, security, USB, and programmable I/O | Closest open-core MCU and deterministic-I/O reference, without integrated radio |
| [ST STM32U5](https://www.st.com/en/microcontrollers-microprocessors/stm32u5-series.html) | Ultra-low-power secure MCU family with large embedded memory and graphics options | Energy-efficiency, security, and industrial MCU ecosystem reference rather than an ISA-equivalent peer |

Tiny-MCU should be compared primarily with RP2350 and lower-memory STM32U5
devices. Tiny-Connect should be compared with ESP32-H2; ESP32-C6 is the upper
feature reference when Wi-Fi is included.

## Mini: Family Anchor

### Status and Position

retroSoC Mini is currently an open-source RISC-V microcontroller-class SoC
with a fixed Hazard3 management core and one software-selected user core. The
planned Linux-capable configuration adds a 32-bit VexiiRiscv user core. The
VexiiRiscv integration and Linux boot flow are product targets, not supported
repository configurations yet.

Mini is the price, complexity, and Linux-capability anchor for the family. It
targets industrial control, protocol gateways, compact human-machine
interfaces, and retro multimedia systems that need Linux but do not need a
desktop-class graphics pipeline. Hazard3 remains the trusted management core,
and one RV32 VexiiRiscv application core runs Linux in the planned
configuration.

The product target starts at 64 MiB of external SDRAM, with 128 MiB preferred.
A simple display controller or framebuffer is compatible with the Mini
position, but a 3D GPU, NPU, coherent multiprocessing, and a full graphical
desktop are deliberately outside the defining Mini requirements. This keeps
Mini below Std in memory bandwidth, software complexity, die area, and power.
Mini is not intended to compete with general-purpose Linux application
processors that require RV64, cache-coherent multiprocessing, or
high-bandwidth DDR interfaces.

An optional NPU derivative may be explored separately as Mini-AI without
changing the base Mini requirements. The commercial survey, memory-system
constraints, and initial accelerator direction are recorded in
[Mini NPU Commercial Reference Survey](ip/mini-npu.md). No NPU is implemented by
the current Mini profiles.

### Current Mini Baseline

The current executable RTL and generated integration inputs define these
capabilities:

- A fixed Hazard3 management core owns system control and has a permanent JTAG
  Debug Module.
- The C0-C5 extension fabric permits one selected user core to run at a time.
- SYSCTRL controls user-core selection, reset, interrupt admission, and bus
  admission. A stop request blocks new user transactions, drains an accepted
  transaction, and then asserts reset.
- The canonical address map exposes 128 KiB of on-chip SRAM, a 32 MiB SDRAM
  window, and an 8 MiB PSRAM window. Address-window capacity does not guarantee
  that every implementation includes the corresponding physical memory.
- AXI4 is the active 32-bit interconnect. It supports linear one- through
  sixteen-beat transfers, one transaction per master, and concurrent accesses
  to different targets.
- Current external-memory targets serialize accepted AXI4 bursts into ordered
  scalar engine accesses. They do not yet combine a burst into a native SDRAM,
  PSRAM, flash, or SPI-SD physical transaction.

The generated address map, user-extension map,
[AXI4 contract](axi4-interconnect.md), and retained
[RIB protocol contract](rib-interconnect.md) remain the integration references
for the implemented baseline.

### Planned Linux Configuration

The Linux configuration keeps Hazard3 as the always-available trusted
management core and adds VexiiRiscv as the application processor. Hazard3 is
responsible for clock and memory initialization, image selection, VexiiRiscv
boot release, fault recovery, and final power-state control. Linux must not be
able to reconfigure the management-core lifecycle controls.

The initial VexiiRiscv configuration should provide:

- RV32IMAC with machine, supervisor, and user modes.
- Sv32 virtual memory, hardware page-table walking, and the privileged CSRs
  required by the supported Linux kernel.
- LR/SC atomics, separate 16 KiB instruction and data caches, and uncached MMIO
  regions.
- A PLIC-compatible external interrupt controller, CLINT-compatible timer and
  software interrupts, and a deterministic reset vector.
- A documented DMA cache-maintenance contract unless the memory system supplies
  hardware coherency.

The management firmware initializes external memory, verifies and places the
OpenSBI firmware, device tree, kernel, and initial filesystem, programs the
VexiiRiscv entry point, and then enables its bus access and releases reset. A
normal stop first requests Linux shutdown through a mailbox. After Linux
acknowledges and flushes persistent data, the management core disables new bus
transactions, drains the final accepted transaction, and asserts reset. A
bounded timeout permits fault recovery through forced isolation and reset.

### Product Targets

The following values define a useful commercial target rather than an
implemented or cross-PDK guarantee:

| Area | Minimum target | Preferred target |
| --- | --- | --- |
| VexiiRiscv frequency | 150 MHz | PDK-qualified maximum above 150 MHz |
| Main memory | 64 MiB SDRAM | 128 MiB SDRAM |
| L1 caches | 16 KiB I-cache and 16 KiB D-cache | Same, with measured refill and DMA behavior |
| Memory transport | Native cache-line burst | Native burst with two to four outstanding transactions per master |
| Boot storage | SPI NAND or qualified SDIO path | SDIO/eMMC plus recovery image |
| Linux platform devices | UART, timer, interrupt controller, storage | Ethernet or USB selected by the product profile |

Meeting these targets requires enlarging the current 32 MiB SDRAM address
window and replacing the scalar external-memory bottleneck. A dedicated memory
fabric may evolve independently while APB4 and APB remain the stable peripheral
register interfaces. Frequency claims must be qualified separately for each
PDK and physical implementation.

### Commercial Reference Points

The products below are reference points along different axes. None is a
pin-compatible or performance-equivalent substitute for retroSoC Mini.

| Commercial SoC | Relevant architecture | Comparison with the planned Mini |
| --- | --- | --- |
| [Bouffalo Lab BL808](https://github.com/bouffalolab/bl808_linux) | RISC-V Linux application core with separate MCU and low-power cores | Closest RISC-V heterogeneous architecture; substantially stronger wireless, multimedia, memory, and application-core capability |
| [NXP i.MX 7ULP](https://www.nxp.com/products/i.MX7ULP) | Cortex-A7 Linux core and Cortex-M4 system master with boot and power-control responsibilities | Closest commercial lifecycle-control model; a much larger application-processor platform |
| [ST STM32MP151](https://www.st.com/en/microcontrollers-microprocessors/stm32mp151a.html) | Single Cortex-A7 Linux core and Cortex-M4 real-time core | Useful industrial heterogeneous-MPU reference; DDR, cache, interconnect, and peripheral capabilities are substantially higher |
| [CV1800B and SG2002](https://milkv.io/docs/duo/overview) | Two RISC-V application-class cores supporting Linux and real-time workloads, with 64 or 256 MiB SiP memory | Closest low-cost dual-system RISC-V market reference; 64-bit cores and multimedia acceleration place it above Mini |
| [Allwinner F133](https://www.allwinnertech.com/index.php?c=product&id=101) | RV64 C906 Linux processor with 64 MiB SiP DDR and display/video functions | Direct low-cost RISC-V Linux market reference without the same independent management-core model |
| [Allwinner F1C200s](https://www.allwinnertech.com/uploads/pdf/201812181725033b.pdf) | 32-bit ARM9 Linux processor with 64 MiB SiP DDR in a compact package | Closest cost, memory, and lightweight-Linux application reference, but without a separate management core |
| [Ingenic X1000/X1000E](https://www.ingenic.com.cn/products-detail/id-50.html) | 32-bit MIPS Linux processor with 32 or 64 MiB LPDDR and fast-boot positioning | Comparable low-power Linux product segment with much higher CPU frequency and a mature multimedia subsystem |
| [Espressif ESP32-P4](https://docs.espressif.com/projects/esp-techpedia/en/latest/esp-friends/get-started/board-selection.html) | Dual 32-bit RISC-V high-performance cores and a low-power core | Relevant core-topology and power-control reference, but not a direct general-purpose MMU Linux competitor |

The closest architectural reference points are BL808 and i.MX 7ULP. The
closest cost and lightweight-Linux reference is F1C200s, while F133 and
CV1800B represent the nearest commercial RISC-V Linux market. ESP32-P4 is a
control-topology reference rather than a Linux performance reference.

After the Linux configuration meets the memory and interconnect targets above,
retroSoC Mini should be positioned between F1C200s and BL808: less capable than
modern 64-bit multimedia SoCs, but differentiated by open RTL and explicit
management-core control over Linux-core boot, bus admission, shutdown, and
fault recovery.

## Std: RV32 Heterogeneous Graphical Linux

### Position

Std is the full-featured 32-bit Linux tier for industrial HMI, smart gateways,
edge AI terminals, audio products, robotics panels, and graphical embedded
systems. It retains a 32-bit software and address model while adding a
performance core, an efficiency/real-time core, a high-throughput memory
fabric, and production Linux drivers for its accelerators.

Std is not considered complete merely because a kernel reaches a shell. Its
product acceptance requires a hardware-accelerated graphical desktop, stable
shared-memory operation across CPU and accelerators, and a documented
management/real-time communication path.

### CPU and Lifecycle Topology

- The always-available Hazard3 management core owns root-of-trust boot, clock
  and reset sequencing, external-memory initialization, application-core bus
  admission, fault isolation, and final power-state control.
- The performance core is the highest configuration of RV32 VexiiRiscv that
  can be validated for the selected PDK: dual-issue in-order execution,
  RV32IMAFDC, selected ratified B extensions, machine/supervisor/user modes,
  Sv32, branch prediction, and separate 32 KiB instruction and data caches.
- The efficiency core is a single-issue RV32IMAC VexiiRiscv configuration with
  machine/user modes, PMP, and 8-16 KiB caches or tightly coupled memory. It
  omits the double-precision FPU and runs RTOS or dedicated real-time firmware.
- Linux runs on the performance core. The efficiency core is exposed through a
  documented remote-processor and mailbox/RPMsg-style lifecycle contract, not
  as an asymmetric Linux SMP hart.

The management core may stop either VexiiRiscv domain only after blocking new
transactions and draining accepted traffic. Linux or RTOS software may request
a lifecycle transition, but cannot override management-core access controls.

### AXI4 and Memory Contract

Std uses a 64-bit AXI4 memory fabric for CPUs, the memory controller, GPU, NPU,
display, audio, and high-bandwidth DMA. APB4 or APB remains suitable behind
bridges for low-bandwidth register peripherals.

The AXI4 implementation target includes:

- Independent read and write channels and aligned `INCR` bursts of up to 16
  beats for cache-line and DMA traffic.
- At least four outstanding reads and four outstanding writes for each
  high-bandwidth master, with four to eight transaction IDs available per
  master.
- Out-of-order completion across different AXI IDs while preserving ordering
  within the same ID and all applicable AXI4 ordering, exclusive-access, and
  response rules used by the software platform.
- Arbitration QoS, starvation bounds, transaction timeouts, address firewalls,
  per-master fault reporting, and a quiesce/drain interface for power control.

AXI4 does not itself provide cache coherency. The product target therefore adds
a 512 KiB shared system cache and an I/O-coherent port for GPU, NPU, display,
audio, and DMA traffic. An FPGA prototype may use explicit DMA cache
maintenance, but it must not be presented as the final Std shared-memory
contract.

### Graphics, Audio, AI, and Memory

| Area | Minimum product target | Preferred target |
| --- | --- | --- |
| Main memory | 512 MiB DDR | 1 GiB DDR, with 2 GiB as the validated product ceiling |
| GPU | 2D and 3D acceleration, DRM/KMS, Mesa, OpenGL ES 2.0 | OpenGL ES 3.x with sustained desktop composition |
| Display | One 1080p60 pipeline | 1080p60 display plus independent composition and scaling |
| Audio | DMA, I2S/TDM/PDM, hardware decoder or programmable DSP, ALSA ASoC | Concurrent playback, capture, mixing, and low-power decode |
| AI | 0.5 TOPS INT8 with a versioned Linux user ABI | 1 TOPS INT8 with a supported model-conversion flow |
| Storage and I/O | SD/eMMC, USB 2.0, and Ethernet | Gigabit Ethernet, PCIe or USB 3.0 selected by product package |

The graphical acceptance image should boot a maintained Linux kernel into a
Wayland/Weston desktop at 1080p60, exercise GPU rendering, play decoded audio,
run one NPU inference workload, and stress concurrent display, storage, and
network DMA without data corruption.

### Commercial Reference Points

There is no exact current commercial peer combining this feature set with an
RV32 application core. The references therefore cover architecture and product
capability along separate axes.

| Commercial SoC | Relevant axis | Position relative to Std |
| --- | --- | --- |
| [ST STM32MP157](https://www.st.com/en/microcontrollers-microprocessors/stm32mp157.html) | Dual 32-bit Cortex-A7, Cortex-M4, 3D GPU, display, and industrial I/O | Closest 32-bit heterogeneous graphical Linux architecture reference |
| [NXP i.MX 6SoloX](https://www.nxp.com/products/i.MX6SX) | Cortex-A9 Linux core, Cortex-M4 real-time core, and 2D/3D GPU options | Direct application-plus-real-time-core topology reference |
| [TI AM5728](https://www.ti.com/product/AM5728) | 32-bit application cores, MCU cores, DSP/vision engines, 2D/3D graphics, and Linux | Upper 32-bit heterogeneous multimedia and accelerator reference |
| [NXP i.MX 8M Plus](https://www.nxp.com/products/i.MX8MPLUS) | Linux cores, real-time core, GPU, audio DSP, NPU, video, and industrial networking | 64-bit feature-set reference for Std's graphics, audio, and AI integration, not a CPU-performance peer |

Std should be presented as a modern open-RISC-V interpretation of the
STM32MP157 and i.MX 6SoloX architecture, with AM5728-class heterogeneity and a
reduced i.MX 8M Plus-style accelerator set.

## Pro: RV64 Coherent Multimedia SoC

### Position

Pro is the only 64-bit retroSoC tier and the highest-performance device in the
current family. It targets graphical edge computers, industrial vision,
robotics, multimedia terminals, development boards, and systems that need more
than 4 GiB of directly addressable memory or a conventional RV64 Linux
distribution.

"Highest performance" is relative to the retroSoC family. VexiiRiscv's current
maximum configuration is dual-issue and in-order, so Pro must not be described
as performance-equivalent to modern wide out-of-order Cortex-A76/A78 or
desktop-class processors without measured evidence.

### CPU, Coherency, and Memory

- Hazard3 remains the isolated management and recovery core.
- The Linux application cluster contains four identical maximum-configuration
  RV64 VexiiRiscv cores with dual-issue in-order execution, RV64IMAFDC,
  selected ratified B extensions, machine/supervisor/user modes, and Sv39.
- Each application core has at least 32 KiB instruction and 32 KiB data cache;
  64 KiB of each is the preferred physical-design target.
- A 2 MiB shared coherent L2 cache and verified atomic, snoop, cache
  maintenance, interrupt, and TLB-shootdown behavior are mandatory for Linux
  four-hart SMP.
- The system uses a 128-bit coherent high-bandwidth fabric. Accelerators and
  bridges expose full AXI4 interfaces with multiple IDs, outstanding traffic,
  QoS, isolation, timeout, and lifecycle drain behavior.
- Main memory starts at 2 GiB DDR4 or LPDDR4, 4 GiB is preferred, and 8 GiB is
  the initial maximum validated configuration.

AXI4 compatibility at an IP boundary must not be confused with CPU cache
coherency. If the coherent fabric uses a different native protocol, its AXI4
bridges must preserve ordering, coherency attributes, fault isolation, and DMA
ownership semantics required by Linux drivers.

### Multimedia and AI Targets

| Area | Pro product target |
| --- | --- |
| GPU | 2D/3D GPU with upstreamable DRM/KMS and Mesa support, OpenGL ES 3.2, and Vulkan 1.2 |
| Display | 4K30 or two independent 1080p60 pipelines with composition and scaling |
| AI | 2-4 TOPS INT8 NPU with a versioned kernel and user-space ABI |
| Video | H.264/H.265 4K30 decode and 1080p60 encode, subject to IP and codec licensing |
| Audio | Multi-channel I2S/TDM/PDM, programmable DSP or decoder, and ALSA ASoC support |
| High-speed I/O | PCIe, USB 3.0, Gigabit Ethernet, SDIO/eMMC, and camera/display serial interfaces selected by package |

The product acceptance image should boot an RV64 Debian- or Ubuntu-class
distribution into a hardware-accelerated Wayland desktop, bring up all four
application harts, address more than 4 GiB when fitted, and concurrently stress
GPU, NPU, video, storage, and network traffic. A binary-only demonstration is
not sufficient for an open-SoC claim: redistribution terms and maintained
kernel/user-space integration must be documented for each licensed
accelerator.

### Commercial Reference Points

| Commercial SoC | Relevant axis | Position relative to Pro |
| --- | --- | --- |
| [StarFive JH7110](https://starfivetech.com/en/index.php?c=show&id=1&s=computing) | Quad RV64 Linux cores, coherent L2, 3D GPU, video codecs, and high-speed I/O | Closest RISC-V baseline for coherent SMP and graphical Linux |
| [T-Head TH1520 in BeagleV-Ahead](https://www.beagleboard.org/blog/2023-07-12-beaglev-ahead-announcement) | Quad RV64 application cores, auxiliary cores, GPU, 4 TOPS NPU, and multimedia | Upper RISC-V heterogeneous multimedia and AI reference |
| [Rockchip RK3568](https://www.rock-chips.com/a/en/products/RK35_Series/2021/0113/1276.html) | Quad 64-bit application cores, Mali GPU, NPU, video, and mature Linux products | Arm-market reference for integration, memory bandwidth, and software maturity |
| [NXP i.MX 8M Plus](https://www.nxp.com/products/i.MX8MPLUS) | Quad application cores, management/real-time core, GPU, NPU, DSP, video, and industrial I/O | Industrial lifecycle, AI, multimedia, and long-term software reference |

JH7110 is the nearest first target for Pro's RISC-V graphical Linux identity.
TH1520 is the upper RISC-V feature reference, while RK3568 and i.MX 8M Plus set
expectations for accelerator drivers, multimedia integration, and product
software quality.

## Product Claim Gates

| Tier | Claim gate |
| --- | --- |
| Tiny | Measured active and sleep power, bounded wake latency, secure-boot validation, and qualified edge-connectivity operation |
| Mini | Repeatable Linux boot, at least 64 MiB usable main memory, native memory bursts, and management-controlled start/stop recovery |
| Std | Full AXI4 ordering tests, coherent accelerator traffic, 1080p60 graphical desktop, audio playback, and NPU inference under concurrent DMA load |
| Pro | Four-hart coherent SMP stress, RV64 distribution boot, more-than-4-GiB memory validation, and concurrent GPU/NPU/video operation |

No tier becomes a supported repository configuration until it has a committed
profile, locked dependencies, generated integration inputs, firmware, and the
applicable simulation, synthesis, timing, warning, and metric coverage.

Commercial information and links in this document were checked on 2026-08-06.
The referenced products are architecture and market comparison points, not
pin-compatible, price-equivalent, power-equivalent, or performance-equivalent
substitutes. Their specifications must be revalidated before use in product,
cost, or performance claims.
