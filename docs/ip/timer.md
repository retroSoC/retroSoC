# RIBP General Timer

The Mini SoC contains two identical 32-bit general-purpose timers. Each timer
has a 16-bit prescaler, free-running, periodic, and one-shot modes, selectable
up/down counting, two compare channels, sticky interrupts, and optional freeze
while the management Hazard3 core is halted by its Debug Module.

## Integration

| Property | Timer 0 | Timer 1 |
| --- | --- | --- |
| RIBP base address | `0x10002000` | `0x10003000` |
| RIBP interrupt group bit | 3 | 4 |
| Management-core interrupt | 3 | 4 |
| Counter width | 32 bits | 32 bits |
| Prescaler width | 16 bits | 16 bits |
| Compare channels | 2 | 2 |

The timer remains accessible while its counter is debug-frozen. The freeze
input is the management hart's synchronized halted indication; it does not
create or gate a clock. Both the prescaler and the main counter use the normal
SoC clock and stop through synchronous enables.

## Register ABI

All registers are 32 bits and naturally aligned. Unmapped, unaligned, and
direction-invalid accesses complete with `resp_err`. Partial writes are
supported for RW registers. Write-one-to-clear and software-interrupt writes
only act on a selected low byte.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `CTRL` | RW | Enable, mode, direction, debug freeze, and compare enables. |
| `0x004` | `LOAD` | RW | Active period value; a write also loads the live counter. |
| `0x008` | `VALUE` | RO | Current counter value. |
| `0x00C` | `BGLOAD` | RW | Replaces `LOAD` without changing the live counter; used at the next periodic reload. |
| `0x010` | `PRESCALE` | RW | Divide the source clock by `PRESCALE + 1`; writable only while stopped. |
| `0x014` | `COMPARE0` | RW | Compare channel 0 value. |
| `0x018` | `COMPARE1` | RW | Compare channel 1 value. |
| `0x01C` | `STATUS` | RO | Bit 0 `ACTIVE`, bit 1 `DEBUG_FROZEN`. |
| `0x020` | `INTR_STATE` | RW1C | Sticky timeout, compare 0, and compare 1 state. |
| `0x024` | `INTR_ENABLE` | RW | Interrupt enable mask. |
| `0x028` | `INTR_STATUS` | RO | `INTR_STATE & INTR_ENABLE`. |
| `0x02C` | `INTR_TEST` | WO | Write-one software interrupt test. |
| `0x0F8` | `IP_VERSION` | RO | ABI version, currently `0x00020000` (2.0). |
| `0x0FC` | `CAPABILITY` | RO | Implemented counter, prescaler, mode, compare, direction, and debug-freeze capabilities. |

`CTRL.MODE` is `0` for free-running, `1` for periodic, and `2` for one-shot;
`3` is reserved and rejected. Bit 3 selects down-counting. Bits 4 through 6
enable debug freeze, compare 0, and compare 1 respectively. Mode and direction
cannot change while `CTRL.ENABLE` is set. Software must stop the timer before
changing either field or the prescaler.

The three interrupt bits are timeout at bit 0, compare 0 at bit 1, and compare
1 at bit 2. Events win over a simultaneous software clear, preventing hardware
events from being lost. The external interrupt is the reduction OR of
`INTR_STATE & INTR_ENABLE`.

The RTL ABI constants are maintained directly in
`rtl/ip/peripheral/timer_define.svh`. The matching HAL offsets and masks
are maintained directly in `crt/src/hal/timer.c`. Changes to either definition
must update the other definition, this document, and the RTL/software tests in
the same change.

## Counting Semantics

One counter update occurs every `PRESCALE + 1` SoC clocks. For up-counting
periodic and one-shot modes, a terminal event occurs at `VALUE >= LOAD`. For
down-counting modes, it occurs at `VALUE == 0`. A periodic timer reloads zero
when counting up and `LOAD` when counting down. A one-shot timer holds its
terminal value and clears `CTRL.ENABLE`.

Free-running mode wraps at the natural 32-bit boundary. Periodic and one-shot
periods contain `LOAD + 1` timer ticks. Compare events sample the current value
on a timer tick and become sticky when the corresponding compare channel is
enabled.

The HAL exposes structured configuration, bounded millisecond delays, value
and status snapshots, compare programming, and interrupt control. Delay
conversion uses the active clock reported by SYSCTRL and selects the smallest
16-bit prescaler that fits the requested interval in the 32-bit counter.

## Verification and Current Scope

The self-checking RTL test covers both count directions, all operating modes,
prescaling, background reload, both compare channels, debug freeze/resume,
sticky interrupt clear/test behavior, byte strobes, and RIBP access errors.
The SBY target proves response, hold, one-shot stop, sticky-event, and interrupt
invariants and covers normal and error paths. Host C tests cover period
conversion boundaries, and the `ci_smoke` firmware exercises both timer
instances through the public HAL.

The current ABI does not include capture inputs, PWM outputs, cascaded 64-bit
operation, DMA requests, or multiple clock sources. Those features require new
SoC pins or routing and a versioned ABI extension; they must not reinterpret
the existing register fields.
