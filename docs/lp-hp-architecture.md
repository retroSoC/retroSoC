# Mini Product LP/HP Architecture

## Product contract

Every committed `MINI_MODE=PRODUCT` profile instantiates two fixed harts:

| Property | LP management | HP application |
| --- | --- | --- |
| Core | Hazard3 | generated VexiiRiscv |
| Hart ID | 0 | 1 |
| ISA | profile RV32I/RV32IM | RV32IMAFDC, S/U mode, Sv32 |
| Reset clock | REF24 at 24 MHz | external 72 MHz safe clock |
| Role | boot, control, diagnostics, recovery | high-throughput application/Linux |
| JTAG | reset owner | selectable while HP is held in reset |

The product generator reports `USER_CORE_COUNT=0`, `USER_IP_COUNT=0`, and
`EXTENSION_COUNT=2`. The former C0-C3 cores and selectable user-IP designs are
available only through `configs/cluster/mini-mpw.mk`; they are not part of the
product address, interrupt, or lifecycle ABI.

There is no hardware cache coherency. Firmware and operating systems must use
explicit ownership, fences, and cache maintenance for shared buffers.

## Clock and reset domains

`soc_clock_reset_subsystem` is the product clock/reset implementation behind
the compatibility `rcu` wrapper.

| Domain | Root | Implemented policy |
| --- | --- | --- |
| AON | dedicated REF24 input | fixed 24 MHz; PLL/clock/pad control and 1 MHz tick |
| LP | REF24 or divided HP | reset default REF24; AUTO/MANUAL division never exceeds 72 MHz |
| HP | EXT72 or PLL | reset default EXT72; generic model supports 72-240 MHz in 24 MHz steps |
| PCLK | LP generated clock | `/1`, `/2`, `/4`, `/8`, `/16`; APB register banks |
| memory | EXT72 `/2` | stable 36 MHz root exported for protocol-engine migration |
| audio | dedicated input | independent audio/RTC/watchdog engine clock |
| DVP, ULPI, JTAG | external functional clocks | dedicated CDC and reset contracts |

Root selection uses Common `safe_clock_mux`; integer division uses Common clock
dividers. The PCLK divider is reset from AON so generated-clock startup cannot
depend on its own downstream reset. `clock_reset_domains.json` records reset
synchronizers and the approved CDC primitives.

`pll_rcu_controller` runs from AON and implements validate, quiesce, LP park,
EXT72 safe selection, PLL apply, lock-low observation, lock qualification,
PLL selection, LP restore, response, and fail-safe states. It blocks new HP
traffic while switching and falls back to EXT72 on timeout or runtime lock
loss. Fault state is sticky until explicitly cleared.

The generic functional PLL maps selectors 0-7 to 72, 96, 120, 144, 168, 192,
216, and 240 MHz from REF24. The ICS55 hard-macro wrapper accepts selector 0
only; other selectors fail safe. This is a digital integration contract, not
PLL jitter, PVT, or clock-tree signoff.

## Control plane

Hazard3 keeps a direct 32-bit control path:

```text
Hazard3 -> AHB-Lite adapter -> LP AXI32 control fabric
        -> LP/PCLK bridge -> APB4 peripheral and system register banks
```

HP uncached MMIO is downsized to AXI32 and crosses HP to LP through
`axi4_async_bridge`. Product access control rejects HP writes to root SYSCTRL,
watchdog, and GPIO administration windows with `SLVERR`; Hazard3 retains full
management access.

The LP control fabric remains the compatibility path for Hazard3 boot and
external-memory accesses. HP, DMA, and accelerator payload traffic uses the
native data plane described below. Moving the remaining controller protocol
engines from LP/PCLK to the exported memory root is an explicit follow-up; the
present RTL does not claim that migration or its physical CDC signoff.

## Native AXI64 data plane

`soc_data_plane` contains an 8-master, 6-target AXI64 crossbar. Read and write
ownership are independent, so one target may read and write concurrently and
different targets progress concurrently. Each direction permits one active
transaction per master and per target; global IDs contain a fixed master
prefix plus the source ID.

| Master | Entry path |
| --- | --- |
| HP I-cache | native AXI64, ID prefix 0 |
| HP D-cache | native AXI64, ID prefix 1 |
| central DMA | PCLK-to-HP async bridge, AXI32-to-64 upsizer |
| SDIO0 / SDIO1 | PCLK-to-HP async bridge, upsizer |
| SPI-SD / USB2 | PCLK-to-HP async bridge, upsizer |
| EXT-H | PCLK-to-HP AXI64 async bridge, ID prefix 7 |

Targets are SRAM, SDRAM, QPI PSRAM, OPI/HyperBus PSRAM, XPI/flash, and a
finite-latency error slave. Current 32-bit memory frontends use AXI64-to-32
downsizers followed by HP-to-LP async bridges. Inactive QPI/OPI windows route
to `SLVERR`. HP I-cache, D-cache, and MMIO no longer share the retired
`hp_axi4_mux3` path.

All async AXI channels use Common `cdc_fifo` storage and a reset barrier. A
single-ended reset aborts the link epoch rather than returning a stale response.

## Memory and shared pads

Product profiles instantiate on-chip SRAM, SDRAM, QPI, OPI/HyperBus, and XPI
integration paths. The on-chip SRAM product size is 32 KiB. ICS55 uses two
16 KiB `SRAM_4096X32_M8_BW` macros; committed ICS55 regression profiles keep
the SRAM interface/macro disabled until commercial models are supplied locally.

QPI and OPI share GPIO21-31 through `memory_pad_mux`. AON retains
`MEM_PAD_MODE` and its lock across LP/HP changes. Reset selects QPI to preserve
the established boot flow. The inactive controller receives safe input values,
its clock/chip-select/output-enable path is inactive, and mapped data access
returns `SLVERR`. The first product implementation permits boot-time selection
only, not a live protocol switch.

## Extensions

Product Mini has fixed control windows:

| Slot | Window | IRQ | Data path |
| --- | --- | --- | --- |
| EXT-L 0 | `0x20008000-0x20008FFF` | LP IRQ 27 | APB4 only |
| EXT-H 1 | `0x20009000-0x20009FFF` | LP IRQ 28 | APB4 plus AXI64 master/stream capability |

Each slot exposes identification, version, capability, owner/lock, lifecycle,
status, timeout, first fault, fault address, and request count. EXT-H adds read
and write ACL ranges. The current reference slot is idle and issues no data
traffic; its interface and isolation contract are live. Software discovers it
through `<retrosoc/hal/extension.h>`.

The old `APB4_USER_IP` window is a read-only compatibility/capability window.
Product writes to `CORESEL`, `IPSEL`, `USER_CORE_RESET`, or
`USER_CORE_STATUS` return APB `PSLVERR`; legacy HAL mutators return
`RS_ENOTSUP`.

## Configuration and local ICS55 models

Committed `configs/ci/ics55.mk` and `configs/cluster/ics55.mk` deliberately set
both PLL and SRAM to `NO`. `configs/local/ics55.example.mk` documents an
ignored local profile with PLL, SRAM interface, SRAM macro, and 32 KiB enabled.
`LOCAL_RTL_FILES` injects commercial SRAM and PLL simulation models into only
that generated variant filelist. `configs/local/*.mk` and `*.sv` are ignored,
so absolute commercial paths are never tracked.

## Evidence boundary

Behavioral RTL, firmware, directed PLL/SYSCTRL tests, manifest parity, and
quality checks are the evidence for this implementation. It must not be called
cache coherent, power isolated, hot-reset safe, timing closed, CDC/RDC signed
off, or silicon-qualified. Synthesis, netlist simulation, STA, MMMC, clock-tree,
DFT, and analogue PLL qualification are separate gates.
