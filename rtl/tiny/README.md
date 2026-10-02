# Tiny MCU Integration

Tiny is the independent single-Hazard3 wired MCU product. Its frozen target
contract is [Tiny Gen1 QFN64](../../docs/ip/tiny-soc.md). Use
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

The 2026-09-30 P6 target adds shared RNG/CRC/WS2812/Crypto, eight-channel DMA
and a Tiny-owned RCU/SYSCTRL, with no-PLL 96 MHz and single-output-PLL
240 MHz limits. It preserves QFN64 and adds WS2812 on GPIO26 ALT0. The
committed RTL/profile still describes the initial 24 MHz/no-PLL implementation;
P7/P8 must implement the new addresses, streams, clock domains,
reset barriers and shared-driver compatibility. No PLL macro/timing support
is implied by the new specification or the `HAVE_PLL` selector alone.

The 2026-10-01 P10 documentation refreeze adds the existing DVP V2 contract,
camera GPIO12-23 ALT1 (mutually exclusive with I2S), DMA2/request 11 and
optional XPI NSS1 PSRAM at `0x54000000` through GPIO29. Whole-frame external
storage does not change the 128 KiB SRAM, NOR boot, QFN64/power budget or
three-master/eight-channel target. CAM_XCLK shares RCU CLKOUT; RCU target 14
and DVP endpoint capabilities remain unsupported until actual integration.
The remaining order is P10 -> P7 -> P8 -> P11 (PSRAM transport) -> P12
(camera capture) -> P9 (system/physical qualification). P11/P12 require real
pin-level XPI PSRAM and full-frame readback, not fast-flash or the separate
PSRAM controller's tests. No camera/PSRAM rate is qualified by this freeze.

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
