# APB4 I2S

The I2S block is a stereo master transceiver with an APB4 control plane and
dedicated AXI4-Stream TX/RX data ports. It keeps the existing phase-separated
PHY: one SCLK edge updates control and shifter state, and the opposite edge
samples ADC data or updates DAC data. Four format presets cover the previous
16/24-bit and 48/96 kHz combinations. Software can also program SCLK, LRCK,
and MCLK dividers. Host and audio clocks are independent; configuration uses
`cdc_2phase` and sample words use `cdc_fifo_warm_flush`.

## Integration

| Property | Value |
| --- | --- |
| APB4 base address | `0x10007000` |
| APB4 interrupt group bit | 8 |
| Pads | `mclk_o`, `sclk_o`, `lrck_o`, `dacdat_o`, `adcdat_i` |
| AXI4-Stream data width | 32 bits |
| FIFO depth | 128 words |
| DMA request selectors | `I2S_TX`, `I2S_RX` on bulk DMA channel 3 |
| ABI version | `0x00010000` |

MCLK is a buffered copy of `clk_aud_i` when `CLK_DIV[23:16]` is zero. SCLK and
LRCK run only while `CTRL.ENABLE` is set. Slave, TDM, PDM, and left/right
justified formats are not implemented.

## Register ABI

All registers are 32 bits and naturally aligned. Unmapped, unaligned, and
direction-invalid accesses complete with `pslverr`. `FORMAT` and `CLK_DIV`
writes are rejected while `CTRL.ENABLE` is set. `TXDATA` requires
`pstrb=4'hF` and is rejected when the TX FIFO is full or stream TX is enabled.
`RXDATA` reads are rejected when the RX FIFO is empty or stream RX is enabled.
RW registers support byte strobes except the 32-bit data windows.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `CTRL` | RW | Enable, TX/RX enable, loopback, and programmable-clock select. |
| `0x004` | `COMMAND` | WO | TX and RX FIFO flush pulses. |
| `0x008` | `STATUS` | RO | FIFO flags, stall, enable/busy, occupancy, and flush busy. |
| `0x00C` | `STREAM_CTRL` | RW | AXI4-Stream TX and RX enables. |
| `0x010` | `FORMAT` | RW | Preset `[1:0]` and programmable bit-width. |
| `0x014` | `CLK_DIV` | RW | `SCLK[7:0]`, `LRCK[15:8]`, `MCLK[23:16]`. |
| `0x018` | `FIFO_TH` | RW | `UPBOUND[7:0]` and `LOWBOUND[15:8]`. |
| `0x01C` | `TXDATA` | WO | PIO TX word when stream TX is disabled. |
| `0x020` | `RXDATA` | RO/pop | PIO RX word when stream RX is disabled. |
| `0x024` | `INTR_STATE` | RW1C | Sticky threshold and underrun/overrun events. |
| `0x028` | `INTR_ENABLE` | RW | Interrupt enable mask. |
| `0x02C` | `INTR_STATUS` | RO | `INTR_STATE & INTR_ENABLE`. |
| `0x030` | `INTR_TEST` | WO | Write-one software interrupt injection. |
| `0x0F8` | `IP_VERSION` | RO | ABI version, currently `0x00010000` (1.0). |
| `0x0FC` | `CAPABILITY` | RO | Master, 16/24-bit, 128-deep FIFO, stream, and programmable clock. |

`CTRL` bit 0 enables the PHY clocks, bits 1 and 2 enable TX and RX, bit 3
selects analog ADC-to-DAC loopback, and bit 4 selects programmable dividers.
When bit 4 is clear, `FORMAT[1:0]` selects the legacy presets:

| Preset | Width | Fs | `SCLK_DIV` | `LRCK_DIV` |
| --- | --- | --- | --- | --- |
| 0 | 16-bit | 48 kHz | 5 | 15 |
| 1 | 16-bit | 96 kHz | 2 | 15 |
| 2 | 24-bit | 48 kHz | 3 | 23 |
| 3 | 24-bit | 96 kHz | 1 | 23 |

The toggle divider keeps the previous period formula:
`SCLK = clk_aud / (2 * (SCLK_DIV + 1))` and
`LRCK = SCLK / (2 * (LRCK_DIV + 1))`. Occupancy is tracked on the system clock
from local push/pop counts plus a `cdc_2phase` snapshot of the audio-side
counter. DMA stall uses the previous hysteresis around `UPBOUND`/`LOWBOUND`.

The four interrupt bits are TX below `LOWBOUND`, RX above `UPBOUND`, TX
underrun, and RX overrun. Hardware events have priority over a simultaneous
software clear. `irq_o` is the reduction OR of `INTR_STATE & INTR_ENABLE`.

The RTL ABI constants are maintained directly in
`rtl/ip/serial/i2s_define.svh`. Matching HAL offsets and masks are maintained
directly in `crt/src/hal/i2s.c` and `crt/src/hal/i2s_math.c`, not in
`crt/include/retrosoc/core/soc.h`. Changes to either definition must update
the other definition, this document, and the RTL/software tests in the same
change.

## AXI4-Stream and Sample Packing

16-bit mode packs two samples into one 32-bit word: the older sample occupies
`[15:0]` and the newer sample occupies `[31:16]`. 24-bit mode places one sample
in `[23:0]`. `TKEEP` and `TSTRB` are `4'hF`. I2S RX does not assert `TLAST`.
DMA asserts `TLAST` on the final programmed TX word.

## HAL Sequence

Applications should use `rs_i2s_configure()`, `rs_i2s_enable()`, and either
`rs_i2s_write()`/`rs_i2s_read()` or a channel-3 DMA stream configuration.
DMA stream configurations use `RS_DMA_KIND_MM_TO_STREAM` with `I2S_TX` or
`RS_DMA_KIND_STREAM_TO_MM` with `I2S_RX`; the unused address is zero. Program
format and dividers while the controller is disabled.
`rs_i2s_div_from_hz()` derives legal toggle-divider values for an exact
`clk_aud` and sample rate.

## Verification

```
python3 -m pytest -q tests/test_i2s.py
make CONFIG=configs/ci/ihp130.mk formal-i2s
```

The directed test covers version/capability, `pslverr`, enable-protected clock
programming, interrupt test, SCLK activity, and FIFO flush completion. Formal
covers APB handshake completion and the IRQ reduction.
