# GPIO Controller

The Mini and Tiny SoC GPIO block controls 32 bidirectional pads. It provides
software, alternate-function, and user-IP ownership modes, atomic output and
output-enable commands, open-drain operation, synchronized and optionally
filtered inputs, per-pin interrupts, irreversible configuration locks, and
capability discovery. The register ABI is directly encoded in RTL and C; a
register generator is intentionally not used in this version.

The [PIO-lite contract](piolite.md) freezes a prospective Tiny binding of the
existing user-IP owner to PIO-lite across all 32 GPIO. The integration and HAL
requirements below are not implemented capabilities: current Tiny ties the
user-IP outputs inactive. GPIO's APB ABI remains V2.0, with unchanged offsets,
reset values, ALT0/ALT1 assignments and lock semantics. This is not an ALT2,
new-pad, QFN64 change or a Mini PIO integration. Existing evidence and Tiny R2
phase IDs remain unchanged; PIO-lite has its own development order.

## Integration

| Property | Value |
| --- | --- |
| User-core APB4 window | `0x10000000`, user access `rw` |
| Management APB4 window | `0x10014000`, user access `none` |
| Pins | 32 |
| APB4 interrupt group | Bit 11 |
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

## Frozen Tiny PIO-lite ownership binding

### Integration and input timing

Tiny MUST bind the PIO block's output data/enables to `user_gpio_if` and consume
its synchronized input path. All 32 ordinary GPIO remain routable; dedicated
boot XPI, JTAG and system pins are outside this binding. `USER_SELECT` selects
the existing user-IP owner over software GPIO and ALT0/ALT1, preserving their
mapping and the existing one-clock high-impedance handoff. Existing peripheral
inputs may still observe their raw pad routes, so software must quiesce the
previous peripheral owner before claiming a pin. Routable pins are not a claim
that all 32 are simultaneously unused by a board profile.

Expose read-only integration outputs for `USER_SELECT`, `USER_STATUS` and
`FILTER_ENABLE`. `USER_SELECT` is the actual GPIO owner-selection register;
`USER_STATUS` MUST equal the active ownership mask already read through APB:
`USER_SELECT & ~handoff`. These are status wires to the PIO integration, not
new APB registers or a new GPIO version. Mini may leave the new outputs unused;
its user-IP ownership behavior remains unchanged.

Tiny's sole user-IP pad owner is PIO-lite. Its `OWNED_MASK` and the Tiny RCU
GPIO gate/reset veto MUST therefore use actual `USER_SELECT`, including the
acquisition handoff interval, independently of mutable SM `CLAIM_MASK` values.
Rewriting a claim or clearing block configuration cannot release or conceal
selected GPIO. Normal PIO block reset/gating and GPIO gate/reset require
`USER_SELECT=0` after checked handback; the existing peripheral-reset contract
also applies. Tiny RCU supplies GPIO clock/reset readiness. Retained GPIO
status bits alone do not prove that its clock runs.

Before SM START, every participating IN/WAIT/OUT/OE pin MUST be claimed and
present in `USER_STATUS`, with its `FILTER_ENABLE` bit clear and GPIO lifecycle
ready. PIO SM output masks MUST be disjoint; input masks may be shared only
within the PIO session. The PIO output enables are continuously qualified by
valid pin ownership and readiness. Lost ownership, enabled filtering on a
claimed pin or lost readiness forces affected PIO outputs high impedance,
stops the affected SMs and records a sticky fault. Restoration of the GPIO
state MUST NOT automatically restart an invalidated session.

Once GPIO ownership has been acquired for a session, guard invalidation also
covers its disabled-but-armed SMs, including an armed DMA job or DMA-prefilled
FIFO waiting for START. Unexpected GPIO reset or lost ownership/readiness
invalidates those sessions, closes their transport admissions and requires
explicit drain/reset recovery and reacquisition before restart. Monitoring
only RUNNING/PAUSED/HALTED would permit stale prefilled data to survive into a
replacement session. Passive CPU preload before any session acquisition is
not supported: CPU FIFO access and enabling a DMA binding require the same
valid ownership/filter/readiness guard. Neither a preload nor a binding
implicitly claims GPIO; software must acquire ownership first.

Filtering is disabled for claimed pins, but the existing input path still
contains two synchronizer stages and a registered filtered-input stage.
PIO timing specifications MUST account for that pipeline and asynchronous
sampling uncertainty. This binding adds no raw-input bypass, independent input
clock or claim of single-cycle external edge observation. PIO and GPIO share
PCLK; PIO's integer divider is an execution enable, not another GPIO clock.

### Checked acquisition and release

The PIO HAL MUST provide checked session acquisition/release instead of treating
the current sequential `rs_gpio_configure()` or `rs_gpio_user_ip_select()`
writes as an atomic reservation. The shared software owner serializes pin
changes against interrupt handlers and other drivers. Hardware pin ownership
checks complement this software contract; they are not a privilege or security
boundary against arbitrary same-hart register writes.

1. Reserve the complete union of participating pins and verify the selected
   board profile, prior owners, SM masks and requested electrical settings.
   Read `USER_SELECT`, `USER_STATUS`, `USER_LOCK`, `CONFIG_LOCK`, filter and
   relevant mode/pad state before mutation. Reject conflicts and every locked
   change required for both acquisition and eventual safe release.
2. Stop the previous peripheral owners, drain their traffic and release their
   external drivers. Prepare a safe native GPIO/ALT state for later handback.
   Keep the PIO SMs stopped and their output enables zero. Disable filtering
   only for claimed pins; do not reprogram the global filter divider/count or
   alter another session's pins. Apply supported pad settings and verify them.
3. Set `USER_SELECT` for the claimed mask and wait boundedly for matching
   `USER_STATUS` after the handoff guard. Verify the unfiltered input and
   lifecycle guards before enabling the SMs. Partial failure keeps affected
   PIO output enables zero and uses checked rollback; it cannot report a
   successful claim or silently resume a previous owner.
4. Release first stops pin activity and completes the bound DMA/stream cleanup
   specified in [DMA V2.1](dma.md#cancellation-and-stream-cleanup). Keep output
   enables zero. Before clearing `USER_SELECT`, ensure the native software OE
   and alternate output path are safe. A retained ALT selection must not
   reactivate a previous peripheral output implicitly.
5. Clear `USER_SELECT` only when permitted, wait boundedly for `USER_STATUS`
   to clear, and then relinquish the software reservation. Restore a previous
   peripheral configuration only through its owner's explicit restart path.
   A timeout or failed readback retains the reservation and reports failure.

Dynamic PIO sessions MUST NOT set `USER_LOCK` or `CONFIG_LOCK` automatically.
`USER_LOCK` protects `USER_SELECT`; `CONFIG_LOCK` protects the separate
mode/pad/filter fields and does not lock ownership. Both remain write-one-set
until GPIO peripheral reset. An existing ownership lock with `USER_SELECT=0`
prevents acquisition. A pin locked with `USER_SELECT=1` cannot be released by
normal cleanup; stop its SM/output, report retained locked ownership and do
not claim that the pin is free. Incompatible configuration locks similarly
fail acquisition/release before an unsafe transition.

Do not reset all GPIO, reset the common DMA or disturb unrelated peripherals
to recover one PIO session. A forced GPIO reset invalidates PIO ownership,
disables the affected SMs/output enables and requires explicit configuration
and reacquisition before restart. Normal PIO/GPIO gate and peripheral-reset
operations must first complete pin release and the associated DMA endpoint
drain/isolation. On timeout, retain the safe state and report failure instead
of acknowledging a reset or transferring ownership prematurely.

### Required implementation evidence

PIO-lite implementation must verify all 32 routes and unchanged ALT0/ALT1,
QFN64 and dedicated boot/debug paths; input pipeline timing; disjoint output
and shared-input claims; two-way handoff; open drain; pre-existing locks;
filter-enabled rejection and filter change while active; same-cycle START and
ownership change; lost readiness/reset; residual DMA/stream traffic; timeout,
rollback, retained locked ownership and explicit rearm. Read-only status
outputs must match APB readback without changing GPIO V2.0 behavior. Verify
that handoff, disabled-but-armed sessions, claim rewrites and block reset
cannot hide selected pins from the RCU veto or restart a stale transport.
Check unrelated pins and affected Mini consumers throughout. The existing tests
below remain baseline evidence and do not establish these new PIO properties.

## Pad capabilities

Digital functionality is identical for every PDK, but pad electrical controls
are reported rather than emulated when a technology lacks a matching cell.
The `pu_o` and `pd_o` signals remain available on the shared GPIO interface so
supported technologies can reach their native IO cells. Unsupported technology
branches do not connect those signals to the IO primitive and do not emulate a
pull in the behavioral model; writes requesting an unsupported pull return
`resp_err`, and the HAL returns `RS_ENOTSUP`.

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
filtering, and configuration lock. The SBY target checks APB4 request
stability, lock monotonicity, user-window isolation, handoff high impedance,
and open-drain safety, with covers for ownership, error, and interrupt paths.
Host C tests cover filter timing limits, and `ci_smoke` checks capability
discovery and public HAL output operations in full-SoC simulation.
