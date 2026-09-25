# retroSoC Tiny MCU Contract

## Purpose and research boundary

This contract freezes the approved Tiny wired-MCU first release. Tiny owns its
integration in `rtl/tiny`; Mini remains a separate product. The committed
`configs/ci/ihp130-tiny.mk` profile is the reproducible implementation boundary.
The design was approved on 2026-09-25. Source presence does not establish
verification, timing closure, silicon qualification, or low-power performance.

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
- TINY-004: 32 GPIO, two UARTs, two I2C controllers, two general timers,
  CLINT, four DMA channels, PWM, RTC, watchdog, SYSCTRL and architecture info.
- TINY-005: IHP130, 24 MHz system clock, no PLL, 1 MHz CLINT timebase. CPU,
  AXI, APB, RTC and watchdog share the system clock.
- TINY-006: Tiny must build independently of MPW, HP CPU generation and
  multimedia inputs. Shared SDK APIs retain the `rs_` namespace.
- TINY-007: no wireless IP, radio-specific host integration, or wireless stack.

Deferred: RV32 A atomics, RTOS ports, authenticated boot, retention/power gating,
independent sleep clock, 256–512 KiB SRAM, USB, SDIO, standalone general SPI,
I2S, CAN, ADC, multimedia accelerators and other PDK qualification. XPI retains
the existing four-chip-select interface; initial pin-level acceptance uses NOR
on NSS0. The unpopulated chip selects are not qualified device configurations.

## Selected architecture and interfaces

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

## DMA and interrupt contract

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

## Register and software ABI

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

## Clock, reset and lifecycle

External reset is asynchronously asserted and synchronously released. Watchdog
reset restarts the system. Debug hart reset waits for the CPU AXI adapter to
be idle; it must not abandon an accepted transaction. JTAG and asynchronous
external inputs retain the approved Common synchronizer/handshake boundaries.
There is no cross-domain system bus or dynamic clock switching in this release.
RTC/WDG run at the configured system frequency and provide no independent
deep-sleep guarantee. SRAM contents are not initialized by reset.

## Errors, observability and security

Decode/protocol faults complete with AXI errors and feed sticky SYSCTRL fault
information. DMA records errors and supports bounded software waits and abort.
Counters and terminal-test status permit firmware and simulation diagnosis.
Watchdog provides whole-system recovery from a nonresponsive target; this
release makes no unrestricted AXI liveness, secure-boot, production-entropy,
isolation, or safety-certification claim.

## Development order and acceptance

### TINY-P0 — Freeze Tiny MCU Contract

Record the approved requirements here and update document indexes. Acceptance:
reviewable specification, valid links and `git diff --check`.

### TINY-P1 — Product Selection and Shared Infrastructure

Add SOC=TINY, the committed profile, dependency selection and shared build/IP
boundaries. Preserve Mini defaults. Acceptance: configuration/generator tests,
dependency lock validation, no implicit Tiny dependency on Mini product RTL.

### TINY-P2 — AXI4/APB4 Tiny RTL

Implement the hierarchy and contracts above. Acceptance: lint, standalone AXI,
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

## Reproducible commands and current evidence

Use the committed profile, and preserve one `BUILD_TIMESTAMP` when commands
must share artifacts:

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
ArchInfo reports SOC_ID `0x54494e59`, topology `0x20200001`, and FEATURES0
`0x00007ffe`: bits 1/2 SRAM interface/macro, 3 AXI, 4 APB, 5 DMA, 6 UART,
7 I2C, 8 PWM, 9 RTC, 10 watchdog, 11 GPIO, 12 CLINT, 13 timers and 14 XPI.
Bit 0 (PLL) is zero. Tiny FAULT_DETAIL contains the raw AXI response (2/3),
FAULT_STATUS reason is 1 for decode and 2 for slave/protocol errors,
and FAULT_MASTER uses 0 for CPU and 1 for DMA; no RIB encoding is exported.
The public watchdog API is `rs_watchdog_*` with `rs_status_t` and bounded waits.

The [verification record](tiny-soc-verification.md) distinguishes successful
functional checks from missing reference inputs and physical closure. The
product remains `prototype`: negative pre-layout reset-fanout timing must not
be presented as a qualified 24 MHz implementation.

## Commercial delivery gaps

Current-revision verification and physical reports govern readiness. Reusable
VIP, coverage closure, full CDC/RDC, DFT/MBIST, PVT/MMMC, post-layout timing,
power characterization, regulatory and silicon qualification remain separate.
