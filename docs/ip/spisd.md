# SPI-SD Host Controller

This document defines the architecture, register ABI, software contract, and
delivery boundary of the self-owned `apb4_spisd` controller. The Mini SoC uses
an APB4 management window at `0x10005000`, native 32-bit AXI4 master number 5,
management IRQ6, and the existing `spi_if` pads. The old memory-mapped card
aperture at `0x60000000-0x9fffffff` is retired and returns an AXI decode error.

## Scope and maturity

The controller is a single-slot SD Memory SPI-mode host. It supports SD Memory
v2 SDSC/SDHC enumeration, generic 48-bit commands, R1/R1b/R2/R3/R7 responses,
single- and multi-block PIO or scatter-gather DMA, CRC7/CRC16, bounded
timeouts, abort, counters, and interrupts. It is strictly SPI mode 0, SDR, and
single clock domain: `clk_i` is the only internal clock.

This is a commercial-style engineering MVP, not SD Association certification
or production silicon signoff. It deliberately excludes native SD/SDIO,
eMMC, DDR, UHS, 1.8 V switching, tuning, command queueing, cache coherency,
hotplug, card detect, write protect, and power switching. The existing native
SD/SDIO host remains a separate IP.

## Commercial reference survey

The following first-party sources were reviewed on 2026-08-20. "Active"
means the vendor still publishes a current product or SDK page; it does not
assert a specific product lifecycle guarantee.

| Reference | Problem and architecture | Dependencies | Status | Reuse / avoid |
| --- | --- | --- | --- | --- |
| [Espressif ESP-IDF SD/SDIO/MMC](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/storage/sdmmc.html) and [SDSPI host](https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32/api-reference/peripherals/sdspi_host.html) | Separates card protocol from the host implementation, allowing the same enumeration/block layer to use a dedicated SDMMC host or a general SPI host. DMA-capable aligned buffers and a reusable bounce buffer handle memory constraints. | ESP-IDF SPI master, GPIO/CS policy, DMA-capable memory, protocol driver | Active; latest ESP-IDF documentation is published. | Reuse protocol/host layering, explicit capability reporting, aligned DMA/bounce-buffer policy. Avoid software-controlled bit-level protocol, shared-bus arbitration, and dynamic allocation in the freestanding SDK. |
| [Microchip MPLAB Harmony SDSPI](https://onlinedocs.microchip.com/oxy/GUID-EDFB1AB8-CD6B-446F-8E25-F2167287A1AF-en-US-4/GUID-824D74D6-8B88-479A-8E92-981DECBE8204.html) | Presents SDSPI above either an SPI PLIB or driver and connects optional DMA through event callbacks. It solves portability across MCU SPI/DMA implementations. | Harmony SPI PLIB/driver, DMA PLIB, callback/event framework | Active documentation is published. | Reuse bounded completion/error events and a PIO fallback. Avoid callback-only state ownership and external-DMA coupling that cannot make command/data/DMA launch atomic. |
| [NXP MCUXpresso uSDHC](https://mcuxpresso.nxp.com/api_doc/dev/320/group__usdhc.html) | A dedicated SD host exposes capability discovery, command/data descriptors, watermarked buffering, interrupts, and ADMA2 descriptor tables. It removes per-byte CPU service and standardizes error recovery. | Native SD pads/PHY, uSDHC registers, SDK driver, ADMA memory | Active MCUXpresso API page is published. | Reuse capability registers, separate command/data status, descriptor ownership, precise DMA errors, watermarked PIO, and interrupt masks. Avoid native-bus-only/UHS/eMMC scope and the full SDHCI register model. |
| [Arasan SD 4.1 host IP](https://www.arasan.com/products/sd4/sd-4-1-host/) and [total IP solution](https://www.arasan.com/total-sd-card-ip-solution/) | Commercial IP combines hardware command processing, PIO on a slave interface, DMA on a host-master interface, multi-block operations, RTL, VIP, software, documentation, and hardware validation. | AXI/AHB/OCP integration, SD PHY, verification IP, software stack | Active product and delivery pages are published. | Reuse the APB/AXI split, internal SG DMA, full error accounting, and delivery-package mindset. Avoid claiming compliance, proven silicon, UHS, PHY, or throughput without equivalent evidence. |
| [SD Association simplified specifications](https://www.sdcard.org/downloads/pls/) | Defines the normative card protocol and publishes Physical Layer Simplified Specification 9.10 and Host Controller Simplified Specification 4.20. | Specification/license review and physical interoperability work | Active specification portal. | Use it as the protocol authority. Do not infer certification from simulation or copy restricted material into the repository. |

The selected architecture is intentionally hybrid. It keeps the pin-efficient
SPI-mode target and software-driven card policy seen in MCU solutions, but
moves command framing, data tokens, CRC, timeouts, FIFO flow control, and DMA
into a dedicated controller. Its APB control plus native AXI master resembles
commercial storage hosts without importing native SD/UHS complexity.

## Architecture

```text
management CPU -> APB4 registers -> transaction sequencer
                                      |       |
                               command engine data engine
                                      \       /
                                  phase clock -> SPI pads
                                         |
                         TX/RX Common FIFOs (16 x 32-bit)
                                         |
                    reused SDIO SG DMA -> native AXI4 master
```

`spisd_core` sequences training, command, data, optional CMD12 stop, and
phase-safe finish. `spisd_clock` generates clock-enable pulses and never uses
`spi.sck_o` as a logic clock. `spisd_command` owns command CRC7, response start
search, response capture, R1b busy, and command/busy timeout. `spisd_data` owns
tokens, byte serialization, CRC16, FIFO backpressure, write response, and
data/busy timeout. Common `dffr`/`dffrc` and FIFO components own state and
buffering; the proven `sdio_dma`/`dma_axi4_master` path is reused for AXI.

Configuration remains software policy. RTL does not hard-code the card
enumeration sequence or SDSC/SDHC address conversion.

## Clock and phase contract

`CLOCK_CTRL[23:8]` is the number of `clk_i` cycles per SPI half-period. Zero
is treated as one. The reported clock is:

```text
spi_sck_hz = InputClockHz / (2 * max(half_period, 1))
```

Clock stop and FIFO pause complete the current high phase and stop low. MOSI
and CS change on falling phase events; MISO is sampled on rising phase events.
Power-up training generates exactly 80 rising edges while CS is high. The
72 MHz Mini profile uses half-period 90 for 400 kHz initialization, 2 for
18 MHz default operation, and 1 for an explicitly verified 36 MHz high-speed
mode. The theoretical wire ceiling at 36 MHz is 4.5 MB/s before command,
token, CRC, card busy, and AXI overhead.

## Protocol behavior

- Commands contain start/direction, six-bit index, 32-bit argument, CRC7, and
  terminal bit. CRC7 is always generated, including commands for which a card
  might ignore it.
- No-response, R1, R1b, R2, R3, and R7 formats are selectable. CMD12 can
  discard its mandatory stuff byte. R1 error bits terminate the transaction.
- Reads search for token `0xfe`, receive exactly `BLOCK_SIZE * BLOCK_COUNT`
  bytes, and compare CRC16 when enabled.
- Writes emit `0xfe` for single blocks and the multi-block start/stop tokens
  for CMD25, send CRC16, require an accepted data-response token, and wait for
  card busy release. Multi-block read can issue automatic CMD12.
- Command, data, and busy timeouts are independently programmable in `clk_i`
  cycles. Abort stops new work, allows accepted AXI traffic to drain in the
  reused DMA, and reports a terminal abort event.
- PIO is lane-0-first: bits `[7:0]` and `PSTRB[0]` are the first wire byte;
  every byte is serialized MSB first. Partial final PIO words are represented
  by contiguous low strobes.

## APB4 register ABI

The 4 KiB window is defined manually in `rtl/ip/storage/spisd_define.svh` and
mirrored manually in `crt/include/retrosoc/hal/spisd_regs.h`.
`tests/test_spisd_register_parity.py` rejects drift; no register generator is
used. Unknown offsets and writes to read-only registers return `PSLVERR`.
Protected configuration writes begun while busy return `PSLVERR`; abort, DMA
abort, FIFO service, IRQ, and error operations remain available.

| Offset | Register | Access | Purpose |
| ---: | --- | --- | --- |
| `000` | `IP_ID` | RO | `0x53504953` (`SPIS`) |
| `004` | `IP_VERSION` | RO | ABI version `1.0.0` |
| `008` | `CAPABILITY` | RO | SD Memory v2, SPI0, SDR, SG DMA, PIO, CRC, multi-block, burst16 |
| `00c` | `HOST_CTRL` | RW/pulse | enable, abort, global IRQ enable |
| `010` | `CLOCK_CTRL` | RW/pulse | enable, 80-clock train, half-period |
| `014` | `CLOCK_ACTUAL` | RO | calculated SCK Hz |
| `018-020` | timeout registers | RW idle | command, data, and busy cycle bounds |
| `024` | `STATUS` | RO | aggregate, command, data, DMA, FIFO, clock, enable state |
| `040-048` | command setup/start | RW idle / WO | argument, index/response/flags, launch |
| `04c-054` | command status/response | RO | busy/error/timeout/error code and up to 40 response bits |
| `080-088` | data setup | RW idle | block size/count, direction, DMA, multi-block, CRC |
| `08c` | `PIO_DATA` | RW | blocking FIFO access with APB wait state |
| `090-094` | data/FIFO status | RO | progress/error and FIFO level/full/empty |
| `0c0-0c8` | DMA setup/control | RW idle / WO | descriptor base/count, start/abort |
| `0cc-0dc` | DMA status | RO | busy/done/error, current descriptor, bytes, precise AXI error |
| `100-108` | IRQ | W1C/RW/WO | sticky status, enable, test |
| `10c` | `ERROR_STATUS` | W1C | sticky CRC, timeout, command/data/DMA/abort events |
| `110-120` | diagnostics | RO | last command and saturating CRC/timeout/AXI/stall counters |

`CMD_START` atomically launches the command engine and, when data/DMA flags
are set, the descriptor engine. `DMA_CTRL.START` is an explicit alias for the
same coordinated DMA launch and is not a general memory-copy operation.

IRQ bits are command done, data done, DMA done/descriptor IRQ, command error,
data error, DMA error, and abort. Status is sticky until W1C. The pin asserts
only when the matching status and enable bit plus `HOST_CTRL.IRQ` are set.

## Scatter-gather DMA ABI

Descriptors are 16 bytes and 16-byte aligned:

| Word | Field | Contract |
| ---: | --- | --- |
| 0 | `BUFFER_ADDRESS` | 32-bit aligned source/destination |
| 1 | `BYTE_COUNT` | positive transfer length |
| 2 | `NEXT_ADDRESS` | 16-byte aligned next descriptor or zero at END |
| 3 | `CONTROL_STATUS` | OWN, CHAIN, END, IRQ; DONE/ERROR writeback |

OWN, CHAIN, END, and IRQ are bits 0-3; DONE and ERROR are bits 16-17. A chain
is bounded to 16 descriptors. Software initializes the descriptor, publishes
buffer contents, executes a memory barrier, and sets OWN last. Hardware clears
OWN and writes DONE or ERROR at completion. Buffer length across the chain
must equal the programmed block byte count.

The AXI master uses aligned 32-bit INCR bursts up to 16 beats and never crosses
a 4 KiB boundary, as required by the [Arm AXI4 specification](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf).
It supports one transaction at a time, ID 0, and reports `SLVERR`, `DECERR`,
bad IDs, malformed `RLAST`, descriptor errors, current descriptor, error
address, and bytes completed. There is no IOMMU, cache snooping, or address
firewall in this IP; integration software owns cache maintenance if a future
profile adds caches.

## SDK and filesystem contract

`<retrosoc/hal/spisd.h>` exposes probe, clock calculation, command, PIO,
DMA, initialization, high-speed switch, sector I/O, abort, status, IRQ, and
card-information APIs. Pure clock, CSD, address, and descriptor helpers live
in `spisd_math.c` so host tests can validate them without real registers.

Initialization is bounded and follows CMD0, CMD8, repeated CMD55/ACMD41,
CMD58, CMD9, optional CMD16 for SDSC, and CMD59. It parses CSD rather than
assuming capacity, distinguishes SDSC byte addresses from SDHC block
addresses, enables CRC, and settles at 18 MHz. `rs_spisd_high_speed_enable()`
issues CMD6, checks the returned function status, and only then changes to a
maximum 36 MHz. Failure leaves the default clock unchanged.

FatFs obtains sector count from parsed card geometry and uses DMA sector APIs.
The compatibility byte-read API interprets addresses in the retired
`TF_CARD_START` range as card offsets and uses a bounded sector bounce buffer;
it does not restore memory-mapped hardware behavior.

## MVP and development order

The implemented MVP order is:

1. Freeze the APB/descriptor ABI and single-clock phase contract.
2. Implement and unit-test CRC, clock, command, and data engines.
3. Add Common FIFOs and reuse the native AXI4 SDIO SG DMA.
4. Integrate APB, AXI master 5, IRQ6, pads, and retire the old aperture.
5. Add freestanding enumeration, CSD/address helpers, PIO/DMA sector APIs, and
   FatFs integration.
6. Add register parity, behavioral card model, directed RTL tests, firmware,
   synthesis/timing regression, and documentation.

The next commercial-alignment stages are constrained to useful SPI-mode work:

- Add full standalone card-model enumeration, PIO/DMA 512-byte and multi-block
  read/write, descriptor-chain, AXI backpressure/error, abort-drain, and fault
  injection regressions.
- Add assertions/formal checks for phase changes, APB stability, AXI 4 KiB and
  payload stability, descriptor ownership, and terminal progress.
- Collect line/toggle/FSM/assertion coverage with reviewed exclusions and
  close a requirements traceability matrix.
- Run FPGA/board interoperability across SDSC/SDHC vendors, long writes,
  removal/brownout, signal integrity, PVT timing, and sustained throughput.
- Freeze versioned release notes, integration checklist, synthesis/STA/CDC/RDC
  reports, known-issues list, and reproducible release manifest.

Features to avoid in this IP are native SD/SDIO/eMMC compatibility layers,
UHS/DDR PHY logic, a second clock domain, arbitrary outstanding AXI IDs,
memory-mapped card caches, unbounded descriptor walking, and silent CRC or
timeout recovery. Those features add verification and physical risk without
improving the constrained SPI-mode product.

