# RIB Interconnect Protocol

RIB is the retroSoC Interconnect Bus. The SoC-owned version 1 transport uses
separate command, write-data, and response channels. It supports one
outstanding 32-bit transaction per master and two linear lengths:

- `INCR1` transfers one word.
- `INCR4` transfers four words at `address + 0`, `+4`, `+8`, and `+12`.

`INCR4` commands must be 16-byte aligned. They may not cross a generated
address-map capability boundary. There are no IDs, wrapping bursts, narrow
read beats, reordering, or multiple outstanding transactions in version 1.
The response carries a beat index, terminal marker, error flag, and response
code. `BURSTERR` reports an unsupported length, bad alignment, unsupported
target, or malformed write-last sequence.

The generated address map is the capability source of truth. Register and APB
regions remain `INCR1` only. SRAM, SDRAM, PSRAM, flash/XPI, and SPI-SD memory
windows accept `INCR4`; the interconnect validates both the first and last
address before forwarding a command. A DMA transfer falls back to `INCR1`
unless both endpoints, including their fourth words, support `INCR4`.

## Compatibility and Performance

The management core and the currently integrated user cores retain their
single-word interfaces through SoC-owned legacy-to-burst adapters. A future
user core can select the burst interface in `user_extensions.json`. DMA is a
native burst master and uses the common four-entry FIFO for each chunk.

The SRAM target is native burst RTL. It pipelines synchronous reads and uses
the common two-entry spill register to absorb response backpressure. The spill
register contract assumes that `flush_i` and `valid_i` are not asserted
together. When both entries are full it does not accept a replacement item in
the same cycle as a downstream pop, so recovery from a full stall contains one
refill bubble. This does not affect the no-bubble four-beat path when the
response consumer remains ready.

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

`make CONFIG=configs/ci/ihp130.mk FORMAL=YES formal` checks the arbiter and both
compatibility adapters. It also proves the common spill register's externally
observable occupancy, ready/valid, flush, and stalled-output contracts. The
deterministic Icarus scoreboard additionally checks spill-register data order,
and the SRAM test covers INCR4 reads, writes, no-bubble responses, and prolonged
backpressure.

The `APP=benchmark` UART records include `cycles` and interconnect wait
counters. `make CONFIG=configs/benchmark/ihp130-hazard3.mk SIMU=VERILATOR
benchmark-report` stores the parsed result in the variant metadata directory.
