# ULPI USB 2.0 Dual-Role Controller

This document is the architecture, register ABI, software, integration, and
verification contract for the self-owned `apb4_usb2` controller. The Mini SoC
management window is `APB4_USB2` at `0x10016000`. Payload data uses a dedicated
32-bit AXI4 master; configuration and status use APB4.

## Commercial reference selection

The reference review was refreshed on 2026-08-21 from vendor-owned material.
These products are references, not source-code dependencies and not evidence
that retroSoC has inherited their certification.

| Reference | Problem and architecture | Status and decision |
| --- | --- | --- |
| [Synopsys DesignWare USB 2.0 digital controllers](https://www.synopsys.com/designware-ip/interface-ip/usb/usb-2-0-digital-controllers.html) | Separates host/device/OTG digital control from either discrete ULPI or integrated UTMI/UTMI+ PHYs and emphasizes low-power integration. | The official product family remains published. Reuse the controller/PHY boundary and role-specific policy; do not add every PHY type or LPM mode to this fixed-ULPI design. |
| [Cadence USB 2.0 Controller IP](https://www.cadence.com/en_US/home/tools/silicon-solutions/design-ip/interface-ip/usb/usb2-controller.html) and [device-controller brief](https://www.cadence.com/content/dam/cadence-www/global/en_US/documents/tools/silicon-solutions/design-ip/design-ip-usb-2-0-device-controller-br.pdf) | Uses endpoint logic, configurable dual-port RAM, register control, and an AXI scatter-gather DMA engine; advertises up to 8 IN and 8 OUT endpoints. | The official product page remains active. Reuse the endpoint/RAM/DMA decomposition, software driver boundary, and deliverable categories. Avoid a hidden fixed FIFO partition and an opaque descriptor ABI. |
| [STM32 OTG HS software architecture](https://www.st.com/resource/en/user_manual/cd00289278-stm32f105xx-stm32f107xx-stm32f2xx-and-stm32f4xx-usb-onthego-host-and-device-library-stmicroelectronics.pdf) and [ST USB hardware guidance](https://www.st.com/resource/en/application_note/an4879-usb-hardware-design-guidelines-for-stm32-microcontrollers-stmicroelectronics.pdf) | Demonstrates a deployed dual-role core with external ULPI, programmable FIFO partitioning, DMA, interrupts, DCD/HCD software layers, dynamic role switching, and suspend/resume policy. | ST continues to publish the documents. Reuse explicit DCD/HCD primitives and dynamic packet-memory allocation. Avoid tying a high-speed peripheral to general GPIO mux policy or depending on UART output as a functional verdict. |
| [Microchip USB3320](https://www.microchip.com/en-us/product/USB3320), [data sheet](https://ww1.microchip.com/downloads/aemDocuments/documents/OTH/ProductDocuments/DataSheets/00001792E.pdf), and [hardware checklist](https://ww1.microchip.com/downloads/aemDocuments/documents/OTH/ProductDocuments/SupportingCollateral/USB3320-Hardware-Design-Checklist-00003003B.pdf) | Provides the external USB 2.0 HS PHY, 8-bit SDR ULPI DATA, DIR/NXT/STP arbitration, register access, and a 60 MHz ULPI clock. | Microchip lists USB3320 as in production. It is the primary PHY target. Board and ASIC timing must use the selected clock mode and the current data-sheet numbers, not generic GPIO timing. |

The selected architecture is a custom descriptor dual-role controller rather
than EHCI. EHCI would bring operating-system compatibility, but its queue-head,
periodic-tree, and hub/split-transaction cost is disproportionate for this
management-class SoC. The retained commercial patterns are a stable register
ABI, autonomous DMA, explicit endpoint/channel resources, configurable packet
memory, clock-domain isolation, interrupts, error capture, a HAL, and a
verification matrix.

## Delivered scope and maturity

The delivered RTL is a synthesizable controller foundation with these fixed
resources:

- USB 2.0 device and embedded-host roles, plus software-forced or ID/VBUS
  selected role switching.
- Eight bidirectional device endpoint numbers: EP0 plus EP1..EP7, with
  independent IN and OUT enable, stall, descriptor, packet-RAM, completion,
  byte-count, and data-toggle state.
- Sixteen host channels with device address, endpoint, direction, transfer
  type, speed, interval, data toggle, packet-RAM region, and descriptor head.
- Control, bulk, interrupt, and single-transaction isochronous data paths.
  Interrupt and isochronous host commands are retained until their programmed
  microframe interval is due.
- HS/FS device operation; HS/FS and direct-attached LS host transaction
  encoding. Hubs and split transactions are not implemented.
- A 16 KiB dynamically partitioned packet RAM with SECDED protection and
  saturating corrected/uncorrectable counters.
- A 32-bit AXI4 scatter-gather DMA master, 32-byte descriptors, 16-beat INCR
  bursts, 4 KiB boundary protection, byte strobes on the final word, precise
  response/ID/RLAST checks, and bounded abort.
- ULPI packet TX/RX, PID/CRC5/CRC16 checking, receive-command status capture,
  register viewport, timeout handling, and link-owned DATA output enable.
- APB4 interrupts with sticky W1C status, first-error snapshots, endpoint W1C
  completion maps, performance counters, and a SystemCtrl USB AXI wait counter.
- Handwritten C register ABI, descriptor helpers, low-level DCD/HCD-style HAL
  primitives, and a non-invasive bring-up register self-test.

This is not yet a USB-IF-certified or production-qualified IP release. The
current repository tests establish digital block behavior and SoC integration;
they do not establish analog PHY, package, board, protocol compliance, CDC/RDC,
DFT, or silicon signoff. High-bandwidth isochronous transactions, OTG HNP/SRP,
LPM, hubs/splits, and a class stack remain outside this release.

## Architecture

The system and link sides are deliberately separate:

```text
management core -- APB4 -- register/IRQ/error/perf
                              |
                       role + scheduler
                              |
memory fabric <--- AXI4 SG-DMA <--> async data FIFOs
                              |
                     16 KiB SECDED packet RAM
                              |
                         transaction engine
                              |
                      PID/CRC SIE + ULPI link
                              |
                    dedicated 3.3 V ULPI pads
                              |
                           USB3320 PHY
```

`clk_i` owns APB, DMA, descriptors, role policy, scheduler state, interrupts,
and performance counters. `clk_ulpi_i` is the PHY-supplied 60 MHz clock and
owns packet RAM access, transaction state, SIE, and the physical ULPI pins.
Commands, results, setup packets, packet-store commands, viewport requests,
and packet streams cross through Common `async_reqack`, `cdc_fifo`, `cdc_sync`,
and `edge_det` components. Each packet-stream CDC FIFO has eight 37-bit words;
this covers pointer synchronization and short AXI/ULPI rate differences without
placing a 32-word data-array reset load on the 60 MHz ready path. A Common
`spill_register` at the ULPI-to-system packet-stream boundary cuts the packet
store backpressure path while retaining one-word-per-cycle steady-state flow.
Role changes wait for active work to quiesce, then flush queued commands and
reset the link domain before the new role starts.

The command front end retains endpoint and channel writes while the scheduler
is busy. Multiple bits for one resource coalesce; software must not submit a
second transfer for the same resource until completion. Endpoint commands have
priority over host channels, then the lowest numbered ready resource wins.

The packet RAM uses 4096 40-bit words: 32 data bits plus the encoded SECDED
bits. IHP130 maps this to two `4096x16` and one `4096x8` single-port macros.
The `Issue -> Wait -> Send` packet-store pipeline registers corrected read data
between SECDED decode and the DMA/SIE consumers. This keeps the SRAM read delay
and byte-wise TX CRC logic in separate 60 MHz timing stages.
Other profiles use the technology wrapper's inferred model. The `RAM_BIST`
register is reserved for a future DFT wrapper and is not advertised by
`CAPABILITY0`.

## AXI4 and performance contract

USB DMA is AXI master 6; management, user, central DMA, SDIO0, SDIO1, and
SPI-SD retain masters 0..5. Transfers are 32-bit INCR bursts with at most 16
beats and never cross 4 KiB. The engine permits one read or write operation at
a time and checks every response. Descriptor control and runtime words are
written back before hardware clears `OWN`.

The performance design target is at least 40 MiB/s sustained one-way HS bulk
payload with large descriptors, 512-byte max packets, memory without prolonged
backpressure, and interrupts coalesced at transfer rather than packet
granularity. The raw ULPI byte rate is 60 MB/s, so software, packet boundaries,
handshakes, AXI arbitration, and CDC overhead determine the measured result.
This target is a release gate, not a claim from the current unit tests. Measure
it on FPGA/silicon with the per-IP byte/retry/stall counters and SystemCtrl
`PERF_USB2_WAIT_LO/HI` counters.

## APB4 register contract

The window is 4 KiB. An accepted APB enable phase completes through a
registered `PREADY`. Misaligned or unknown accesses return `PSLVERR`.
Configuration that changes role, PHY, timeout, endpoint/channel layout, or
descriptor heads must be written while `GLOBAL_CTRL.ENABLE` is clear. Command,
reset, abort, performance-clear, BIST-reserved, IRQ-test, and viewport starts
are pulses. `IRQ_STATUS`, `ERROR_STATUS`, and endpoint completion maps are W1C.
Reads have no side effects except the unimplemented PIO aperture, which returns
`PSLVERR`; DMA is the supported payload path.

| Offset | Register group | Contract |
| ---: | --- | --- |
| 0x000-0x00c | IP_ID, IP_VERSION, CAPABILITY0/1 | RO identity, feature bits, endpoint/channel counts, 16 KiB RAM |
| 0x010-0x03c | global, role, PHY, viewport, timeout, frame, test | mixed control/status; viewport address is 6 bits |
| 0x040-0x05c | IRQ and first error snapshot | 16 IRQ sources; sticky W1C and descriptor/buffer fault addresses |
| 0x060-0x07c | performance | TX/RX bytes, packets, retries, AXI/RAM stalls, IRQ count, clear pulse |
| 0x100-0x120 | device global and completion maps | address, setup packet, pending and W1C completion |
| 0x200 + n*0x40 | endpoint n | CFG, IN/OUT RAM, IN/OUT descriptor, command, status, byte counters |
| 0x400-0x414 | host and schedule global | host/port controls, frame and scheduler status |
| 0x500 + n*0x40 | host channel n | CFG, target, interval, RAM, descriptor, command, status, bytes |
| 0x900-0x918 | packet RAM, ECC, debug | RAM state, ECC counters, reserved BIST pulse, debug snapshot |

The executable bit/offset source is `rtl/ip/usb/usb2_define.svh`. The direct,
hand-maintained C mirror is `<retrosoc/hal/usb2_regs.h>`; the parity test fails
if one side changes without the other. No register generator is used.

## DMA descriptor ABI

Each little-endian descriptor is 32-byte aligned and must not start above
offset `0xfe0` within a 4 KiB region:

| Word | Name | Ownership |
| ---: | --- | --- |
| 0 | BUFFER_ADDR | software; non-zero and 32-bit aligned |
| 1 | BYTE_LENGTH | software; positive, no 32-bit address wrap |
| 2 | NEXT_ADDR | software; 32-byte aligned and same boundary rule, zero at END |
| 3 | CONTROL | software flags and hardware completion flags |
| 4 | ACTUAL_LENGTH | hardware writeback |
| 5 | STATUS | hardware writeback |
| 6 | FRAME | software scheduling metadata, bits 31:27 reserved |
| 7 | RESERVED | zero |

`CONTROL` uses OWN/CHAIN/END/IRQ/SHORT_OK/ZERO_PACKET in bits 0..5 and
DONE/SHORT/STALL/TIMEOUT/CRC/PROTOCOL/AXI/ABORTED in bits 16..23. A chain has at
most 256 descriptors. Software initializes payload and runtime words, executes
a full memory barrier, and sets `OWN` last. A chain is published tail-first so
the DMA cannot reach an unpublished next descriptor. Hardware writes runtime
state and clears `OWN` last. Descriptors and buffers must be in DMA-visible,
non-cached memory or be maintained with platform cache operations.

## Software sequence

1. Hold the USB3320 in reset and call `rs_usb2_probe()` or the non-invasive
   `rs_usb2_controller_selftest()`.
2. Call `rs_usb2_reset()`, then `rs_usb2_configure()` while disabled. Choose a
   forced role or ID/VBUS auto-role, timeout, FS override, IRQ mask, and PHY
   reset release policy.
3. Allocate non-overlapping packet-RAM regions. Prepare and publish DMA
   descriptors. Configure endpoints with `rs_usb2_endpoint_configure()` or host
   channels with `rs_usb2_channel_configure()`.
4. Enable the controller. Device software arms OUT or primes IN endpoints;
   host software starts a channel. The HAL executes a memory barrier before the
   command write.
5. Service setup/endpoint/channel/DMA/error interrupts. Read descriptor
   writeback only after observing completion and a memory barrier. Clear W1C
   bits after consuming state.
6. Disable or abort and wait for idle before changing protected layout. A role
   switch invalidates queued transaction context and requires reconfiguration.

For periodic host transfers, HAL `interval` is in microframes at HS and frames
at FS/LS; it converts FS/LS intervals into the internal microframe time base.
The current layer provides controller primitives, not USB enumeration, class,
hub, or operating-system integration.

## ASIC and board boundary

The ASIC top exposes dedicated `usb2_ulpi_clk_i_pad`, `usb2_ulpi_data0_io_pad`
through `usb2_ulpi_data7_io_pad`, `usb2_ulpi_dir_i_pad`,
`usb2_ulpi_nxt_i_pad`, `usb2_ulpi_stp_o_pad`, and `usb2_ulpi_reset_n_o_pad`.
They do not enter the GPIO alternate-function mux. All ULPI signals and the PHY
reset pad belong to a reviewed 3.3 V I/O bank with an explicit pad-ring,
power-up, isolation, ESD, drive-strength, slew, and package assignment.

USB3320 output-clock mode is the integration default: the PHY supplies the
60 MHz `clk_ulpi_i`. STA must apply the selected data-sheet setup/hold and
output-delay values at the package boundary, including DATA turnaround. Reset,
reference clock/crystal, REFSEL straps, VBUS switch/current limit, ID/VBUS
sensing, connector ESD, and USB differential routing are board responsibilities.
The FPGA profile intentionally leaves these pads unbound until a board with a
3.3 V bank and reviewed constraints exists.

The core-STA profile declares `usb2_ulpi_clk_i_pad` as an asynchronous 60 MHz
root clock in `clock_reset_domains.json`. IHP130 timing runs always link the
`4096x16` and `4096x8` slow-corner Liberty views used by the USB packet RAM;
missing macro models or a missing `clk_usb2_ulpi` path group invalidate the STA
evidence even when the OpenSTA process exits successfully.

## Verification and commercial release gates

Current automated evidence covers PID/CRC vectors, descriptor rejection, ECC
correction/detection, packet-store paths, APB errors/W1C, DMA fetch/payload/
writeback, host transaction flow, ISO no-handshake completion, scheduler queue
retention and interval gating, ULPI link-domain smoke, generated address/pin/
IRQ topology, firmware self-test, synthesis compilation, SoC simulation, and
quality gates.

A commercial release additionally requires:

- USB protocol VIP for device and host randomized traffic, error injection,
  reset/suspend/resume, all endpoint types, retry/toggle corner cases, and
  coverage closure. The testbench boundary must permit replacing the local PHY
  model with commercial VIP.
- Static CDC/RDC signoff of every system/ULPI crossing and reset sequence;
  lint, synthesis, equivalence, DFT, scan, memory BIST integration, STA with
  actual pads/macros, IR/EM, and gate-level reset/X testing.
- FPGA validation with USB3320 and protocol-analyzer traces, 24-hour stress,
  cable attach/remove, malformed traffic, memory backpressure, suspend/resume,
  and measured 40 MiB/s bulk throughput.
- USB-IF electrical and protocol compliance, selected PHY/package/board signal
  integrity, production diagnostics, versioned release notes, integration
  scripts, timing constraints, coverage reports, waivers, safety/security
  review, and a supported DCD/HCD plus class stack.

Until those gates close, use the IP for architectural integration and digital
validation, not as a certified drop-in replacement for a licensed commercial
USB controller.
