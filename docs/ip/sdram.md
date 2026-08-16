# AXI4 SDRAM Controller

The Mini SoC SDRAM block exposes an AXI4 data port and a separate APB4 register
port. The data path is 32-bit, accepts one transaction at a time, and supports
single-beat, `FIXED`, `INCR`, and legal `WRAP` bursts up to sixteen beats. An
`axi4_word_bridge` serializes each AXI beat into one native word request so the
existing phase-separated SDRAM command engine remains unchanged in timing
behavior.

## Integration

| Property | Value |
| --- | --- |
| AXI4 data window | `0x38000000` - `0x3BFFFFFF` |
| Data window size | 64 MiB |
| APB4 configuration window | `0x1000D000` - `0x1000DFFF` |
| Data width | 32 bits over SDRAM x16 |
| Address organization | 2-bit bank, 13-bit row, 10-bit column |
| Physical interface | `sdram_if` (`BA[1:0]`, `A[12:0]`, `DQ[15:0]`) |
| Clocking | Single-edge command/data update plus opposite-edge sampling |

Configuration requests enter through the timed `sdram_cfg` APB4 port exported
by `apb4_periph`. AXI data requests enter `axi4` and are serialized by
`axi4_word_bridge` into one native word request for `sdram_core`. Register
accesses stay on the APB4 configuration window and do not share the data-path
arbiter. The physical SDRAM instance remains in the SoC top rather than inside
`apb4_periph`.

## Register ABI

All registers are 32-bit and naturally aligned. Invalid offsets return
`pslverr`; partial writes are accepted according to `pstrb`.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `CLKDIV` | RW | SDRAM clock divider selection. |
| `0x004` | `CFG` | RO | Reserved for the future timing/profile extension. |

The current implementation keeps the existing direct RTL register definition;
software headers and register-generation are intentionally not unified in this
change.

## Address Mapping and Timing

The controller subtracts `SOC_ADDR_SDRAM_BASE` before decoding a request. For
the 64 MiB x16 geometry, relative byte address bits map as follows:

`bank = addr[25:24]`, `row = addr[23:11]`, `column = {addr[10:2], 1'b0}`.

The controller maintains its existing initialization, auto-refresh, row
activate, CAS-latency, write-mask, and auto-precharge sequence. AXI burst
support changes only the transport address sequence; it does not claim native
SDRAM command coalescing or outstanding requests.

## Verification and Delivery

The RTL testbench drives AXI4 writes and reads, masked writes, and a high
address within the expanded 64 MiB aperture. It can run against the zero-delay
Verilator model or the Micron timing model. The Verilator model uses 13-bit
rows and 25-bit half-word storage (64 MiB); the default Micron x16 512-Mbit
configuration provides the same capacity.

`tests/test_sdram.py` is the reproducible unit entry point. The IHP130
regression additionally compiles the generated top-level route, AXI fabric, and
netlist flow. Future native burst optimization must add row-hit/row-miss,
refresh contention, backpressure, partial-write, and error-termination coverage
before changing the compatibility engine into a pipelined SDRAM scheduler.
