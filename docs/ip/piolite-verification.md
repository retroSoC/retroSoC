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

## PIOLITE-P1 Host Implementation Evidence

The 2026-10-28 working-tree implementation based on source revision
`557f8b452745ed2cc28a73f08a452804f0a3cc74` adds the host-only ISA, model,
assembler, handwritten programs, and focused tests. It has
`phase_accepted: false`: this evidence is not phase acceptance, Tiny
integration, protocol-waveform/rate qualification, or a firmware/RTL result.
The Tiny verification ledger is intentionally unchanged at this stage.

The focused commands and observed results are:

```sh
python3 -m pytest -q tests/test_piolite_isa.py tests/test_piolite_model.py tests/test_piolite_assembler.py
python3 -m pytest -q
ruff check .
git diff --check
for object in build/piolite-p1-2026-10-28/generated/piolite/*.c; do
  cc -std=c11 -fsyntax-only "$object"
done
```

The focused Pytest run passed 176 tests: 23 ISA, 99 model/application, and 54
assembler/allocation/footprint tests. The full repository run passed 2300 tests
with one skip in 4767.84 seconds; the skip is the existing optional `pypdf`
import in `test_publication_retrieval.py`, not a PIOLite case. Ruff and C11
syntax checks passed. The
ISA test independently enumerates all 65536 encodings: 22257 legal forms
round-trip and 43279 illegal forms are rejected. Model traces cover the frozen
PCLK/divider/delay, dual-SM, lifecycle, counter, wrap, fault, shift, packing,
and pre-edge FIFO behavior; they do not use the model as its own oracle.

### Independent application-source review closure

The independent review cleared the ISA/model/assembler/allocation and identified
three application-source defects. Their host behavioral closures are:

- **P1-1 UART RX schedule.** The old four-tick post-WAIT path sampled the start
  bit and then D0..D6. `uart_rx.piolite` now waits ten delay ticks after the NOP
  commit. With its declared eight ticks/bit, independent 8N1 stimulus verifies
  data samples at edges 12, 20, 28, 36, 44, 52, 60, and 68, followed by the STOP
  WAIT at 76. `test_uart_rx_application_samples_independent_8n1_stimulus`
  verifies exact received bytes for A5, 00, and FF, not only a metadata claim.
- **P1-2 programmable pulse phases.** The old program copied one OSR value to
  both counters and drove LOW inside the HIGH loop, producing one-tick pulses.
  `pulse_generate.piolite` now consumes separate 16-bit HIGH and LOW duration
  words, pre-decrements both counts, holds each output level throughout its
  countdown, returns HIGH, and HALTs.
  `test_pulse_generate_application_has_independent_exact_phase_durations`
  checks every output transition for HIGH/LOW settings 3/5 and 8/2 ticks.
- **P1-3 uniform logic capture.** The old paired-IN loop alternated one- and
  two-tick sample intervals. `logic_capture.piolite` now derives 32767 loop
  iterations through OSR, adds one initial sample, and executes a strict
  IN/branch two-tick loop. `test_logic_capture_application_uniform_cadence_and_exact_counts`
  drives an independent changing GPIO8..15 pattern and checks all 32768 sample
  edges, all 8192 packed words, HALT, and empty residual ISR at DIV 1 and 3.

These seven new cases are deterministic host-model application tests with
independent stimulus and expectations. They close the reviewed P1 source
defects; they are not RTL pin-BFM, electrical, baud/rate, or P4 protocol
qualification.

### FIX_P0_P1 review closure

A second independent review found two P1 defects and one P2 coverage group.
Their closures are:

- **P1-1 logic-capture item metadata.** `.packing 0, 8192, 32` described FIFO
  words rather than application items. The source now declares
  `.packing 0, 32768, 8` with `.clock_ticks 2, stretchable` per 8-bit sample.
  `test_logic_capture_metadata_describes_application_samples` checks the
  program and emitted C metadata. The behavioral capture test derives its
  expected word count as `32768*8/32 = 8192` and its four-lane layout from the
  item width rather than hardcoding either one.
- **P1-2 selected-but-unused test pin.** Selection previously enabled the pin
  even without a test-pin branch, while claim metadata followed actual use.
  Rule **(a)** is selected: `test_pin_is_used` infers enable only from an actual
  `TEST_PIN_HIGH` branch. This follows the register contract's "GPIO checked
  only when enabled/used" qualification and referenced-resource metadata rule;
  an unused selection does not invent a claim. The C emitter and default
  `SMConfig.from_allocation` share that query. Two
  `test_selected_test_pin_enable_follows_actual_branch_use` cases run the full
  assemble/C/default-config/START path: selected-unused starts with enable 0
  and claim 0; selected-used starts with enable 1 and GPIO5 claimed, then takes
  the false-condition path to HALT. START authorization checks are unchanged.
- **P2 confirmed-behavior probes.** Eight permanent model cases now cover a
  false-condition out-of-region branch; START TX preservation, nonempty-RX and
  partial-IMEM rejection, sticky history and initial XY/data/OE; automatic PUSH
  clearing last-FIFO-failed; PULL high-bit zeroing; PAUSE acceptance during a
  stalled WAIT at DIV 65535; and runtime IN/OUT window-authorization faults.
  These tests codify review-confirmed behavior without changing the model.

These eleven new tests join the prior behavioral coverage. The second review's
enable/used wording allowed either consistent rule; rule (a) is an explicit
judgment call, not an unresolved specification conflict or a weakened check.

### Fourth independent review closure

The fourth review found one allocator defect and one assembler-diagnostics
defect. Five regressions close them:

- **P1 foreign allocation handles.** `unload()` previously trusted the caller's
  base/length after checking only the numeric handle, so equal handles in two
  allocators could remove the wrong live record while retaining stale bitmap
  bits. It now resolves the handle to this allocator's canonical record and
  requires the exact canonical allocation object before changing references or
  bitmap state; all clearing uses the canonical base/length.
  `test_foreign_allocation_handle_collision_is_rejected_atomically` uses two
  allocators with colliding handle 1 and checks unchanged bitmap, live
  references and allocations, followed by successful legitimate unload/reload.
- **P2 pathological numeric diagnostics.** A 5000-digit decimal can raise the
  interpreter integer-conversion-limit `ValueError` before the normal range
  check. `_number()` now converts inside a checked exception boundary and
  raises `AssemblyError` with its original source line. Two library and two CLI
  cases cover 5000-digit decimal and equivalent-length hexadecimal tokens;
  every case returns a normal `line 13: SET immediate ...` diagnostic, CLI
  status 2, no traceback and no generated output file.

No application source or footprint changed in this closure, so the program
hashes and allocation evidence remain valid; only the validation logs and this
ledger require refresh.

### Fifth independent review closure

The fifth review, including 140k-edge randomized differential validation, found
three P1 defects. Six directed regressions close them:

- **P1-1 narrow OUT pin preservation.** OUT PINS/DIRECTIONS used the whole
  window mask when committing a narrow chunk. The model now forms the update
  mask from the emitted count and window base while retaining whole-window
  authorization. Two `test_narrow_out_preserves_unrelated_output_bits` cases
  use a four-bit window with nonzero initial upper bits; each destination
  produces D0 for the changed field and preserves C0 in the other field.
- **P1-2 IMEM publication lifecycle.** Publication now requires every SM to be
  DISABLED and rejects already-valid overlapping slots before changing IMEM.
  Scoped host-model `unpublish()` clears exactly an unloaded image's validity
  region; it is the model counterpart of program unload, not a new HAL ABI.
  Replacement requires invalidation before publication, so a two-word image
  replaced by one word leaves the vacated slot invalid. Tests prove live
  publish/unpublish rejection is atomic, overlap rejection is atomic, unrelated
  valid words survive, vacated APB reads return zero, and forced fetch of the
  vacated slot raises INVALID_FETCH.
- **P1-3 atomic CLI output.** Direct destination writes could expose truncated
  C files after an output error. The CLI now writes a same-directory temporary
  file, closes it successfully, then uses `os.replace`; every output-failure
  path attempts temporary-file cleanup. Injected mid-write failures after 32
  bytes prove no destination appears for a new output and a pre-existing
  known-good destination remains unchanged, with no temporary files left.

No application program or pair footprint changed, so existing program hashes
and allocation evidence remain valid; validation logs and this ledger are
refreshed for the closure.

### Sixth independent review closure

The sixth review found three P1 defects and three P2 items. Their 32 new or
expanded regression cases close them:

- **P1-1 guarded full invalidation.** `invalidate_imem()` now applies the same
  all-SMs-DISABLED check as scoped publication changes and clears publication
  identity only after that check succeeds. A running-SM test proves payload,
  validity and execution state remain unchanged after rejection.
- **P1-2 authenticated unpublish and sharing.** The model now tracks exact
  published allocation objects and publication reference counts independently
  of allocator-local numeric handles. Unknown, foreign, shortened and
  same-length/different-content images are rejected before validity changes.
  Shared publication keeps its region valid until the final reference is
  removed. Full invalidation clears this identity state.
- **P1-3 disabled SET windows.** SET_PIN and SET_DIR now raise
  PIN_AUTHORIZATION before effects when SET width is zero, matching assembler
  rejection. Directed tests cover both destinations and zero retirement.
- **P2-1 bounded temporary names.** The CLI uses the fixed `.piolite-`
  temporary prefix rather than the full destination basename. Outputs with 242-
  and 255-character basenames assemble successfully without temporary residue.
- **P2-2 destination modes.** Before replacement, the temporary file receives
  the existing destination's mode or `0666 & ~umask` for a new destination.
  Tests verify a new 0644 file under umask 022 and preservation of existing
  0644 and 0444 modes while replacing content atomically.
- **P2-3 confirmed behavior matrix.** Delay tests now cover every value 0..15;
  further cases cover START of one DISABLED SM while the other RUNNING,
  unclaimed/non-output initial outputs, WAIT FLAG pre-edge/non-clearing at all
  four indices, and a delay-15 taken branch winning over wrap. These probes
  assert confirmed behavior without changing it.

No application source or pair footprint changed. Existing program hashes and
allocation evidence remain valid; validation logs and this ledger are refreshed.

Every application was assembled twice and each pair of C outputs compared
byte-for-byte:

```sh
out=build/piolite-p1-2026-10-28
for source in app/asm/piolite/*.piolite; do
  name=${source##*/}
  stem=${name%.piolite}
  python3 scripts/piolite_asm.py "$source" "$out/generated/piolite/$stem.c"
  python3 scripts/piolite_asm.py "$source" "$out/rebuild/piolite/$stem.c"
  cmp "$out/generated/piolite/$stem.c" "$out/rebuild/piolite/$stem.c"
done
```

All ten comparisons passed. `build/piolite-p1-2026-10-28/assembly.log` records
the assembler output; `footprints.json` binds source/C hashes, metadata,
relocation sites, pair allocations, and `phase_accepted: false`.

| Program | Words | Required pair | Relocated total |
| --- | ---: | --- | ---: |
| `logic_capture` | 9 | — | — |
| `pulse_generate` | 12 | `pulse_generate+pulse_capture` | 20 |
| `pulse_capture` | 8 | `pulse_generate+pulse_capture` | 20 |
| `uart_tx` | 12 | `uart_tx+uart_rx` | 24 |
| `uart_rx` | 12 | `uart_tx+uart_rx` | 24 |
| `spi_master` | 15 | — | — |
| `ir_tx` | 10 | `ir_tx+ir_rx` | 23 |
| `ir_rx` | 13 | `ir_tx+ir_rx` | 23 |
| `led_scan` | 14 | — | — |
| `gamepad` | 11 | — | — |

The pulse pair occupies slots 0..19, UART duplex slots 0..23, and the IR pair
slots 0..22 in their respective independent allocations. No IMEM enlargement,
padding demonstration, protocol claim, or simultaneous all-application claim
is made. P2-P5 requirements remain open as listed below.

## Freeze Record and Remaining Gaps

| Phase | Status |
| --- | --- |
| PIOLITE-P0 | Documentation freeze complete; local links/anchor, command dry-runs, unchanged legacy/R2 IDs and QFN64/ALT tables, documentation-only scope and whitespace checks passed on 2026-10-04 |
| PIOLITE-P1 | Host model, assembler, focused tests and actual 32-word footprints added on 2026-10-28; `phase_accepted: false`; Tiny integration and protocol qualification remain absent |
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
