# PLL Dynamic Clock Control

The system powers up on the `extclk_i_pad` external safe clock. After software
submits a PLL frequency request through SYSCTRL, the RCU switches to the safe
source, configures the PLL, waits for lock, and switches back in the external
reference-clock domain. PLL lock transitions do not reset the system. A failed
configuration leaves the system on the safe clock.

## Registers

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x08` | `PLL_CFG` | RW | `HP_PSTATE[2:0]`: 72, 96, 120, 144, 168, 192, 216, or 240 MHz. |
| `0x0c` | `PLL_CMD` | WO | bit 0 is `APPLY`; bit 1 is `CLEAR_ERROR`. |
| `0x1c` | `PLL_STATUS` | RO | Active profile, validity, busy state, error and cause, safe-clock source, lock state, and capability. |

Applications use `rs_clock_set_frequency()` and `rs_clock_get_status()` from
`<retrosoc/hal/clock.h>`; PDK-specific PLL divider settings are not exposed.

## Software Flow

1. Run the transition routine from SRAM, disable interrupts, and quiesce DMA,
   serial transfers, and other frequency-sensitive transactions.
2. Call `rs_clock_set_frequency()` and wait with a bounded timeout.
3. On success, reprogram UART, SPI, I2C, timer, and other divider-dependent
   peripherals for the new frequency before restoring normal operation.
4. `RS_ENOTSUP` means the current PDK has no integrated dynamic PLL or
   glitch-free clock-switch backend. The system remains on the external safe
   clock.

`PDK_BEHAV` provides all eight dynamic frequencies and lock behavior. A real PDK
must integrate a characterized PLL macro, lock timing, and glitch-free clock
switch before setting capability to 1. The ICS55 hard wrapper advertises only
the qualified selector-0 configuration; requests for other selectors fail safe.
