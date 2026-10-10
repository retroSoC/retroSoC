# Tiny MCU Integration

Tiny is the independent single-Hazard3 wired MCU product. Its frozen target
contract is [Tiny Gen1 QFN64 R2](../../docs/ip/tiny-soc.md). The 2026-10-07
default is ICS55, `HAVE_PLL=YES`, SAFE24 boot, with the PLL macro parked off.
Use `make CONFIG=configs/ci/ics55-tiny.mk setup` followed by
`make CONFIG=configs/ci/ics55-tiny.mk firmware sim`. IHP130/no PLL remains
explicit compatibility through `configs/ci/ihp130-tiny.mk`. See the
[platform runbook](../../docs/ip/tiny-ics55-platform.md) for source-bound
validation; backend frequency tests are not SYS switching or timing qualification.

The [R2-P4 implementation](../../docs/ip/tiny-soc-r2-local-memory.md) connects the
official dual-port CPU to four independently serviced 32 KiB local SRAM groups.
The 32 physical macros and register ABI are unchanged. Only non-SRAM CPU work
uses the tagged slow path; the external fabric stays serialized until P5.
Source presence alone is not completed phase or physical qualification.

`top` owns product integration, `address_map`, `pin_map` and `integration` own
canonical address, pad, IRQ and clock/reset inputs, `filelist` selects sources,
`dv` owns product verification, and `mk` owns product configuration. Reusable
RTL lives in `rtl/ip`; Common and Hazard3 remain locked managed inputs.
No Tiny source list includes RIB/RIBP or Mini product RTL. Build rules invoke
shared helpers in `scripts/rtl` directly; generated files belong only under
the selected build variant.

The initial IHP130 profile has 128 KiB SRAM, 24 MHz AXI32/APB4, four DMA channels,
and RV32IMC without atomics. Wireless, external RAM, HP cores and accelerators
are outside this release. Run both Icarus and Verilator, the Tiny directed
tests, and the IHP130 regression before claiming qualification. Synthesis and
STA use the Tiny top and clock inventory, not Mini constraints.

The 2026-10-04 R2 target preserves QFN64, the existing peripheral contracts,
eight-channel DMA, Tiny RCU and the DVP/XPI framebuffer target. It adds dual
CPU I/D paths to four contiguous 32 KiB main-SRAM arbitration groups, each with
independent request/response state and an external AXI frontend. CPU and all
main-SRAM macros share SYS at the selected 24/96/192/240 MHz target; no SRAM
CDC or slower SRAM divider is introduced. Only non-SRAM CPU I/D requests merge
into the external path, preserving three external owners with central DMA and
SDIO. Per-target arbitration replaces the global transaction lock. XPI stays
in MEM at 24/96/96/120 MHz and Crypto's six private banks remain PCLK.

The active order inserts TINY-ICS55-P1 before remaining R2 foundation through
P10, followed by SPI, PIO-lite and PPALite functional stages, then a combined
R2-P11/SPI-P5/PIOLITE-P5/PPALITE-P5 complete-product campaign. Existing IDs and
titles remain intact; pre-final post-synthesis timing is observational while
final timing closure is mandatory. Software/DMA scheduling is `TINY-R2-P3`, local CPU/SRAM
`TINY-R2-P4`, concurrent fabric `TINY-R2-P5`, shared-IP/eight-channel integration
`TINY-R2-P6`, RCU `TINY-R2-P7`, XPI PSRAM `TINY-R2-P8`, camera capture
`TINY-R2-P9`, system qualification `TINY-R2-P10` and complete-product physical
qualification `TINY-R2-P11` (historical IHP130 title; now default ICS55).
Legacy `TINY-P0` through `TINY-P12` remain in
the contract history. Executable profiles retain SAFE24 and four DMA channels;
ICS55's present PLL stays off. No faster CPU/SRAM or PLL timing support
follows from this freeze or the `HAVE_PLL` selector alone.

The R2-P2 candidate keeps that executable clock/memory configuration and adds
five-edge local reset release, separate reset leaves for the existing targets,
and CPU-last startup. Shared debug-wrapper defaults remain unchanged for Mini.
The [reset/feasibility runbook](../../docs/ip/tiny-soc-r2-reset-feasibility.md)
defines the source-bound audit and analysis-only frequency sweep. Results and
phase acceptance remain in the verification ledger; this is not routed timing
or high-frequency qualification.

The separately approved [PIO-lite extension](../../docs/ip/piolite.md) is part
of the future standard Tiny product, with its own `PIOLITE-P0` through
`PIOLITE-P5` phases. It adds two state machines, shared 32 x 16-bit program
storage, 32-bit ISR/OSR, 16-bit X/Y and per-machine 8 x 32-bit TX/RX FIFOs in
PCLK. `USER_SELECT` reaches all 32 user GPIO without replacing ALT0/ALT1
assignments or changing the QFN64 pad budget. Planned allocations are APB4
`0x1001C000..0x1001CFFF`, IRQ24, RCU target15 and DMA requests
`PIOLITE_TX=14` / `PIOLITE_RX=15`. TX borrows
bulk channel3 and RX borrows channel2 only after the previous owner releases
it; the eight-channel target and three external AXI owners are unchanged.

PIO-lite is not present in the committed 24 MHz RTL/profile. Integration
depends on the applicable R2-P6/P7 DMA/RCU functionality; GPIO gate/reset must
be rejected while PIO owns any pad. PCLK24/48/60 are engine targets, not
qualified external-I/O rates. `PIOLITE-P5` may join R2-P11 physical work only
on the same PIO-inclusive source and configuration with both evidence sets.
The original R2 phase IDs/titles and performance-only scope remain intact.

Camera GPIO12-23 ALT1 remains mutually exclusive with I2S. DMA2/request 11,
optional XPI NSS1 PSRAM at `0x54000000` through GPIO29 and shared CAM_XCLK
retain their existing target contracts. RCU target 14 and DVP capabilities
stay unsupported until actual integration. `TINY-R2-P8` and `TINY-R2-P9`
require pin-level XPI PSRAM and full-frame readback, not fast-flash or
separate-controller evidence.
No camera/PSRAM rate is qualified by this freeze.

The separately approved [SPI extension](../../docs/ip/spi.md) adds SPI0 to the
future standard Tiny product, with its own `SPI-P0` through `SPI-P5` phases.
It is a PCLK master-only 8/16-bit controller with separate 8 x 32-bit TX/RX
FIFOs, APB4 `0x1001D000..0x1001DFFF`, IRQ25 and RCU target16. DMA V2.2 adds
paced fixed-MMIO requests `SPI_TX=16` / `SPI_RX=17`; payload MMIO retains
single-beat transactions. TX borrows channel3 and RX channel2 only after
prior owners fully drain and release them. No extra AXI master, DMA channel,
SRAM capacity or pad is added. None of these paths exists in the current
24 MHz/no-PLL/four-channel RTL/profile.

The frozen Gen1 routes add only GPIO27 ALT0 SCK, GPIO28 ALT1 MOSI, GPIO30
ALT1 MISO and GPIO31 ALT1 CS_N. Write-only display mode uses ordinary GPIO30
as D/C instead of MISO. Other Gen1 alternates, GPIO29 NSS1 and QFN64 terminal
assignments remain unchanged. `SPI-P3` depends on R2-P6 applying the approved
Gen1 routes, including moving legacy GPIO30/31 PWM capture to GPIO24/25 ALT0,
and on R2-P7 clock/reset behavior. PIO-lite remains the sole USER owner;
SPI native-ready requires USER_SELECT and handoff clear on its session mask
plus valid ALT and GPIO lifecycle state; PIO may retain unrelated pads.
Zero USER_STATUS alone does not prove native readiness.
GPIO gate/reset is rejected while actual PIO ownership or a latched SPI
session remains, including prefill, retained CS and closing/drain state.
SPI gate/reset and PCLK changes require inactive CS and complete wire/DMA drain.

`SPI-P4` camera/PSRAM acceptance depends on R2-P8/R2-P9 and follows capture,
full-frame verification, display, then SD save. It does not add continuous
double-buffer capture/display. The complete camera profile plus display uses
all 32 GPIO; separate display reset/backlight/TE needs an explicit board
solution. `SPI-P5`, PIOLITE-P5 and final R2 physical acceptance must identify
the same SPI- and PIO-inclusive source, configuration and netlist. PCLK24/48/60
and arithmetic SCK12/24/30 MHz ceilings are not qualified pad rates. See the
[SPI evidence ledger](../../docs/ip/spi-verification.md) for pending gates.

The separately approved [PPALite extension](../../docs/ip/ppalite.md) is a
future standard camera-inline PCLK processor, with APB4 `0x1001E000..0x1001EFFF`,
IRQ27 and RCU target17. It performs YUV Y extraction/gray display mapping,
RGB565 ordering, fixed1/2/4 sampling and row-aligned packing after the existing
DVP CDC FIFO. RAW remains default; PROCESS exclusively uses the same
DVP_RX11/DMA2 path. No Pad/pinmux, user-SRAM, DMA request/channel or AXI-owner
change is made. Full source/route/lifecycle wiring is required before capability.

`PPALITE-P0..P5` preserves prior phases. P2 must close or reuse qualified DVP
error/statistic/snapshot/CDC fixes, retaining its ABI and512 B payload FIFO.
P3 depends on applicable R2-P6/P7, P4 on R2-P8/P9 and display's SPI stages.
RAW/PROCESS changes require source/processor and all-DMA quiescence; repeated
frames in a fixed PROCESS route do not stop unrelated channels. Completion
requires source integrity, exact padded layout and final memory responses,
not PIPE_DONE alone. Missing-clock cleanup retains failed ownership.
See the [PPALite ledger](../../docs/ip/ppalite-verification.md); full product
qualification requires the same PPALite/PIO/SPI-inclusive source and netlist.

`make CONFIG=configs/ci/ihp130-tiny.mk regress-pr` runs only Tiny's IHP130
matrix. The regression runner also accepts `--soc TINY`; leaving it unset
retains the combined Mini/Tiny IHP130 matrix. `netsim-boot` uses the compact
assembly SRAM/pad test, while `netsim` uses the full SDK acceptance image.
See the [verification record](../../docs/ip/tiny-soc-verification.md) for
qualification boundaries and the observed reset-distribution timing deficit.

The [Tiny Gen1 datasheet](../../publications/datasheets/tiny/README.md) provides
the source-bound product/register/software reference. Its publication build is
separate from RTL acceptance and does not promote historical test or timing
records into new qualification results.
