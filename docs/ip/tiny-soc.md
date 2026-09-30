# retroSoC Tiny Gen1 Product and Package Contract

## Purpose and research boundary

This contract freezes the Tiny Gen1 QFN64 product, package planning and GPIO
alternate-function requirements approved on 2026-09-26. The selected clock
architecture is a 24 MHz crystal with a bypassable PLL and a maximum processor
frequency target of 144 MHz. New integration ABI decisions are explicitly
deferred below; this product/package freeze does not establish implemented
PLL, I2S, SDIO, timing closure, silicon qualification or low-power performance.

Tiny owns its integration in `rtl/tiny`; Mini remains a separate product. The
committed `configs/ci/ihp130-tiny.mk` profile still describes the initial
2026-09-25 implementation: 24 MHz external clock, no PLL, two UARTs and two I2C
controllers. Its RTL, canonical maps, SDK, configuration, generated datasheet
and verification evidence remain the executable baseline until separate
integration work updates them. The baseline sections below retain that
contract and must not be read as the new QFN64 pinout or 144 MHz qualification.

The [RP2350](https://www.raspberrypi.com/products/rp2350/) is a Hazard3-based MCU
reference for software, SRAM, and deterministic I/O. Its dual-core, security,
USB, and PIO features are not Tiny requirements. The
[CAST SRAM controller](https://www.cast-inc.com/peripherals/memory-controllers/sram-ctrl)
illustrates native AXI synchronous SRAM and documented verification delivery;
no commercial implementation or qualification is reused.

## Requirements and non-goals

- TINY-001: one Hazard3 hart, RV32IMC with A disabled, mandatory debug support;
  existing RV32IM firmware remains the default compiler target.
- TINY-002: native 32-bit AXI4 data and APB4 control. The CPU's native AHB-Lite
  terminates at a direct AXI adapter. No RIB/RIBP source or interface is part of
  Tiny's compilation or elaboration closure.
- TINY-003: 128 KiB technology-backed SRAM, XPI NOR boot, no external RAM
  dependency. Reset vector is `0x00000000`; SRAM begins at `0x30000000`.
- TINY-004: 32 bidirectional user GPIO, one UART, one I2C controller, one
  full-duplex I2S controller, one SDIO host, two general timers, CLINT, four
  central DMA channels, four PWM outputs, RTC, watchdog, SYSCTRL and
  architecture info. UART1 and I2C1 are absent from the Gen1 target.
- TINY-005: IHP130, 24 MHz crystal reference and bypassable PLL, with a maximum
  processor frequency target of 144 MHz and a 1 MHz CLINT timebase. Processor,
  bus and external-interface clock rates must be specified separately; this
  requirement does not assign 144 MHz to every bus or peripheral.
- TINY-006: Tiny must build independently of MPW, HP CPU generation and
  multimedia inputs. Shared SDK APIs retain the `rs_` namespace.
- TINY-007: no wireless IP, radio-specific host integration, or wireless stack.
- TINY-008: QFN64 has exactly 64 perimeter terminals: 32 user GPIO, six
  dedicated boot XPI pins, five dedicated JTAG pins, five clock/system-control
  pins and 16 power/ground pins. The exposed pad (EP) is separate from these
  64 terminals. Boot XPI and JTAG do not consume the 32 user GPIO.
- TINY-009: all digital interfaces use one 3.3 V IO supply; IHP130 Core power
  is planned at 1.2 V from an external regulator. The clock analog supply and
  return must meet the selected oscillator/PLL macro requirements. Position
  labels on supply pins do not create independently powered IO banks.
- TINY-010: GPIO retains the `ALT_ENABLE`/`ALT_SELECT` model with GPIO, ALT0
  and ALT1 modes. The Gen1 table below defines the logical mapping. UART/I2C
  alternate input locations must have one selected route, never an OR of
  competing inputs. I2C must preserve open-drain drive and input readback.
- TINY-011: reset must leave user GPIO as high-impedance inputs with alternate
  functions disabled, preserve dedicated boot/debug access, and meet the
  system-control and board-bias requirements below.
- TINY-012: SDIO supports 3.3 V, 1-bit/4-bit operation; 1.8 V switching is not
  a Gen1 requirement. I2S targets master/slave operation, separate transmit and
  receive data, optional MCLK output and an external audio-reference input.
  SDIO/I2S peripheral inputs bypass ordinary GPIO debounce/filter logic;
  their controllers own interface sampling and clock-domain crossings.

Deferred: RV32 A atomics, RTOS ports, authenticated boot, retention/power gating,
independent sleep clock, 256-512 KiB SRAM, USB, standalone general SPI, CAN, ADC,
multimedia accelerators and other PDK qualification. I2S and SDIO are Gen1
requirements awaiting integration, not deferred product features. XPI retains
four chip selects: CS0_N is dedicated to boot NOR, while CS1_N through CS3_N
use GPIO29 through GPIO31. Additional XPI device configurations still require
their own qualification.

## QFN64 package and power planning

QFN64 with EP is the selected package. A 9 x 9 mm body with 0.5 mm pitch is the
preferred outline, subject to die dimensions, pad ring, bond-wire clearance and
the package supplier's drawing. This is a package planning baseline, not a
signed-off bonding diagram. The table uses top-view terminal numbering; a
reviewed physical-order change must preserve the logical GPIO function mapping.

### Terminal budget

| Category | Count | Signals or supplies |
| --- | ---: | --- |
| User GPIO | 32 | GPIO0 through GPIO31 |
| Dedicated boot XPI | 6 | XPI_SCK, XPI_CS0_N, XPI_D0 through XPI_D3 |
| Dedicated JTAG | 5 | TCK, TMS, TDI, TDO, TRST_N |
| Crystal | 2 | XIN, XOUT |
| System control | 3 | RESET_N, BOOT_MODE, TEST_MODE |
| IO supply | 4 | VDDIO_A through VDDIO_D |
| IO return | 4 | VSSIO_A through VSSIO_D |
| Core supply | 3 | VDDCORE_A through VDDCORE_C |
| Core return | 3 | VSSCORE_A through VSSCORE_C |
| Clock analog supply/return | 2 | AVDD_CLK, AVSS_CLK |
| Perimeter total | 64 | 48 signal terminals and 16 power/ground terminals |
| Exposed pad | Separate | EP, intended GND connection pending package confirmation |

### Power and electrical requirements

| Group | QFN pins | Planned connection |
| --- | --- | --- |
| VDDIO_A/B/C/D | 1, 17, 33, 49 | Same 3.3 V IO rail |
| VSSIO_A/B/C/D | 2, 18, 34, 50 | GND, distributed IO return |
| VDDCORE_A/B/C | 9, 31, 47 | Same 1.2 V Core rail for IHP130 |
| VSSCORE_A/B/C | 10, 32, 48 | GND, distributed Core return |
| AVDD_CLK | 53 | Voltage and filtering defined by the oscillator/PLL macro |
| AVSS_CLK | 54 | Ground/return connection defined by the clock macro |
| EP | Center, unnumbered | Intended GND; die attach, substrate and internal connection require confirmation |

GPIO, XPI and JTAG all use the same digital IO voltage. A/B/C/D are physical
position labels, not independent voltage banks; mixed 1.8 V/3.3 V bank use is
outside this contract. Gen1 assumes no internal LDO and allocates no VCAP,
VBAT or 32.768 kHz crystal terminals. RTC/watchdog presence does not imply a
backup power domain or timekeeping with the system clock stopped.

EP supplements the perimeter grounds and must not replace them. The clock
macro is planned to require no external loop-filter terminals; macro selection
must confirm that assumption before the package is signed off. Sixteen power
and ground pins are a budget, not proof of 144 MHz operation. Qualification
must cover Core/SRAM current, simultaneous IO switching, pad drive/load,
bond-wire/package parasitics, voltage drop and electromigration.

Board planning may start with 100 nF near each digital VDD terminal plus bulk
decoupling per rail; final values and placement require regulator and power
network analysis. Clock-supply decoupling follows the selected macro. Pad drive
strength is a technology selection and does not imply software-programmable
drive-strength control in the current GPIO ABI.

### Perimeter pin assignment

| Pin | Name | Pin | Name |
| ---: | --- | ---: | --- |
| 1 | VDDIO_A | 33 | VDDIO_C |
| 2 | VSSIO_A | 34 | VSSIO_C |
| 3 | XPI_CS0_N | 35 | GPIO12 |
| 4 | XPI_SCK | 36 | GPIO13 |
| 5 | XPI_D0 | 37 | GPIO14 |
| 6 | XPI_D1 | 38 | GPIO15 |
| 7 | XPI_D2 | 39 | GPIO16 |
| 8 | XPI_D3 | 40 | GPIO17 |
| 9 | VDDCORE_A | 41 | GPIO18 |
| 10 | VSSCORE_A | 42 | GPIO19 |
| 11 | GPIO26 | 43 | GPIO20 |
| 12 | GPIO27 | 44 | GPIO21 |
| 13 | GPIO28 | 45 | GPIO22 |
| 14 | GPIO29 | 46 | GPIO23 |
| 15 | GPIO30 | 47 | VDDCORE_C |
| 16 | GPIO31 | 48 | VSSCORE_C |
| 17 | VDDIO_B | 49 | VDDIO_D |
| 18 | VSSIO_B | 50 | VSSIO_D |
| 19 | GPIO0 | 51 | GPIO24 |
| 20 | GPIO1 | 52 | GPIO25 |
| 21 | GPIO2 | 53 | AVDD_CLK |
| 22 | GPIO3 | 54 | AVSS_CLK |
| 23 | GPIO4 | 55 | XIN |
| 24 | GPIO5 | 56 | XOUT |
| 25 | GPIO6 | 57 | RESET_N |
| 26 | GPIO7 | 58 | BOOT_MODE |
| 27 | GPIO8 | 59 | TEST_MODE |
| 28 | GPIO9 | 60 | JTAG_TCK |
| 29 | GPIO10 | 61 | JTAG_TMS |
| 30 | GPIO11 | 62 | JTAG_TDI |
| 31 | VDDCORE_B | 63 | JTAG_TDO |
| 32 | VSSCORE_B | 64 | JTAG_TRST_N |

Boot Flash occupies pins 3-8, SDIO occupies pins 19-24, I2S occupies pins
35-40 including its optional reference input, and clock analog/control signals
occupy pins 53-59. The no-PLL external-144-MHz alternative is not the selected
Gen1 definition; pins 53-56 retain AVDD_CLK, AVSS_CLK, XIN and XOUT.

## Gen1 GPIO alternate functions

Every row supports ordinary bidirectional GPIO mode. `Reserved` means no
assigned alternate function; it does not remove the GPIO capability. This
table supersedes the legacy Mini-derived Tiny routing for the Gen1 target,
but is not yet implemented by the current Tiny canonical maps.

| GPIO | QFN pin | ALT0 | ALT1 | Direction or use |
| --- | ---: | --- | --- | --- |
| GPIO0 | 19 | SDIO_CLK | Reserved | Clock output |
| GPIO1 | 20 | SDIO_CMD | Reserved | Bidirectional command |
| GPIO2 | 21 | SDIO_D0 | Reserved | Bidirectional data 0 |
| GPIO3 | 22 | SDIO_D1 | Reserved | Bidirectional data 1 |
| GPIO4 | 23 | SDIO_D2 | Reserved | Bidirectional data 2 |
| GPIO5 | 24 | SDIO_D3 | Reserved | Bidirectional data 3 |
| GPIO6 | 25 | Reserved | Reserved | GPIO input for SD_CD_N |
| GPIO7 | 26 | Reserved | Reserved | GPIO output for SD_PWR_EN |
| GPIO8 | 27 | UART0_TX | PWM0 | Default UART TX |
| GPIO9 | 28 | UART0_RX | PWM1 | Default UART RX |
| GPIO10 | 29 | I2C0_SCL | PWM2 | Default open-drain I2C clock with readback |
| GPIO11 | 30 | I2C0_SDA | PWM3 | Default open-drain I2C data with readback |
| GPIO12 | 35 | I2S_BCLK | Reserved | Master output or slave input |
| GPIO13 | 36 | I2S_LRCLK | Reserved | Master output or slave input |
| GPIO14 | 37 | I2S_DOUT | Reserved | Audio data output |
| GPIO15 | 38 | I2S_DIN | Reserved | Audio data input |
| GPIO16 | 39 | I2S_MCLK | Reserved | Optional audio master-clock output |
| GPIO17 | 40 | I2S_REFCLK_IN | Reserved | External audio-reference input |
| GPIO18 | 41 | PWM0 | Reserved | Default PWM channel 0 output |
| GPIO19 | 42 | PWM1 | Reserved | Default PWM channel 1 output |
| GPIO20 | 43 | PWM2 | Reserved | Default PWM channel 2 output |
| GPIO21 | 44 | PWM3 | Reserved | Default PWM channel 3 output |
| GPIO22 | 45 | PWM_FAULT | Reserved | PWM fault input |
| GPIO23 | 46 | PWM_SYNC | Reserved | PWM synchronization input |
| GPIO24 | 51 | PWM_CAP0 | UART0_TX | PWM capture 0 or alternate UART TX |
| GPIO25 | 52 | PWM_CAP1 | UART0_RX | PWM capture 1 or alternate UART RX |
| GPIO26 | 11 | Reserved | I2C0_SCL | Alternate open-drain I2C clock with readback |
| GPIO27 | 12 | Reserved | I2C0_SDA | Alternate open-drain I2C data with readback |
| GPIO28 | 13 | CLKOUT | Reserved | Divided clock observation output |
| GPIO29 | 14 | XPI_CS1_N | Reserved | Second XPI chip select |
| GPIO30 | 15 | XPI_CS2_N | Reserved | Third XPI chip select |
| GPIO31 | 16 | XPI_CS3_N | Reserved | Fourth XPI chip select |

UART and I2C alternate locations connect to the same UART0 and I2C0 instances.
Repeated PWM names are routes for the same four channels, not extra channels.
UART RX and both I2C input paths require explicit, exclusive routing; the
selection controls and conflict/error behavior are deferred integration ABI.
I2C SCL and SDA must use bidirectional pads with low-drive/release behavior and
external pull-ups, including SCL input readback. Peripheral inputs use the raw
pad path, with sampling and CDC inside the receiving controller rather than
the ordinary GPIO debounce/filter path described in [GPIO](gpio.md).

PWM_CAP0/1 belong to the PWM capture interface. They are not capture pins for
Tiny's two general timers. GPIO6/7 are software GPIO assignments, not extra
SDIO protocol ports. This package table assigns no UART RTS/CTS pins; the old
GPIO0/1 flow-control routes must not be inferred from the legacy mapping.

### Concurrent default usage

| Function | GPIO allocation | Count |
| --- | --- | ---: |
| 4-bit SDIO | GPIO0-5 | 6 |
| Full-duplex I2S with MCLK | GPIO12-16 | 5 |
| UART0 | GPIO8-9 | 2 |
| I2C0 | GPIO10-11 | 2 |
| Total | Non-overlapping default routes | 15 |
| Remaining user GPIO | 32 minus 15 | 17 |

Adding SD card detection/power control on GPIO6/7 and four PWM outputs on
GPIO18-21 uses 21 GPIO in total, leaving 11. External audio reference, PWM
fault/sync/capture and extra XPI chip selects consume additional GPIO when
enabled. The product claim is 32 user-programmable GPIO plus independent boot
Flash and five-wire JTAG, with simultaneous default SDIO/I2S/UART/I2C routing;
it is not 32 unused GPIO after all peripherals are enabled.

## Gen1 clock, reset and board requirements

The selected crystal/PLL architecture reserves XIN/XOUT and AVDD_CLK/AVSS_CLK.
The oscillator and PLL macros, lock/fault handling, safe bypass, reset-release
sequence and frequency-control ABI must be frozen before implementation.
The 144 MHz number is the maximum processor design target, not a measured
operating point, an APB/AXI rate or an IO speed rating. Integration must define
bus and peripheral clocks and parameterize timer, PWM, RTC, watchdog and other
time-dependent behavior while retaining the 1 MHz CLINT timebase. Gen1 makes
no independent sleep-clock or battery-backed RTC claim.

SDIO uses 3.3 V 1-bit/4-bit signaling. The 24 MHz and 48 MHz SD clock rates are
validation targets subject to divider, PHY, pad and card timing checks; the
144 MHz processor target alone does not prove either rate is realizable by
the selected divider. XPI maximum clock and load limits require their own
definition and verification, independent of processor frequency.

Audio requires its own clock source and CDC boundary. For example, 48 kHz
stereo with 32-bit slots needs `48,000 * 2 * 32 = 3.072 MHz` BCLK and a
`256 * 48,000 = 12.288 MHz` MCLK. Neither is obtained by integer division of
144 MHz. GPIO17 provides an external reference for master-mode clock
generation; alternatively a codec can supply BCLK/LRCLK for slave operation.
The existing shared [I2S block](i2s.md) implements master mode only. Slave
mode, the Tiny reference-clock route, bidirectional clock pads and associated
CDC/reset behavior are new Gen1 integration requirements. This frequency
example does not qualify a sample format or board-level audio mode.

### Reset states and external bias

| Pin or group | Required reset/startup behavior | Board or integration requirement |
| --- | --- | --- |
| GPIO0-31 | Input, high impedance, alternate functions disabled | Software initializes each peripheral route |
| XPI_CS0_N | Inactive high before boot access | External pull-up prevents unintended NOR selection |
| XPI_SCK, XPI_D0-3 | Deterministic states from the boot state machine | Must not depend on GPIO software initialization |
| RESET_N | Active until supplies are stable | External pull-up; POR/reset circuit depends on selected implementation |
| BOOT_MODE | External pull-down selects 0 | 0 means normal XPI boot; nonzero behavior is deferred |
| TEST_MODE | External pull-down selects 0 | Reserved for manufacturing test, not ordinary GPIO |
| JTAG | Dedicated debug access remains available | Application pinmux must not disconnect the debug path |
| GPIO7 / SD_PWR_EN | External pull-down keeps card power disabled | Drives a load-switch enable, never the SD card supply directly |

The current IHP GPIO binding provides no internal pull-up/down capability;
required reset, boot, test and bus bias must not rely on internal resistors.
BOOT_MODE does not imply an implemented UART download ROM or recovery loader.
The detailed strap-sampling, test-entry, boot signal levels and reset timing
belong to the subsequent integration contract.

## Deferred Gen1 integration contract

This freeze defines product capabilities and external connections. It does
not allocate new software-visible addresses, IRQs, request selectors or
register fields. The next design stage must close the following items before
an RTL/SDK implementation phase is approved:

| Area | Required follow-up |
| --- | --- |
| Address, IRQ and discovery | Allocate I2S/SDIO control windows and interrupts; retire UART1/I2C1 routes; update capabilities and hardware identity together with the implementation. |
| DMA and AXI | Retain four central DMA channels; freeze channel/request ownership, I2S TX/RX stream paths and SDIO data access. The shared SDIO host has a private AXI DMA master, so its integration must explicitly resolve fabric admission and the legacy two-master limit. |
| Pin routing and software | Freeze alternate-input selection, conflicting-route behavior, CLKOUT controls, HAL pin selection and reset-safe output enables; define handwritten RTL/C register parity. |
| Clock and reset | Select qualified macros and define PLL/bypass controls, bus/peripheral rates, lock/fault handling, timebase updates, audio CDC/RDC and reset sequencing. |
| Boot and manufacturing test | Define strap sampling, nonzero BOOT_MODE behavior and TEST_MODE entry/control; do not infer a download boot ROM. |
| Physical and validation | Confirm analog supply, loop-filter assumption, EP connection, outline/bonding, IO drive/load, power integrity and PVT/post-layout timing; add current-revision simulation, firmware and hardware evidence. |

The shared [DMA](dma.md), [I2S](i2s.md) and [SDIO](sdio.md) contracts describe
existing IP interfaces. Their Mini allocations and standalone test results
must not be copied into a claim of completed Tiny integration. The current
Tiny DMA disables streams, and neither I2S nor SDIO is integrated in its
baseline. The selected package itself does not enable those data paths.

## Existing 24 MHz implementation baseline

The following architecture, DMA/IRQ allocation, register values and lifecycle
describe the committed initial implementation only. They remain useful for
reproducing existing evidence; Gen1 integration changes require the separate
contract freeze above.

### Architecture and interfaces

`retrosoc_tiny` integrates the CPU, two-master fabric, SRAM, XPI and one APB
island. `retrosoc_tiny_asic` owns technology pads; `retrosoc_tiny_tb` owns device
models and terminal verdicts. Product maps, filelists and bindings belong to
Tiny; reusable core/debug, memory and bus utilities belong to shared RTL IP.

AXI has 32-bit addresses/data and one-bit ID/USER. CPU and DMA share one
globally active read or write transaction. Round-robin ownership changes only
after B or RLAST handshake; accepted W traffic cannot change owners. Backpressure
must preserve VALID payloads. Memory accepts naturally aligned 1/2/4-byte INCR
transactions of 1–16 beats within a target and 4 KiB page. MMIO accepts one-beat
FIXED/INCR accesses. Unsupported size/burst/lock/alignment or crossing returns
SLVERR; absent regions return DECERR. Rejected reads return the advertised
number of response beats; rejected writes drain their accepted data before B.

APB uses full setup/access phases, PSTRB and PSLVERR. Registers retain their
existing IP offset, access and reset contracts. A missing peripheral has no
successful decode. GPIO alternate functions retain the selected Mini mappings;
unsupported alternate functions drive neither pads nor peripheral requests.
UART TX/RX and XPI have dedicated pins.

### DMA and interrupt contract

DMA retains the V2 manual register ABI, direct and TCD modes, 32-bit transfers,
up-to-16-beat memory bursts and existing completion/error/W1C/abort semantics.
Four channels are available: 0 UART0, 1 I2C0, 2 I2C1, 3 bulk/XPI. UART1 uses
PIO/IRQ. Stream endpoints and requests for omitted devices are unsupported and
must fail validation rather than wait indefinitely. Capability discovery and
SDK range checks must agree with hardware.

CLINT software/timer occupy core bits 0/1. Reused external sources keep Mini
core-bit numbering: UART0 2, timer0 3, timer1 4, I2C0 7, XPI 9, PWM 11,
RTC 13, watchdog 14, GPIO 18, I2C1 19, DMA 20, UART1 26. The vector has 32
bits (30 Hazard3 external inputs); all omitted sources are zero.

### Register and software ABI

Tiny maps reuse the addresses of implemented Mini peripherals, Flash alias and
XPI aperture. Generated outputs contain address/IRQ/capability metadata and
linker regions, not new generated IP register definitions. SVH/C register pairs
remain handwritten and checked for parity. Hardware identity must describe Tiny,
one MCU hart, 128 KiB SRAM and actual capabilities.

Tiny SYSCTRL preserves fault capture, performance enable/clear and TEST_STATUS
at the existing offsets. The first full-word TEST_STATUS write with bit 31 set
is sticky until system reset; bit 0 is pass and bits 15:8 are the result code.
Unsupported Mini lifecycle/clock controls fail safely; they do not enable HP or
user-core behavior. Unavailable IP drivers are omitted from the Tiny firmware composition.
Unsupported SYSCTRL lifecycle/PLL operations and DMA channel/endpoint requests
return an error before MMIO. GPIO alternate modes follow the Tiny pin map.

The `bringup` and `ci_smoke` applications select product-specific entrypoints.
Startup skips PSRAM setup on Tiny and uses `ld2_all_sram`: code/data copy from
Flash into SRAM, with SRAM BSS and stack. IRQ/CSR support is enabled. Public
headers remain under `<retrosoc/...>`; retired `tiny*.h` paths are not restored.

### Clock, reset and lifecycle

External reset is asynchronously asserted and synchronously released. Watchdog
reset restarts the system. Debug hart reset waits for the CPU AXI adapter to
be idle; it must not abandon an accepted transaction. JTAG and asynchronous
external inputs retain the approved Common synchronizer/handshake boundaries.
There is no cross-domain system bus or dynamic clock switching in this baseline.
RTC/WDG run at the configured system frequency and provide no independent
deep-sleep guarantee. SRAM contents are not initialized by reset.

### Errors, observability and security

Decode/protocol faults complete with AXI errors and feed sticky SYSCTRL fault
information. DMA records errors and supports bounded software waits and abort.
Counters and terminal-test status permit firmware and simulation diagnosis.
Watchdog provides whole-system recovery from a nonresponsive target; this
baseline makes no unrestricted AXI liveness, secure-boot, production-entropy,
isolation, or safety-certification claim.

## Development order and acceptance

TINY-P0 through TINY-P4 retain their original IDs/titles and apply to the
initial 24 MHz implementation approved on 2026-09-25. They do not establish
completion of the QFN64 Gen1 target or waive the recorded timing gaps.
TINY-P5 is the product/package refreeze; integration ABI and subsequent
implementation phases require a separate design freeze.

### TINY-P0 — Freeze Tiny MCU Contract

Record the initial MCU requirements here and update document indexes. Acceptance:
reviewable specification, valid links and `git diff --check`.

### TINY-P1 — Product Selection and Shared Infrastructure

Add SOC=TINY, the committed profile, dependency selection and shared build/IP
boundaries. Preserve Mini defaults. Acceptance: configuration/generator tests,
dependency lock validation, no implicit Tiny dependency on Mini product RTL.

### TINY-P2 — AXI4/APB4 Tiny RTL

Implement the 24 MHz baseline hierarchy and contracts. Acceptance: lint, standalone AXI,
APB, memory, reset and IRQ checks; no RIB/RIBP in the resolved source closure.

### TINY-P3 — SDK Boot and System Verification

Implement generated capabilities, SRAM-only startup, HAL selection and firmware.
Acceptance: both simulators boot through pin-level NOR and emit SIM_TEST_PASS;
test SRAM boundaries, DMA, peripherals, IRQ, disabled A, C instructions and debug.

### TINY-P4 — IHP130 Qualification and Documentation

Add Tiny to IHP130 regression without replacing Mini coverage. Run format/style,
lint, software policy/host tests, Ruff, Pytest, firmware and supported regressions.
Run Yosys, Icarus netlist and OpenSTA; archive macro mapping, area, cell count,
24 MHz timing and warnings under the configuration's build variant. Check docs
and example commands. Record unrun/failed gates explicitly; do not promote
warning baselines or metrics policy as part of this feature.

### TINY-P5 - QFN64 Gen1 Product and Package Refreeze

Freeze TINY-004/005 and the added package, power, pinmux, clock and reset
requirements, preserve the existing implementation/evidence boundary, and
update document indexes and product positioning. This phase changes the
product's specified external interface but makes no RTL, mapping JSON, SDK,
build-configuration, generated-datasheet or register-ABI change.

Acceptance: all perimeter numbers 1-64 occur exactly once; all 32 GPIO match
their package pins and ALT0/ALT1 assignments; the budget is 48 signals plus
16 power/ground terminals with EP separate; the four default interfaces use
15 distinct GPIO and leave 17. Verify reset/power constraints, deferred ABI
items, historical evidence labels, links and commands, then run
`git diff --check`. No new hardware acceptance result is claimed by this
documentation phase. The next stage is Gen1 integration-contract freeze,
followed by separately approved RTL/SDK and physical-qualification phases.

## Baseline reproducible commands and evidence

These commands and numerical values apply only to the initial 24 MHz/no-PLL
implementation. Use the committed profile, and preserve one `BUILD_TIMESTAMP`
when commands must share artifacts:

```sh
make CONFIG=configs/ci/ihp130-tiny.mk setup doctor
make CONFIG=configs/ci/ihp130-tiny.mk firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk SIMU=IVERILOG firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130-tiny.mk SIMU=IVERILOG netsim-boot
make CONFIG=configs/ci/ihp130-tiny.mk STA=OPENSTA sta
make CONFIG=configs/ci/ihp130-tiny.mk metrics package
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
```

`netsim-boot` runs the dedicated `app/asm/tiny_boot.S` gate-level image. It checks
pin-level NOR boot, both ends of physical SRAM, a byte-lane write, UART and the
SYSCTRL terminal result. It requires `SIM_TEST_PASS`; this is separate from the
complete SDK/IRQ/DMA/watchdog acceptance in both RTL simulators. `netsim` retains
the full firmware option. The shared SRAM IP's capability register describes
the IP's native superset; end-to-end requests must obey Tiny's narrower fabric
contract above.

Tiny uses two-cycle AHB ERROR completion so Hazard3 can trap AXI failures. The
shared core/bridge parameters retain Mini's existing default behavior. Tiny
baseline ArchInfo reports SOC_ID `0x54494e59`, topology `0x20200001`, and FEATURES0
`0x00007ffe`: bits 1/2 SRAM interface/macro, 3 AXI, 4 APB, 5 DMA, 6 UART,
7 I2C, 8 PWM, 9 RTC, 10 watchdog, 11 GPIO, 12 CLINT, 13 timers and 14 XPI.
Bit 0 (PLL) is zero; this is not the new Gen1 target capability bitmap.
Tiny FAULT_DETAIL contains the raw AXI response (2/3),
FAULT_STATUS reason is 1 for decode and 2 for slave/protocol errors,
and FAULT_MASTER uses 0 for CPU and 1 for DMA; no RIB encoding is exported.
The public watchdog API is `rs_watchdog_*` with `rs_status_t` and bounded waits.

The [verification record](tiny-soc-verification.md) distinguishes successful
functional checks from missing reference inputs and physical closure. The
baseline remains `prototype`: negative pre-layout reset-fanout timing must not
be presented as a qualified 24 MHz implementation, and provides no evidence
of a 144 MHz Gen1 operating point.

## Commercial delivery gaps

Current-revision verification and physical reports govern readiness. Reusable
VIP, coverage closure, full CDC/RDC, DFT/MBIST, PVT/MMMC, post-layout timing,
power characterization, regulatory and silicon qualification remain separate.
Gen1 additionally requires the deferred integration ABI, oscillator/PLL
characterization, package/bonding and power-integrity review, pad-level
I2S/SDIO validation and 144 MHz processor timing evidence before those product
targets may be advertised as supported operating conditions.
