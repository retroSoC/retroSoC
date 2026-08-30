# Mini Resource Controller

## Scope

The Resource Controller at `0x2000_A000` is the root-management ownership and
interrupt-routing authority for central DMA, USB2, SDIO0, SDIO1, SPI-SD, and
EXT-H. Hazard3 has read/write access; HP MMIO may inspect status but writes are
rejected by the root-control firewall.
It is handwritten RTL and has a matching handwritten
`<retrosoc/hal/resource.h>` API; no register generator is used.

Resource indices are fixed:

| Index | Resource | HP PLIC source |
| ---: | --- | ---: |
| 0 | central DMA | 4 |
| 1 | USB2 | 5 |
| 2 | SDIO0 | 6 |
| 3 | SDIO1 | 7 |
| 4 | SPI-SD | 8 |
| 5 | EXT-H | 3 |

Owner `0` routes the resource interrupt to the existing LP vector. Owner `1`
removes it from LP and routes it to the listed HP PLIC source. Reset masks both
routes. Hardware never delivers one resource interrupt to both owners.

## Register ABI

| Offset | Name | Access | Contract |
| ---: | --- | --- | --- |
| `0x000` | `IP_ID` | RO | `0x52534354` (`RSCT`) |
| `0x004` | `IP_VERSION` | RO | `0x00010000` |
| `0x008` | `CAPABILITY` | RO | resource count and ABI capability |
| `0x00C` | `GLOBAL_STATUS` | RO | cache request/clean and resource fault summary |
| `0x010` | `CACHE_CONTROL` | RW | bit 0 clean ACK, bit 1 live request |

Each resource has a `0x20` stride starting at `0x100`:

| Relative offset | Name | Access | Contract |
| ---: | --- | --- | --- |
| `0x00` | `OWNER` | RW | bits 1:0 owner, bit 8 sticky owner lock |
| `0x04` | `CONTROL` | RW | bit 0 quiesce request, bit 1 reset request |
| `0x08` | `STATUS` | RO | owner, lifecycle request, idle, fault, raw IRQ, and HP block ACK |
| `0x0C` | `FAULT` | RW1C | rejected handoff fault |
| `0x10` | `HANDOFF_COUNT` | RO | saturating successful-owner-change count |

An owner change is accepted only after software requests quiesce and the
resource reports both HP block ACK and idle. The HAL performs block-new,
round-trip CDC acknowledgement, bounded drain, owner write,
and release in that order. An illegal owner, busy handoff, or write after owner lock returns APB `PSLVERR`,
leaves the owner unchanged, and raises the resource-fault interrupt on LP IRQ
29. The implementation currently uses the conservative whole-data-plane idle
condition for DMA and I/O resources; this is safe but can delay an otherwise
independent handoff.

## Cache Maintenance

VexiiRiscv implements `Zicbom` with a 64-byte CBO block. On HP shutdown the AON
lifecycle controller first asserts the Resource Controller cache request while
HP remains released and its MMIO path remains open. Software cleans and
invalidates shared ranges with CBO operations, reports completion to LP, and LP
writes `CACHE_CONTROL.CLEAN`. AON then blocks new addresses and drains the data
plane. Missing acknowledgement is bounded by the lifecycle timeout and records
a forced fault before reset proceeds.

This handshake provides an execution window and explicit evidence point; it
does not create hardware coherency. Buffer ownership, fences, CBO range policy,
and a Linux platform driver remain software responsibilities.

## Delivery Boundary

Central owner/lock, quiesce-gated handoff, cache request/ACK, fault IRQ, and
LP/HP IRQ routing are implemented and directed-tested. `CONTROL.QUIESCE`
blocks the corresponding data-crossbar master and waits per-master outstanding
zero; shared I/O gateways are conservatively blocked as a pair. `CONTROL.RESET`
also blocks new data and masks IRQ but is not yet connected to every peripheral
engine's internal reset state machine. It must not be
described as independent peripheral power isolation or reset containment until
those downstream acknowledgements and fault-injection tests exist.
