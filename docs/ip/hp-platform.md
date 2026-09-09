# HP Interrupt and Mailbox Platform

The experimental LP/HP profile adds a 32-source, two-context PLIC at
`0x0C000000` and a bidirectional mailbox at `0x10019000`. Both are self-owned
APB4 peripherals. Their role in boot and lifecycle control is defined by
[LP/HP Architecture](../lp-hp-architecture.md).

## PLIC

Source 0 is permanently reserved. Source 1 is UART1, source 2 is the HP-side
mailbox doorbell, source 3 is EXT-H, and sources 4 through 10 are central DMA,
USB2, SDIO0, SDIO1, SPI-SD, JPEG, and APU respectively. Sources 11 through 31
are reserved and tied low. Resource-owned sources are suppressed unless HP is
the exclusive owner. Each source has a three-bit priority. Context 0 drives HP
machine external interrupt and context 1 drives HP supervisor external interrupt.

| Address offset | Register | Access |
| --- | --- | --- |
| `0x000000 + 4 * source` | source priority | RW |
| `0x001000` | pending bits 31:0 | RO |
| `0x002000 + 0x80 * context` | enable bits 31:0 | RW |
| `0x200000 + 0x1000 * context` | threshold | RW |
| `0x200004 + 0x1000 * context` | claim/complete | RO/RW |

Claim returns the lowest source ID at the greatest priority strictly above the
context threshold, clears its pending bit, and marks it claimed. Writing that
nonzero ID to the same context's claim/complete register completes it. A level
source that remains asserted becomes pending again after completion. Priority
zero disables delivery. The MVP implements one 32-bit pending/enable word and
does not implement MSI, AIA, virtualization, or affinity routing.

## Mailbox

LP writes the `LP_*` bank and rings `LP_DOORBELL`, which sets the HP interrupt
state. HP writes the `HP_*` bank and rings `HP_DOORBELL`, which sets the LP
interrupt state. State is sticky W1C and is qualified by a separate enable for
each destination.

| Offset | Register | Access | Purpose |
| --- | --- | --- | --- |
| `0x000` | `IP_VERSION` | RO | `0x00010000` |
| `0x004` | `CAPABILITY` | RO | `0x00000007` |
| `0x010` | `LP_COMMAND` | RW | LP-to-HP message code |
| `0x014` | `LP_ARG0` | RW | LP-to-HP argument |
| `0x018` | `LP_SEQUENCE` | RW | LP publication sequence; zero means none |
| `0x01C` | `LP_DOORBELL` | WO | Set HP interrupt state |
| `0x020` | `HP_EVENT` | RW | HP-to-LP event code |
| `0x024` | `HP_ARG0` | RW | HP-to-LP argument |
| `0x028` | `HP_SEQUENCE` | RW | HP publication sequence; zero means none |
| `0x02C` | `HP_DOORBELL` | WO | Set LP interrupt state |
| `0x030`/`0x034`/`0x038`/`0x03C` | LP interrupt state/enable/status/test | mixed | LP destination IRQ control |
| `0x040`/`0x044`/`0x048`/`0x04C` | HP interrupt state/enable/status/test | mixed | HP destination IRQ control |

The publication order is code, argument, sequence, memory fence, then
doorbell. `<retrosoc/hal/hp_mailbox.h>` supplies the LP-side API. The initial
Linux userspace acceptance script reports event 1, argument `0x4C4E5801`, and
sequence 1 after init; this is a bring-up verdict, not a general Linux mailbox
driver ABI.

`tests/rtl/plic_tb.sv` and `tests/rtl/hp_mailbox_tb.sv` cover register and
interrupt behavior. `tests/test_hp_boot_bundle.py` enforces the handwritten
mailbox RTL/C offset parity. Production work still requires a Linux mailbox
driver, concurrent sequence/wrap policy, malformed-message tests, lifecycle
timeouts, and fault-injection coverage.
