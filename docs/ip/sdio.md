# Standalone SD/SDIO Host Foundation

This document is the contract for the standalone `apb4_sdio` IP and its dual
Mini SoC integration. The two management windows are `APB4_SDIO0` at
`0x1000F000` and `APB4_SDIO1` at `0x10015000`; both are public to the
management core and denied to the user core.

## Scope and maturity

The host is a single-clock-domain, single-slot native SD host. `clk_i` is the
only logic clock. `sdio.sck_o` is a registered output and is never used as a
clock for state. Low/high phase clock-enables update outputs and sample inputs.
The wrapper has one APB4 management port, one 32-bit native AXI4 master port,
and one `sdio_if.dut` pad interface. Instances are independent when integrated.

The foundation contains generic command, data, CRC, phase, PIO, and bounded
scatter-gather DMA building blocks. Card enumeration and card-type policy
remain software driven.

## Supported behavior

- Native 1-bit and 4-bit SDR transfers.
- Generic six-bit command index and 32-bit argument.
- No response and R1, R1b, R2, R3, R4, R5, R6, and R7 response framing.
- Command index/end checks and CRC7 checks where the response type defines CRC.
  R3 and R4 do not force a CRC check.
- Data token, payload, CRC16, write response, DAT0 busy, and command/data/busy
  timeout state are present in the protocol engines.
- Write response tokens are checked in full: accepted continues to DAT0 busy,
  CRC-error and write-error tokens terminate with distinct error semantics,
  and only the accepted path uses `TIMEOUT_BUSY`.
- `TIMEOUT_CMD` covers command launch and response framing, `TIMEOUT_DATA`
  covers data tokens, payload, CRC, and write-response tokens, and
  `TIMEOUT_BUSY` covers only R1b/DAT0 busy phases.
- The 4-bit serializer keeps independent CRC16 state for each DAT lane; CRC
  errors remain sticky until the next transaction or reset.
- PIO word transfers use a 32-bit word and four byte strobes. Lane 0
  (`word[7:0]`/`WSTRB[0]`) is the first wire byte; each byte is serialized
  MSB first. Descriptor DMA uses the same stream contract and supports a
  byte-granular final word in both directions.
- The intended software protocols are SD Memory v2 SDSC/SDHC and SDIO v2
  CMD5/CMD52/CMD53. SDSC byte addressing and SDHC block addressing are software
  policy, not hard-coded card enumeration in the RTL.
- SDIO high-speed initialization is software sequenced: CCCR speed capability
  is read, the high-speed enable bit is written and read back, and only a
  verified enable permits the host clock/info flag to change.
- The capability word advertises SD Memory v2, SDIO v2, 1/4-bit SDR, CRC, PIO,
  SG DMA, and 16-beat maximum bursts.

The implementation does not claim SD Association compliance or certification.
Normative specifications and any required licensing must be obtained and
reviewed separately before a compliance claim.

## Clock and I/O boundary

`CLOCK_CTRL[0]` enables the host clock and `CLOCK_CTRL[23:8]` supplies the
half-period in `clk_i` cycles. A value of zero is treated as one cycle. The
actual frequency is approximately:

```
sdclk_hz = clk_i_hz / (2 * half_period)
```

Clock stop completes a high phase and stops only low. Command/data output
changes occur on launch phase enables; command/data inputs are consumed on
sample phase enables. The current SoC profile is 72 MHz, so its evidence
boundary is 400 kHz, 24 MHz, and 36 MHz integer-divider modes. A 50 MHz
SDCLK requires a separately validated `clk_i >= 100 MHz` environment. No
statement about pad, package, board, voltage, or I/O timing signoff follows
from the RTL clock test.

The MVP is fixed-present and 3.3 V SDR. Card-detect, write-protect,
power-enable, hot-remove recovery, UHS, 1.8 V switching, DDR, eMMC, MMC,
SPI-mode operation, 8-bit mode, tuning/DLL, CQE, and combo-card policy are
unsupported.

## APB4 register contract

The window is 4 KiB and uses the offsets in `rtl/ip/storage/sdio_define.svh`.
An APB access is accepted in the enable phase and completes with a registered
one-cycle `PREADY`. Reads have no side effects. Unknown offsets, out-of-window
addresses, malformed start writes, and protected configuration writes while
active return `PSLVERR`. Command, data, and DMA starts are write pulses.
`IRQ_STATUS` and `ERROR_STATUS` are write-one-to-clear. `IRQ` is the masked
status reduction.

`ERROR_STATUS` is event-latched: command/data CRC and timeout, AXI, protocol,
and abort events set bits once and remain set until software writes one to the
corresponding bit. Level/status signals are not continuously re-ORed after a
clear. `DEBUG[0]` is PIO data valid and `DEBUG[1]` is PIO transmit ready.
`STALL_COUNT` counts cycles in which a valid PIO/DMA stream word is held
without a ready consumer.

| Offset | Register | Access |
| ---: | --- | --- |
| 0x000 | IP_ID | RO |
| 0x004 | IP_VERSION | RO |
| 0x008 | CAPABILITY | RO |
| 0x00c | HOST_CTRL | RW; enable, abort, IRQ enable |
| 0x010 | CLOCK_CTRL | RW; enable and half-period |
| 0x014 | CLOCK_ACTUAL | RO |
| 0x018 | BUS_CTRL | RW; 1-bit/4-bit |
| 0x01c-0x024 | TIMEOUT_CMD/DATA/BUSY | RW |
| 0x028-0x02c | STATUS/PRESENT | RO |
| 0x040-0x060 | CMD_ARG, CMD_CFG, CMD_START, CMD_STATUS, RESP0..RESP4 | mixed |
| 0x080-0x098 | block/data/PIO/FIFO controls | mixed |
| 0x0c0-0x0dc | descriptor and DMA status | mixed |
| 0x100-0x124 | IRQ, error, last-command, and counters | mixed |

R2 is 136 bits and is exposed in `RESP0..RESP4`; the upper register contains
the upper eight response bits in its low byte. Reads are side-effect free
except for `PIO_DATA`: a valid `PIO_DATA` read consumes exactly one held word,
and an empty `PIO_DATA` read completes with `PSLVERR`.

## Descriptor ABI

Each descriptor is 16-byte aligned and contains four little-endian 32-bit
words:

| Word | Name | Meaning |
| ---: | --- | --- |
| 0 | BUFFER_ADDR | 32-bit aligned memory buffer |
| 1 | BYTE_COUNT | positive byte count |
| 2 | NEXT_ADDR | 16-byte aligned next descriptor; zero at END |
| 3 | CONTROL_STATUS | OWN, CHAIN, END, IRQ; DONE and ERROR writeback |

`OWN` is bit 0, `CHAIN` bit 1, `END` bit 2, `IRQ` bit 3, `DONE` bit 16, and
`ERROR` bit 17. Software publishes the descriptor and buffer, executes its
platform memory barrier, and sets OWN last. Hardware clears OWN and writes
DONE or ERROR after payload completion or a precise failure. `DESC_COUNT` is
an inclusive hardware traversal bound; zero length, unaligned descriptor or
buffer, malformed chain, loop, early END, total-length mismatch, and an
unowned active descriptor are errors. A chain must terminate with END before
the bound.

The descriptor `IRQ` flag raises the visible `IRQ_STATUS.DMA_DONE` event when
that descriptor is written back; the same bit is also raised for terminal DMA
completion. Descriptor IRQ events obey the normal mask and W1C rules.

AXI payload bursts are INCR, 32-bit, at most 16 beats, and never cross 4 KiB.
Read response errors, write response errors, bad IDs, and RLAST mismatches are
reported. A descriptor fetch address with low 12-bit value `0xFF0` or above
is rejected so the 16-byte fetch remains within one 4 KiB region. A final
descriptor word may use any non-zero contiguous low-byte WSTRB pattern that
exactly matches its remaining byte count. The initial buffer address must be
aligned; software must use a bounce buffer for an unaligned head. Abort stops
new work, drains an accepted AXI transaction, clears OWN, and completes with
ERROR.
There are no multiple IDs or outstanding transactions.

## Software sequencing and integration contract

1. Reset the host, program clock/width/timeouts, and leave host disabled while
   changing protected configuration.
2. Program command and response policy, issue `CMD_START`, and inspect
   `CMD_STATUS` and response words.
3. Program block/data policy. For PIO, write/read `PIO_DATA`; for DMA, fill a
   descriptor chain, publish OWN last, program `DESC_BASE/DESC_COUNT`, set
   `DATA_CFG.DMA`, and issue one `DATA_START` operation. `DATA_START` starts
   DMA and the card data engine atomically. `DMA_CTRL.START` is retained as a
   compatibility alias for the same coordinated operation and must not be
   used as an independent memory-transfer start.
4. Enable only the desired IRQ bits and clear sticky status with W1C.
5. On timeout, CRC, protocol, or AXI error, issue abort/reset, inspect the
   first error snapshot, and re-enumerate in software.

Each wrapper's AXI interface is a native 32-bit master. The SoC assigns
`sdio0` and `sdio1` to AXI master IDs 3 and 4, respectively; management,
user, and central DMA retain IDs 0, 1, and 2. The per-master wait counters
are snapshotted by SystemCtrl at `0x08C/0x090` and `0x094/0x098`.

`sdio0` remains on GPIO15..20 ALT0. `sdio1` uses dedicated
`sdio1_clk_o_pad`, `sdio1_cmd_io_pad`, and
`sdio1_dat0_io_pad` through `sdio1_dat3_io_pad` pads.
The canonical pin map leaves these pads unbound in the FPGA profile until a
board package and 3.3 V bank assignment are approved; the existing LVCMOS18
constraints are not evidence for SDIO electrical compliance.

The standalone IP does not allocate memory, perform cache maintenance,
implement an IOMMU/firewall, or provide a hosted/runtime C API. The SoC
integration only supplies the two native AXI/APB/IRQ/pad paths; the SDK driver
is maintained by a separate workstream.
