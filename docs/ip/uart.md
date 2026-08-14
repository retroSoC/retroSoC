# RIBP UART

UART0 is the Mini SoC management console and a general-purpose full-duplex
serial port. The UART provides independent 64-byte transmit and receive FIFOs,
fractional baud-rate generation, configurable framing, receive diagnostics,
watermark and timeout interrupts, internal loopback, break generation,
generic-DMA request pacing, and automatic active-low RTS/CTS flow control.

## Integration

| Property | Value |
| --- | --- |
| RIBP base address | `0x10001000` |
| TX/RX FIFO depth | 64 entries each |
| RIBP interrupt group bit | 2 |
| Management-core interrupt | 2 |
| DMA modes | 5 UART TX, 6 UART RX |
| Dedicated signals | `uart0_tx`, `uart0_rx` |
| Flow-control signals | GPIO0 ALT0 `uart0_cts_n`, GPIO1 ALT0 `uart0_rts_n` |

UART0 and the generic DMA share the SoC clock domain. The self-owned `uart_if`
contains RX, TX, active-low CTS/RTS, and IRQ. RX/TX retain their dedicated
package pads. CTS/RTS reuse GPIO0/1 ALT0, while GPIO0/1 ALT1 remains the PS/2
clock/data route. DMA readiness is a separate internal connection.

## Register ABI

All registers are 32-bit and naturally aligned. Unmapped, unaligned,
direction-invalid, reserved-field, and semantically illegal accesses complete
with `resp_err`. RW registers support byte strobes. Command and data registers
require the low byte lane; selected upper lanes must contain zero.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `BAUD_INT` | RW | Integer clocks per serial bit, 24 bits; minimum 16. |
| `0x004` | `BAUD_FRAC` | RW | Fractional clocks per bit in units of 1/256. |
| `0x008` | `LINE_CTRL` | RW | Data width, stop count, and parity. |
| `0x00C` | `CTRL` | RW | TX/RX enable, internal loopback, and TX break. |
| `0x010` | `TXDATA` | WO | Push one character from bits 7:0. |
| `0x014` | `RXDATA` | RO/pop | Character plus parity, frame, break, and noise flags. |
| `0x018` | `STATUS` | RO | Enable, activity, FIFO, configuration, break, and DMA state. |
| `0x01C` | `FIFO_LEVEL` | RO | TX count at bits 6:0 and RX count at bits 22:16. |
| `0x020` | `FIFO_CTRL` | WO | Bits 0/1 flush the disabled, idle TX/RX FIFO. |
| `0x024` | `TX_WATERMARK` | RW | Low-water threshold, 0 through 63; reset value 16. |
| `0x028` | `RX_WATERMARK` | RW | High-water threshold, 1 through 64; reset value 32. |
| `0x02C` | `RX_TIMEOUT_BITS` | RW | Idle bit periods before timeout; zero disables, reset value 32. |
| `0x030` | `ERROR_STATUS` | RW1C | Overrun, parity, frame, break, noise, config, command. |
| `0x034` | `INTR_STATE` | RW1C | RX water/timeout, TX water/done, RX error, break, CTS change. |
| `0x038` | `INTR_ENABLE` | RW | Interrupt enable mask. |
| `0x03C` | `INTR_STATUS` | RO | `INTR_STATE & INTR_ENABLE`. |
| `0x040` | `INTR_TEST` | WO | Write-one interrupt injection. |
| `0x044` | `DMA_CTRL` | RW | TX and RX DMA request enables. |
| `0x048` | `FLOW_CTRL` | RW | Bit 0 enables automatic CTS; bit 1 enables automatic RTS. |
| `0x04C` | `RTS_WATERMARK` | RW | Assert/ready level at bits 6:0 and deassert/halt level at bits 22:16. |
| `0x0F8` | `IP_VERSION` | RO | `0x00030000`, ABI 3.0. |
| `0x0FC` | `CAPABILITY` | RO | `0x03FF4040`, depths and implemented features. |

`LINE_CTRL.DATA_BITS` values 0 through 3 select 5 through 8 bits. Bit 2
selects two stop bits. Bits 4:3 select none, even, or odd parity; value 3 is
reserved. `CTRL` bits 0 through 3 are TX enable, RX enable, loopback, and TX
break.

`RXDATA[7:0]` is the character. Bits 8 through 11 report parity error, frame
error, break, and inconsistent majority samples. A full RX FIFO drops the new
character and sets global overrun. An empty `RXDATA` read returns `resp_err`.

`STATUS[12]` reports synchronized CTS asserted, `STATUS[13]` reports RTS
asserted, and `STATUS[14]` reports that queued TX data is waiting for CTS.
Interrupt bit 6 is sticky on either synchronized CTS edge while automatic CTS
is enabled. All interrupt state, enable, status, test, and clear masks are
seven bits in the configured frame format.

`RTS_WATERMARK` resets to assert/ready level 32 and deassert/halt level 48.
Software must program `assert < deassert <= 64`. UART configuration registers,
including both flow-control registers, can change only while TX/RX are disabled
and both engines are idle. Illegal thresholds or an active-engine update return
`resp_err` and set the configuration error bit.

## Timing and transfer behavior

The programmed bit period is `BAUD_INT + BAUD_FRAC / 256`. A phase accumulator
generates a 16-times sample clock without accumulating whole-bit rounding
error. RX synchronizes the pad and votes three samples around each bit center;
mixed samples set the character noise flag. Start bits are confirmed before
data collection, and invalid starts return directly to idle.

Baud and line format can change only while TX/RX are disabled and both state
machines are idle. Clearing TX enable prevents a new character from starting
but lets the current frame finish; clearing RX enable aborts a partial frame.
TX break is accepted only while the transmitter is idle. FIFO contents are
preserved by enable changes and are discarded only by an accepted flush.

With automatic CTS enabled, synchronized low `cts_n` permits the transmitter
to remove a character from the TX FIFO and start a frame. CTS deassertion never
truncates an active frame; it prevents only the next frame. Internal loopback
bypasses CTS so production test cannot deadlock on an unconnected pad. The CTS
synchronizer resets to not-clear-to-send, which is fail-safe when flow control
is enabled before a valid external level arrives.

With automatic RTS enabled and RX enabled, `rts_n` is low while the receiver can
accept data. At or above the deassert watermark it rises to request that the
peer stop. It remains high until software drains the FIFO to or below the
assert watermark, providing hysteresis. The output releases high immediately
when automatic RTS or RX is disabled. FIFO push/pop changes affect the
registered hysteresis state at the following SoC-clock boundary.

A full `TXDATA` write applies RIBP backpressure while the enabled transmitter
can make progress. A full write while disabled is rejected, avoiding an
unbounded bus wait. TX-done is raised when a transmitted character leaves both
the serializer and FIFO empty. Watermark conditions reassert their interrupt
state while the condition remains true, even after a software clear.

## DMA and software contract

The DMA transfers one 32-bit word per character. UART TX mode uses an
incrementing memory source and fixed `TXDATA` destination; bits 31:8 must be
zero. UART RX mode uses fixed `RXDATA` source and an incrementing memory
destination; bits 11:8 retain per-character errors. RX overrun remains global
because the dropped character cannot carry metadata.

The public HAL exposes structured configuration, bounded CPU reads/writes,
status and interrupt control, FIFO flush, and UART-paced DMA transfers.
`rs_uart_timing_calculate()` uses 64-bit arithmetic and nearest rounding.
`putch()` remains the internal formatted-output sink, while applications use
`rs_uart_init()` or `rs_uart_configure()` instead of raw registers.

Enabling automatic CTS or RTS through `rs_uart_configure()` selects GPIO0 or
GPIO1 ALT0 respectively. Disabling flow control leaves that GPIO mux selection
unchanged so another driver is never enabled implicitly; software must
explicitly reconfigure a pin before reusing it. Default initialization leaves
both automatic functions disabled, preserving console behavior on boards that
do not route flow-control signals.

## Verification and current scope

The self-checking RTL test covers the versioned ABI, access errors, FIFO depth,
8N1 loopback, external frame errors, CTS frame-boundary gating, loopback bypass,
RTS hysteresis, CTS-change interrupt behavior, and DMA request gating. The SBY
target proves FIFO bounds, IRQ composition, disabled-DMA gating, RTS release,
flow-block consistency, forbidden TX FIFO pops, and TX idle/break levels, and
covers bus error, TX/RX activity, flow blocking, RTS assertion, error, and IRQ
paths. Host tests cover exact fractional timing and invalid ranges; the CI smoke
firmware verifies capability registers and loopback through the public HAL.

IrDA, RS485 direction control, automatic baud detection, modem-status inputs,
and low-power wakeup are outside the UART scope. Adding one requires an ABI
and, where applicable, explicit pad and clock/reset integration.
