# AXI4 Interconnect Contract

AXI4 is the active Mini SoC system interconnect. The Common `axi4_if`
declaration, `memory_map.json`, and `axi4_interconnect.sv` are the executable
sources of truth. RIB remains documented and verified as an independent legacy
protocol; it is not an active Mini SoC fabric link.

## Supported Subset

The interconnect has 32-bit addresses and 32-bit data. It supports only linear
`INCR` transfers with one through sixteen beats (`AxLEN` 0 through 15), natural
1-, 2-, or 4-byte alignment, and no 4 KiB boundary crossing. `FIXED`, `WRAP`,
locked, wider, misaligned, and cross-target transactions receive `SLVERR`.
Unmapped addresses receive `DECERR`.

Each master may own at most one read or write transaction. IDs and user fields
are one bit because no outstanding or out-of-order completion is supported.
Read and write ordering is therefore program order at each master. Different
masters may use different targets concurrently; requests to one target use a
Common round-robin arbiter and retain ownership through `B` or `RLAST`.

The three masters are the Hazard3 management core, the selected user core, and
DMA. Hazard3 AHB-Lite and the current user-core RIBP ABI issue single-beat AXI4
transactions through adapters. DMA converts its existing four-word chunks to
AXI4 `INCR4`, so non-burst masters remain compatible while burst-capable masters
can use the wider contract.

## Targets and Access Control

The fixed targets are the RIBP configuration plane, APB, SRAM, SDRAM, PSRAM,
XPI/Flash, SPI-SD, `DECERR`, and `SLVERR`. RIBP and APB accept only single-beat
transactions. SRAM uses a direct AXI4 target with pipelined synchronous reads
and response buffering. External-memory data windows accept up to sixteen
beats; their current compatibility bridge serializes each beat into the
existing controller data engine. Register configuration remains on RIBP.

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
- Keep RIBP configuration and AXI4 data apertures separate in the canonical
  address map. An IP may arbitrate the two internally, but a data address must
  not be routed through the global configuration decoder.
- Add controller-native command/data queues before claiming physical burst
  coalescing. The compatibility bridges establish protocol correctness, not
  SDRAM row, serial chip-select, or media-sector amortization.

## Verification and Performance Gates

`tests/test_axi4.py` covers a four-beat write/read, response backpressure, and
rejection of a seventeen-beat request without touching the RIBP target. The
IHP130 `ci_smoke` regression is the end-to-end boot and configuration check.
CoreMark uses SRAM and must not regress more than five percent from the recorded
7,620,324-cycle baseline. A controller may be promoted to a native burst target
only after aligned sixteen-word tests show at least twenty percent improvement
and cover partial writes, backpressure, device timing, and error termination.
