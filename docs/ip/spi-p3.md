# SPI-P3 Tiny GPIO RCU and SDK Integration

SPI-P3 binds the accepted SPI-P2 shared-DMA ABI to the Tiny product. It adds
the frozen APB, IRQ25, RCU target16 and four Gen1 routes while preserving the
QFN64 package, existing GPIO ownership, DMA channels and legacy XPI LCD path.

Tiny internal AXI transactions carry a private four-bit source marker. Fabric
admission rewrites the owner marker, the APB/CDC bridges retain it through the
terminal response, and SPI accepts DMA aliases only for a qualified central
DMA channel. CPU and other-owner accesses cannot use DMA aliases. SPI DMA
requests are fixed to `0x1001D054` (TX) and `0x1001D058` (RX).

GPIO readiness combines USER_SELECT, handoff, ALT/electrical state and the
Tiny lifecycle reset. Raw GPIO30 input feeds MISO directly; the ordinary GPIO
filter path is not used for SPI sampling. GPIO and SPI gate/reset operations
remain blocked while a PIO user claim or latched SPI session is active.

The freestanding `rs_spi_*` HAL performs capability discovery, bounded
configuration, acquire/release, CPU segments, status and recovery. It does not
add a display adapter; display and snapshot application work remain SPI-P4.

Focused P3 records belong under `build/<variant>/meta/spi-p3/`. Tiny acceptance
requires command success, `TEST_STATUS`/`SIM_TEST_PASS` and no forbidden error
marker. `phase_accepted` remains false until human review. Pre-final STA is
observational; SPI-P5 remains the final physical qualification phase.
