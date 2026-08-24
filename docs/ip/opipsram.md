# OPI PSRAM and Single-Clock HyperBus Controller

## Status and Scope

This document freezes the version 1 architecture and software-visible contract
for the retroSoC octal PSRAM controller. The controller is a prototype until a
specific 3.3 V OPI PSRAM and a specific 3.3 V single-clock HyperBus-style
device have completed electrical, timing, board, and silicon qualification.

The same controller, digital PHY, and pins support two boot-selected profiles:

- an octal DDR xSPI transaction profile for OPI PSRAM; and
- a HyperBus transaction profile modified for one externally routed clock.

Software selects a profile after reset. `COMMAND.INIT` latches and locks that
profile until `COMMAND.SOFT_RESET` completes. A live protocol switch is not
supported.

The controller coexists with the ESP-PSRAM64H controller. Its data and
management windows are:

| Window | Address range | Purpose |
| --- | --- | --- |
| AXI4 memory | `0x48000000` - `0x4FFFFFFF` | CPU, user core, and central-DMA data access |
| APB4 management | `0x10010000` - `0x10010FFF` | Configuration, indirect access, status, interrupts, and counters |

Version 1 has one chip select, one single-ended clock, eight DDR data pins, and
one bidirectional RWDS/DQS pin. The 128 MiB aperture does not imply device
capacity. `DEVICE_SIZE` bounds every mapped access; an out-of-range access
returns `SLVERR` and never wraps to device address zero.

## Evidence and Compatibility Boundary

The digital PHY is adapted from PULP Platform HyperBus v0.0.4 at commit
`80de8df600edc5d7956a94c9d42f911d6e61efd7`, as locked by the Basilisk
integration. The following files retain their corresponding upstream Solderpad
Hardware License 0.51 (`SHL-0.51`) copyright and author notices:

| retroSoC file | PULP HyperBus source |
| --- | --- |
| `rtl/ip/memory/opipsram_phy.sv` | `src/hyperbus_phy.sv` |
| `rtl/ip/memory/opipsram_trx.sv` | `src/hyperbus_trx.sv` |
| `rtl/tech/tc_opipsram_delay.sv` | `src/hyperbus_delay.sv` |

retroSoC modifications adapt the PHY to OPI/xSPI, one routed clock for the
HyperBus profile, the project's Common primitives and interfaces, reset
conventions, and technology-specific delay mapping. The upstream `SHL-0.51`
text is preserved in [`../../licenses/PULP_Platform-SHL-0.51`](../../licenses/PULP_Platform-SHL-0.51);
the retroSoC modifications retain their Mulan PSL v2 declaration in each file.

The following upstream concepts are reused:

- separate system and PHY clock domains;
- transaction and response handshakes plus asynchronous payload FIFOs;
- a shared DDR DQ/RWDS transceiver below a protocol-specific transaction FSM;
- a programmable delay on RWDS before receive sampling; and
- a PHY input clock at twice the external memory clock.

The HyperBus command/address encoder is not reusable for OPI. OPI uses
command/address/dummy/data phases; HyperBus uses a 48-bit CA phase, RWDS
additional-latency indication, and protocol-specific turnaround. The two
engines therefore share the transceiver but not protocol state.
The upstream IP exposes an AXI slave and Regbus configuration port but no
controller-owned DMA engine or interrupt output; those are SoC integration
features in retroSoC.

Upstream references:

- <https://github.com/pulp-platform/hyperbus/tree/80de8df600edc5d7956a94c9d42f911d6e61efd7>
- <https://github.com/pulp-platform/cheshire-ihp130-o/blob/560f00f1c14a7f2f22861df6bb4816eacf7f2e7e/Bender.lock#L99-L117>
- <https://github.com/pulp-platform/hyperbus/blob/80de8df600edc5d7956a94c9d42f911d6e61efd7/src/hyperbus_trx.sv#L62-L240>

The PULP sources are provenance references, not a build-time checkout or a
restricted vendor-model dependency. The retained source notices and the
repository NOTICE cover the adapted PHY files; unrelated controller, protocol,
register, interface, HAL, model, and SoC integration code remains retroSoC
owned.

## Commercial Reference Selection

The following public commercial-SoC implementations were evaluated in order of
relevance. They are architecture references, not evidence that one device
simultaneously provides a 3.3 V OPI memory interface and a 3.3 V,
single-clock HyperBus interface.

| Rank | Reference | Problem solved and architecture | Reuse in retroSoC | Boundary to avoid |
| --- | --- | --- | --- | --- |
| 1 | STM32H7B3 OCTOSPI | Memory-mapped and indirect HyperRAM access with DQS, fixed latency, DMA reachability, and explicit cache-maintenance constraints | Separate mapped/indirect paths, latency configuration, error reporting, and cache policy | The MCU or board supply does not prove that the memory protocol, device, or pads meet this project's 3.3 V and single-clock requirements |
| 2 | NXP i.MX RT1180 FlexSPI2 | A programmable LUT feeds both an AHB memory window and IP commands; examples exercise HyperRAM and the surrounding DMA ecosystem | Bounded transaction profiles, software-reset boundaries, and mapped/IP-command layering | FlexSPI capability and electrical support vary by part and board; an unrestricted waveform LUT would also make verification impractical |
| 3 | ESP32-S3 MSPI | Octal DTR PSRAM startup, identification, command/address geometry, and phase calibration | Low-speed discovery, versioned device profiles, and calibration flow | Its OPI engine is not a HyperBus CA/RWDS engine, and high-frequency SDK settings are not reusable signoff evidence |
| 4 | Renesas RA8P1 OSPI-B/XSPI | An 8D-8D-8D OPI HyperRAM profile with fixed latency and direct memory access | Explicit command-set profiles and separation of direct and register access | The product name “HyperRAM” does not imply conventional HyperBus CA encoding; opcodes and dummy cycles remain device-specific |
| 5 | ESP32-P4 MSPI | A high-bandwidth, separately routed external-memory path with optional ECC and execute-in-place integration | Future ECC, bandwidth, and cache-roadmap reference | Its wider AP-memory path is not a standard octal OPI or HyperBus compatibility reference |

These vendor SDK families remain maintained and useful as integration
references. The most reusable common pattern is a restricted, versioned
transaction profile behind separate mapped and indirect front ends, followed
by startup identification and timing calibration. The design deliberately
avoids an arbitrary waveform-programming interface, undocumented cache
coherency, runtime protocol switching, and frequency claims derived only from
another SoC's software configuration.

Public reference evidence:

- STM32H7B3 OCTOSPI HyperRAM example:
  <https://github.com/STMicroelectronics/STM32CubeH7/blob/8511b80f03ac2f579fc0ba3a622571b0de6d0076/Projects/STM32H7B3I-EVAL/Examples/OSPI/OSPI_RAM_MemoryMapped/readme.txt#L20-L118>
- NXP RT1180 FlexSPI HyperRAM example:
  <https://github.com/nxp-mcuxpresso/mcuxsdk-examples/blob/2a340e10a1105bc0af8e7176bc19148911f4cf12/driver_examples/flexspi/hyper_ram/polling_transfer/flexspi_hyper_ram_polling_transfer.c#L25-L204>
- ESP32-S3 octal PSRAM driver:
  <https://github.com/espressif/esp-idf/blob/08e0d30a74ad0bfd5a34933142b80f45619ee410/components/esp_psram/esp32s3/esp_psram_impl_octal.c#L24-L206>
- Renesas RA8P1 8D-8D-8D example:
  <https://github.com/renesas/cpk_examples/blob/48b3da8ea4568d64a9314ab17d95f62cd582b8ed/cpkcor_ra8p1/hyperram_cpkcor_ra8p1_ep/e2studio_llvm/src/hyper_ram.c#L9-L47>
- ESP32-P4 external PSRAM configuration:
  <https://github.com/espressif/esp-idf/blob/08e0d30a74ad0bfd5a34933142b80f45619ee410/components/esp_psram/esp32p4/Kconfig.spiram#L1-L91>

## Clock, Reset, and CDC Contract

`clk_i` and `rst_n_i` own AXI4, APB4, interrupts, and software-visible state.
`clk_phy_i` and `rst_phy_n_i` own transaction serialization and receive
sampling. Common handshakes and asynchronous FIFOs carry commands, payload,
responses, and warm-flush state across the boundary.

The PHY divides `clk_phy_i` by two to produce external `ck_o`. The Mini SoC
version 1 integration connects the PHY and system clocks together. With the
committed 72 MHz system clock this produces a 36 MHz external clock. A later
integration may provide a qualified 144-200 MHz PHY clock to produce a
72-100 MHz external clock without changing the IP interface.

Reset holds `ck_o` low, `cs_n_o` high, DQ and RWDS output enables low, and the
memory window unavailable. Reset assertion is asynchronous at each domain;
release is synchronized by the owning SoC reset tree. A warm reset flushes both
directions of every CDC queue before accepting another initialization.

The GPIO21-31 Mini SoC binding does not route a dedicated device reset pin.
Boards must provide the device-defined reset state, such as an external pull-up
or an approved command reset sequence. A device that requires a separately
driven reset or complementary clock is not compatible with that pin binding.

## AXI4 Contract

The slave has 32-bit data, one-bit ID, and one-bit USER fields. Version 1
accepts one mapped transaction at a time and supports:

- aligned 1-, 2-, and 4-byte beats;
- `INCR` bursts of at most 16 beats;
- byte write strobes, including sparse strobes;
- read and write backpressure; and
- complete response termination after protocol, timeout, availability, or
  bounds errors.

Unsupported burst types, unaligned beats, 4 KiB crossings, aperture crossings,
device-size crossings, exclusive accesses, and accesses while the memory
window is unavailable return `SLVERR`. An invalid write drains all promised W
beats before its B response. An invalid read returns the promised number of R
beats with the final `RLAST`.

Mapped and indirect commands arbitrate at command boundaries. An indirect
operation prevents new AXI addresses but never interrupts an accepted AXI
transaction. A 32-byte, four-entry read-line buffer may accelerate legal
linear reads. A mapped or indirect write invalidates a matching entry;
initialization, abort, soft reset, profile changes, and errors invalidate all
entries.

The existing central AXI4 DMA accesses this window as ordinary memory. The
controller has no private DMA engine and adds no `dma_req_if` request source.

## Protocol Profiles

### OPI/xSPI Profile

Version 1 provides a constrained 8D-8D-8D template:

- 8- or 16-bit command;
- 24- or 32-bit address;
- programmable read, write, register-read, and register-write commands;
- programmable fixed latency/dummy cycles;
- optional DQS output for writes and required DQS/RWDS input for reads; and
- programmable linear burst boundary.

The controller does not expose arbitrary edge-by-edge waveform programming.
Configuration validation rejects command geometry that the transaction engine
cannot execute. A profile is evidence for a specific device only after its
data sheet, ID/register sequence, model, and board test are recorded.

### Single-Clock HyperBus Profile

Version 1 implements the HyperBus CA, memory/register address spaces, fixed or
RWDS-requested additional latency, read/write recovery, and linear burst
turnaround while routing only `ck_o`. It does not route the complementary CK#
used by conventional HyperBus devices. This is a documented device-profile
extension, not a blanket claim of standard HyperBus interoperability.

The software and AXI interfaces use byte addresses. Before forming CA, the
controller converts a HyperBus byte address to the device's 16-bit word
address. Odd-address memory accesses share CA with the preceding even byte and
use RWDS to mask the leading byte; odd transfer lengths similarly mask the
trailing byte. HyperBus register-space writes do not drive RWDS and therefore
require an even address and even length.

## Digital PHY and Technology Delay

The transmit path uses the two-times PHY clock to create the external clock and
DDR data phases without an analog phase shifter. The receive path delays
RWDS/DQS before using it to sample DQ. Software may update a delay tap only
while CS# is inactive, the receive clock gate is disabled, and the CDC payload
queues are empty.

ICS55 has `DLY1X2H7R` and `DLY4X2H7R` cells. Its implementation uses a
fine/coarse tapped chain and a balanced mux tree protected from optimization.
The 3-bit coarse selector covers eight taps with seven `DLY4X2H7R` stages; the
5-bit fine selector covers 32 taps with 31 `DLY1X2H7R` stages. The synthesized
ICS55 netlist retains all 38 delay cells, the seven coarse muxes, and the 31
fine muxes. The smoke STA loads this netlist and the locked slow-corner
libraries, but it does not constrain or report the delayed-RWDS capture path.
Tap monotonicity, useful range, source-synchronous constraints, placement,
PVT, and pad timing therefore remain physical-signoff work.

The current IHP130, GF180, and SKY130 integrations do not define a qualified
programmable delay cell for this IP. They may run protocol, RTL, synthesis, and
netlist-connectivity tests, but they are not source-synchronous PHY signoff.
Behavioral simulation delay is not ASIC timing evidence.

## Register ABI

Registers are 32-bit and naturally aligned. Unmapped, unaligned,
directionally-invalid, or forbidden busy-time accesses return APB4 `pslverr`.
Configuration registers accept byte strobes. Action and RW1C registers require
the low byte strobe.

<!-- Keep this table synchronized with opipsram_define.svh and opipsram_regs.h. -->

| Offset | Name | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| `0x000` | `IP_ID` | RO | `0x4F504938` | ASCII-compatible OPI8 identifier |
| `0x004` | `IP_VERSION` | RO | `0x00010000` | ABI version 1.0 |
| `0x008` | `CAPABILITY` | RO | implementation | Geometry and feature bits |
| `0x00C` | `CTRL` | RW | `0` | enable `[0]`, memory enable `[1]`, auto-init `[2]`, line buffer `[3]` |
| `0x010` | `COMMAND` | WO | `0` | init `[0]`, abort `[1]`, soft reset `[2]`, train `[3]` |
| `0x014` | `STATUS` | RO | `0` | busy/initialized/ready/quiesced/trained/error |
| `0x018` | `PROTOCOL_CFG` | RW | `0` | OPI `0`, single-clock HyperBus `1`; locked after init |
| `0x01C` | `DEVICE_SIZE` | RW | `0x00800000` | Valid bytes, power of two, maximum 128 MiB |
| `0x020` | `OPI_READ_CMD` | RW | `0x0000EE11` | Read command and width |
| `0x024` | `OPI_WRITE_CMD` | RW | `0x000012ED` | Write command and width |
| `0x028` | `OPI_REG_READ_CMD` | RW | `0` | Register-read command |
| `0x02C` | `OPI_REG_WRITE_CMD` | RW | `0` | Register-write command |
| `0x030` | `OPI_TIMING` | RW | implementation | Address bytes, dummy cycles, DQS policy, burst boundary |
| `0x034` | `HYPER_TIMING` | RW | implementation | Initial/additional latency and recovery cycles |
| `0x038` | `CLK_CONFIG` | RW | `0` | Divider mode and effective PHY ratio |
| `0x03C` | `CS_TIMING` | RW | implementation | CS setup, hold, and high cycles |
| `0x040` | `POWERUP_CYCLES` | RW | implementation | Minimum wait before initialization |
| `0x044` | `TIMEOUT_CYCLES` | RW | implementation | Transaction watchdog |
| `0x048` | `RX_DELAY` | RW | `0` | Fine `[4:0]`, coarse `[7:5]`; idle-only |
| `0x04C` | `PROFILE_STATUS` | RO | implementation | Latched profile and validation result |
| `0x050` | `INDIRECT_CTRL` | RW/action | `0` | Direction, register space, length, start |
| `0x054` | `INDIRECT_ADDR` | RW | `0` | Device-local byte address |
| `0x058` | `INDIRECT_WDATA_LO` | RW | `0` | Write payload `[31:0]` |
| `0x05C` | `INDIRECT_WDATA_HI` | RW | `0` | Write payload `[63:32]` |
| `0x060` | `INDIRECT_RDATA_LO` | RO | `0` | Read payload `[31:0]` |
| `0x064` | `INDIRECT_RDATA_HI` | RO | `0` | Read payload `[63:32]` |
| `0x068` | `LAST_ERROR` | RO | `0` | Error class and protocol phase |
| `0x06C` | `LAST_ERROR_ADDR` | RO | `0` | First failing mapped or local address |
| `0x070` | `TRAIN_STATUS` | RO | `0` | Busy, valid, selected tap, and window width |
| `0x074` | `TRAIN_WINDOW` | RO | `0` | First and last passing taps |
| `0x080` | `INTR_STATE` | RW1C | `0` | Sticky interrupt state |
| `0x084` | `INTR_ENABLE` | RW | `0` | Interrupt mask |
| `0x088` | `INTR_STATUS` | RO | `0` | `INTR_STATE & INTR_ENABLE` |
| `0x08C` | `INTR_TEST` | WO | `0` | Set interrupt state bits |
| `0x090` | `PERF_CTRL` | RW/action | `0` | enable, freeze, and clear |
| `0x094` | `PERF_READ_BYTES` | RO | `0` | Saturating mapped-read byte count |
| `0x098` | `PERF_WRITE_BYTES` | RO | `0` | Saturating mapped-write byte count |
| `0x09C` | `PERF_COMMANDS` | RO | `0` | Saturating physical-command count |
| `0x0A0` | `PERF_CACHE_HITS` | RO | `0` | Saturating read-line hit count |
| `0x0A4` | `PERF_STALL_CYCLES` | RO | `0` | Saturating AXI stall count |
| `0x0A8` | `PERF_ERROR_COUNT` | RO | `0` | Saturating error count |

Interrupt bits are init done `[0]`, indirect done `[1]`, training done `[2]`,
error `[3]`, and timeout `[4]`. New events win over a same-cycle RW1C clear.

Error classes are none `0`, illegal transaction `1`, unavailable `2`, timeout
`3`, profile `4`, aborted `5`, PHY `6`, protocol `7`, bounds `8`, and training
`9`.

## MVP and Deferred Features

Version 1 includes one device, one accepted transaction, 16-beat bursts,
indirect access, manual delay programming, software-assisted training,
interrupts, counters, a read-line buffer, and central-DMA access.

Deferred features include multiple chip selects, multiple AXI outstanding
transactions, write combining, coherent cache, ECC/scrub, inline encryption,
runtime protocol switching, online PVT tracking, low-power retention, and
execute/boot from this window.

## Verification and Signoff

The delivery requires:

- self-owned OPI and HyperBus protocol models with no restricted vendor model;
- APB4 ABI/access, AXI4 burst/error-drain/backpressure, protocol, reset, abort,
  timeout, delay-window, interrupt, counter, and DMA tests;
- formal checks for AXI termination, FIFO bounds, CDC handshakes,
  configuration locking, legal FSM recovery, and sticky interrupts;
- RTL formatting/style/readiness, host C tests, Pytest, firmware, IHP130
  regression, and ICS55 synthesis/STA/netlist evidence; and
- warning and metric review without hand-editing baselines.

The local IHP130 regression may use `--netsim-boot-only`; it terminates the
long Icarus netlist simulation only after `Hello retroSoC!` and continues the
remaining STA, warning, and metric steps.

The 2026-08-19 delivery candidate completed the IHP130 and ICS55 PR
regressions, including firmware, Verilator and Icarus RTL simulation, Yosys
synthesis, Icarus netlist boot, and OpenSTA smoke analysis. Both netlist runs
observed `Hello retroSoC!` and terminated through the configured success-marker
path. The ICS55 netlist inspection confirmed the delay and mux counts above.
Final prove, BMC, and cover runs passed, and self-owned OPI RTL has no new
Verilator lint signatures. The final post-cleanup IHP130 rerun skipped netsim
by operator request; its firmware, RTL simulations, synthesis, STA, warning,
and metric stages completed, while the earlier IHP130 netlist result remains
the recorded boot evidence.

Metrics remain in `observe` mode. The smoke STA reports contain global SoC
timing violations and are not timing closure. Warning review also remains open:
the regression records increased Yosys aggregate signatures without modifying
the approved baselines. These observations do not invalidate protocol or
netlist-connectivity results, but they prevent a claim of physical signoff.

Controller RTL, I/O pads and voltage domains, single-ended clock output,
RWDS/DQS delay calibration, CDC constraints, refresh assumptions, board-level
signal integrity, cache consistency, DMA reachability, timeout/error handling,
and PVT evidence are separate acceptance items. Protocol simulation cannot
substitute for any of those physical or system-level signoff items.
