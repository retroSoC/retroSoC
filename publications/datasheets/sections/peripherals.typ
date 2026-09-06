#import "../style.typ": *

#pagebreak()
== Peripherals
The following sections retain the original functional grouping. Address and interrupt summaries
are generated from the reviewed SoC maps. An absent dedicated interrupt is stated explicitly;
bus errors and shared system faults can still be reported through platform mechanisms.

=== Memory Interface
==== Non-Volatile Memory (NVM)
===== XPI Universal Controller (XPI) <xpi>
#ip("xpi")
XPI V2 supports programmable command sequences, SDR serial phases and independent chip-select
configuration. The command LUT supports serial flash reads and indirect transfers without
embedding one device's opcode sequence into software-visible hardware policy. Memory reads,
command programming, DMA and status polling share a controlled transaction engine.

The boot alias begins at address zero. The main XPI data aperture is 256 MiB, while the boot
alias is 16 MiB; these are decoder windows, not fitted flash capacities. Data-plane writes are
denied. Firmware uses indirect transactions for flash programming and erase. DTR and a qualified
maximum SCK are not specified for this implementation.

===== SPI SD Card Controller (SPISD) <spisd>
#ip("spisd")
The host controls SD cards in SPI mode and moves payloads through a private AXI4 master, routed
through I/O gateway B. Resource ownership determines which hart receives its interrupt.
The former 1 GiB memory-mapped card aperture is reserved; software must use command/data
operations. Card initialization, capacity discovery and supported transfer details belong to
the SPI-SD contract, rather than fixed card-size claims in the feature list.

===== SD Card Controller (SDIO0) <sdio0>
#ip("sdio0")
SDIO0 provides native SD command/data transfers and descriptor-driven DMA through I/O gateway A.
Its signals share the GPIO alternate-function matrix. The card, pull-ups, bus voltage and board
timing are external integration requirements. Do not equate protocol support with a qualified
card-speed grade. SDIO1 uses the same controller family with a separate instance and pad group.

==== Volatile Memory (VM)
===== On-Chip Memory (OCM / SRAM) <sram>
#ip("sram")
The reference profile selects eight 4 KiB banks for 32 KiB total. The configuration accepts
4, 16, 32, 64 or 128 KiB; only 32 KiB is selected by the committed product profiles.
SRAM has a native AXI64/ID6 data interface in the HP domain and an APB4 configuration window.
Technology macros and behavioral models are selected by the configuration. A larger configurable
capacity is not a statement of qualified area, timing or yield.

===== PSRAM Controller (PSRAM) <psram>
#ip("psram")
The QPI controller addresses four ESP-PSRAM64H devices, each 8 MiB. It uses four SDR data pins
and device-specific initialization, recovery and restricted commands. It does not implement
octal PSRAM, DDR/DTR, DQS or generic CPOL/CPHA selection. The QPI data port uses local
AXI64-to-32 adaptation and an HP-to-memory clock crossing.

===== OPI PSRAM / HyperBus-Style Controller <opipsram>
#ip("opipsram")
One controller supports a boot-selected octal DDR transaction profile or a single-clock
HyperBus-style profile. Initialization locks the selected protocol until soft reset. The
128 MiB aperture is addressability, not a device-density commitment. QPI and OPI share memory
pads and must not drive them concurrently.
#note[This is a prototype interface. A specific 3.3 V OPI or single-clock HyperBus-style device
still requires electrical, timing, board and silicon qualification. It is not a blanket claim
of compatibility with every HyperBus device.]

===== SDRAM Controller (SDRAM) <sdram>
#ip("sdram")
The fixed x16 SDR geometry has two bank bits, thirteen row bits and ten column bits. The
controller tracks open rows, accepts native bursts and exposes programmable timing values in
SDRAM-clock cycles. AXI64 crosses into the stable memory domain before local 64-to-32 adaptation.
Firmware must initialize the device and program timings for the fitted part before use.

=== General-Purpose Input Output (GPIO) <gpio>
#ip("gpio")
Software controls per-pin mode, output data, output enable, open-drain behavior, input filtering
and interrupt configuration. Alternate-function and user-IP paths share the same 32 physical
GPIOs. Atomic set/clear/toggle operations avoid software read-modify-write races.

==== System IO / Management Window
The administration window owns pad mode, electrical controls, filters, user access masks and
configuration locks. The user access mask resets to zero. Configuration ownership and lock
semantics apply to the single controller; this window is not a separate GPIO bank.

==== User Custom IO / User Window
The restricted window exposes only the data and interrupt operations permitted by the
management mask. MPW user-IP handoff uses the same ownership boundary. The old GPIO0/GPIO1
section names must not be interpreted as two independent sets of pads. See @gpio-mux for
the generated alternate-function matrix.

=== Direct Memory Access (DMA) <dma>
#ip("dma")
==== Architecture
Eight channel contexts share one AXI32 master. The production integration uses 32-bit words,
up to sixteen beats per burst and thirty-two words of buffering. Direct mode supports memory
copies, fixed MMIO and selected AXI4-Stream endpoints. Linked-list mode fetches 64-byte,
64-byte-aligned transfer-control descriptors. Arbitrary nonzero memory-copy byte counts are
supported with aligned addresses and a partial final write beat.

Narrow transfer widths, unaligned realignment, cyclic descriptors, 2D stride and hardware
cache coherency are not implemented. Firmware must perform ownership and cache maintenance
before handing shared buffers to DMA.

==== Hardware Trigger Channels
UART0 uses channel 0; I2C0 and I2C1 use channels 1 and 2. I2S and DVP use bulk channel 3.
Channels 0-5 retain defined endpoint ownership, channel 6 is reserved for HP boot and channel
7 is reserved. Crypto streaming and other endpoint details remain defined by the DMA contract;
drivers must not silently share a context.

=== Timers
==== General-Purpose Timer (TIM0, TIM1) <timer>
#ip("timer")
Both timers support free-running, periodic and one-shot operation, up/down counting and sticky
interrupt status. An optional debug-freeze input stops counting while management Hazard3 is
halted, without preventing register access. No separate TIM2 advanced timer is integrated.

==== Real-Time Clock (RTC) <rtc>
#ip("rtc")
RTC V2 provides a 64-bit Unix-epoch counter, 1/256-second resolution, two alarms, a periodic
wake timer and smooth digital calibration. Time reads use an atomic snapshot. The engine uses
the independent audio input frequency selected by the profile rather than assuming a
32.768 kHz crystal. RTC interrupt and wake outputs are distinct integration signals.
#tbd[Battery-backed operation, oscillator accuracy and retention across loss of board power
are not specified by the current digital integration.]

==== Watchdog (WDG) <wdg>
#ip("wdg")
The watchdog remains clocked independently of the APB register domain. Early-warning IRQ14
allows software intervention before the reset request. Software starts the watchdog once and
services it with a two-key sequence. Timeout, early-window service and malformed service
sequences request reset. An APB reset does not stop the running watchdog core. The integrated
reset-request pulse parameter is eight watchdog cycles.

==== Pulse Width Modulation (PWM) <pwm>
#ip("pwm")
Four PWM outputs, two capture inputs, a fault input and a synchronization input are routed
through the GPIO alternate-function matrix. The managed V2 implementation includes interrupt
reporting and management-debug halt integration.
Program divider and waveform parameters against the active peripheral clock; a register field
width alone does not establish a qualified output frequency.

=== IO Interface
==== Universal Asynchronous Receiver/Transmitter (UART)
===== Management Console (UART0) <uart0>
#ip("uart0")
UART0 supports configurable framing, fractional baud generation, watermark and receive-timeout
interrupts, receive diagnostics, break, loopback and automatic active-low RTS/CTS. TX/RX have
dedicated pads; GPIO0/1 ALT0 carry CTS/RTS. DMA pacing is connected only for UART0.

===== Application Console (UART1) <uart1>
#ip("uart1")
UART1 uses the same 64-byte FIFO UART v3 ABI, not a separate non-FIFO implementation. Its
dedicated TX/RX pads serve the HP console. HP PLIC source 1 is distinct from the LP vector
number above. The initial Linux console uses OpenSBI/hvc0; a native Linux UART driver remains
a separate delivery item.

==== Inter-Integrated Circuit (I2C) <i2c>
#ip("i2c")
Each instance has sixteen-entry command and receive FIFOs, 7/10-bit addresses, repeated START,
clock stretching, arbitration-loss detection, filtering, bounded waits and bus recovery.
GPIO7/8 ALT0 route I2C0; GPIO3/4 ALT1 route I2C1. External pull-ups and a validated board timing
budget are required. The current IP is controller-mode, not an I2C target/slave peripheral.

==== WS2812 LED Interface <ws2812>
#ip("ws2812")
GPIO2 ALT1 carries the single transmit output. Words are sent GRB, most-significant bit first.
Symbol high/low durations and reset-low time are programmable. This is not a Dallas/Maxim
1-Wire controller and must not be used as a substitute for that protocol.

==== Personal System/2 (PS2) <ps2>
#ip("ps2")
GPIO0/1 ALT1 route PS/2 clock/data. The integration binds input sensing and active-low drive
behavior for an open-drain bus. External pull-ups are required. Before changing GPIO ownership,
firmware disables the controller and confirms that both output enables are released.

==== SDIO Controller (SDIO1) <sdio1>
#ip("sdio1")
The second native SD instance uses dedicated clock, command and four data pads and is routed
through I/O gateway B. Resource ownership controls DMA submission and LP/HP interrupt delivery.
The dedicated pad group is intentionally unbound in the generic FPGA profile until board pin,
I/O-bank voltage and timing constraints are approved.

==== USB 2.0 Dual-Role Controller <usb2>
#ip("usb2")
The digital controller uses an external 8-bit ULPI PHY, descriptor-driven AXI DMA and APB4
control. Its dedicated thirteen-pad interface includes ULPI clock, DATA[7:0], DIR, NXT, STP
and PHY reset. These pads do not enter the GPIO mux. The primary external PHY target is USB3320.
#note[The custom controller is not an EHCI register-compatible block. Host/device software,
protocol coverage, USB compliance and board/PHY timing have their own release gates.
An integrated digital controller does not establish USB-IF certification.]

==== Architecture Information (ARCHINFO) <archinfo>
#ip("archinfo")
Discovery registers report the generated build/configuration identity, topology, SRAM bytes
and technology capabilities. Device-ID inputs are tied invalid and read-disabled in the
current SoC integration; the document does not claim a provisioned unique silicon identity.

==== System Controller (SYSCTRL) <sysctrl>
#ip("sysctrl")
Root-controlled registers manage lifecycle and faults. Automated firmware reports completion
through TEST_STATUS: bit 31 is valid, bit 0 is pass and bits 15:8 hold the result code.
The first valid full-word write is sticky until reset. UART startup output is diagnostic,
not the acceptance verdict.

==== Reset Clock Unit (RCU)
RCU functionality is accessed through system control and the clock/reset subsystem rather
than an additional standalone APB window. Clock switching, safe fallback and qualification
limits are described in the Clock and Reset section.
#source("docs/pll-clock-control.md")

==== Management Local Interrupts (CLINT) <clint>
#ip("clint")
CLINT supplies machine software and timer interrupts for the management hart. The committed
timebase is 1 MHz. It is separate from the HP local-interrupt window and from the PLIC external
interrupt controller.

==== HP Interrupt and Mailbox Platform <hp-platform>
#ip("hp-platform")
The mailbox exchanges boot and lifecycle state between LP and HP. Doorbells notify the
receiving hart. The HP local timer/software block and PLIC serve different interrupt classes;
their address ranges must not be treated as ordinary dense register arrays.

==== Resource Controller <resource>
#ip("resource")
Eight resources are managed: central DMA, USB2, SDIO0, SDIO1, SPI-SD, EXT-H, JPEG and APU.
Ownership changes require quiesce, completion of accepted traffic and cache-maintenance
handoff. HP can inspect allowed status but cannot take over root writes. An ownership grant
does not bypass the target access policy or EXT-H address bounds.

==== Fabric Monitor <monitor>
#ip("monitor")
The monitor observes accepted requests, beats, waits, outstanding high-water marks, aging,
timeouts, isolation and warm flushes. Saturating counters are read through explicit snapshots.
Sticky first-fault attribution keeps source identity and decoded target information. Monitoring
does not alter arbitration or admission policy.

=== Multimedia
==== Inter-Integrated Circuit Sound (I2S) <i2s>
#ip("i2s")
The stereo master supports 16/24-bit and 48/96 kHz presets plus programmable clock dividers.
TX/RX streams use 32-bit words and 128-word FIFOs. Configuration and sample CDC handle the
independent audio clock. Slave, TDM and PDM modes are not advertised. A codec/DAC/ADC and
board-level audio-clock qualification are external requirements.

==== Extended Peripheral Interface (XPI)
XPI can serve serial peripherals through its indirect command engine as well as serial
memory. It is the same XPI controller described in @xpi, not a second multimedia instance.

==== Digital Video Port (DVP) <dvp>
#ip("dvp")
The 8-bit parallel input supports RGB565 and YUV422, programmable sync polarity and sampling
edge, snapshot/continuous capture and rectangular cropping. AXI4-Stream marks start-of-frame
and end-of-line; central DMA moves capture data to memory. A maximum sensor resolution or frame
rate requires a validated sensor, clock, buffer and memory-bandwidth configuration.

==== JPEG Encoder / Decoder <jpeg>
#ip("jpeg")
The block implements 8-bit Baseline Sequential JPEG for images up to 2048 × 2048. Encoding and
decoding are mutually exclusive in one instance. Direct jobs and a scatter-gather ring use a
private 64-bit DMA master. Resource ownership, interrupts and bounded error completion are
part of the integration. Progressive JPEG and a sustained video-rate claim are not specified.

==== Audio Processing Unit (APU, partial) <apu>
#ip("apu")
The coreless APU includes private DMA, ring infrastructure, a microcode loader, a bounded
sequencer, local storage and processing primitives. The current capability word is
#code("0x00000198"): private DMA, ring, sequencer and resampler bits are set. WAV, MP3, FLAC,
streams and KWS capability bits are clear.

Public direct-job start, ring kick/doorbell, non-bypass stream-route selection and KWS start
are rejected by the current register implementation. The APU therefore must not be advertised
as a usable WAV/MP3/FLAC decoder or keyword detector merely because these register fields and
future engine contracts exist.
#tbd[Production codec microcode, complete codec engines, enabled codec submission, KWS models,
Linux integration and codec/physical qualification remain future deliverables.]

=== Encryption and Data Integrity
==== Crypto Controller <crypto>
#ip("crypto")
The engine provides PIO and central-DMA streaming for AES and SHA-2, plus raw RSA-2048 modular
exponentiation. Software must supply protocol-level padding, key policy and validated operation
parameters. This is not a claim of secure key storage, certified cryptography or side-channel
resistance. HP access is restricted by the management-only control contract.

==== Cyclic Redundancy Check (CRC) <crc>
#ip("crc")
CRC V2 supports 7-, 8-, 16- and 32-bit widths, programmable polynomial, initial/final XOR,
input/output reflection and byte order. Software or system DMA supplies data; the block has
no private memory master or interrupt. CRC is a data-integrity primitive, not encryption or
authentication. Firmware must use the parameters required by its file, packet or boot format.

==== Random Number Generator (RNG) <rng>
#ip("rng")
The integration supplies a deterministic diagnostic source with qualification deasserted.
The controller must retain its fail-closed behavior for unqualified entropy. It cannot be
used as a production cryptographic random source until a qualified PDK entropy source and
the associated validation are integrated.

=== Product Extension Slots
==== Low-Bandwidth Extension (EXT-L) <ext-l>
#ip("ext-l")
EXT-L is a fixed APB4 control slot with one interrupt. Its current capability declaration has
no data master, stream interface or local SRAM.

==== High-Bandwidth Extension (EXT-H) <ext-h>
#ip("ext-h")
EXT-H adds a native AXI64 data master with read/write address bounds, ownership and timeout
handling. Its current capability declaration has no stream interface or local SRAM. It is a
fixed product slot, not the legacy runtime IPSEL multiplexer.
