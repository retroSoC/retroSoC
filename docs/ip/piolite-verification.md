# PIO-lite Verification and Evidence Ledger

The normative architecture is [piolite.md](piolite.md). This ledger targets
TINY/IHP130 and the separately approved `PIOLITE-P0..P5` roadmap. Freeze date:
2026-10-04. Only the documentation contract is delivered here; no test case,
model, assembler, RTL, firmware, performance or physical result below is
marked passed by this freeze. Existing Tiny/R2/DMA/GPIO evidence does not
automatically cover the new feature.

## Configuration and Evidence Identity

- Current normative default: TINY/ICS55, `HAVE_PLL=YES`, SAFE24 boot under the
  [2026-10-07 Tiny policy](tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07).
  `configs/ci/ics55-tiny.mk` now exists with a parked PLL; platform acceptance
  belongs to the Tiny ledger. The profile below remains IHP130 compatibility,
  not an ICS55 or PIO-lite test result.
- All pre-final post-synthesis timing is observational. Retain failed/unrun
  measurements and functional/protocol, synthesis/mapping and netlist-function
  gates. PIOLITE-P5 joins R2-P11/SPI-P5/PPALITE-P5 only after all functional
  stages, with mandatory final timing closure on one complete-product netlist.
  Existing phase names and historical evidence retain their original identity.

- Starting profile: `configs/ci/ihp130-tiny.mk`, TINY, IHP130, 24 MHz/no PLL,
  current four-channel DMA and no PIO-lite.
- Planned integration: two SMs, shared 32x16 IMEM, per-SM TX/RX 8x32, PCLK
  execution, APB `0x1001C000`, IRQ24, RCU15, DMA V2.1 requests 14/15.
- PCLK 48/60 testing requires the corresponding committed R2 platform inputs;
  do not invent an executable profile or substitute Mini for Tiny.
- Every evidence record MUST identify source SHA, dependency/configuration
  digests, profile/PDK, variant, tool versions, source programs and assembled
  code, clock rates, pin assignment/electrical model, DMA bindings, commands,
  logs, structured verdict and observed gaps. Artifacts belong below the
  repository's `build/<profile>-<date-time>-<config-hash>/` layout.
- Shared Mini regressions validate compatibility only: PIO ports and support
  bits remain disabled there. P5, R2-P11, SPI-P5 and PPALITE-P5 close together
  only on the same complete-product source/netlist/configuration.

## Requirement Matrix

All rows currently have status **required, not run**. Implementation updates
must add evidence references and exact scope without deleting unmet cases.

| ID | Requirements | Required evidence / owner phase |
| --- | --- | --- |
| PL-V01 | PL-01/03/06 | All legal opcode/operand/delay combinations and illegal encodings against the reference model; independent ISA/APB version rejection; P1/P2 |
| PL-V02 | PL-01/06 | Deterministic assembly, duplicate/unknown labels, relocation at 0/31, exhaustion/fragmentation/sharing, invalid entry/wrap and failed-load publication; P1 |
| PL-V03 | PL-01/03 | Two SMs commit on the same tick without fetch arbitration; DIV 1/65535, delay 0/15, synchronized START, tick phase and PAUSE/resume; P1/P2 |
| PL-V04 | PL-01/02 | X/Y0/1/65535, saturating decrement, count 0=32 only for IN/OUT, MOVE narrowing/validity, wrap false/taken branches and out-of-region fault; P1/P2 |
| PL-V05 | PL-02 | Left/right packing, 1/8/16/31/32 bits, zero-valued valid words, partial PUSH, exact thresholds, partial OSR underrun and no partial effects; P1/P2 |
| PL-V06 | PL-02/07 | FIFO0/1/7/8 occupancy, simultaneous push/pop, blocked/nonblocking transfer, pre-sample autopush backpressure, stable beats and stall accounting; P2 |
| PL-V07 | PL-06/07 | Every CSR reset/access/field, reserved/unaligned/partial-strobe/unimplemented-SM errors, bounded APB response, repeated-access suppression, SVH/C parity; P2 |
| PL-V08 | PL-03/07 | Same-edge command/commit, flag set/clear/W1C, first-fault precedence, saturating counters and paused execution snapshot while DMA moves; P2 |
| PL-V09 | PL-04/09 | All 32 GPIO paths; unchanged ALT rows/pads; input pipeline; output-overlap rejection, shared input, windows atGPIO31, WAIT/test pin authorization; P3 |
| PL-V10 | PL-04/07 | Native-owner drain, two-way high-Z handoff, locks, open-drain/capability rejection, partial claim rollback, lost ownership/filter/readiness, unexpected GPIO reset, explicit rearm; P3 |
| PL-V11 | PL-05/06 | DMA V2.0 rejection before unsupported offset access; V2.1 identity/parity/static masks/accurate stream count; staged wiring and Mini disabled ports; P3 |
| PL-V12 | PL-05/07 | Direct/TCD TX/RX, direction/channel checks, distinct full-duplex channels, non-PIO-to-PIO chain, suspension, accepted START/rebind/reset race; P3 |
| PL-V13 | PL-05/07 | Descriptor-fetch backpressure, abort at fetch/parse/activation, payload/B-response drain, no stale activation, invalid TX beat discard, full-TX and empty-RX abort; P3 |
| PL-V14 | PL-05/07 | Residual RX VALID after byte-count completion, isolated endpoint reset, failed drain timeout retains ownership, unaffected SM/channel progress and no global reset; P3 |
| PL-V15 | PL-03/07/09 | RCU clock/gate/reset from WAIT/PAUSED/HALTED, GPIO ownership veto including multi-target commands, source-rate rediscovery, no stale epoch after reset; P3 |
| PL-V16 | PL-06/08 | HAL argument/range/overflow/capacity checks, static allocation, readback failures, finite timeouts, locks/interrupt serialization, actual demo object footprints; P1/P3/P4 |
| PL-V17 | PL-02/05/08 | Independent digital/serial/lighting BFMs, nominal and adverse schedules, exact FIFO/DMA counts and final responses, all acceptance targets below; P4 |
| PL-V18 | PL-08/10 | Sustained load, longest DMA service gap, CPU progress, errors/recovery, full Tiny regression and affected Mini regression with source-bound logs; P4 |
| PL-V19 | PL-03/09/10 | Storage mapping, block/full synthesis, netlist simulation, CDC/RDC/reset, PVT timing, pad/board/package and physical evidence; P5 |

Directed boundary cases also cover OUT with empty OSR and autopull disabled,
an autopull width exceeding TX_BITS without TX dequeue, HALT at the last
instruction outside wrap, rejection of CLOSING-to-DISABLE/START, CPU FIFO
rejection during closing, and pre-edge full/empty simultaneous FIFO activity.
Also verify that clearing/replacing SM claims cannot hide USER_SELECT from
OWNED_MASK/RCU, acquisition handoff keeps the veto asserted, block reset needs
released GPIO ownership, disabled-but-armed/prefilled sessions fault on GPIO
reset, and a drained failed buffer can be reclaimed without publishing its
partial contents as a valid result.

Model differential testing must not be the only oracle. Independent assertions
check handshake stability, FIFO bounds, one-owner outputs, no stalled partial
commit, isolation epochs and canceled descriptor non-activation. Protocol BFMs
check waveforms rather than sharing the assembler/model's expected trace code.
Formal bounds and assumptions must be recorded, especially eventual bus
response assumptions; bounded proofs do not establish arbitrary external
liveness or analog CDC safety.

## Application Acceptance

All programs and every required dual-SM combination MUST fit 32 instructions
after assembly/relocation. Do not increase IMEM to pass a demo. Each scenario
lists native peripheral conflicts and obtains GPIO/DMA ownership explicitly.
No simultaneous execution of all three groups is required or implied.

| Scenario | Required observations |
| --- | --- |
| Eight-channel logic capture | Exactly 32768 samples in a 32 KiB user buffer at 1 MSPS; four samples/FIFO word, 8192 DMA words; compare deterministic/ramp/pseudorandom independent pin input, endpoints and guard canaries; any capture stall invalidates lossless success |
| Pulse generation plus capture | Both SMs active; varied duty/length, WAIT entry phases, 0/1/65535 counter boundaries, programmed stop and abort-mid-pulse; measured widths agree with documented pipeline/tick quantization |
| UART8N1 | TX/RX at 115200 baud with <=2% actual error; independent asynchronous phase sweeps, back-to-back bytes, framing errors, break/noise recovery and deliberate FIFO starvation; both programs fit 32 words |
| SPI master | Modes 0..3, 8/16/32-bit frames at 1 MHz; known/random duplex data, first/last edges, CS setup/hold and short frames; documented safe pause phase or rejected waveform on starvation; exact full-word DMA counts |
| IR |38 kHz carrier with <=2% frequency error, known mark/space patterns and demodulated pulse input; bound timing quantization, timeout/buffer overflow and rearm; variable RX uses CPU/IRQ, not early DMA success |
| LED scan | External row/column driver model for 8x8 monochrome matrix; >=200 frames/s, correct row order/data, blanking before FIFO wait and no unintended row during reset/abort; do not assume direct LED current from Pads |
| Gamepad | Eight-bit latch/clock/data shift-register model; fixed and changing button patterns, sampling delay, disconnect/timeout and repeated scans with bounded CPU service |

For each applicable scenario run PCLK 24 first, then 48/60 only when enabled.
Record actual integer divisors, instruction path lengths, valid bits per word,
memory word counts, throughput and longest stall. Initial arithmetic budgets
are in the main contract; they are not proof that complete programs already
fit or meet protocol timing. FIFO IRQ watermark choices and service deadlines
must be justified for each program, including CPU/IRQ IR reception.

## Validation Commands and Status

For P0 documentation only:

```sh
git diff --check
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --dry-run
```

Also verify relative links/anchors and command options against their sources.
Dry-runs validate command definitions, not execution or PIO integration.

P1 uses Ruff and Pytest for the new model/assembler. P2 adds discovered tests
and the existing lint/style/formal/synthesis mechanisms; test names and build
entries are created in that implementation phase, not invented as working
commands here. P3/P4 use the main contract's SDK/firmware/regression commands
and focused DMA/GPIO/PIO tests. P5 joins the selected-PDK complete-product
physical campaign with frozen full-source inputs and required collateral;
the ICS55 Tiny full-chip adapter remains pending, and existing IHP130 flows
are compatibility-only evidence.

For Tiny firmware, success requires command exit 0, the configured
`SIM_TEST_PASS`, and no `FAILED`, `FATAL`, `assertion failed`, `%Error`,
`SIM_TEST_FAIL` or `SIM_TEST_TIMEOUT`. SYSCTRL TEST_STATUS is the terminal
verdict; UART output is diagnostic. Run both Verilator and Icarus pin-level
checks; preserve simulator-specific unsupported coverage rather than replacing
one with the other. Neither a dry-run nor a skipped fixture is a passing test.

## Freeze Record and Remaining Gaps

| Phase | Status at this freeze |
| --- | --- |
| PIOLITE-P0 | Documentation freeze complete; local links/anchor, command dry-runs, unchanged legacy/R2 IDs and QFN64/ALT tables, documentation-only scope and whitespace checks passed on 2026-10-04 |
| PIOLITE-P1 | Not started: model, assembler and actual 32-word program evidence absent |
| PIOLITE-P2 | Not started: core, CSR/ISA parity and standalone RTL/formal/synthesis evidence absent |
| PIOLITE-P3 | Not started: R2-dependent Tiny wiring, DMA V2.1 and GPIO/RCU/HAL lifecycle absent |
| PIOLITE-P4 | Not started: complete SDK/application and dual-simulator/contention qualification absent |
| PIOLITE-P5 | Not started: PIO-inclusive IHP130 timing, physical, Pad/package and silicon evidence absent |

Executed P0 validation used `git diff --check`, local Markdown link/anchor and
new-file whitespace checks, and structural comparison with HEAD of all 25
legacy/R2 phase headings, the QFN64 package section and 32 ALT rows. The Tiny
PR and nightly dry-runs above passed using the local `python` executable;
`python scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI --dry-run`
also passed for the shared-IP compatibility command path. These are definition
checks only. No P1 model, firmware build, simulator, formal, synthesis, STA or
physical flow was run because this change is documentation-only.

No MISRA deviation, warning-baseline change, metrics promotion, new PDK support,
maximum Pad rate or security/safety claim is approved here. Record missing
tools, vendor models, PDK/macro/Pad timing views and hardware access in later
phase evidence. Freeze completion does not close any of those gaps.
