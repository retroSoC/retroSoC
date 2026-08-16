# APB4 I2C

The Mini SoC provides two independent controller-mode I2C instances. The I2C
implements 7-bit and 10-bit addressing, queued write and read commands,
repeated START, clock stretching, multi-controller arbitration detection,
programmable digital input filtering, bounded waits, bus recovery, interrupts,
and generic-DMA pacing. The register ABI is directly encoded in RTL and C; a
register generator is intentionally not used in this version.

The electrical and timing behavior follows the controller requirements in the
[NXP UM10204 I2C-bus specification](https://www.nxp.com/docs/en/user-guide/UM10204.pdf).
The FIFO command model and explicit error, timeout, and recovery reporting
follow common commercial controller practice without copying another IP ABI.

## Integration

| Property | I2C0 | I2C1 |
| --- | --- | --- |
| APB4 base address | `0x10006000` | `0x10011000` |
| Command / RX FIFO depth | 16 / 16 | 16 / 16 |
| GPIO alternate function | GPIO7/8 ALT0 | GPIO3/4 ALT1 |
| APB4 interrupt group bit | 7 | 12 |
| Management-core interrupt | 7 | 19 |
| DMA TX/RX modes | 7 / 8 | 9 / 10 |

Both instances and the generic DMA run in the SoC clock domain. Each pad uses
open-drain signaling: the controller output value is permanently zero and its
output enable means pull the line low. External pull-ups are required. The GPIO
HAL selects the corresponding alternate function and open-drain mode during
I2C configuration.

## Architecture

`apb4_i2c` composes four implementation blocks:

- `i2c_reg` owns the APB4 ABI, command and receive FIFOs, sticky error and
  interrupt state, capability discovery, and DMA pacing.
- `i2c_filter` synchronizes SCL and SDA with the Common `cdc_sync` component
  and changes each filtered value only after its programmed stability period.
- `i2c_core` executes START, address, data, ACK/NACK, repeated START, STOP, and
  nine-clock recovery sequences. Common register components hold all protocol
  state.
- `i2c_if` remains the ClusterIP boundary between controller logic and GPIO
  alternate-function integration.

Software queues one 12-bit command per transferred byte. The engine owns the
bus across adjacent commands and enters a bounded hold state when the command
FIFO temporarily empties. A direction change or explicit `RESTART` emits a
repeated START without an intervening STOP. A read command pushes one byte into
the receive FIFO. The last read before STOP must set `NACK_LAST`.

## Register ABI

All registers are 32-bit and naturally aligned. Unmapped, unaligned,
direction-invalid, reserved-field, and semantically illegal accesses complete
with `resp_err`. RW configuration registers support byte strobes. Timing,
filter, and timeout registers can change only while the controller is disabled
and idle.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `CTRL` | RW | Bit 0 enables the controller after valid timing is installed. |
| `0x004` | `SCL_TIMING` | RW | SCL low cycles at 15:0 and high cycles at 31:16. |
| `0x008` | `START_TIMING` | RW | START hold cycles at 15:0 and setup cycles at 31:16. |
| `0x00C` | `DATA_TIMING` | RW | Data hold cycles at 15:0 and setup cycles at 31:16. |
| `0x010` | `STOP_TIMING` | RW | STOP setup cycles at 15:0 and bus-free cycles at 31:16. |
| `0x014` | `FILTER` | RW | SCL filter cycles at 3:0 and SDA filter cycles at 11:8. |
| `0x018` | `STRETCH_TIMEOUT` | RW | Maximum SCL-low stretch wait in SoC clocks; zero disables. |
| `0x01C` | `BUS_IDLE_TIMEOUT` | RW | Maximum bus-idle or bus-free wait; zero disables. |
| `0x020` | `COMMAND_TIMEOUT` | RW | Maximum active-command time; zero disables. |
| `0x024` | `TARGET_ADDR` | RW | Address at 9:0; bit 10 selects 10-bit addressing. |
| `0x028` | `DATA_CMD` | WO/push | Data at 7:0; READ, RESTART, STOP, NACK_LAST at bits 8 through 11. |
| `0x02C` | `RXDATA` | RO/pop | Pop one received byte; an empty read returns `resp_err`. |
| `0x030` | `STATUS` | RO | Enable, activity, FIFO, line, configuration, recovery, and DMA state. |
| `0x034` | `FIFO_LEVEL` | RO | Command count at 7:0 and receive count at 23:16. |
| `0x038` | `COMMAND` | WO | Bits 0 through 3 request abort, recovery, command flush, and RX flush. |
| `0x03C` | `CMD_WATERMARK` | RW | Command low-water threshold, 0 through 15; reset value 4. |
| `0x040` | `RX_WATERMARK` | RW | Receive high-water threshold, 1 through 16; reset value 8. |
| `0x044` | `ERROR_STATUS` | RW1C | Sticky protocol, timeout, overflow, configuration, abort, and recovery errors. |
| `0x048` | `INTR_STATE` | RW1C | Sticky raw interrupt state; active watermarks reassert after clear. |
| `0x04C` | `INTR_ENABLE` | RW | Interrupt enable mask. |
| `0x050` | `INTR_STATUS` | RO | `INTR_STATE & INTR_ENABLE`. |
| `0x054` | `INTR_TEST` | WO | Write-one interrupt injection. |
| `0x058` | `LINE_STATE` | RO | Filtered SCL, SDA, and bus-free state at bits 0 through 2. |
| `0x0F8` | `IP_VERSION` | RO | `0x00020000`, ABI 2.0. |
| `0x0FC` | `CAPABILITY` | RO | `0x007F1010`, feature mask and FIFO depths. |

`STATUS` bits 0 through 12 report enable, controller busy, external bus busy,
command empty/full, RX empty/full, valid configuration, recovery active, SCL,
SDA, TX DMA request, and RX DMA request.

`ERROR_STATUS` bits 0 through 10 report address NACK, data NACK, arbitration
loss, stretch timeout, bus timeout, command timeout, malformed command, RX
overflow, invalid configuration, abort, and failed recovery. Error and event
state is sticky, with a newly observed event taking priority over a concurrent
software clear.

`INTR_STATE` bits 0 through 7 report transfer done, command watermark, RX
watermark, NACK, arbitration loss, timeout, aggregate error, and recovery done.
The external interrupt is the reduction OR of enabled state.

## Protocol and failure behavior

For 7-bit transfers, the engine sends the target address and direction bit.
For 10-bit writes it sends the write header and low address byte. A 10-bit read
first sends that write-form address, issues a repeated START, then sends the
read header. Arbitration is checked whenever the controller releases SDA for a
transmitted one; observing low ends the transfer, releases both lines, flushes
pending commands, and records `ARB_LOST`.

The engine waits for synchronized SCL high, so target clock stretching is
honored on address, data, ACK, STOP, and recovery phases. Independent stretch,
bus, and active-command watchdogs prevent a faulty target or missing command
from holding the controller indefinitely. Software can abort an active
transfer. Recovery generates nine SCL pulses followed by STOP and reports
success only after both lines remain high for the programmed bus-free period.

## Timing, DMA, and software

`rs_i2c_timing_calculate()` converts the source clock and requested bus rate
into integer cycle constraints using 64-bit ceiling arithmetic. It supports
Standard-mode through 100 kHz, Fast-mode through 400 kHz, and Fast-mode Plus
through 1 MHz. It enforces the mode-specific minimum low, high, START, data,
STOP, and bus-free intervals rather than programming only a nominal divider.

The public HAL exposes structured configuration, 7-bit and 10-bit combined
transfers, abort, nine-clock recovery, status, interrupt control, and bounded
waits. Register-oriented devices use `rs_i2c_register_read()` and
`rs_i2c_register_write()` with an `rs_i2c_register_access_t` descriptor. The
descriptor explicitly selects I2C target address width and 8-bit or 16-bit
register addressing, while the API selects I2C0 or I2C1 independently. The
retired fixed-I2C0 compatibility API is not retained. All operations that can
wait take a timeout and return `rs_status_t`.

DMA moves one 32-bit word per command or received byte through the fixed
`DATA_CMD` and `RXDATA` addresses. The initial DMA API deliberately limits a
transfer to 16 bytes because one generic DMA channel cannot refill commands or
drain RX concurrently beyond the hardware FIFO proof boundary. Longer and
combined transfers use the bounded CPU streaming API. Removing this limit
requires scatter/gather or linked DMA descriptors and an end-to-end overflow
proof.

## Verification and current scope

The self-checking RTL test covers ABI discovery and access errors, 7-bit write,
7-bit combined write/repeated-START read, 10-bit read, clock stretching, address NACK,
arbitration loss, and nine-clock recovery. The SBY target proves FIFO bounds,
IRQ composition, valid command consumption, idle open-drain release, and
recovery/busy consistency; 80-cycle covers reach APB4 errors, TX and RX data
paths, DMA pacing, activity, recovery, interrupt, and error state. Deep cover
results retain a compact Yosys witness instead of automatically expanding a
hundreds-of-MiB VCD. Host C tests cover exact timing conversion and invalid
timing ranges.

Target/peripheral mode, SMBus/PMBus extensions, High-speed mode, wakeup from a
separate low-power clock, and multi-controller fairness policy are outside I2C
Adding one requires an ABI, explicit clock/reset and pad review,
and dedicated protocol verification.
