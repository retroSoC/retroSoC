# Mini AXI4 Interconnect Contract

Mini uses two cooperating AXI fabrics. `axi4_interconnect` is the 32-bit LP
control/compatibility plane; `axi4_data_crossbar` is the 64-bit HP payload
plane. Common `axi4_if`, `memory_map.json`, and `soc_topology.json` are the
executable protocol, address, and integration sources of truth.

## LP control plane

The LP fabric has 32-bit address/data, one-bit ID/user fields, and eight master
slots. Product wiring assigns management, five down-converted data gateways,
HP MMIO, and an idle terminator. The former selected user-core slot name is
retained only at the module compatibility boundary; product mode does not
instantiate a user core.

It supports aligned 1-, 2-, and 4-byte `FIXED`, `INCR`, and legal AXI `WRAP`
transfers up to sixteen beats. One read or write transaction may be active per
master. Requests to one target use Common round-robin arbitration and retain
ownership through `B` or `RLAST`. Misaligned, unsupported, cross-page, and
cross-target transactions return `SLVERR`; unmapped addresses return `DECERR`.

Hazard3 accesses APB4 registers through LP-to-PCLK async-safe bridges. HP MMIO
is downsized and crosses HP-to-LP. Product access policy prevents the HP MMIO
master from writing SYSCTRL/RCU, watchdog, and GPIO administration windows.

## HP data plane

The native payload fabric is AXI64 with 32-bit addresses and six-bit global
IDs. It has eight masters:

| Index | Master | Adaptation |
| ---: | --- | --- |
| 0 | Vexii I-cache | native AXI64, source ID preserved |
| 1 | Vexii D-cache | native AXI64, source ID preserved |
| 2 | central DMA | PCLK-to-HP CDC, AXI32-to-64 |
| 3 | I/O gateway A | USB2 and SDIO0, PCLK-to-HP CDC, AXI32-to-64 |
| 4 | I/O gateway B | SDIO1 and SPI-SD, PCLK-to-HP CDC, AXI32-to-64 |
| 5 | LP data gateway | Hazard3 memory traffic, LP-to-HP CDC, AXI32-to-64 |
| 6 | reserved | permanently idle and denied |
| 7 | EXT-H | PCLK-to-HP AXI64 CDC |

Each source receives a fixed three-bit master prefix. The crossbar maintains
independent read and write arbitration for each target, enabling read/write
overlap and cross-target concurrency. Different IDs from HP/DMA/EXT-H may be
active on the same or different targets up to master and target credits. The
same source ID is blocked until completion. SRAM/SDRAM target credits are four
reads and two writes; serial and error targets use one read and one write.

| Target | Current backend |
| --- | --- |
| on-chip SRAM | native AXI64/ID6 striped technology macros in HP |
| SDRAM | HP-to-memory AXI64 CDC, local 64-to-32 SDRAM adaptation |
| QPI PSRAM | AXI64-to-32, CDC, selected QPI frontend |
| OPI/HyperBus | AXI64-to-32, CDC, selected OPI frontend |
| XPI/flash | AXI64-to-32, CDC, XPI frontend |
| error | finite-latency `SLVERR` responder |

`block_new_i` prevents new address acceptance during HP clock changes. Existing
owners retain their response route until terminal completion. QPI/OPI decode is
fail-closed according to the synchronized AON pad mode.

## Width and CDC adapters

- `axi4_upsizer_32to64` preserves byte lanes and adds the master ID prefix.
- `axi4_downsizer_64to32` splits 64-bit beats for current memory frontends and
  recombines read responses.
- `axi4_async_bridge` carries AW, W, B, AR, and R through independent Common
  coordinated warm-flush FIFOs and reports clear-busy and epoch state.
- `apb4_async_bridge` converts one APB request into a request/response CDC
  transaction and guarantees a finite APB completion when the destination runs.

Normal HP shutdown requests software cache maintenance, blocks new addresses,
drains accepted traffic, and performs a coordinated warm flush. Target guards
provide bounded synthetic `SLVERR` completion and fail-closed isolation for a
stopped target.

## Verification boundary

`tests/test_axi4.py` retains LP fabric, downsizer, burst, response, and
backpressure coverage. Full-product Verilator/Icarus simulation exercises LP
boot, HP elaboration, the memory gateways, and product APB paths. The current
implementation does not claim cache coherency, full AXI formal proof, CDC
signoff, or physical bandwidth closure.
