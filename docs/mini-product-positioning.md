# retroSoC Mini Product Positioning

## Status

retroSoC Mini is currently an open-source RISC-V microcontroller-class SoC
with a fixed Hazard3 management core and one software-selected user core. This
document also defines a planned Linux-capable configuration built around a
32-bit VexiiRiscv user core. The VexiiRiscv integration and Linux boot flow are
product targets, not supported repository configurations yet.

Mini is the price, complexity, and Linux-capability anchor for the planned
[retroSoC product family](soc-family-positioning.md). Tiny removes the Linux
and external-DRAM requirements for low-power MCU use, while Std adds RV32
performance and efficiency cores, full AXI4 memory transport, and graphical
and AI acceleration. Pro is the only planned RV64 tier.

The target product position is a low-cost, heterogeneous, 32-bit RISC-V Linux
control SoC for embedded control, compact human-machine interfaces, gateways,
and retro multimedia systems. It is not intended to compete with general-purpose
Linux application processors that require RV64, cache-coherent multiprocessing,
or high-bandwidth DDR interfaces.

## Current Mini Baseline

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
- RIB v1 is a 32-bit interconnect with `INCR1` and aligned four-word `INCR4`
  transfers and one outstanding transaction per master.
- Current external-memory targets serialize an accepted RIB burst into ordered
  scalar RIBP accesses. They do not yet combine an `INCR4` request into a native
  SDRAM, PSRAM, or flash streaming transaction.

The generated address map, user-extension map, and
[RIB protocol contract](rib-interconnect.md) remain the executable sources of
truth for the implemented baseline.

## Planned Linux Configuration

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

## Product Targets

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
fabric may evolve independently while RIBP and APB remain the stable peripheral
register interfaces. Frequency claims must be qualified separately for each
PDK and physical implementation.

## Commercial Reference Points

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

Commercial information and links in this table were checked on 2026-08-06.
Specifications can change and must be revalidated before being used in product,
cost, or performance claims.

## Positioning Summary

The closest architectural reference points are BL808 and i.MX 7ULP. The
closest cost and lightweight-Linux reference is F1C200s, while F133 and
CV1800B represent the nearest commercial RISC-V Linux market. ESP32-P4 is a
control-topology reference rather than a Linux performance reference.

After the Linux configuration meets the memory and interconnect targets above,
retroSoC Mini should be positioned between F1C200s and BL808: less capable than
modern 64-bit multimedia SoCs, but differentiated by open RTL and explicit
management-core control over Linux-core boot, bus admission, shutdown, and
fault recovery.
