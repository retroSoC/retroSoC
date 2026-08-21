# AXI4 Interconnect Contract

AXI4 is the active Mini SoC system interconnect. The Common `axi4_if`
declaration, `memory_map.json`, and `axi4_interconnect.sv` are the executable
sources of truth. RIB remains documented and verified as an independent legacy
protocol; it is not an active Mini SoC fabric link.

## Supported Subset

The interconnect has 32-bit addresses and 32-bit data. It supports `INCR` and
`FIXED` transfers with one through sixteen beats (`AxLEN` 0 through 15), and
AXI-legal `WRAP` transfers with two, four, eight, or sixteen beats
(`AxLEN` 1, 3, 7, or 15). All transfers require natural 1-, 2-, or 4-byte
alignment and must remain inside one 4 KiB page and one decoded target.
Locked, wider, misaligned, and cross-target transactions receive `SLVERR`.
Unmapped addresses receive `DECERR`.

Each master may own at most one read or write transaction. IDs and user fields
are one bit because no outstanding or out-of-order completion is supported.
Read and write ordering is therefore program order at each master. Different
masters may use different targets concurrently; requests to one target use a
Common round-robin arbiter and retain ownership through `B` or `RLAST`.

The three masters are the Hazard3 management core, the selected user core, and
DMA. Hazard3 AHB-Lite and the current user-core RIBP ABI issue single-beat AXI4
transactions through adapters. DMA is a native AXI4 master: its production
six-channel engine uses fixed ID zero, independently schedules one read and
one write transaction, and issues aligned `INCR` bursts up to sixteen beats.
Fixed-address and APB4/MMIO endpoints are always single-beat. See the
[DMA MVP](ip/dma.md) for its ownership, abort, and FIFO-credit contract.

## Targets and Access Control

The fixed targets are the APB4 configuration plane (`apb4_periph`), APB
(`apb4_system`), SRAM, SDRAM, 4-bit PSRAM, OPI PSRAM, XPI/Flash, SPI-SD,
`DECERR`, and `SLVERR`. APB4 and APB accept only single-beat transactions.
SRAM uses a direct AXI4 target with pipelined synchronous reads and response
buffering. External-memory data windows accept up to sixteen beats; their
controller front ends validate and serialize or coalesce the physical
transactions while preserving the documented AXI response contract. Register
configuration remains on APB4.

The user-core firewall validates both the first and last byte before target
arbitration. User access to SYSCTRL, CLINT, DMA configuration, and other
management-only regions is rejected with `SLVERR`. SYSCTRL records the address,
master, write strobes, reserved/access classification, and response code for a
terminal error. The internal fault classification maps an unmapped address to
`DECERR`, a malformed or unsupported burst to `BURSTERR`, and a firewall or
access-control rejection to `PROTERR`.

## Integration Rules

- Instantiate every Mini SoC AXI4 link with `ADDR_WIDTH=32`, `DATA_WIDTH=32`,
  `ID_WIDTH=1`, and `USER_WIDTH=1`; do not rely on Common defaults.
- Hold address/control and response payload stable while `VALID` is asserted
  without `READY`. Write data must assert `WLAST` on the declared final beat.
- Keep APB4 configuration and AXI4 data apertures separate in the canonical
  address map. An IP may arbitrate the two internally, but a data address must
  not be routed through the global configuration decoder.
- Add controller-native command/data queues before claiming physical burst
  coalescing. The compatibility bridges establish protocol correctness, not
  SDRAM row, serial chip-select, or media-sector amortization.

## Verification and Performance Gates

`tests/test_axi4.py` covers a four-beat write/read, response backpressure, and
rejection of a seventeen-beat request without touching the APB4 target. The
bridge unit test also covers Common address generation for FIXED and WRAP
sequencing. The IHP130 `ci_smoke` regression is the end-to-end boot and
configuration check.
CoreMark uses SRAM and must not regress more than five percent from the recorded
7,620,324-cycle baseline. A controller may be promoted to a native burst target
only after aligned sixteen-word tests show at least twenty percent improvement
and cover partial writes, backpressure, device timing, and error termination.
