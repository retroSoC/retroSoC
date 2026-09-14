# Mini Resource Controller

[GA2D Phase 2](ga2d.md#phase-2---expand-axi64-fabric-and-resource-integration)
adds resource 8 and version 1.1. It covers only the dedicated PCLK-to-HP
AXI64/ID3 GA2D bridge placeholder, whose source is idle. LP vector 32 / HP
PLIC source 11 and `APB4_GA2D` shell wiring are implemented in Phase 3. The
shell has IRQ-only capability; it does not create GA2D payload/DMA or pixel
work, and the bridge source remains idle. Its source-stop/drain-before-block
sequence is specified there. Existing resources and register fields are not
renumbered or reinterpreted.

## Scope

The Resource Controller at `0x2000_A000` is the root-management ownership and
interrupt-routing authority for central DMA, USB2, SDIO0, SDIO1, SPI-SD,
EXT-H, JPEG, and APU. Hazard3 has read/write access; HP MMIO may inspect status
but writes are rejected by the root-control firewall.
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
| 6 | JPEG | 9 |
| 7 | APU | 10 |
| 8 | GA2D APB shell and idle bridge placeholder | 11 |

For resources 0 through 7, owner `0` routes the resource interrupt to the
existing LP vector. Owner `1` removes it from LP and routes it to the listed HP
PLIC source. Resource 8 routes the GA2D shell raw IRQ to LP vector 32/external
ordinal 30 for owner `0`, or HP PLIC source 11 for owner `1`. Reset masks both
routes. Hardware never delivers one resource interrupt to both owners.

## Register ABI

| Offset | Name | Access | Contract |
| ---: | --- | --- | --- |
| `0x000` | `IP_ID` | RO | `0x52534354` (`RSCT`) |
| `0x004` | `IP_VERSION` | RO | `0x00010001` |
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

For resource 8, the PCLK source stop admits an already presented address
handshake before closing new traffic. Its HP block and acknowledgement require
a fresh synchronized source-quiesced confirmation after the source has drained
its AXI state. This prevents a stale idle indication from acknowledging a legal
`WVALID`-before-`AWVALID` write. The PCLK controller view also qualifies
resource-8 idle and ACK with the live source-safe-idle signal.

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
LP/HP IRQ routing are implemented and directed-tested. Phase 3 adds the GA2D
PCLK shell raw IRQ to resource 8, while its AXI bridge remains idle and it does
not provide a functional GA2D engine. `CONTROL.QUIESCE` blocks the corresponding
data-crossbar master and waits per-master outstanding zero; shared I/O gateways
are conservatively blocked as a pair. `CONTROL.RESET` also blocks new data and
masks IRQ but is not yet connected to every peripheral engine's internal reset
state machine. The APU-P1 shell is an exception: its index-7 quiesce
acknowledgement and reset are connected locally in PCLK. It must not be
described as independent peripheral power isolation or reset containment until
those downstream acknowledgements and fault-injection tests exist.
