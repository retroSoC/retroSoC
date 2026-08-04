# RIB Family Protocols

retroSoC uses a scalar peripheral protocol and a native burst interconnect.
The interface declarations and generated address map are the executable source
of truth; this document fixes the ownership, ordering, and adaptation rules at
each boundary.

| Protocol | Interface | Purpose | Transfer shape |
| --- | --- | --- | --- |
| RIBP | Common `ribp_if` | Scalar core and peripheral compatibility | One scalar word request and response |
| RIB | `rib_if` | Native retroSoC interconnect | Split command, write-data, and response channels |

## RIBP

RIBP is the scalar Common protocol used at every core and peripheral boundary.
A master presents
`valid`, `addr`, `wdata`, and `wstrb`; a slave completes the request with
`ready`, `rdata`, and `resp_err`. `wstrb == 0` denotes a read. There is no
burst metadata, response code, ID, reordering, or more than one transaction
in flight through the RIBP adapter.

`ribp2rib` converts RIBP requests to native `INCR1` RIB transactions. It
maps the terminal RIB response to the RIBP `ready` handshake and propagates
the RIB error flag as `resp_err`.

Leaf RIBP IP currently responds with `resp_err == 0`. RIBP multiplexers,
register slices, and bypass paths preserve a selected downstream error. The
APB bridge maps `PSLVERR` directly to `resp_err`; this is the only current
RIBP error producer.

## RIB

RIB is the retroSoC Interconnect Bus. Version 1 has independent command,
write-data, and response channels and permits one outstanding 32-bit
transaction per master.

- A command transfers `cmd_addr`, `cmd_write`, and `cmd_len` with
  `cmd_valid/cmd_ready`.
- Write beats transfer `wdata`, `wstrb`, and `wlast` with `w_valid/w_ready`.
- Responses transfer `rdata`, `resp_err`, `resp_code`, `rsp_beat`, and
  `rsp_last` with `rsp_valid/rsp_ready`.
- `INCR1` transfers one word. `INCR4` transfers four ascending words at
  `address + 0`, `+4`, `+8`, and `+12` and requires a 16-byte aligned address.

RIB has no IDs, narrow read beats, wrapping bursts, reordering, or multiple
outstanding transactions. `BURSTERR` reports an unsupported length, bad
alignment, unsupported target, or malformed write-last sequence. The response
code definitions are in `rib_defs.svh`.

The generated address map is the capability source of truth. Register and APB
regions remain `INCR1` only. SRAM, SDRAM, PSRAM, flash/XPI, and SPI-SD memory
windows accept `INCR4`; the interconnect validates both the first and last
address before forwarding a command. DMA falls back to `INCR1` unless both
endpoints, including their fourth words, support `INCR4`.

`rib2ribp` serializes legal RIB beats into RIBP accesses and reconstructs
ordered RIB responses. An asserted RIBP `resp_err` is mapped to native RIB
`SLVERR`; RIBP intentionally carries no response-code field.

## Targets and Performance

Management and current user cores use RIBP through the SoC adapters. Future
user cores can select native RIB in `user_extensions.json`. DMA is a native
RIB master and uses the common four-entry FIFO for each chunk.

`rib2ram` is the native RIB SRAM target. It pipelines synchronous reads
and uses the Common two-entry spill register for response backpressure. The
Common repository owns direct verification of that utility; retroSoC verifies
the RIB target behavior and its integration contract.

The current external-memory boundary accepts one `INCR4` command and converts
it into ordered legacy word accesses. This reduces upstream command and
arbitration overhead but does not combine SDRAM, PSRAM, XPI, or SPI-SD physical
transactions. Controller-level coalescing must be introduced separately and
qualified against the relevant device timing model. The implementation order
is driven by the reproducible benchmark cycles and wait counters:

1. SDRAM row-hit bursts and bank scheduling.
2. XPI/PSRAM chip-select amortization and data streaming.
3. SPI-SD cache-hit streaming; media misses remain sector based.

Do not promote an external controller to a native burst target until directed
tests cover alignment, partial writes, response backpressure, device timing,
and error termination.

## Verification

`make CONFIG=configs/ci/ihp130.mk FORMAL=YES formal` checks the arbiter and
both compatibility adapters. The SRAM test covers INCR4 reads, writes,
no-bubble responses, and prolonged backpressure. Direct spill-register
simulation and formal coverage is maintained by the Common repository.

The `APP=benchmark` UART records include `cycles` and interconnect wait
counters. `make CONFIG=configs/benchmark/ihp130-hazard3.mk SIMU=VERILATOR
benchmark-report` stores the parsed result in the variant metadata directory.
