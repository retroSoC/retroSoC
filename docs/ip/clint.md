# Core-Local Interruptor

The Mini SoC CLINT provides machine software and machine timer interrupts for
the management hart. Its register layout follows the conventional SiFive
CLINT and RISC-V ACLINT-compatible offsets, while its bus-facing logic uses the
retroSoC RIBP target protocol.

## Integration

| Property | Value |
| --- | --- |
| RIBP base address | `0x10020000` |
| RIBP aperture | 64 KiB |
| Implemented Mini SoC harts | 1 management hart |
| RTL hart parameter range | 1 through 4095 |
| Timebase frequency | 1 MHz |
| Management-core interrupts | software IRQ 0, timer IRQ 1 |
| User-core access | denied by the AXI4 interconnect access policy |
| User-core interrupt visibility | masked |

The timebase divider runs from the buffered external reference clock, not the
PLL-selected system clock. A toggle crosses into the system domain through the
Common `edge_det` synchronizer and produces one system-clock pulse per
microsecond. Consequently, changing the PLL frequency does not change the
meaning of an `mtime` tick. `EXT_CLK_HZ` must be an integer multiple of
`CLINT_TIMEBASE_HZ`; committed profiles use 72 MHz and 1 MHz respectively.

## Register ABI

All implemented registers are 32-bit aligned RIBP accesses. Unmapped,
unimplemented-hart, and unaligned accesses complete with `resp_err` and read as
zero. Partial writes use byte strobes. The Mini SoC implements hart 0; the RTL
array dimensions and address decoder are parameterized for additional harts.

| Offset | Name | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| `0x0000 + 4 * hart` | `MSIP` | RW | 0 | Bit 0 controls the hart machine software interrupt. |
| `0x4000 + 8 * hart` | `MTIMECMP_LO` | RW | all ones | Low half of the 64-bit timer comparison value. |
| `0x4004 + 8 * hart` | `MTIMECMP_HI` | RW | all ones | High half of the 64-bit timer comparison value. |
| `0xBFF8` | `MTIME_LO` | RW | 0 | Low half of the shared 64-bit time counter. |
| `0xBFFC` | `MTIME_HI` | RW | 0 | High half of the shared 64-bit time counter. |

The timer interrupt for hart `n` is asserted when `mtime >= mtimecmp[n]` and is
deasserted after software moves the comparison into the future. The registered
interrupt output adds one system-clock cycle of latency. Resetting
`mtimecmp` to all ones prevents an unintended interrupt at reset.

## RV32 Software Contract

The public `<retrosoc/hal/clint.h>` API avoids C 64-bit volatile accesses,
which are not atomic on RV32. Time and comparison reads use a bounded
high-low-high sequence and retry if the high word rolls over. Comparison
writes use the recommended low-all-ones, high, low sequence so an intermediate
value cannot spuriously assert the timer interrupt.

Writing `mtime` itself is inherently non-atomic on a 32-bit bus. Software that
changes it must first prevent concurrent timer handling and account for the
global discontinuity. Normal scheduling code should leave `mtime` running and
only update `mtimecmp`.

## Verification and Current Scope

The self-checking RTL test instantiates two harts and covers reset values,
standard offsets, independent software interrupts, timer comparison, `mtime`
writes, byte strobes, invalid accesses, and synchronized reference-clock
ticks. The SBY target proves bounded RIBP response, `mtime` load/tick/hold
priority, registered timer interrupt behavior, and reaches software interrupt,
timer interrupt, write-time, and error paths. The `ci_smoke` firmware checks
the standard map through the public HAL before completing the normal SoC boot
test.

The current Mini integration does not implement supervisor timer comparison,
multiple privilege domains, or per-hart access filtering inside CLINT. Adding
those features should use the RISC-V ACLINT MTIMER and MSWI split-device model
and a versioned SoC integration update.

The register layout and machine interrupt behavior follow the RISC-V
[machine timer requirements](https://docs.riscv.org/reference/isa/priv/machine.html),
the conventional [SiFive E31 CLINT map](https://starfivetech.com/uploads/e31_core_complex_manual_21G1.pdf),
and the [RISC-V ACLINT specification](https://github.com/riscvarchive/riscv-aclint/blob/main/riscv-aclint.adoc).
