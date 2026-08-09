# GPIO Controller

The Mini SoC GPIO V2 block controls 32 bidirectional pads. It provides
software, alternate-function, and user-IP ownership modes, atomic output and
output-enable commands, open-drain operation, synchronized and optionally
filtered inputs, per-pin interrupts, irreversible configuration locks, and
capability discovery. The register ABI is directly encoded in RTL and C; a
register generator is intentionally not used in this version.

## Integration

| Property | Value |
| --- | --- |
| User-core RIBP window | `0x10000000`, user access `rw` |
| Management RIBP window | `0x10014000`, user access `none` |
| Pins | 32 |
| RIBP interrupt group | Bit 11 |
| Core interrupt | 18 |
| Input synchronizer | Two stages in the SoC clock domain |
| ABI version | `0x00020000` |

The two windows reach one register block. The user window exposes only data
and interrupt operations selected by `USER_ACCESS_MASK`; this mask resets to
zero. The management window owns pin mode, pad controls, filters, interrupt
trigger configuration, user-IP handoff, access policy, and locks. The existing
SoC bus firewall rejects user-core transactions to the management window, so
the peripheral does not infer privilege from request timing or address alone.

## User window

All registers are 32 bits and naturally aligned. Unmapped, unaligned, and
direction-invalid accesses complete with `resp_err`. User data returned from
the block is ANDed with `USER_ACCESS_MASK`; writes can affect only mask bits
that are one.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `DATA_IN` | RO | Synchronized and filtered pin inputs. |
| `0x004` | `DATA_OUT` | RW | Software output latch. |
| `0x008` | `OUT_SET` | WO | Atomically set output-latch bits. |
| `0x00C` | `OUT_CLEAR` | WO | Atomically clear output-latch bits. |
| `0x010` | `OUT_TOGGLE` | WO | Atomically toggle output-latch bits. |
| `0x014` | `INTR_STATE` | RW1C | Sticky raw interrupt state. |
| `0x018` | `INTR_STATUS` | RO | `INTR_STATE & INTR_ENABLE`. |
| `0x01C` | `INTR_ENABLE` | RW | Per-pin interrupt enable. |
| `0x020` | `INTR_ENABLE_SET` | WO | Atomically set interrupt-enable bits. |
| `0x024` | `INTR_ENABLE_CLEAR` | WO | Atomically clear interrupt-enable bits. |
| `0x0F8` | `IP_VERSION` | RO | ABI version. |
| `0x0FC` | `CAPABILITY` | RO | Implemented digital feature summary. |

## Management window

| Offset | Name | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| `0x000` | `DATA_IN` | RO | `0` | Synchronized and filtered inputs. |
| `0x004` | `DATA_OUT` | RW | `0` | Software output latch. |
| `0x008` | `OUT_SET` | WO | - | Atomic output set. |
| `0x00C` | `OUT_CLEAR` | WO | - | Atomic output clear. |
| `0x010` | `OUT_TOGGLE` | WO | - | Atomic output toggle. |
| `0x014` | `OUTPUT_ENABLE` | RW | `0` | Software output-enable latch. |
| `0x018` | `OE_SET` | WO | - | Atomic output-enable set. |
| `0x01C` | `OE_CLEAR` | WO | - | Atomic output-enable clear. |
| `0x020` | `OE_TOGGLE` | WO | - | Atomic output-enable toggle. |
| `0x024` | `OPEN_DRAIN` | RW | `0` | Drive zero for output low and release for output high. |
| `0x028` | `INPUT_CMOS` | RW | `0` | Select the PDK CMOS input characteristic when supported. |
| `0x02C` | `PULL_UP` | RW | `0` | Enable pad pull-up when supported. |
| `0x030` | `PULL_DOWN` | RW | `0` | Enable pad pull-down when supported. |
| `0x034` | `ALT_ENABLE` | RW | `0` | Select an alternate function instead of software output. |
| `0x038` | `ALT_SELECT` | RW | `0` | Select ALT1 when set and ALT0 when clear. |
| `0x03C` | `USER_SELECT` | RW | `0` | Select user-IP pad ownership. |
| `0x040` | `USER_LOCK` | W1S/RO | `0` | Permanently lock `USER_SELECT` bits until reset. |
| `0x044` | `USER_STATUS` | RO | `0` | Active user ownership after the handoff guard cycle. |
| `0x048` | `USER_ACCESS_MASK` | RW | `0` | Permit user-window data and interrupt bits. |
| `0x04C` | `INTR_RISE_ENABLE` | RW | `0` | Rising-edge event selection. |
| `0x050` | `INTR_FALL_ENABLE` | RW | `0` | Falling-edge event selection. |
| `0x054` | `INTR_HIGH_ENABLE` | RW | `0` | High-level event selection. |
| `0x058` | `INTR_LOW_ENABLE` | RW | `0` | Low-level event selection. |
| `0x05C` | `INTR_ENABLE` | RW | `0` | Per-pin interrupt output enable. |
| `0x060` | `INTR_STATE` | RW1C | `0` | Sticky raw interrupt state. Events win over clear. |
| `0x064` | `INTR_STATUS` | RO | `0` | Enabled interrupt state. |
| `0x068` | `INTR_TEST` | WO | - | Write-one software interrupt test. |
| `0x06C` | `FILTER_ENABLE` | RW | `0` | Enable the digital stability filter per pin. |
| `0x070` | `FILTER_DIV` | RW | `0` | Sample every `FILTER_DIV + 1` clocks. |
| `0x074` | `FILTER_COUNT` | RW | `0` | Required stable samples, valid range 1 through 15. |
| `0x078` | `CONFIG_LOCK` | W1S/RO | `0` | Permanently lock per-pin configuration until reset. |
| `0x0F4` | `PAD_CAPABILITY` | RO | PDK-specific | CMOS, pull-up, and pull-down support. |
| `0x0F8` | `IP_VERSION` | RO | `0x00020000` | ABI version 2.0. |
| `0x0FC` | `CAPABILITY` | RO | `0x007F4220` | Digital feature, filter width, ABI, and pin count. |

`CONFIG_LOCK` protects output enable, open-drain, input mode, pulls, alternate
selection, user access, interrupt trigger selection, and filter enable.
`USER_LOCK` independently protects user-IP ownership. Both are write-one-set
and clear only on peripheral reset. Writes that request an unsupported pad
feature, simultaneous pull-up and pull-down, conflicting edge and level
triggers, a zero filter count, a timing change while any filter is active, or
a change to a locked bit complete with `resp_err` and do not update state.

## Pin and interrupt behavior

Software output and output-enable aliases avoid read-modify-write races. ALT0
and ALT1 outputs are selected per pin. Setting `USER_SELECT` changes the source
to `user_gpio_if`; every ownership transition forces the physical output
enable low for one complete SoC clock before the new owner can drive. Open
drain is applied after this mux: logical zero drives low, while logical one
releases the pad.

The raw pad input passes through a two-stage synchronizer. When filtering is
disabled, the synchronized value feeds `DATA_IN`, the interrupt detector, and
the user IP. When enabled, the input must disagree with the current filtered
value for `FILTER_COUNT` samples before changing. Alternate peripheral inputs
continue to receive the raw pad signal because each peripheral owns its CDC
requirements, for example the DVP pixel clock.

Each pin supports rising, falling, both-edge, high-level, or low-level
interrupt operation. Edge and level modes cannot be combined for one pin, and
high plus low is invalid. Level events reassert sticky state while the level
remains active. The output interrupt is the reduction OR of
`INTR_STATE & INTR_ENABLE`.

## Pad capabilities

Digital functionality is identical for every PDK, but pad electrical controls
are reported rather than emulated when a technology lacks a matching cell.

| PDK | CMOS input select | Pull-up | Pull-down |
| --- | --- | --- | --- |
| GF180 | Yes | Yes | Yes |
| ICS55 | Yes | Yes | Yes |
| SKY130 | Yes | No | No |
| IHP130 | No | No | No |
| S110 / generic behavioral | No | No | No |

Drive strength, slew rate, sleep retention, and wakeup are deliberately not
implemented as generic GPIO bits. They require qualified PDK pad cells,
power-domain state, and UPF/physical-design ownership before a portable ABI is
safe.

## Software and verification

`<retrosoc/hal/gpio.h>` exposes structured pin configuration, atomic data
operations, interrupt control, user ownership and access policy, lock
commands, capability discovery, and integer filter timing conversion. The HAL
returns `RS_ENOTSUP` before requesting unsupported electrical features.

The self-checking RTL test covers reset values, access errors, atomic output
and OE, user-window masking, guarded user-IP handoff, open drain, pull
conflicts, edge interrupt state, W1C, interrupt test, trigger conflicts,
filtering, and configuration lock. The SBY target checks RIBP request
stability, lock monotonicity, user-window isolation, handoff high impedance,
and open-drain safety, with covers for ownership, error, and interrupt paths.
Host C tests cover filter timing limits, and `ci_smoke` checks capability
discovery and public HAL output operations in full-SoC simulation.
