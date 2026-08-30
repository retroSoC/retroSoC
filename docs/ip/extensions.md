# Product Extension Slots

Mini product mode replaces runtime `IPSEL` multiplexing with two fixed APB4
control windows. `user_extensions.json` schema 3 is the slot/IRQ capability
source of truth; `generate_user_extensions.py` emits RTL and C counts without
generating register definitions.

| Slot | Kind | Base | ID | IRQ | Capability |
| ---: | --- | --- | --- | ---: | --- |
| 0 | EXT-L | `0x20008000` | `0x4558544C` (`EXTL`) | 27 | APB4, one IRQ |
| 1 | EXT-H | `0x20009000` | `0x45585448` (`EXTH`) | 28 | APB4, AXI64 master, stream, one IRQ |

## Register ABI

| Offset | Name | Access | Meaning |
| ---: | --- | --- | --- |
| `0x000` | `IDENTIFICATION` | RO | Fixed EXT-L/EXT-H ID |
| `0x004` | `VERSION` | RO | ABI version `0x00010000` |
| `0x008` | `CAPABILITY` | RO | IRQ count and data-master/stream/local-SRAM features |
| `0x00C` | `OWNER` | RW | LP/HP owner and write-once owner lock |
| `0x010` | `COMMAND` | RW | quiesce, reset, and clear-fault controls |
| `0x014` | `STATUS` | RO | present, idle, quiesced, reset, fault |
| `0x018`-`0x024` | `READ/WRITE_BASE/LIMIT` | EXT-H RW | inclusive data-master ACL ranges |
| `0x028` | `TIMEOUT` | EXT-H RW | nonzero transaction timeout budget |
| `0x02C` | `FAULT` | RO | sticky fault state |
| `0x030` | `FAULT_ADDRESS` | RO | first rejected control address |
| `0x034` | `REQUEST_COUNT` | RO | saturating accepted APB request count |
| `0x100` | `DMA_SOURCE` | EXT-H RW | aligned memory-copy source |
| `0x104` | `DMA_DESTINATION` | EXT-H RW | aligned memory-copy destination |
| `0x108` | `DMA_LENGTH` | EXT-H RW | nonzero byte count |
| `0x10C` | `DMA_COMMAND` | EXT-H WO | start or abort |
| `0x110` | `DMA_STATUS` | EXT-H RO | busy, done pulse, and fault |

EXT-L rejects ACL and timeout writes. Invalid or read-only writes complete with
APB `PSLVERR`, set the slot fault, and record the first offending address.
The reference EXT-H master performs sequential 64-bit memory copies. It
supports a byte-masked final beat and reports AXI response errors and
no-progress timeouts. Programmed ranges are enforced by the data-plane M7
firewall; M6 and control-plane addresses remain denied in hardware.

OWNER also controls interrupt routing. LP ownership delivers the slot event on
LP IRQ 28; HP ownership delivers it on HP PLIC source 3. The two routes are
mutually exclusive. Quiesce or reset blocks new EXT-H AXI addresses and STATUS
does not report idle until the DMA and address gate have drained.

`<retrosoc/hal/extension.h>` provides discovery, status, ownership, lifecycle,
and EXT-H ACL operations. Register constants remain independently handwritten
in RTL and software; parity is verified without a register generator.

The legacy `APB4_USER_IP` window remains read-only in product mode and reports
the product extension capability. Its selector APIs return `RS_ENOTSUP`.
Legacy selectable designs and their private register ABIs remain in the MPW
manifest and profile.
