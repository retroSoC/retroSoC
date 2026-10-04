# Shared RTL IP

This directory owns project RTL IP.

Self-owned IP is grouped by function: interconnect, util, memory, storage,
serial, USB, multimedia, and peripheral. Mini and Tiny select active sources
explicitly in their product filelists.
Source order is part of the build contract. Shared Hazard3/debug wrappers are
in `core`, AXI adapters in `interconnect`, and native AXI SRAM in `memory`.
Both products reference these shared files directly in their own filelists.
Tiny does not select any RIB/RIBP module.

The [PIO-lite contract](../../docs/ip/piolite.md) specifies a future owned
programmable-I/O block for Tiny, with shared GPIO ownership and DMA V2.1
integration changes. Its planned hierarchy is not present in the active
filelists yet. The [verification ledger](../../docs/ip/piolite-verification.md)
keeps model, RTL, integration and physical gates separate from design freeze;
shared DMA/GPIO changes must preserve Mini behavior without enabling PIO there.

The [independent SPI master](../../docs/ip/spi.md) is a separately frozen future
Tiny block, distinct from SPI-SD and XPI. Its APB/packed FIFOs, native GPIO
guard, source-qualified DMA V2.2 MMIO pacing and `SPI-P0..P5` gates are defined
there, with [pending verification](../../docs/ip/spi-verification.md). A
specification or reserved route does not add it to the current RTL/filelists.

experimental contains retained inactive RTL. It is not included by any active
filelist and must not become a build dependency without an explicit integration
change and matching validation.
