# Tiny MCU Integration

Tiny is the independent single-Hazard3 wired MCU product. Its frozen target
contract is [Tiny Gen1 QFN64 R2](../../docs/ip/tiny-soc.md). Use
`make CONFIG=configs/ci/ihp130-tiny.mk setup` followed by
`make CONFIG=configs/ci/ihp130-tiny.mk firmware sim`.

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

The active execution order is sequential `TINY-R2-P0` through `TINY-R2-P11`
in the linked contract. Software/DMA scheduling is `TINY-R2-P3`, local CPU/SRAM
`TINY-R2-P4`, concurrent fabric `TINY-R2-P5`, shared-IP/eight-channel integration
`TINY-R2-P6`, RCU `TINY-R2-P7`, XPI PSRAM `TINY-R2-P8`, camera capture
`TINY-R2-P9`, system qualification `TINY-R2-P10` and IHP130 physical
qualification `TINY-R2-P11`. Legacy `TINY-P0` through `TINY-P12` remain in
the contract history. The committed RTL/profile still implements the initial
24 MHz/no-PLL/four-channel design; no faster CPU/SRAM or PLL timing support
follows from this freeze or the `HAVE_PLL` selector alone.

Camera GPIO12-23 ALT1 remains mutually exclusive with I2S. DMA2/request 11,
optional XPI NSS1 PSRAM at `0x54000000` through GPIO29 and shared CAM_XCLK
retain their existing target contracts. RCU target 14 and DVP capabilities
stay unsupported until actual integration. `TINY-R2-P8` and `TINY-R2-P9`
require pin-level XPI PSRAM and full-frame readback, not fast-flash or
separate-controller evidence.
No camera/PSRAM rate is qualified by this freeze.

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
