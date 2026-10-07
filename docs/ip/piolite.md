# Tiny PIO-lite Programmable I/O

## Purpose and Research Boundary

This is the approved `piolite` design freeze dated 2026-10-04, targeting
**TINY only**. It specifies a future standard Tiny feature, not an implemented
peripheral or a qualified device. `PIOLITE-P0` is the documentation gate;
P1-P5 require separately authorized implementation and evidence. The term
PIO-lite means this programmable engine; ordinary programmed register I/O
elsewhere in the repository does not imply this engine is present.

Authoritative inputs are the [Tiny product contract](tiny-soc.md),
[GPIO](gpio.md), [central DMA](dma.md),
[family positioning](../soc-family-positioning.md),
[engineering workflow](../engineering.md), and
[owned RTL policy](../rtl-coding-style.md). Executable configuration wins for
claims about current hardware. The baseline topology still has four DMA
channels and no PIO-lite. This freeze changes documentation only: no RTL,
firmware, configuration, dependency, warning baseline or quality-policy change.

## Target SoCs and Integration Scope

The [2026-10-07 Tiny refreeze](tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07)
selects default TINY/ICS55, `HAVE_PLL=YES`, SAFE24 boot, retaining explicit
IHP130 compatibility. `configs/ci/ics55-tiny.mk` remains planned until
TINY-ICS55-P1; commands below are existing IHP130 references. Pre-final
post-synthesis timing is observational, while functionality, protocol,
synthesis/mapping and netlist-function checks remain required. PIOLITE-P5
joins R2-P11, SPI-P5 and PPALITE-P5 after all functional stages on the same
complete-product netlist. Preserve phase IDs/titles and historical evidence;
titles containing IHP130 retain their names with this updated default scope.
PIO implementation and unrelated dependency changes remain outside this refreeze.

| Item | Frozen boundary |
| --- | --- |
| Target | TINY, future standard QFN64 product feature |
| Default target / planned profile | ICS55, `HAVE_PLL=YES`, SAFE24 boot; `configs/ci/ics55-tiny.mk` pending TINY-ICS55-P1 |
| Starting profile / PDK | `configs/ci/ihp130-tiny.mk` / IHP130; existing 24 MHz, no-PLL baseline |
| Product integration | `rtl/tiny/top/retrosoc_tiny.sv`, `rtl/tiny/integration/soc_topology.json`, `rtl/tiny/address_map/memory_map.json`, `rtl/tiny/pin_map/pin_map.json`, `rtl/tiny/integration/clock_reset_domains.json` |
| Filelists | `rtl/tiny/filelist/ip.fl`, `inc.fl`, `top.fl`, `tb.fl` and their existing build flow |
| Software composition | Shared freestanding `crt/` HAL; Tiny generated capability/memory/IRQ headers; independent `bringup` acceptance scenarios in `app/` |
| APB4 window | `0x1001C000..0x1001CFFF`, 32-bit configuration and FIFO access |
| Interrupt / RCU target | Tiny CPU IRQ24 / Tiny RCU target 15; not a family-wide assignment |
| DMA | Requests 14/TX and 15/RX through central DMA V2.1; no new memory master |
| Pads | Existing GPIO0..31 through GPIO `USER_SELECT`; no new ALT encoding, Pad or package terminal |
| Clocks | PCLK 24 baseline, PCLK 48/60 functional targets after R2 platform enablement; physical qualification only in the final campaign |
| Deferred products | MINI, STD, PRO and any four-SM product configuration |

Mini requires compatibility testing of shared DMA/GPIO changes but does not
gain PIO-lite. Its IRQ24 assignment is unaffected. Tiny retains 128 KiB main
SRAM, CPU/main-SRAM same-frequency SYS, private Crypto storage, the planned
eight central DMA channels and three external AXI owners. The new 64 B
instruction and 128 B FIFO payload stores are additional local register
arrays, not reservations from user SRAM. No dependency revision changes.

The performance-only R2 approval and all `TINY-R2-P0..P11` IDs/titles remain
historical truth. This separately approved feature extends the future product;
it does not rewrite old R2 evidence to include PIO-lite. Full integration
requires the applicable R2-P6 shared-IP/eight-channel and R2-P7 clock/reset
contracts. Standalone model/core development may precede those dependencies.

## Commercial References

Research checked on 2026-10-04. These are architecture references, not copied
implementations, binary compatibility promises or Tiny performance evidence.

| Primary reference | Confirmed external behavior and reuse boundary |
| --- | --- |
| [RP2040 datasheet, chapter 3](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf), PDF build 2025-02-20 | Four SMs per block share 32 instructions; each has shift/scratch registers, normal 4-word TX and RX FIFOs, DMA pacing and IRQ flags. Reuse autonomous execution, independent fetch, clock enables and explicit stalls. Tiny instead has two SMs, 8-word FIFOs in each direction, integer division and its own ISA. |
| [Pico SDK PIO API](https://www.raspberrypi.com/documentation/pico-sdk/hardware.html#hardware_pio) | Maintained software distinguishes divider restart, SM restart and FIFO clearing. Reuse explicit lifecycle and resource allocation; no Pico SDK or RP instruction compatibility. |
| [NXP AN12174](https://www.nxp.com/docs/en/application-note/AN12174.pdf), Rev 0 June 2018 | S32K1xx FlexIO combines four shifters, four timers and eight pins with polling, IRQ and DMA. Resource discovery is useful; fixed shifter/timer configuration is less suitable than microcode for arbitrary short sampling/pulse/scan programs. |
| [NXP AN13358](https://www.nxp.com/docs/en/application-note/AN13358.pdf), Rev 0 August 2021 | SPI reload/frame-boundary interactions motivate explicit first/last-bit, short-frame and starvation tests, not merely successful bulk data movement. |

The RP2040 and [S32K1](https://www.nxp.com/products/S32K1) vendor product and
documentation families remain supported references at the research date.
The public NXP application notes are older than the current product manuals;
login-gated current timing manuals were not used as verified evidence.
No reference supplies Tiny area, power, metastability MTBF, maximum Pad rate,
IHP130 timing closure or production qualification. RP2350's larger resources
are not required for this MVP. Vendor synchronizer bypass and fractional
division are deliberately not imported.

## Requirements and Non-goals

| ID | Normative requirement |
| --- | --- |
| PL-01 | MUST implement two independent SMs, one shared 32x16 instruction store with independent reads, and per-SM 32-bit ISR/OSR plus 16-bit X/Y. |
| PL-02 | MUST provide per-SM TX and RX 8x32 FIFOs, exact bit packing and atomic stall semantics; MUST NOT silently overwrite or invent data. |
| PL-03 | MUST execute in PCLK using integer enables, deterministic commit/delay rules and masked phase-aligned START. |
| PL-04 | MUST route only claimed existing GPIO, forbid overlapping SM output authorization, verify ownership/filter/readiness and fail to high impedance. |
| PL-05 | MUST use the shared central DMA pair 14/15 with whole-job channel ownership, stable stream beats and bounded abort/recovery. |
| PL-06 | MUST expose versioned APB/ISA discovery, truthful capabilities, a handwritten RTL/C register mirror, deterministic assembler and freestanding HAL. |
| PL-07 | MUST distinguish execution stop from transport completion, preserve unrelated channels/SMs, and require explicit clean restart after fault/reset/clock change. |
| PL-08 | MUST qualify all three application groups, including combined-program capacity, independent pin-level protocol checks and contention budgets. |
| PL-09 | MUST preserve QFN64/Pad count, ALT definitions, R2 CPU/SRAM clocks, memory capacities, DMA count and AXI-owner count. |
| PL-10 | MUST bind validation to SoC, profile, PDK, source revision and variant; targets are not measured capabilities. |

MUST NOT add RP binary compatibility, eFPGA fabric, general memory access, an
independent AXI master, dedicated general SPI, recovery Boot ROM, caches,
fractional SM division, external SM clocks, raw asynchronous input bypass,
side-set, instruction injection, computed PC, FIFO joining or a general ALU.
Four-SM enablement, deeper instruction storage, variable-length DMA framing,
other PDKs/products and simultaneous execution of all demo groups are DEFERRED.
No unresolved architecture choice blocks P1; physical limits remain evidence
gates and MUST NOT be resolved by relaxing correctness or claiming completion.

## Selected Architecture

### Module hierarchy and storage

The intended owned hierarchy is `apb4_piolite` around `piolite_reg`,
`piolite_core`, two instances of `piolite_sm`, shared `piolite_imem`, and
`piolite_dma_adapter`/`piolite_gpio_guard`. `piolite_if` carries internal
control/status and `piolite_define.svh` the handwritten ABI constants.
Implementation follows the owned naming, Common register and FIFO policy;
these names describe planned files, not existing sources.

Two independent combinational instruction reads MUST deliver one instruction
to each eligible SM tick without arbitration jitter. The 32-word store has
per-word validity: invalid locations read as zero over APB but fault on fetch.
Validity, not reset of every payload bit, excludes stale code after reset.
FIFO empty state similarly hides old payload. Inferred/register storage is an
explicit small-memory exception; synthesis must verify its size and mapping.
Parameterizing storage or instance arrays does not authorize advertising a
four-SM product. APB reserves four slots; Tiny V1 implements slots 0 and 1 only.

### Tick, commit and control precedence

Each SM uses `DIV=N`, 1..65535. START clears the divider phase; the first
instruction executes after N PCLK rising edges following the START edge.
Initial output data/OE apply on START itself, after all ownership checks.
A successful instruction commits atomically on its tick, then consumes D
additional ticks of delay. The next instruction is eligible on the following
tick. Failed WAIT or blocking FIFO operations retain PC, shifts, counters,
pins and delay state; delay begins only after successful commit.

Reset, fault/ABORT, accepted PAUSE/DISABLE, and instruction execution have
descending precedence. Mask commands validate every selected SM first and
are all-or-nothing. PAUSE takes effect on the APB control acceptance edge,
independent of N or a stalled WAIT, and wins over that edge's instruction.
Accepted DMA START uses the registered route and wins over a competing route
write, which returns APB error. Hardware events/set operations win W1C/clear.
Flags and input conditions are observed from pre-edge state; two SMs cannot
communicate through a same-edge combinational flag path.

### Instruction set, ISA1.0

All instructions are `opcode[15:12], delay[11:8], operand[7:0]`. Unlisted
operands/reserved bits are illegal before any instruction side effect.
IN/OUT count field 0 encodes 32, otherwise 1..31. This encoding does not apply
to X/Y: counter zero always means zero, never 65536.

| Opcode | Instruction | Operand encoding |
| --- | --- | --- |
| `0` | CTRL | `[7:5]`: NOP=0, HALT=1, CLEAR_ISR=2, CLEAR_OSR=3; `[4:0]=0`; HALT requires delay 0 |
| `1` | SET_PIN | Unsigned 8-bit immediate applied to SET window |
| `2` | SET_DIR | Unsigned 8-bit OE immediate applied to SET window |
| `3` | SET_COUNT | `[7]`: X=0/Y=1; `[6:0]` unsigned immediate |
| `4` | IN | `[7:5]`: pins=0/X=1/Y=2/zero=3; `[4:0]` bit count |
| `5` | OUT | `[7:5]`: pins=0/directions=1/X=2/Y=3/discard=4; `[4:0]` bit count; counter destination count <=16 |
| `6` | MOVE | `[7:6]`: ISR=0/OSR=1/X=2/Y=3; `[5:3]`: ISR=0/OSR=1/X=2/Y=3/zero=4/ones=5; `[2:0]=0` |
| `7` | FIFO | `[7]`: PULL=0/PUSH=1; `[6]`: nonblocking=0/blocking=1; `[5:0]=0` |
| `8` | WAIT | `[7]`: pin 0/flag 1; `[6]` required level; `[5:1]` index; `[0]=0`; flag index 0..3 |
| `9` | BRANCH | `[7:5]`: always 0/X-zero 1/Y-zero 2/dec-X-nonzero3/dec-Y-nonzero4/test-pin-high 5/last-FIFO-failed6/test-flag-set 7; `[4:0]` absolute relocated target |
| `A` | FLAG | `[7]`: clear 0/set 1; `[6:5]` flag 0..3; `[4:0]=0` |
| `B..F` | Reserved | Illegal-instruction fault |

X/Y reads zero-extend and MOVE writes retain low 16 bits. Decrement branches
decrement only a nonzero counter, then branch only if the result is nonzero.
MOVE ISR/OSR creates 32 valid bits; CLEAR sets the respective value/count to 0.
WAIT on a flag does not clear it. A test-pin branch requires TEST_PIN_ENABLE
and a claimed pin; flag tests use TEST_SELECT. Runtime WAIT outside CLAIM_MASK
faults. SET ignores immediate bits above the SET width. IN/OUT to pins requires
count <= configured window width; other pins retain their value/direction.

Explicit PULL replaces OSR with the next TX word and TX_BITS valid bits.
Explicit PUSH requires a nonzero ISR valid count, emits the normalized word,
and clears ISR/value count on success. Nonblocking failure advances PC without
data changes, sets last-FIFO-failed and FIFO_FAIL; successful FIFO transfer
clears last-FIFO-failed. Blocking stall does not count as nonblocking failure.
The last-FIFO-failed state clears on START/reset and is also updated by a
successful automatic FIFO transfer. HALT is terminal until DISABLE/START;
it retains output levels and does not promise external protocol success.

Each SM has BASE, LEN1..32, ENTRY, WRAP_BOTTOM and WRAP_TOP. Their addresses
are absolute instruction indices 0..31; BASE+LEN must be <=32 and all entry/wrap
positions inside the program region, with bottom <= top. Taken branch wins
over wrap; otherwise executing WRAP_TOP selects WRAP_BOTTOM, else PC+1.
An out-of-region target/fallthrough faults, never truncates. Prologue/cleanup
may be outside the wrap interval. A finite loop must place HALT after its
conditional branch without accidentally wrapping on the false branch.
HALT is exempt from successor/wrap validation: it retains its own PC, enters
HALTED and does not calculate PC+1. Thus a final HALT outside the wrap interval
does not fault merely because its hypothetical successor is outside the region.

### Shifts and FIFO word validity

TX_BITS/RX_BITS are 1..32. PULL uses the low TX_BITS bits of a FIFO word and
zeros unused high bits. Right OUT consumes the least-significant requested
bits first; left OUT consumes the highest bits within the remaining valid
range, then keeps the lower remainder. The selected chunk is low-aligned at
its destination. Autopull occurs only when OSR is empty and an OUT needs data;
a nonempty OSR with too few valid bits faults rather than joining words.
OUT with an empty OSR and AUTOPULL=0 also faults for shift bounds. With
AUTOPULL=1, validate n<=TX_BITS before touching TX FIFO: an impossible width
faults without dequeuing, while a legal-width empty FIFO stalls. A successful
automatic PULL and OUT commit together with no partially consumed TX word.

IN selects the low n source bits (GPIO window bit 0 is its lowest GPIO).
Right shift inserts those n bits at the top of ISR; PUSH shifts the k valid
bits down by 32-k. Left shift appends n bits at the bottom and needs no such
normalization. Both zero unused high bits on PUSH. Four right-packed samples
produce `s0 | s1<<8 | s2<<16 | s3<<24`; a two-byte tail occupies low 16 bits.
An IN exceeding RX_BITS with autopush, or 32 without it, faults before sampling.
Autopush occurs exactly at RX_BITS and is atomic with IN: full RX FIFO stalls
the instruction before its sample, with no duplicate/partial sample. Manual
partial PUSH is allowed. SHIFT counts describe validity, not nonzero content.

FIFO overflow/underflow never overwrites data or fabricates zero words. A
stall is observable even if the external protocol cannot tolerate it. FIFO
budget uses emitted words: RX headroom is free_words/word_rate; TX reserve is
queued_words/word_rate, with a separately justified ISR/OSR reserve. Service
latency includes arbitration, descriptor reads, other DMA clients and memory
responses, not only average bandwidth.

All FIFO eligibility uses pre-edge occupancy, with no empty fall-through or
full look-ahead. At full, an attempted enqueue stalls/errors even if a dequeue
occurs on that edge; at empty, a dequeue stalls/errors even if a producer
arrives. At intermediate occupancy an eligible simultaneous enqueue/dequeue
preserves level and dequeues the old head. An SM transfer, CPU access and DMA
handshake therefore have the same model/RTL cycle boundary.

## Interfaces

### APB4 and memory data path

APB is 32-bit address/data, little endian, aligned words only. Accepted writes
require `PSTRB=0xF`; partial/unaligned/unmapped, reserved-bit, illegal-state and
wrong-direction accesses complete with PSLVERR and no requested side effect.
Reads use ordinary APB read strobes. WO reads and RO writes error; all reserved
read bits are zero. One transfer completes once; no repeated FIFO side effect
while APB remains asserted. Responses MUST be bounded independently of an SM
or FIFO condition, using the repository registered APB response convention.
Full TX write/empty RX read returns error immediately, never waits for space.

PIO-lite has no AXI memory port. The central DMA is the only PIO payload
memory owner, using Tiny AXI32's existing ordering, bursts (at most 16 beats),
4 KiB boundaries and errors. CPU accesses cross the existing SYS/PCLK bridge.
DMA buffers/descriptors stay owned until all accepted memory responses drain;
no cache, coherence or new executable-memory policy is implied.

### GPIO acquisition and guard

IN/OUT windows have base 0..31 and width 0..32; SET width 0..8. Width 0 disables a
window; base+width must not exceed 32. Every enabled window and WAIT/test pin
must belong to CLAIM_MASK. OUT/SET windows and initial OE must be subsets of
OUTPUT_MASK, itself a subset of CLAIM_MASK. Both SM OUTPUT_MASK values MUST be
disjoint, even when their current OE is zero. Input-only claims may overlap;
one SM may observe another's authorized output. Release requires software
reference-counting overlapping claims.

Use the existing GPIO `user_gpio_if` data/OE and synchronized input route.
GPIO must export read-only USER_SELECT, USER_STATUS and FILTER_ENABLE plus RCU lifecycle
readiness. START requires all claims owned, filters disabled, GPIO ready and
legal masks. CPU FIFO access and enabling a DMA binding also require these
guards; preload is performed after acquisition, not before claiming pins.
An SM session is live while RUNNING/PAUSED/HALTED or while an enabled binding,
bound DMA job, held beat or prefilled FIFO exists, including
DISABLED execution with DMA armed. Loss of any guard condition closes and
faults that session; stale prefill cannot survive into a new claim. Merely
writing a DISABLED, empty, unbound configuration before acquisition does not
create a fault. Physical OE is continuously qualified by ownership/readiness, so
the fault path cannot leave an unauthorized driven level for a software cycle.
The existing GPIO handoff high-impedance interval remains authoritative.

The input path contains the GPIO synchronizer and registered filter/bypass
stage. FILTER_ENABLE=0 removes debounce, not these registers; there is no
new PIO synchronizer or raw bypass. Account for the whole pipeline and SM tick
quantization in protocol timing. Independent asynchronous bus bits are not a
coherent source-synchronous bus without board/setup/hold constraints.

HAL acquisition MUST check CONFIG_LOCK/USER_LOCK, native and board ownership,
electrical capabilities and output contention; quiesce native outputs, input
consumers and interrupts; prepare native OE0/ALT-disabled fallback; disable
filters; select USER ownership and verify USER_STATUS after handoff before
START. Existing unchecked GPIO helpers alone are not sufficient. Dynamic
sessions do not set USER_LOCK. No speculative probing of absent product MMIO.

Release stops execution/drains transport, releases PIO OE, prepares/verifies
the native high-impedance fallback, clears USER_SELECT and verifies readback
before dropping the software claim. Do not restore a latent ALT driver.
USER_LOCK failure retains high-impedance ownership and returns error; no
automatic global GPIO reset. Unexpected GPIO reset invalidates the session,
requiring explicit reacquisition. RCU rejects GPIO gating/reset while any PIO
claim remains owned, including commands naming GPIO and PIO together; an
explicit coordinated system reset is a separate whole-system operation.

GPIO IRQ/filter/electrical changes on owned pins require session coordination.
This is trusted bare-metal ownership, not a security firewall. Dedicated boot
XPI/JTAG pads remain outside the routable mask. External drivers must be
quiesced or isolated; firmware routing cannot remove board-level contention.

Tiny's sole USER data/OE source is PIO-lite. OWNED_MASK and the RCU GPIO veto
therefore follow GPIO USER_SELECT, including an acquisition handoff, not the
mutable SM CLAIM_MASK union. START still requires active USER_STATUS. Clearing
or replacing a stopped SM claim cannot hide a still-selected USER pad; the
HAL retains its reservation until checked GPIO release completes. RCU rechecks
the ownership/readiness handshake at gate/reset commit, not only command issue.

## DMA and Interrupt Contract

### Shared pair and admission

PIO TX uses `PIOLITE_TX=14`, MM_TO_STREAM; RX uses `PIOLITE_RX=15`,
STREAM_TO_MM. Only
32-bit widths and positive lengths divisible by 4 are valid. One TX SM and
one RX SM can use DMA at once; they may be the same SM. Each enabled binding
names a distinct exclusive channel; the opposite FIFO direction may still
use CPU access. CPU cannot access the DMA-owned FIFO port, including during
pause or recovery. Default software assignment is TX channel 3 and RX channel 2
only after releasing bulk/DVP users. Other free channels need explicit
application ownership; Crypto/audio reservations are not silently stolen.

The authoritative shared extension is [DMA V2.1](dma.md):
`IP_VERSION=0x00020001`, `SUPPORTED_REQUESTS` at 0x028, requests 14/15 added
without widening the selector or modifying the 64 B TCD. REQUEST_STATUS is
live readiness, not presence. The capability stream count reflects actual
wired supported directions (at most 7 with I2S, DVP, Crypto and PIO), not a
constant for all products. Mini's PIO support/grants default off.

TX_BIND/RX_BIND select SM, channel and enable. Old/new affected SMs must be
DISABLED, old/new channel jobs fully drained and the endpoint free of held
beats before a change. Bindings supply one-hot channel admission grants to
both DMA direct START and TCD activation. An accepted START locks the current
registered binding. A job reservation spans the complete chain, including
non-PIO descriptors and suspended intervals; unrelated clients MUST NOT share
that chain. No global-DMA-idle condition is imposed.

Complete drain includes accepted descriptor reads and pending parse/activation,
not just payload R/W ownership or current TVALID. Cancel/error suppresses new
descriptor fetch/activation, drains accepted descriptor reads, discards their
results and clears canceled pending work before releasing the channel. Fixing
the baseline DMA abort gap is part of P3, not assumed existing behavior.

### Stream and completion semantics

Both endpoints use 32-bit AXI4-Stream in PCLK with TKEEP/TSTRB=0xF, one-bit
ID/DEST/USER=0. RX TLAST=0; TX TLAST is ignored because byte count controls DMA
completion. Invalid TX strobes/keep or nonzero identity/user fields fault the
SM and enter discard recovery; an already asserted invalid beat is accepted
and discarded so it cannot deadlock abort. RX data/VALID remain stable until
handshake or the explicit isolated endpoint-reset boundary.

PIO DMA length is four times the number of emitted FIFO words. UART byte-per-
word programs and four-byte-packed logic programs therefore differ. Program
metadata determines tail validity; DMA never infers it from zero high bits or
TLAST. No partial-keep tail or fabricated padding beats are supported.

Finite success requires program HALT, exact TX/RX word counts, DMA success
including final memory responses, expected FIFO/shift tail state, and no
disqualifying program/transport error. HALT, DMA idle, aborted DMA or cleared
interrupt alone is not success. Extra residual RX data is a length mismatch,
not permission to rebind. Variable-length infrared receive uses CPU/IRQ FIFO
service in V1 instead of aborting a maximum-length DMA and calling it success.

### Interrupts

Tiny IRQ24 is the level OR of enabled global sources. IRQ_STATUS bits 0..3
are each SM's enabled sticky events (unimplemented bits zero), bits 8..11 are
shared flags, bits 16..19 are TX occupancy <= TX_LOW, and bits 24..27 are RX
occupancy >= RX_HIGH. FIFO watermarks are level conditions independent of
execution state; service/disable their enables to deassert them. IRQ_ENABLE
uses the same mask. Flags are cleared explicitly, never by WAIT.

Per-SM EVENTS bits 0..5 are HALT, ABORT, FAULT, TX_STALL, RX_STALL and FIFO_FAIL.
EVENT_ENABLE selects their contribution. Hardware set wins concurrent W1C;
global flag SET wins all clears, including another SM or CPU. APB access
errors are reported to the bus without silently faulting an unrelated SM.

## Register and Software ABI

### APB1.0 map

Offsets are relative to the Tiny window. All registers are 32 bits. Reset
values are zero unless stated otherwise. Configuration writes require the
affected SM DISABLED and associated transport quiescent; live IRQ enable/W1C,
FIFO ports and lifecycle commands have the explicit exceptions below.

| Offset | Register | Access / fields |
| --- | --- | --- |
| `000` | IP_ID | RO `0x50494F4C` (PIOL) |
| `004` | IP_VERSION | RO `0x00010000`, APB1.0 |
| `008` | ISA_VERSION | RO `0x00010000`, independent ISA1.0 |
| `00C` | CAPABILITY | RO `[7:0]` SM count 2, `[15:8]` instruction words 32, `[23:16]` TX depth 8, `[31:24]` RX depth 8 |
| `010` | ROUTABLE_MASK | RO `0xFFFFFFFF` on fully integrated Tiny |
| `014` | CLOCK_HZ | RO actual current PCLK Hz, not SYS Hz |
| `018` | FLAGS | RO shared flags `[3:0]` |
| `01C`, `020` | FLAG_SET, FLAG_CLEAR | WO masks `[3:0]` |
| `024`, `028` | IRQ_STATUS, IRQ_ENABLE | RO aggregate / RW global enables |
| `02C`, `030` | TX_BIND, RX_BIND | RW `[1:0]` SM, `[10:8]` DMA channel, `[31]` enable; disabled reset 0 |
| `034` | TRANSPORT_STATUS | RO bits 0/1 TX/RX channel job owned, 2/3 TX/RX held beat, 4/5 TX/RX closing |
| `038` | IMEM_VALID | RO bitmap of 32 valid instruction slots |
| `03C` | OWNED_MASK | RO GPIO USER_SELECT on Tiny, independent of SM claims; includes handoff, reset follows GPIO |
| `040` | START | WO SM mask `[3:0]`, from DISABLED only; validate all selected SMs atomically |
| `044`, `048` | PAUSE, RESUME | WO SM masks, RUNNING to PAUSED / PAUSED to RUNNING |
| `04C`, `050` | DISABLE, ABORT | WO SM masks; lifecycle rules below |
| `054` | SM_RESET | WO SM mask; coordinated local endpoint reset after bound jobs drain |
| `058` | BLOCK_RESET | WO bit 0; all SMs DISABLED, bindings disabled, endpoints quiescent and OWNED_MASK=0 |
| `100..17C` | IMEM[0..31] | RW low 16 instruction, high 16 zero; validity set on write |
| `200..27C`, `280..2FC` | SM0, SM1 | Implemented per-SM slots below |
| `300..3FC` | SM2, SM3 | Reserved future slots; accesses error in Tiny V1 |

Offsets not listed error. Mask bits naming unimplemented SMs error even in
lifecycle/IRQ writes; commands with mask 0 are no-ops. IMEM writes require
all SMs DISABLED, both bindings disabled and no held/accepted transport.
BLOCK_RESET clears the block-local state on its accepted edge; its APB
response still completes. It is not an uncontrolled asynchronous reset.
CPU FIFO accesses are permitted in DISABLED/RUNNING/PAUSED/HALTED only when
that port is not DMA-owned and has the required space/data. CLOSING rejects
both CPU FIFO ports; diagnostics and recovery commands remain accessible.

### Per-SM map

The stride is 0x80. All reserved field bits are zero on read and must be zero
on write. Scalar range checks occur on writes; cross-register program/pin
consistency is checked again before START. Reset may be an unconfigured state.

| Offset | Register | Access / fields and nonzero reset |
| --- | --- | --- |
| `00` | STATUS | RO state `[2:0]`: DISABLED=0/RUNNING=1/PAUSED=2/HALTED=3/CLOSING=4; stall `[6:4]`: none=0/pin=1/flag=2/TX=3/RX=4; `[8]` last-FIFO-failed |
| `04` | CONFIG | RW bits 0 AUTOPULL, 1 AUTOPUSH, 2 TX_RIGHT, 3 RX_RIGHT, 4 TEST_PIN_ENABLE |
| `08` | DIV | RW `[15:0]` 1..65535; reset 1 |
| `0C` | PROGRAM | RW BASE `[4:0]`, LEN `[13:8]` 1..32, ENTRY `[20:16]` |
| `10` | WRAP | RW BOTTOM `[4:0]`, TOP `[12:8]` |
| `14`, `18`, `1C` | IN_PINS, OUT_PINS, SET_PINS | RW base `[4:0]`, width `[13:8]`; width 0 disables |
| `20`, `24` | CLAIM_MASK, OUTPUT_MASK | RW 32-bit pin masks |
| `28`, `2C` | INITIAL_VALUE, INITIAL_OE | RW 32-bit GPIO-aligned START values; non-output bits must be zero |
| `30` | INITIAL_XY | RW initial X `[15:0]`, Y `[31:16]` |
| `34` | SHIFT_LIMITS | RW TX_BITS `[5:0]`, RX_BITS `[13:8]`, both 1..32; reset `0x00002020` |
| `38` | TEST_SELECT | RW test GPIO `[4:0]`, test flag `[9:8]`; GPIO checked only when enabled/used |
| `3C` | WATERMARKS | RW TX_LOW `[3:0]` 0..8, RX_HIGH `[11:8]` 1..8; reset `0x00000100` |
| `40`, `44` | TXDATA, RXDATA | WO CPU push / RO CPU pop; errors for unavailable or DMA-owned port |
| `48` | FIFO_LEVELS | RO TX `[3:0]`, RX `[11:8]`, range 0..8 |
| `4C`, `50` | EVENTS, EVENT_ENABLE | W1C sticky / RW bits 0..5 |
| `54` | FAULT | RO first code `[7:0]`, PC `[12:8]`; cleared by SM/block reset |
| `58` | PC | RO current instruction index `[4:0]` |
| `5C`, `60`, `64` | ISR, OSR, XY | RO live shifts; X low 16/Y high 16 |
| `68` | SHIFT_COUNTS | RO ISR `[5:0]`, OSR `[13:8]` valid bits |
| `6C` | TICK_COUNT | RO saturating 32-bit count of unpaused execution ticks, including stalls/delays |
| `70`, `74` | TX_STALL_COUNT, RX_STALL_COUNT | RO saturating 32-bit count of execution ticks stalled for that FIFO |
| `78` | RETIRED_COUNT | RO saturating 32-bit successful instruction commits |
| `7C` | EXEC_PHASE | RO divider edges remaining `[15:0]`, delay ticks remaining `[19:16]` |

START resets runtime PC/divider/shifts/counts/counters/last-FIFO-failed, loads
INITIAL_XY/data/OE, and preserves prefilled TX FIFO and sticky event history.
RX FIFO must be empty. A held/accepted TX beat may continue filling the FIFO
under its already valid binding; an RX job may be armed waiting for samples.
START therefore checks valid route ownership, not global DMA idle. It does
not bypass IMEM/configuration/route-write quiescence. Stale fault requires
SM_RESET before reuse. HAL clears prior event history deliberately.

### Software contract and program format

Handwrite the future `piolite_define.svh` and
`crt/include/retrosoc/hal/piolite_regs.h` mirror, with a parity test covering
offsets, masks, resets, opcodes and enumerations. No register generator.
APB and ISA versions evolve separately; incompatible versions return
RS_ENOTSUP before loading code. Product-generated presence, RCU target
capability and PIO discovery agree. Do not invent an ARCHINFO bit; absent
product metadata must prevent probing an unmapped PIO window. PIO DMA requires
DMA major2/minor>=1 with the requested direction's support bit; full Tiny MVP
integration must expose both bits. A future unknown major is not implicitly
compatible. Do not read offset 0x028 on older V2.0 hardware.

The assembler input extension is `.piolite`. It supports labels, the exact
instructions above, optional delay 0..15, and directives `.program`, `.entry`,
`.wrap_bottom`, `.wrap_top`, `.in`, `.out`, `.set`, `.tx_bits`, `.rx_bits`,
`.test`, `.packing` and `.clock_ticks` for required metadata. Numeric values
are unsigned decimal or
hexadecimal; no implicit truncation, macros, include downloading or executable
expressions. Program/label identifiers use ASCII letters/digits/underscore,
starting with a letter/underscore. Comments begin `;`. Reject duplicate/unknown
labels, illegal operands, unresolved timing/resource metadata and >32 words.
Timing metadata states normal-path ticks and whether WAIT/FIFO can stretch it;
it never certifies an arbitrary program's external protocol.

Directive syntax is `.program NAME`; `.entry LABEL`, `.wrap_bottom LABEL`,
`.wrap_top LABEL`; `.in BASE, WIDTH`, `.out BASE, WIDTH`, `.set BASE, WIDTH`;
`.tx_bits N, left|right, manual|auto` and the equivalent `.rx_bits` form;
`.test PIN|none, FLAG`; `.packing TX_ITEMS, RX_ITEMS, ITEM_BITS` (zero items
means application-defined framed words); `.clock_ticks N, fixed|stretchable`
for the declared steady-state item period. Emit the flags/pins actually
referenced by instructions as resource metadata. Disabled windows use width 0;
RX_BITS/TX_BITS still use 1..32. Metadata requiring run-time count/tail framing
is explicitly application-owned, never inferred from zeros or TLAST.

One statement per line uses an optional `label:` and an opcode mnemonic from
the ISA table, with comma-separated symbolic/numeric operands in table order,
then optional `[delay]`. Names are case-sensitive; instruction/operand symbols
are uppercase. BRANCH uses a label, never an unchecked literal absolute PC.
CTRL uses NOP/HALT/CLEAR_ISR/CLEAR_OSR; FIFO uses PULL/PUSH and BLOCKING/
NONBLOCKING; branch symbols are ALWAYS, X_ZERO, Y_ZERO, DEC_X_NONZERO,
DEC_Y_NONZERO, TEST_PIN_HIGH, FIFO_FAILED, TEST_FLAG_SET. WAIT operands are
PIN|FLAG, level, index; FLAG operands are SET|CLEAR, index. P1 implements this
syntax without silently inventing extra instructions or changing their meaning.

Emit deterministic C program objects with ISA version, 16-bit words, length,
entry/wrap offsets, absolute-branch relocation sites, pin/flag/packing metadata
and timing requirements. The same input/options produce byte-identical output,
without timestamps or host paths. Generated arrays belong in
`build/<variant>/generated/piolite/`; handwritten programs remain application
source. No new downloadable assembler dependency is authorized.

Loader allocation uses a shared 32-bit slot bitmap. Patch only branch target
bits, validate base+offset<=31, and validate every relocated instruction before
publishing it. Both SMs can reference the same identical relocated image;
distinct loaded images together consume at most 32 slots. Hold a global HAL
loader/session lock across load/readback/publication; concurrent START, route,
FIFO, reset and program mutations are rejected/serialized, not interleaved.
An interrupted/failed load is not executable until fully validated and
published; software invalidates its allocation and does not start it. START
additionally requires all instruction-valid bits in the configured region.
Branch target bounds are checked even when the branch condition is false,
before counter or other instruction effects.

The public `piolite.h` API groups are discover/configure, program_load/unload,
claim/release, dma_bind/unbind, write/read, start/pause/resume/disable,
wait_done, abort_reset and get_status. All fallible `rs_piolite_*` operations
return `rs_status_t`; lengths/counts use uint32_t, masks uint32_t, instructions
uint16_t and timeouts rs_timeout_t. Static caller-owned program/session/buffer
storage is required. No heap, hosted library or OS dependency. Initialization
must validate 16-bit counters before narrowing, word_count*4 overflow, address
alignment/range/capacity and actual available channel/pin resources.

Use existing RS_EINVAL for invalid arguments, RS_ENOSPC for resources,
RS_ENOTSUP for absent/unsupported capabilities, RS_EFORMAT for bad code,
RS_ETIMEOUT for bounded wait expiry and RS_EIO for hardware/ownership/lock
failures. Status diagnostics distinguish busy/locked/closing even though no
new global status enumeration is added. Publishing a valid DMA result requires
ownership drain and successful program/length checks. After a failed session
has completely drained and isolated, software may reclaim/reuse its memory,
but the partial contents are not a valid capture or successful result.

## Clock, Reset, CDC/RDC, and Lifecycle

The core, APB registers, instruction store, FIFOs and stream adapters all run
in PCLK. SM division is an enable, not a generated-clock constraint. GPIO
already owns input synchronization; CPU APB and DMA memory domain crossings
remain the existing Tiny bridges. No additional CDC is hidden in a PIO route.
PIO consumes the actual RCU PCLK rate; CPU/main SRAM SYS and XPI MEM are not
substitutes. PCLK 24 is the starting environment; 48/60 functional tests require
R2 clock/platform implementation, not intermediate physical qualification.

| Operation/state | Required behavior |
| --- | --- |
| PAUSE | Bounded PCLK control action; retain PC, delay, divider phase, pins and FIFOs; DMA may continue |
| RESUME | PAUSED only; continue retained phase without fresh START initialization |
| HALTED | Terminal program state, pins retained and FIFO/DMA tail service permitted |
| DISABLE | From DISABLED/RUNNING/PAUSED/HALTED only; reject CLOSING or an active associated DMA job; stop execution/release OE and retain FIFO/held stream state, never imply successful transfer |
| ABORT/FAULT | Stop instruction side effects and release OE immediately; latch CLOSING and block new admissions/config/rebinding |
| SM_RESET | From DISABLED/CLOSING only, once its jobs drain; isolate its bound endpoints, cancel an unaccepted held RX beat, flush local FIFOs/runtime/events/fault/counters, disable its bindings and return DISABLED |
| BLOCK_RESET | Clear all configuration, bindings, masks, flags, IMEM validity, runtime and FIFOs; safe OE0 |

SM_RESET preserves its configuration/CLAIM_MASK, shared IMEM/flags and the
other SM's state; it never silently releases GPIO USER ownership. Its retained
configuration is revalidated before reuse. BLOCK_RESET does not reset GPIO;
safe native fallback and explicit GPIO reacquisition are still required.
CLOSING cannot be escaped through DISABLE/START, event clearing or a restored
GPIO guard; only successful SM_RESET recovery can make the affected SM reusable.
Initial reset has all SMs DISABLED, OE0, FIFOs empty, IMEM invalid, IRQ masks 0
and bindings disabled. Physical reset release follows Tiny's existing staged
synchronous release policy. No stale instruction/FIFO payload is observable.

ABORT/FAULT closes both affected bindings, enables TX discard to accept held
DMA beats, and preserves an already asserted RX beat. Abort the owning DMA
jobs, drain payload and descriptor transactions, then isolate/reset those
endpoints. RX abort must complete even when its FIFO is empty or VALID remains
asserted; never generate filler to meet the requested length. Ordinary FIFO
flush/route change cannot withdraw VALID. A timeout leaves the session closed,
owned and non-reusable until explicit successful recovery. Unrelated DMA jobs
and the other SM continue; no global DMA reset is an error-recovery shortcut.

PCLK rate change requires all SMs DISABLED, all PIO jobs drained, no held
beats and clean endpoint isolation. PAUSED/HALTED/WAIT is insufficient. Rate
changes retain stored programs/configuration but invalidate cached timing;
read CLOCK_HZ, recalculate DIV and explicitly START. RCU target 15 publishes
capability only after its idle/reset path is wired. PIO target gate/reset and
BLOCK_RESET additionally require releasing GPIO ownership first, so a stopped
clock or cleared claim register cannot conceal a still-selected USER driver.
This block-level requirement does not apply to recovery SM_RESET, which retains
the session's claim/configuration and reports its safe high-impedance state.
GPIO target 1 cannot be
gated/reset while OWNED_MASK is nonzero, even if PIO is stopped; release first.
Unexpected unilateral reset invalidates sessions, clamps OE and prohibits
automatic resume. A whole-system reset discards the complete traffic epoch;
peripheral-local reset must not strand accepted memory transactions.

CPU-only WFI gating, debug halt or hart reset does not implicitly reset/stop
PIO or its DMA job. Those independent domains retain the R2 service contract.
Restarted firmware must discover active/closing sessions and recover or adopt
them explicitly before reconfiguration; debug software uses PAUSE/ABORT when
pin activity must stop. Only system or qualified PIO-local lifecycle commands
own PIO reset.

## Errors, Recovery, Security, and Observability

FAULT first-code values are 0 none, 1 illegal instruction, 2 invalid fetch,
3 program bounds, 4 shift bounds, 5 pin authorization, 6 ownership/filter lost,
7 GPIO not ready/reset, 8 invalid stream beat. A first error latches code/PC
until SM_RESET; later events cannot overwrite it. If simultaneous, GPIO
readiness/ownership faults precede stream faults, then execution faults;
within the same class the lowest code wins. APB errors have no requested
side effect and remain bus errors rather than silently changing first fault.

Sticky FIFO stall/failure events and saturating counters expose underrun/
overflow pressure without inventing data loss counts. Pin capture may miss
events while stalled; a lossless application rejects any RX_STALL. TX stall
is acceptable only when its protocol explicitly allows extending that phase.
PC/ISR/OSR/X/Y and execution phase are live diagnostics; PAUSE provides an
execution snapshot, not an atomic snapshot of moving FIFO/DMA state.

PIO is trusted firmware functionality, not sandboxed code. GPIO claim checks
do not isolate malicious APB writers, provide secure boot, qualify entropy,
establish functional safety or guarantee electrical fault protection. Drivers
must check external voltage/drive/open-drain/turnaround requirements. No Pin
rate is derived merely from PCLK; pad/board timing and synchronizer behavior
require independent evidence.

## MVP and Commercial-grade Roadmap

MVP means the exact two-SM architecture, software tooling, GPIO/DMA lifecycle
and all three independent application groups below. It is not permission to
expand storage to make an oversized demonstration fit.

| Group | Required finite/observable acceptance |
| --- | --- |
| Digital instruments | Eight-channel 32 KiB finite capture at 1 MSPS, plus pulse generation/width capture using both SMs; no missing/repeated samples and documented synchronizer/tick error bounds |
| Serial protocols | UART8N1 TX/RX at 115200 baud with <=2% actual baud error; SPI master CPOL/CPHA0..3 at 1 MHz and 8/16/32-bit frames;38 kHz carrier/mark-space IR TX and demodulated pulse-width RX |
| Interactive lighting | Externally driven 8x8 monochrome LED matrix at>=200 complete frames/s, with blank-before-wait behavior;8-bit latch/clock/data shift-register gamepad with deterministic and changing input patterns |

These are separate profiles/scenarios, not all simultaneously enabled. UART
duplex and pulse/capture pairs must fit the combined 32 instructions. Each
scenario records SMs, instruction allocation, pin masks, native peripherals
disabled, FIFO packing, DMA ownership and expected word counts. No new APP
selection is required; use existing bringup composition. IR RX variable-length
records use bounded CPU/IRQ service, explicit buffer limits and software
framing, not an unbounded FIFO or early-DMA-success extension.

At 24/48/60 MHz, a two-tick eight-bit capture loop with DIV 12/24/30 gives 1 MSPS;
32 KiB contains 32768 samples and 8192 packed FIFO words. An eight-tick UART bit
with DIV 26/52/65 yields about 115384.6 baud (0.16% high). A 12-tick SPI bit with
DIV 2/4/5 yields1 MHz. These are arithmetic design budgets, not assembled or
tested programs; actual instruction paths, frame boundaries and pin latency
must satisfy them before publication. IR carrier tolerance is<=2%; pulse
envelope error includes documented integer quantization. Faster experiments
are measurements, not substitutes for the three baseline acceptance groups.

Commercial evolution may add four SMs, larger stores or richer timing only
through a separate ABI/resource/physical review. Maintain a reusable program
library, independent protocol models and per-board routing examples first.
Do not advertise a camera+audio+PIO combination without its own pin/DMA/service
budget and tests; existing camera/audio exclusion still applies.

## Verification and Software Validation

P1 supplies a cycle-accurate reference model and deterministic assembler tests;
P2 compares RTL against the model with independent protocol assertions. P3/P4
add actual Tiny pad/stream/firmware integration. The detailed requirement and
evidence ledger is [PIO-lite verification](piolite-verification.md).

Mandatory cases include all opcodes/operand rejection, count 0 encoding 32,
counter 0/65535, DIV 1/65535, every delay, wrap/branch bounds, instruction-store
sharing and exhaustion, simultaneous SM execution, WAIT/PAUSE/ABORT under
infinite stalls, partial pack tails, FIFO full/empty and concurrent push/pop,
set/W1C races, lost ownership/filter changes, GPIO handoff/lock failures,
DMA descriptor abort/activation races, suspended mixed chains, simultaneous
START/rebind, residual RX VALID, memory response errors and timeout retention.
Test unaffected SMs/channels and Mini's PIO-disabled shared-IP integration.

Firmware verdict is Tiny SYSCTRL TEST_STATUS and `SIM_TEST_PASS`, successful
command exit, and no `FAILED`, `FATAL`, `assertion failed`, `%Error`,
`SIM_TEST_FAIL` or `SIM_TEST_TIMEOUT`. UART boot text is not acceptance.
Verilator and Icarus pin BFMs must validate first/last-bit timing, all SPI modes,
UART asynchronous phase/error recovery, pulse bounds and display blanking.

Current commands below describe existing tooling, not proof that PIO tests
already exist. P1/P2 add focused tests to normal test discovery, not fictional
Make targets. After the relevant implementation is authorized:

```sh
ruff check .
python3 -m pytest -q
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130-tiny.mk firmware
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --dry-run
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY
python3 scripts/regress.py --root . --suite nightly --soc TINY
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI
```

P1 Python-only validation does not require running absent PIO RTL or pretending
R2 platforms are ready. New self-owned C follows MISRA C:2012 Amendment 2;
no deviation is approved by this document. Required-rule deviations, if any,
need their own reviewed record. Existing excluded/managed code remains excluded.

## Synthesis, Timing, and Physical Evidence

For default TINY/ICS55 or explicit IHP130 compatibility, record source SHA,
lock/config digest, variant, PCLK/SYS/MEM,
program binaries, pin loads and enabled endpoints for every result. Required
evidence includes block and full-SoC synthesis, register/IMEM/FIFO mapping,
area/cell count, activity-based power, WNS/TNS, reset fanout and release,
CDC/RDC review, netlist simulation, PVT/MMMC and extracted timing. Existing
observe-mode metrics and warning-baseline policy remain unchanged.

PIO PCLK 24/48/60 timing must coexist with the corresponding R2 SYS/SRAM and
MEM operating points; a PIO-only pass cannot qualify CPU240 or SRAM macros.
Physical evidence includes Pad rise/fall, load, setup/hold, OE turnaround,
simultaneous switching, board constraints and QFN64 routing. Structural DFT
and local-storage test coverage must be reviewed; no SRAM MBIST/ECC or silicon
qualification is claimed for these register arrays.

P5 must join TINY-R2-P11, SPI-P5 and PPALITE-P5 in the final campaign after all
applicable functional/system tests. All must identify the same complete-product
source/netlist/configuration. Earlier
R2 qualification does not cover added storage, routing, reset load or pads.
Missing macro/Pad views, vendor models, licensed tools and board/silicon access
remain explicit gaps, not waived requirements.

## Development Order

All phases target TINY; shared-IP regression on Mini is compatibility work.
IDs and titles below are stable. P0 freezes documents only; no later phase is
authorized or marked complete by approval of this document.

| ID / stable title | Dependencies; changes; completion |
| --- | --- |
| PIOLITE-P0 - Contract Freeze | Approved research; create this contract/verification ledger and synchronize Tiny/GPIO/DMA/index docs. Freeze APB/ISA, address/IRQ/RCU, DMA and lifecycle contracts. Check links, commands, consistency and `git diff --check`; no implementation evidence. |
| PIOLITE-P1 - ISA Reference Model and Assembler | P0; add model, assembler, source programs/metadata and deterministic tests. Validate every ISA boundary and actual 32-word application/pair footprints with Ruff/Pytest. No Tiny integration or software-visible contract changes beyond implementing this frozen format. |
| PIOLITE-P2 - Core and Register Implementation | P1; implement owned hierarchy/APB/ISA, FIFOs, guard/adapters at standalone interfaces, handwritten SVH/C parity and testbench/assertions. Model-differential, directed/random/formal, lint/style and block-synthesis evidence; no false integrated capability. |
| PIOLITE-P3 - Tiny GPIO and DMA Integration | P2 plus applicable TINY-R2-P6/P7 and inherited fabric prerequisites; change topology/address/IRQ/RCU/filelists, GPIO sidebands and HAL, DMA V2.1 capability/grants/cancellation. Validate clock/reset ownership, full drain/recovery and unaffected Mini using targeted tests, SDK checks and affected firmware/simulations. |
| PIOLITE-P4 - SDK and Application Qualification | P3; finish freestanding loader/session/example library and all three bringup groups, exact counts/tails, independent BFMs, contention/long-duration/error recovery and complete Tiny regressions. No rate claim without current-program evidence. |
| PIOLITE-P5 - IHP130 Timing and Physical Qualification | Historical title; default ICS55. P4 plus all product functional prerequisites; mandatory final campaign with R2-P11/SPI-P5/PPALITE-P5 on one complete netlist. Close or explicitly block synthesis/netlist/STA/CDC/RDC/physical/pad gates; report measured rates/area/power. |

### Next-phase preflight handoff

```text
Use $retrosoc-feature-implementation. Stage: preflight. Feature slug: piolite. Target SoCs: TINY.
Phase: PIOLITE-P1 - ISA Reference Model and Assembler.
Read docs/ip/piolite.md and docs/ip/piolite-verification.md. Default target: ICS55/HAVE_PLL=YES with SAFE24 boot and planned configs/ci/ics55-tiny.mk; require accepted TINY-ICS55-P1 before integrated default-platform work. Current executable reference: configs/ci/ihp130-tiny.mk, IHP130, 24 MHz/no PLL, no PIO. Apply the 2026-10-07 observational pre-final timing policy and mandatory complete-product final campaign; do not invent an executable profile or relabel historical results.
Plan only the frozen ISA reference model, deterministic assembler, program metadata/relocation and focused tests, including actual 32-word application and dual-SM footprints. Preserve the two-SM architecture, PCLK tick/packing semantics, GPIO/DMA lifecycle contracts and all R2 phase identifiers.
Do not implement RTL, HAL integration, DMA V2.1, GPIO/RCU wiring, new profiles or later phases. Do not alter the ISA/ABI, expand memory or package scope, download new dependencies, change quality policy, commit or push. Report SPEC_CONFLICT if a frozen requirement cannot be met; do not weaken it. Return the scoped preflight and validation plan for explicit approval before implementation.
```

## Commercial Delivery Gaps

At freeze, PIO RTL, model/assembler, register parity, HAL, DMA V2.1 changes,
integration metadata, pin BFMs and application programs are not delivered.
Coverage closure, reusable VIP, reset/CDC/RDC proof, DFT, extracted PVT timing,
power characterization, board routing examples, release artifacts and silicon
validation remain required. A documentation freeze does not update RTL
readiness, approve a new PDK, advance implementation phases or authorize a push.
