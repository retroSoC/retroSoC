# SPI-P2 DMA V2.2 Paced FIFO Integration

This document records the SPI-P2 implementation boundary from [spi.md](spi.md)
and [dma.md](dma.md). The shared DMA source now understands the V2.2 request
encoding and support-register shape, while committed Tiny and Mini product
instances remain V2.0/default-disabled for SPI until full product integration.

The standalone `spi_dma_pacing` block owns source-qualified TX/RX credit
reservation, exactly-once commit and terminal retirement. A reserved credit
remains busy through the corresponding AXI response; CPU accesses, a second
channel, rebind and FIFO reset cannot consume it. The block reports binding
conflict, disabled-admission and DMA-error faults without adding a DMA master,
channel, stream endpoint, SRAM or pad.

## Implemented boundary

- `dma_pkg.sv` exposes five-bit request IDs 16/17 while preserving IDs 0..15.
- `dma_reg.sv` supports `IP_VERSION` parameterization and read-only
  `SUPPORTED_REQUESTS@0x028`; request status is 32 bits.
- `dma_core.sv` accepts a 32-bit request mask and decodes TCD request as
  `{control[25], control[15:12]}`. The channel state preserves all five
  request bits, and SPI direct/TCD jobs enforce the fixed-MMIO increment
  direction only when `EnableSpi` is enabled. Product instances retain their
  explicit V2.0 masks and versions until integration enables V2.2.
- SDK headers and math/submit paths carry the high request bit. Tiny software
  accepts the SPI request shape only after `rs_dma_supports_request()` reads
  `IP_VERSION` and `SUPPORTED_REQUESTS`; V2.0 returns `RS_ENOTSUP` before the
  unsupported offset is read. No undefined compile-time V2.2 macro is required;
  Mini and other non-Tiny validation paths retain their existing rejection.
- `spi_dma_pacing.sv` is included in the standalone SPI source boundary and
  feeds the SPI wrapper's existing credit lifecycle. It is not wired into a
  product fabric, GPIO/RCU path or DMA request allocator.

Descriptor cancellation blocks new fetches, including a same-cycle abort,
treats an in-flight descriptor read and parse as channel ownership, clears
pending descriptor state on abort completion, and prevents an aborted descriptor
from activating. The formal harness proves these assertions, and the dedicated
TCD cancellation cover passes under the retained Mini formal evidence root.

The focused execution passed 53 SPI/DMA/parity checks, 10 SPI-P1 standalone
protocol fixtures, the existing DMA register/native tests, DMA formal
prove/BMC/cover on the Mini-compatible V2.0 configuration, and the host C
suite. The SPI-P2 lint and pacing fixture also pass under ICS55. These results
validate the ABI and pacing boundary; they do not claim product V2.2 capability
or replace the unrun full-product gates.

## Focused validation

The new `tests/test_spi_p2.py` checks the request split, five-bit channel
storage, SPI direction guards, support ABI, product default-disable policy,
stream-status disable behavior and the credit pacing fixture. `spi_dma_p2_tb` covers
admission, commit, retirement, binding collision and disabled admission. The
existing DMA register/native tests and all SPI-P1 standalone fixtures remain
affected compatibility checks.

A prior full Pytest run passed 2089 tests with one optional PDF retrieval skip;
that run predates the latest shared-DMA cancellation and five-bit-state edits.
The post-edit full Pytest campaign remains an explicit unrun gate. The latest
Mini DMA formal prove passed with the TCD abort assertions; the existing DMA
cover and dedicated TCD cancellation cover completed separately under the same
formal build root.

Use a fresh timestamp and explicit TINY/PDK selection. The P2 entrypoints are
`spi-p2-lint`, `spi-p2-rtl` and `spi-p2-report`; generated records belong below
`build/<variant>/meta/spi-p2/`. No phase acceptance, product DMA capability,
physical qualification or SPI-P3 authorization follows from the focused
fixture.
