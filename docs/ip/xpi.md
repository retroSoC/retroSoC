# XPI V2 Controller

## Scope

XPI V2 is the Mini SoC external serial-memory and serial-peripheral
controller. It has a native 32-bit AXI4 memory plane, an APB4 control plane,
four independently configured chip selects, a programmable command LUT,
indirect PIO/DMA transfers, interrupts, and automatic status polling. The PHY
is deliberately limited to SDR and one clock domain. Data changes on one SCK
edge and is sampled on the other edge.

This document freezes the V2 hardware/software contract. The RTL and manual C
definitions remain the executable sources of truth:

- `rtl/ip/storage/xpi_*.sv`, `apb4_xpi.sv`, and `xpi_define.svh`
- `crt/include/retrosoc/hal/xpi_regs.h`
- `crt/include/retrosoc/hal/xpi.h` and `crt/src/hal/xpi.c`

XPI V2 intentionally breaks the retired `qspi.h` register and HAL ABI.

## Commercial Reference Survey

The survey was refreshed on 2026-08-20 from vendor documentation. "Active"
means that the vendor still publishes a current product or SDK document; it
does not imply access to the vendor RTL or its verification closure.

| Reference | Problem and architecture | Dependencies | Activity | Reuse / avoid |
| --- | --- | --- | --- | --- |
| NXP i.MX RT FlexSPI | A programmable LUT describes command, address, mode, dummy, and data phases. An IP-command path is separate from the memory-mapped AHB path. AHB receive buffers, prefetch, cacheable/bufferable attributes, timeout controls, DMA, and selectable sample clocks target both XIP flash and serial RAM. | AHB fabric, buffer RAM, device-specific LUT, clock/sample calibration, SDK driver. | Active in the current [MCUXpresso FlexSPI API](https://mcuxpresso.nxp.com/api_doc/dev/1315/group__flexspi.html). | Reuse the LUT, per-device configuration, timeout, and separate mapped/indirect paths. Defer speculative prefetch until coherency and invalidation behavior are specified. |
| ST STM32 OCTOSPI/HSPI/XSPI | Indirect, automatic status-polling, and memory-mapped modes cover flash configuration/programming, autonomous WIP/WEL polling, XIP, and RAM. Hardware prefetch accelerates mapped reads; CPU or DMA feeds the indirect data register. | AXI/AHB, DMA, IO manager, device timing configuration, optional DQS/delay block, MPU/cache policy. | Active; ST maintains [AN5050](https://www.st.com/resource/en/application_note/an5050-getting-started-with-octospi-hexadecaspi-and-xspi-interfaces-on-stm32-mcus-stmicroelectronics.pdf) and the [XSPI HAL](https://dev.st.com/stm32cube-docs/stm32c5xx-hal-drivers/2.0.0/en/docs/drivers/hal_drivers/xspi/api/hal_xspi_exported_types.html). | Reuse the three-mode programming model and interrupt-driven polling. Avoid presenting mapped NOR writes as ordinary RAM writes: erase, page limits, WEL, WIP, and failure status still require an indirect flash algorithm. |
| AMD Zynq-7000 linear QSPI | APB I/O mode performs all flash operations, while a separate AXI linear window performs read-only mapped access. The controller accepts multiple AXI reads and uses a 252-byte FIFO; continuous-read mode removes repeated command overhead. | AXI/APB fabric, flash-specific linear-mode configuration, FIFO, boot ROM/tool support. | Active; [UG585 revision 1.15](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Quad-SPI-Controller) was current at review time. | Reuse the split control/data planes and burst coalescing. Avoid a fixed 16 MiB-only aperture and avoid coupling the generic peripheral mode to a small hard-coded flash command set. |
| AMD AXI Quad SPI | Configurable AXI4-Lite control plus AXI4 performance/XIP modes. XIP supports INCR/WRAP mapped reads with a fixed flash command choice; enhanced mode exposes burst FIFO access. | Vivado IP configuration, AXI4/AXI4-Lite, separate SPI reference clock, selected flash family. | Active; [PG153 version 3.2](https://docs.amd.com/r/en-US/pg153-axi-quad-spi/Feature-Summary) was released in 2026. | Reuse native AXI burst semantics, explicit mode-0/mode-3 support, command errors, and a 64-word FIFO scale. Avoid compile-time-only command selection and a reset model that requires resetting the whole interconnect. |
| AMD Versal QSPI | Command words are queued in a command FIFO. APB PIO, programmable polling, and AXI DMA indirect reads support boot and bulk transfers, but this block has no linear XIP mapping. | APB, AXI DMA master, command/TX FIFO, PMC clock and pin routing. | Active in [AM011 revision 1.9](https://docs.amd.com/r/en-US/am011-versal-acap-trm/Quad-SPI-Controller). | Reuse hardware polling, queued phase descriptions, and DMA/error reporting. Avoid making DMA the only high-throughput route or assuming that indirect DMA can replace XIP/serial-RAM mapping. |

The most valuable combination for retroSoC is FlexSPI's programmable sequence,
ST's mapped/indirect/polling split, and the native AXI data plane used by the
AMD controllers. XPI does not copy vendor-specific DDR, DQS, parallel-flash,
or cache behavior because those features conflict with the current SDR,
single-domain, phase-separated constraint or need a separate physical-signoff
project.

## Selected Architecture

```text
                         +-------------------------+
 AXI4 mapped window ---> | xpi_mm                  |
                         | burst check/coalesce    |---+
                         +-------------------------+   |
                                                       v
 APB4 ---> xpi_reg ---> TX/RX FIFO ---> xpi_indirect -> arbiter
           |       DMA stall     polling               |
           |       IRQ/error/performance                v
           +-------- slot timing + LUT -----------> xpi_core
                                                       |
                                            xpi_clkgen + xpi_if
```

The implementation reuses the Common `axi4_if`, `apb4_if`, `axi4_addr_gen`,
`fifo`, and `dff*` components. There is no register generator: the reviewed
SystemVerilog macro table and `xpi_regs.h` are maintained together.

An active physical command is never preempted. Indirect or polling work blocks
new mapped requests, and a mapped transaction already accepted by AXI drains
before indirect work owns the core. `ABORT` terminates the physical command and
releases all output enables and chip selects.

There is no XPI read cache or speculative prefetch in V2. This keeps NOR
program/erase, PSRAM writes, DMA, and CPU reads coherent without a hidden
invalidate protocol. Performance comes from quad data phases, AXI burst
coalescing, configurable transaction boundaries, and FIFO/DMA transfers.

## Reset and Boot Contract

Reset makes NSS0 immediately usable as the boot NOR read path:

- controller enabled;
- NSS0 enabled for mapped reads and disabled for mapped writes;
- 16 MiB device size;
- SPI mode 0, `clk_i / 2` SCK, CS high time of two `clk_i` cycles;
- sequence 0 = `CMD 0xEB/1-pad`, `ADDR 24/4-pad`, `MODE 0xF0/4-pad`,
  `DUMMY 4/1-pad`, `RX runtime-length/4-pad`, `STOP`;
- boot alias `0x0000_0000..0x00ff_ffff` maps to NSS0.

Software that has been loaded into PSRAM, SDRAM, or SRAM can wait for idle,
clear `CTRL.ENABLE`, change NSS0 and its LUT, then re-enable the controller.
Configuration writes while enabled or busy fail with `PSLVERR`. A lock bit is
one-way until hardware reset.

## Memory Map and AXI4 Contract

| Address range | Chip select | Device address |
| --- | --- | --- |
| `0x0000_0000..0x00ff_ffff` | NSS0 boot read alias | `addr[23:0]` |
| `0x5000_0000..0x53ff_ffff` | NSS0 | offset from `0x5000_0000` |
| `0x5400_0000..0x57ff_ffff` | NSS1 | offset from `0x5400_0000` |
| `0x5800_0000..0x5bff_ffff` | NSS2 | offset from `0x5800_0000` |
| `0x5c00_0000..0x5fff_ffff` | NSS3 | offset from `0x5c00_0000` |

The memory slave is native 32-bit AXI4. It accepts aligned 1-, 2-, or 4-byte
beats, IDs at the SoC's one-bit width, and up to 16 beats. FIXED, INCR, and
legal 2/4/8/16-beat WRAP bursts are checked. A transaction must remain inside
one 4 KiB AXI boundary, one NSS window, the configured device size, and the
configured serial-burst boundary. Violations return `SLVERR`, set the first
error snapshot, and can raise the AXI-error interrupt.

An INCR read inside the configured boundary is one serial command whose receive
phase covers the complete AXI burst. Other legal accesses are split into one
serial command per AXI beat. Writes buffer at most 16 AXI beats, preserve
`WSTRB`, and convert contiguous active byte lanes into serial write runs. The
boot alias is read-only. A slot must explicitly enable mapped writes, and the
selected write LUT must implement the target memory's write protocol. Enabling
mapped write does not turn NOR flash into byte-writeable RAM.

## LUT and PHY Contract

There are 16 sequences with eight 16-bit instructions per sequence. Two
instructions occupy each 32-bit APB LUT word.

```text
15          12 11    10 9     8 7                         0
+--------------+--------+--------+--------------------------+
| opcode       | pads   | 0      | operand                  |
+--------------+--------+--------+--------------------------+
```

| Opcode | Name | Operand |
| --- | --- | --- |
| `0` | STOP | ignored; deassert CS and complete |
| `1` | CMD | 8-bit value |
| `2` | ADDR | 8, 16, 24, or 32 address bits |
| `3` | MODE | 8-bit value |
| `4` | DUMMY | SCK cycles |
| `5` | TX | byte count; zero selects runtime count |
| `6` | RX | byte count; zero selects runtime count |
| `7` | JUMP_ON_CS | deassert CS, honor CS-high time, continue at PC `[2:0]` |

`pads` values 0, 1, and 2 select one, two, and four data pads. Value 3 is
illegal. Bits `[9:8]` must be zero. PC7 must contain STOP or JUMP_ON_CS, which
prevents an unterminated sequence from indexing outside the LUT.

Only SDR SPI mode 0 and mode 3 are supported. SCK idles at CPOL. For transmit,
data is stable before the leading sample edge and changes on the trailing edge.
For receive, pads are high impedance through dummy and receive phases, input
is sampled on the leading edge, and a byte is exposed for exactly one
ready/valid transfer. The same `clk_i` drives AXI, APB, the core, and SCK phase
generation; there is no internal CDC.

## Indirect, DMA, Polling, and Interrupts

The indirect path executes any LUT sequence on any slot with a 32-bit address
and a 0..65535-byte runtime data count. Sixty-four 32-bit words are provided in
each TX and RX FIFO. PIO accesses use little-endian byte lanes: TXDATA bits
`[7:0]` are the first wire byte, and RXDATA bits `[7:0]` contain the first
received byte.

The central DMA uses the XPI TX/RX request IDs and the existing request-stall
handshake. FIFO watermark fields gate DMA requests. The HAL currently requires
32-bit aligned buffers and transfer lengths for DMA; PIO supports partial final
words. `dma_xfer_done_i` remains connected for SoC compatibility, while XPI
completion is defined by the programmed byte count and physical command done.

Automatic polling repeatedly executes one LUT sequence, accumulates up to four
received status bytes, compares `(value & mask) == (match & mask)`, waits the
programmed interval, and stops on match, timeout, error, or abort. This is the
required path for NOR WEL/WIP handling.

Interrupt state is sticky W1C. Sources are indirect done, poll match, TX
watermark, RX watermark, AXI error, sequence error, timeout, and abort done.
The IRQ output is the OR of enabled sticky sources. The first error snapshot is
also sticky and records code, AXI/device address, slot, and LUT PC.

## APB4 Register ABI

All registers are 32-bit and require word-aligned APB accesses. Unsupported,
misaligned, direction-invalid, busy-time configuration, FIFO overflow/underflow,
and malformed command accesses return `PSLVERR`.

| Offset | Register | Access / purpose |
| --- | --- | --- |
| `0x000` | ID | RO, `0x58504932` (`XPI2`) |
| `0x004` | VERSION | RO, `0x00020000` |
| `0x008` | CAPABILITY | RO, `0x04041010` |
| `0x00c` | CTRL | RW bit 0 enable; reset 1 |
| `0x010` | STATUS | RO enable/busy/FIFO flags |
| `0x014` | COMMAND | WO one-hot indirect-start, poll-start, abort |
| `0x018..0x020` | ERROR_STATE/ADDR/INFO | sticky first-error snapshot; state bit 31 W1C |
| `0x024..0x030` | INTR_STATE/ENABLE/STATUS/TEST | W1C state, mask, masked state, software set |
| `0x034` | DMA_CTRL | TX and RX request enable |
| `0x038` | FIFO_CTRL | TX/RX watermarks; bits 16/17 are flush pulses |
| `0x03c` | FIFO_STATUS | flags and seven-bit TX/RX word counts |
| `0x040/0x044` | TXDATA/RXDATA | PIO FIFO ports |
| `0x048..0x050` | INDIRECT_ADDR/COUNT/CFG | address, byte count, slot and sequence |
| `0x054..0x064` | POLL_CFG/MASK/MATCH/INTERVAL/TIMEOUT | automatic polling contract |
| `0x068..0x07c` | PERF_* | enable/clear and saturating byte/command/stall counters |
| `0x080` | CONFIG_LOCK | one-way global, slot0..3, and LUT locks |
| `0x100 + n*0x20` | SLOTn_* | CTRL, DEVICE_SIZE, SEQ_CFG, TIMING, TIMEOUT, BOUNDARY |
| `0x200..0x2fc` | LUT | 64 words, two instructions per word |

`SLOT_TIMING` packs clock divider, CS setup, CS hold, and CS high into bytes
0..3. `SEQ_CFG[3:0]` is the mapped-read sequence and `[7:4]` is the
mapped-write sequence. A zero boundary allows coalescing to the other AXI and
slot limits; otherwise it must be a power of two from 4 bytes through 64 MiB.

## HAL and JTAG Flash Programming

`<retrosoc/hal/xpi.h>` provides probe, enable/disable, slot and LUT
configuration, PIO and central-DMA transfers, automatic polling, abort,
interrupt, error, performance, lock, and data-only peripheral helpers. The LCD
driver uses explicit wire-order bytes rather than relying on an old QSPI byte
reversal side effect.

The JTAG flow uses the existing Hazard3 Debug Module, OpenOCD, and GDB abstract
commands. It does not add a second hardware JTAG-to-XPI master. The loader ELF
and all of its state execute from SoC SRAM, so the boot NOR can be unavailable
during erase/program:

```sh
make CONFIG=configs/ci/ihp130-xpi-flash-loader.mk firmware

python3 scripts/program_xpi_flash.py \
  --loader build/<xpi-loader-build>/sw/firmware \
  --image firmware.bin \
  --gdb-script build/xpi-flash.gdb

python3 scripts/program_xpi_flash.py \
  --loader build/<xpi-loader-build>/sw/firmware \
  --image firmware.bin \
  --gdb-script build/xpi-flash.gdb \
  --result build/xpi-flash-result.json \
  --execute
```

OpenOCD must already expose its GDB endpoint, which defaults to
`127.0.0.1:3333`. `--execute` is deliberately required because it erases NOR.
The host tool splits the image at 4 KiB boundaries. For every chunk, the SRAM
loader reads the complete sector through the boot alias, overlays the new
bytes, issues WREN/erase/program commands, hardware-polls WIP, programs sixteen
256-byte pages, and verifies the complete sector. This preserves bytes outside
the requested BIN range. The current loader is qualified for the 16 MiB
Winbond-compatible JEDEC ID `EF 40 18`; other parts need reviewed opcodes,
geometry, status bits, and timing.

## MVP, Development Order, and Optimization

The implemented MVP follows this dependency order:

1. Preserve reset-time NSS0 `0xEB` boot reads and the boot alias.
2. Freeze the SDR phase contract and implement the programmable LUT core.
3. Add the four-slot native AXI4 memory plane and burst coalescing.
4. Add APB configuration, strict errors, FIFOs, indirect PIO, DMA requests,
   interrupts, abort, and performance counters.
5. Add hardware status polling, the SRAM loader, sector-preserving JTAG host
   tool, and manual C register ABI.
6. Add PHY-directed tests, SoC XIP simulation, lint/style/quality gates,
   synthesis/netlist/STA regression, and this delivery contract.

The highest-value next optimizations are measurable and ordered:

1. Use performance counters to classify command overhead, AXI stalls, and
   achieved serial payload utilization on real NOR and PSRAM.
2. Add a non-speculative line-fill buffer only if single-beat XIP masters are
   the measured bottleneck. Define program/erase/DMA invalidation before RTL.
3. Add continuous-read/JUMP_ON_CS profiles only for devices whose exit and
   recovery sequences are covered by reset and negative tests.
4. Pipeline more AXI read requests only after response ordering, abort, and
   error fan-out have assertions and constrained-random coverage.
5. Treat higher SCK, DDR, DQS, delay training, and a separate PHY clock as a
   new PHY release requiring IO timing models, CDC/RDC analysis, and silicon
   characterization. They are not incremental V2 register bits.

Do not add an opaque hard-coded flash command decoder, silently acknowledge a
mapped NOR write before WIP completion, or add prefetch without an invalidation
contract. These shortcuts create device lock-in or stale executable data.

## Verification and Commercial Delivery Boundary

| Evidence | V2 status |
| --- | --- |
| Executable requirements and ABI | This document plus RTL/manual C definitions |
| Coding/format checks | `rtl-style-check`, Verible formatting, Verilator lint |
| PHY protocol | Directed mode-0/mode-3 command, dummy, quad receive, pad release, slot selection, and unterminated-LUT error test |
| Boot/XIP integration | IHP130 Hazard3 firmware boots through NSS0; finite `ci_smoke` must report `SIM_TEST_PASS` |
| Software/JTAG host logic | Host tests cover range validation, sector splitting, symbol parsing, persistent script generation, and per-sector calls |
| Full flash model | Icarus regression uses the Winbond model; the fast Verilator model covers reset `0xEB` reads only |
| Implementation | IHP130 Yosys synthesis, Icarus netlist boot, OpenSTA, warning, and metric stages in `regress-pr-ihp130` |

Commercial-IP signoff is not claimed by these tests alone. Release candidates
still need requirements traceability to every register field, APB/AXI protocol
assertion coverage, constrained-random LUT/FIFO/error testing, functional and
code coverage closure, formal deadlock/bounds proofs, reset/X-propagation and
gate-level reset review, physical IO timing across PVT, board tests on every
qualified NOR/PSRAM/LCD, DMA stress with competing AXI masters, JTAG power-loss
and recovery tests, DFT review, security/threat review, and versioned synthesis,
STA, CDC/RDC, lint, waiver, and release manifests.
