# Configurable Native-AXI4 On-chip SRAM

## Scope and maturity

The Mini SoC on-chip SRAM is a synthesis-time configurable, 32-bit native-AXI4
target backed by fixed `1024 x 32` single-port technology wrappers. Supported
capacities are 4, 16, 32, 64, and 128 KiB. The data aperture starts at
`0x3000_0000`; its generated end address and linker length match the selected
physical capacity. A management-only APB4 window at `0x1001_7000` reports the
configuration and saturating performance counters.

This release is a protocol and performance MVP. It is not a safety-certified,
silicon-proven, or tapeout-ready memory subsystem. ECC, autonomous scrubbing,
MBIST, redundancy repair, power gating, retention, and independently licensed
AXI verification IP signoff remain outside the delivered scope.

## Commercial reference review

The reference review was refreshed on 2026-08-24 from vendor-owned material.
These products guide architecture and delivery expectations; they are not RTL
dependencies and do not transfer a vendor's qualification to retroSoC.

| Reference | Problem and architecture | Status and decision |
| --- | --- | --- |
| [Raspberry Pi RP2350](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf) | Main SRAM is split into two four-way word-striped groups. Two independent 4 KiB banks provide low-contention storage for stacks or hot data. | The official data sheet remains maintained. Reuse explicit bank ownership. Do not add low-bit striping while the Mini interconnect grants one transaction per target; it would increase switching without increasing target throughput. |
| [STM32H7 embedded SRAM and RAMECC](https://www.st.com/resource/en/reference_manual/rm0455-stm32h7a37b3-and-stm32h7b0-value-line-_advanced-armbased-32bit-mcus-stmicroelectronics.pdf) | AXI SRAM, AHB SRAM, TCM, backup SRAM, and power domains separate bandwidth, deterministic latency, and retention. SECDED reports failing address/data, and partial writes require read-modify-write. | STM32H7 products remain active. Reuse capability discovery, error localization, and a separate future ECC layer. Avoid claiming unchanged latency before ECC/RMW timing is verified. |
| [NXP i.MX RT FlexRAM](https://www.nxp.com/docs/en/application-note/AN12077.pdf) and [RT1170 ECC guidance](https://www.nxp.com/docs/en/application-note/AN13204.pdf) | Fixed banks can be assigned to OCRAM, ITCM, or DTCM. This depends on boot configuration, legal TCM sizes, linker agreement, and complete ECC initialization. | NXP continues to update RT1170 material. Reuse bank-based product configuration and generated linker consistency. Avoid runtime repartitioning and fuse/boot-order coupling for Mini. |
| [Infineon AURIX TC3xx MTU/SSH](https://www.infineon.com/assets/row/public/documents/10/44/infineon-aurix-tc3xx-part1-usermanual-en.pdf) | SRAM support hardware surrounds memories with ECC/EDC, address monitoring, error tracking, initialization, and MBIST. A central MTU exposes a uniform control plane. | AURIX documentation and products remain active. Reuse separation between functional access and reliability support. Avoid destructive runtime MBIST without a quiesce contract. |
| [CAST SRAM-CTRL and ECC-SRAM](https://www.cast-inc.com/peripherals/memory-controllers/sram-ctrl) | Commercial IP emphasizes native AXI/AHB/APB, byte accesses, low latency, lint/scan readiness, SECDED, testbenches, scripts, and integration documentation. | The products remain offered. Use the features and deliverables as an IP-readiness checklist, not as evidence for this implementation. |
| [Synopsys STAR Memory System](https://www.synopsys.com/articles/embedded-memory-test.html) | Hierarchical test, diagnosis, redundancy repair, tester patterns, and physical failed-bit mapping address manufacturing yield and field diagnosis. | The product family remains published. Keep DFT/repair as a physical-delivery phase instead of embedding an unqualified March engine in the AXI datapath. |

The selected architecture is static capacity configuration plus a native AXI
datapath. Dynamic bank reassignment, caches, multiple outstanding IDs, and
multi-master bank scheduling require changes above this target and are not
cost-effective in the current one-owner-per-target fabric.

## Configuration and address contract

`SRAM_SIZE_KIB` is part of the reproducible configuration digest and accepts
only `4`, `16`, `32`, `64`, or `128`. IHP130, GF180, and SKY130 CI profiles
select `32`; ICS55 keeps the SRAM absent. IHP130 benchmark/CoreMark profiles
retain `128`. The address-map generator uses the selected value for RTL decode
macros, SDK base/size/end constants, and the linker `LENGTH(SRAM)`.

`HAVE_SRAM_IF=YES` marks the memory present and elaborates the bank array. When
it is `NO`, the AXI target returns `DECERR`; the APB window remains readable
with `PRESENT=0`, zero memory bytes, and zero banks.

| `SRAM_SIZE_KIB` | 4 KiB data banks | Address range |
| ---: | ---: | --- |
| 4 | 1 | `0x3000_0000..0x3000_0fff` |
| 16 | 4 | `0x3000_0000..0x3000_3fff` |
| 32 | 8 | `0x3000_0000..0x3000_7fff` |
| 64 | 16 | `0x3000_0000..0x3000_ffff` |
| 128 | 32 | `0x3000_0000..0x3001_ffff` |

## AXI4 datapath

The target uses the project-wide 32-bit address/data and 1-bit ID/USER
geometry. It accepts one active read or write transaction, gives AR priority
when AR and AW are simultaneously valid, and preserves the ID to the terminal
response.

Supported requests are naturally aligned 1-, 2-, or 4-byte transfers using
`FIXED`, `INCR`, or legal 2/4/8/16-beat `WRAP` bursts. Bursts are limited to 16
beats and one 4 KiB page. Because a bank is exactly one 4 KiB page, a legal
transaction selects one bank for its lifetime.

The macro is issued directly on AR acceptance. The first response is available
one cycle later. With `RREADY` asserted, following beats issue on preceding
response cycles, giving one word per cycle without bubbles. Backpressure stops
new reads and holds data, ID, response, and `RLAST` stable.

After AW acceptance the target consumes one W beat per cycle. Strobes outside
the lanes selected by `AWSIZE` and address are illegal. A zero strobe is a
no-op and does not enable a bank. `WLAST` must agree with `AWLEN`; a mismatching
beat is not written and terminates with `SLVERR`. Earlier accepted beats are
not rolled back.

Malformed protocol requests return `SLVERR`. An absent memory or address
outside the parameterized capacity returns `DECERR`. Protocol-invalid requests
are capped to one error response beat at the IP boundary. The SoC interconnect
normally rejects them before they reach SRAM.

## APB4 management ABI

All registers are read-only. Writes, unaligned accesses, and unknown offsets
complete with `PSLVERR`. Counters are 32-bit saturating values controlled by
the existing SYSCTRL `PERF_CTRL` enable and clear signals; no second control
ABI or interrupt is introduced.

| Offset | Name | Description |
| ---: | --- | --- |
| `0x000` | `IP_ID` | `0x5352414d` (`SRAM`) |
| `0x004` | `IP_VERSION` | ABI version `0x00010000` |
| `0x008` | `CAPABILITY` | Present, native AXI4, byte-write, burst, and performance flags; max beats in 15:8 and data bytes in 23:16 |
| `0x00c` | `MEMORY_BYTES` | Implemented capacity, or zero when absent |
| `0x010` | `BANK_COUNT` | Implemented data banks, or zero when absent |
| `0x014` | `BANK_BYTES` | Fixed value 4096 |
| `0x020` | `PERF_READ_REQUESTS` | Accepted AR requests |
| `0x024` | `PERF_WRITE_REQUESTS` | Accepted AW requests |
| `0x028` | `PERF_READ_BEATS` | Accepted R beats |
| `0x02c` | `PERF_WRITE_BEATS` | Accepted W beats, including drained error traffic |
| `0x030` | `PERF_STALL_CYCLES` | Cycles with any AXI VALID blocked by READY |
| `0x034` | `PERF_ERROR_RESPONSES` | Terminal non-OKAY responses |

The SDK exposes `rs_onchip_sram_probe()` and
`rs_onchip_sram_read_performance()`. RTL and C constants remain handwritten;
the register parity test prevents drift without adding a generator.

## Technology mapping

`tc_sram_1024x32` is the stable technology boundary. Behavioral simulation
uses the Common byte-mask RAM model. IHP130 maps to
`RM_IHPSG13_1P_1024x32_c2_bm_bist`. GF180 composes four byte lanes across two
`gf180mcu_fd_ip_sram__sram512x8m8wm1` depth halves and registers the address
high bit for synchronous read selection. SKY130 maps to the OpenRAM-generated
`sky130_sram_4kbyte_1rw_32x1024_8`. Its Liberty-compatible logical boundary
exports 32 data bits and hides OpenRAM's required physical spare column; a
future physical adapter must tie the spare enable and spare input low. The
required spare row expands the macro address port to 11 bits, so the wrapper
ties its high bit low and exposes exactly logical addresses 0 through 1023.
ICS55 retains its existing mapping but its supported profiles keep the macro
disabled. Bank count, rather than technology depth or width, implements every
product size.

The wrapper preserves byte masks and one-cycle synchronous reads. PDK timing,
LEF/GDS placement, power hookup, BIST pins, and foundry signoff remain
physical-flow responsibilities.

## Verification and performance evidence

`tests/test_onchip_ram.py` elaborates all five capacities and covers bank
boundaries, first/last words, byte/half/word masks, `FIXED`, `INCR`, `WRAP`,
16-beat continuous traffic, backpressure, AR/AW priority, absent-memory and
malformed accesses, counters, all four PDK wrapper polarities and masks, and
the GF180 511/512 depth boundary. The setup tests independently validate the
SKY130 artifact manifest and generated-file hashes. Full Verilator regression
firmware exercises the first and last locations through the SoC interconnect.

`make CONFIG=configs/ci/ihp130.mk formal-onchip-ram` runs a 20-cycle bounded
proof and cover set for AXI stability, channel exclusion, response bounds,
physical-write qualification, and reachable read/write/error completions.
The directed performance comparison measures 16 response cycles for a 16-word
native read and 18 through the compatibility bridge. This is an 11.1 percent
total-latency reduction and a complete removal of the bridge's two non-payload
cycles; 16 cycles is the minimum possible on the 32-bit response channel.
The SRAM-resident four-iteration CoreMark run completes in 4,662,868 cycles
against the recorded 7,620,324-cycle compatibility baseline, a 38.8 percent
cycle reduction. It remains an unqualified regression workload rather than a
public CoreMark score.

## Reliability and performance roadmap

The next phase should add SECDED outside the stable data macro. For every four
data banks, one `1024 x 32` bank can store four independent ECC bytes per word
address. A full write computes one ECC byte and writes its byte lane; a partial
write reads and corrects the old word, merges bytes, then writes data and ECC.
The management ABI would add first-error address/syndrome, corrected and
uncorrectable counters, injection, sticky status, and an uncorrectable-error
interrupt. All locations must be initialized with valid data/ECC before reads.

MBIST follows ECC. A future support wrapper must quiesce AXI, exclude CPUs,
DMA, and debuggers, run a reviewed startup March test or qualified
nondestructive runtime test, record the failing bank/address, and hand
technology BIST/redundancy pins to the physical flow. That phase requires DFT
and tester-ready evidence, not only RTL simulation.

Further throughput work is conditional on the fabric. Independent read/write
target ownership, more IDs, or per-bank queues are useful only after concurrent
transactions can reach SRAM. RP2350-style striping, bank-aware arbitration,
QoS, and power gating should then be evaluated from measured contention.
