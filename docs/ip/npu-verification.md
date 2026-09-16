# NPU Verification and Qualification

This is the normative verification companion to [NPU](npu.md). The main
specification owns the architecture and ABI; this document owns evidence,
workload provenance, coverage, and qualification verdicts. All evidence below
is required future work unless a dated report explicitly records its execution.
The architecture freeze itself supplies no simulator, performance, FPGA,
synthesis, timing, or silicon result.

The selected implementation has 64 dense MACs, an eight-MAC depthwise mode,
64 KiB of banked local SRAM, two 256-byte accumulator contexts, a scalar exact
requantizer, private AXI64 DMA, APB4 control, and an ungated HP-domain 72 MHz
initial target. Tensor elements remain INT8; centering widens activations to
signed nine bits before signed 9-by-8 multiplication. Verification MUST test
this implementation, including packing and transport costs, rather than an
idealized dense-compute model.

## Workload Identity and P0 Entry Gate

`NPU-P0 - Workload and Numerical Contract` MUST produce a deterministic
qualification manifest before compute implementation can claim workload
coverage. The manifest MUST record source revisions, exact model paths and
SHA-256 hashes, input IDs and per-input hashes, labels, preprocessing and
quantization definitions, compiler/reference revisions, and aggregate corpus
hashes. Acquiring an external input MUST use the shared dependency helpers and
[dependency lock](../../dependencies/dependencies.lock.json). A model change,
retraining, calibration change, or corpus substitution requires explicit
contract review.

- **KWS:** reuse the existing MLPerf Tiny source at revision
  `4addd0fa08d216e20637637874e084895f289da4`. The model is
  `benchmark/training/keyword_spotting/trained_models/kws_ref_model.tflite`,
  53,936 bytes, SHA-256
  `aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae`.
  Use the complete existing 1,000-case [KWS corpus manifest](apu-kws-corpus.tsv)
  and its input identity rules in [APU](apu.md). The 49-by-10 INT8 feature
  input, first 10-by-4 convolution with stride two, depthwise/pointwise stages,
  global average pool, and FC output MUST retain the source numerical
  semantics. NPU deployment uses its own compiler and ABI; APUM binary
  compatibility and replacing the APU KWS engine are outside this contract.
- **VWW:** resolve the official INT8 MobileNetV1 alpha-0.25 model with
  96-by-96-by-3 input and two classes from the selected locked MLPerf Tiny
  source. The [upstream VWW source directory](https://github.com/mlcommons/tiny/tree/master/benchmark/training/visual_wake_words)
  identifies provenance, not an acceptable floating revision for execution.
  P0 MUST verify the exact model binary and record its path, byte count and
  SHA-256; no VWW binary hash is asserted by this freeze. Select the complete
  official evaluation/test corpus belonging to that locked source and dataset,
  excluding training and calibration data. Its count, ordering and hashes
  MUST become explicit manifest facts. If the source does not provide a
  bounded official evaluation/test bundle that can be acquired and verified,
  P0 is `BLOCKED`; it MUST NOT silently invent a subset or substitute a model.

The scalar reference MUST independently implement the frozen integer
arithmetic and expose every layer output. Existing
[`scripts/apu_kws.py`](../../scripts/apu_kws.py) and
[`tests/test_apu_kws.py`](../../tests/test_apu_kws.py) provide useful numerical
and layer-hash evidence patterns, but their fixed APUM graph is not a general
NPU compiler or an independent proof of the new datapath. P0 MUST compare the
reference against the pinned framework reference on the complete selected
corpora. Missing models, tools or inputs MUST produce an incomplete/blocked
qualification result, never a passing result through skipped tests.

Qualification corpus scope is fixed:

| Execution level | Required scope |
| --- | --- |
| Host reference and compiled-command model | Complete KWS and VWW corpora; exact intermediate and final tensors. |
| Icarus and Verilator RTL | The first ten distinct input IDs per model in bytewise lexicographic order from the frozen manifest, plus all directed arithmetic, tiling, protocol and lifecycle cases below. Both simulators consume identical command/input artifacts. |
| FPGA | Complete KWS and VWW corpora using the production NPU datapath, DMA and runtime; report every mismatch and accuracy result. |
| Synthesized-block simulation | Directed compute, memory, transport and recovery transactions with exact output checks; full-corpus netlist execution is not required. |

Top-1 agreement alone is insufficient. Accelerated layer outputs MUST match
the independent integer reference byte-for-byte; CPU softmax MUST also match
the pinned software reference. Report corpus quality and unchanged-model
accuracy independently. This workload use is not an MLPerf submission claim.

## Verification Matrix

The categories below trace the main specification's requirements without
creating a second source of register, descriptor or operator definitions.
Every report MUST identify the applicable `NPU-Vxxx` IDs and exact phase.

| ID | Requirement category and mandatory evidence | First phase |
| --- | --- | --- |
| `NPU-V001` | **Workload and arithmetic identity:** verified source/model/corpus manifests, independent scalar/reference comparison, reproducible compiler inputs and every-layer golden outputs. | P0 |
| `NPU-V002` | **Dense arithmetic:** raw INT8 to signed-nine-bit centering, signed products, bias once per output, deterministic reduction/chunk order, checked INT32 overflow, exact multiplier/shift rounding, output zero point and clamp. Cover signed extrema, zero points -128/0/127 and KWS 83, negative ties, the defined zero-multiplier flush, shift boundaries, and intentional overflow faults. | P1 |
| `NPU-V003` | **Local memory and packing:** all sixteen 4 KiB technology SRAM instances, synchronous reads, byte strobes, raw/A/W partitions and the separate 8 KiB output/8 KiB parameter regions, inactive-half writes, K-chunk limit 1024 and no uninitialized/stale tile use. Compare behavioral and macro-backed paths; demonstrate active A/W read bandwidth and serial-gather stalls. | P1 |
| `NPU-V004` | **Compute ownership:** both accumulator contexts, bias and carry across K chunks, compute/requantizer overlap, result backpressure, no context overwrite before all its requantized items enter owned output staging, and exactly-once publication. Reset/abort invalidates ownership metadata without requiring physical SRAM clearing. | P1 |
| `NPU-V005` | **APB4 and handwritten ABI:** every register reset value, legal/illegal accesses, alignment, PSTRB behavior, reserved fields, idle-only writes, capability discovery, command admission and independent RTL/C parity. Register generation is not introduced. | P2 |
| `NPU-V006` | **Platform allocation and IRQ:** permanent master and APB/resource allocations, existing master/IRQ ABI preservation, LP and HP routing, masked/unmasked events, sticky first error and simultaneous event/W1C precedence. Prove real ISR entry, acknowledgment and return in enabled interrupt profiles. | P2 |
| `NPU-V007` | **CDC/RDC and lifecycle:** PCLK/HP command handshakes and snapshots under asynchronous phase/ratio sweeps; clock pause with BUSY retained, either-side reset, owner handoff, quiesce, admitted-command preservation and absence of stale completion. The NPU uses SoC lifecycle ownership without adding a power, Q-channel or security feature. | P2 |
| `NPU-V008` | **AXI64 DMA:** independent AW/W/B/AR/R stalls, IDs, burst limits, 4 KiB splitting, permitted memory targets, alignment/tail strobes and no address overflow. Inject every supported bus-error response and malformed response case; check accepted-transfer accounting. | P3 |
| `NPU-V009` | **Job execution:** immutable 128-byte layer records, version/length/operator/range checks, bounded linear traversal, compiler-selected legal tile geometry and K chunks, malformed/truncated input rejection, and no command reuse after terminal completion. Next-layer issue and successful job completion wait for all preceding output B responses. | P3 |
| `NPU-V010` | **Abort, timeout and fault recovery:** stop new admission while honoring accepted AXI transfers, drain before reusable-idle/reset acknowledgment, no discarded outstanding response, sticky diagnostic retention and defined partially written output validity. Cover stalls and faults during fetch, pack, compute, requantize and store. | P3 |
| `NPU-V011` | **Complete operator subset:** Conv kernel dimensions 1..16/stride 1 or 2/dilation 1, KWS 10-by-4, DW3-by-3 multiplier one/eight-MAC mode, FC, Add, pooling/global average and activation clamp, using exactly the main specification's numerical rules. Unsupported modes fail before execution; no hidden CPU fallback for these operators. | P4 |
| `NPU-V012` | **Tiling boundaries:** M/N tails 1/7/8/9, channel and image edges, K 1023/1024/1025, asymmetric zero-point padding, maximum legal geometry, multiple K chunks, bank conflicts and scratch occupancy. Compare equivalent legal tilings against identical golden tensors. | P4 |
| `NPU-V013` | **Compiler and SDK:** deterministic import/lowering/packing, checked address and size arithmetic, malformed-model diagnostics, no external full-image im2col, independently handwritten ABI parity, bounded freestanding API behavior, timeouts, cache maintenance/fences and explicit CPU preprocessing/softmax. | P5 |
| `NPU-V014` | **Integrated model execution:** prescribed dual-simulator input sets, exact per-layer outputs, bare-metal command submission and final SYSCTRL verdicts. Exercise contention with other masters and software polling as well as interrupt completion. | P5 |
| `NPU-V015` | **Formal and coverage closure:** control/DMA/context invariants, reachable success and failure covers, explicit fairness assumptions for any liveness property, reviewed unreachable cases and reported proof/bounded depth. A tool-doctor result or bounded check is not an unbounded proof. | P3; closure P6 |
| `NPU-V016` | **Performance:** complete-corpus FPGA/model comparison under the fixed baseline below; dense, depthwise, packing, scalar-requantization, DMA and contention costs, with achieved utilization and per-model speedup. | P6 |
| `NPU-V017` | **Physical integration:** isolated NPU and full PRODUCT macro-aware synthesis/STA, exact memory mapping, no unexpected latches or unresolved non-PDK black boxes, 72 MHz HP target and unchanged other-domain constraints, complete warnings and metrics. | P1; full qualification P6 |
| `NPU-V018` | **Delivery:** reproducible artifact manifests, full FPGA corpus correctness, synthesized-block transactions, full-SoC regression verdicts, reviewed coverage gaps and separate functional/performance/physical qualification status. | P6 |

Directed tests MUST cover each legal operator and each defined error. Random
tests MUST vary legal memory latency, ready/valid timing, geometry, addresses,
and interrupt timing with recorded seeds. Formal assertions MUST cover
stable stalled payloads, bounded storage access, exclusive context/bank
ownership, exactly-once completion, absence of newly issued work after
admission closes, and accepted-transfer conservation. Progress assumptions
MUST be explicit: arbitrary permanent downstream starvation does not permit
an unconditional liveness claim or early buffer reuse.

The following `NPU-V007`/`NPU-V010` collision cases are mandatory in directed
simulation and the applicable bounded formal harness:

- Assert global `block_new_i` before and after AR/AW acceptance. Retain every
  presented but unaccepted VALID and its payload while paused; drain accepted
  reads and AW-accepted writes, including their W/B obligations. Pause at a
  register-safe boundary without requiring a new blocked address to finish
  the current tile. `clock_pause_ack` can assert with a retained unaccepted
  VALID and BUSY=1 when accepted obligations are zero; it MUST NOT require
  master-idle or BUSY=0. Unblock resumes the same job with identical results.
- Request abort/resource quiesce/reset during global block with an unaccepted
  address. Resource ACK MUST wait for unblock and complete source drain, or
  an explicit coordinated fabric flush. A timeout MUST NOT withdraw VALID,
  fabricate a response, or acknowledge reusable-idle early. Verify that
  administrative pause does not advance the job no-progress watchdog.
- Accept START in the APB shell, then request resource quiesce before the HP
  endpoint accepts the launch mailbox. The pending shell launch MUST prevent
  a false source-quiesced ACK. Exercise subsequent launch/cancellation and
  terminal delivery according to the main lifecycle contract; an HP idle
  sample cannot hide a shell-accepted command or make its buffers reusable.
- Reset PCLK with active HP traffic. The HP AXI state remains live long enough
  to stop/drain; the reset cannot directly discard its accepted operations.
  Mailbox/link reconciliation establishes a new epoch, not successful
  execution. Old result/token traffic, including reused JOB_ID values and
  generation wrap, MUST NOT complete a new launch.
- Apply a coordinated fabric flush to active and idle NPU states. Active work
  is cancelled, never resumed or reported DONE; idle flush creates no job
  event. Rearm only after the specified fabric/resource release and fresh
  epoch reconciliation. Test snapshot/terminal-message collisions with each
  reset path; no partial counter bank may become valid.
- Read a PERF low word, deliver a terminal result, then read its high word
  without an intervening explicit SNAPSHOT or reset. Both words and their
  public job/generation metadata MUST still belong to the same published
  snapshot. Terminal final counters remain separately retained and MUST NOT
  replace the public PERF bank implicitly. Also test explicit capture racing
  with terminal delivery and verify atomic publication and request ordering.

## Performance and Physical Qualification

The reference is the pinned portable-C INT8 implementation on the same
72 MHz HP VexiiRiscv configuration, with the same model, corpus, memory
placement and declared cache policy. Both paths include the inference result
through CPU softmax; the NPU path additionally includes command submission,
DMA transfers, synchronization and wait. Preprocessing is timed separately
and excluded from both inference totals. No dynamic allocation, model
substitution or faster reference/NPU memory placement is allowed to obscure
the comparison. Record first-run and steady-state behavior using the same
declared cache initialization policy for both paths.

For each complete qualified corpus, compute speedup as the sum of reference
inference times divided by the sum of NPU-path inference times. Both KWS and
VWW MUST reach **at least 2.0 times** speedup for performance qualification;
also report median and 99th-percentile latency and individual outliers.
Passing numerical tests without meeting this target establishes functional
evidence only and MUST NOT be described as performance-qualified. Report
baseline and NPU measurements, not a peak-MAC-derived estimate.

The 64-MAC dense peak at 72 MHz is 4.608 GMAC/s, or 9.216 GOP/s when a
multiply and an add count separately. Depthwise has eight active MACs, and
serial patch gathering/scalar requantization can limit throughput. Required
measurements include useful dense/depthwise operations, pack/compute/
requantization cycles, read/write bytes, bank conflicts, DMA stalls, and total
job cycles. Use the frozen counters and verification traces; this requirement
does not add software-visible counter registers. Compare compiler traffic/cycle estimates with measurements and
explain material discrepancies. Contention runs MUST identify competing
masters and cannot be presented as an uncontended bandwidth guarantee.

Use [the committed IHP130 PRODUCT profile](../../configs/ci/ihp130.mk) and
locked tools/PDK. Report NPU-only and complete-SoC cell count/area, sixteen
SRAM macro instances and their area separately, critical paths, WNS/TNS,
unconstrained paths, clock/reset fanout and tool resource use. Timing
qualification requires nonnegative setup WNS, zero setup TNS and reviewed
hold/constraint coverage at the specified corners; reducing the target or
relaxing existing domain constraints is not a passing remedy. Behavioral
storage or FPGA BRAM results do not establish IHP130 macro timing/area.

Post-layout extracted timing, full PVT/MMMC, qualified CDC/RDC signoff,
DFT/scan/MBIST, board characterization and silicon measurements remain
commercial delivery gaps unless separately executed and documented. This
does not authorize NPU security, power-management or Q-channel additions.

## Ordered Phase Evidence

The following IDs and titles match the main specification. Each phase MUST
carry forward earlier evidence affected by its changes; later qualification
does not imply that unexecuted earlier checks passed.

| Phase | Required exit evidence |
| --- | --- |
| `NPU-P0 - Workload and Numerical Contract` | `NPU-V001`; resolved model/corpus provenance and hashes, checked arithmetic, exact workload/operator manifest and independent full-corpus host goldens. Missing VWW source/test bundle blocks this exit. |
| `NPU-P1 - Banked Memory and Compute Feasibility` | `NPU-V002..004` and isolated `NPU-V017`; exact arithmetic and tile traces, packing/requantization bottleneck accounting, directed Icarus/Verilator tests, and successful sixteen-macro IHP130 synthesis/72 MHz STA before platform expansion. No whole-model speed claim. |
| `NPU-P2 - SoC Control and Resource Integration` | `NPU-V005..007`; topology, IRQ, ownership/reset/CDC inventory and assertions, APB shell parity and software interrupt evidence. |
| `NPU-P3 - Private DMA and Job Execution` | `NPU-V008..010` plus applicable bounded `NPU-V015`; independent-channel stalls/errors, descriptor validation, accepted-transfer drain, pause/reset collision cases, final-B completion ordering and updated synthesis/STA. |
| `NPU-P4 - Complete MVP Operator Pipeline` | `NPU-V011..012`; all supported operators, legal tilings and boundary cases match the independent reference; actual DMA/packing/compute/store path participates, with updated synthesis/STA and formal checks. |
| `NPU-P5 - Offline Compiler and Bare-Metal Deployment` | `NPU-V013..014`; deterministic model compilation, SDK/MISRA/host checks, prescribed RTL model inputs and bare-metal result/interrupt paths. |
| `NPU-P6 - MVP Qualification and Delivery` | `NPU-V015..018`; coverage review, full FPGA corpora, both 2.0-times targets, isolated/full-product synthesis and STA, synthesized-block tests, regressions and explicit qualification report. |

## Commands and Evidence Records

Commands run from the repository root in a supported locked tool environment.
These are existing command foundations, verified against current build and
workflow definitions; their presence here does not claim they have run for
NPU. Run the smallest set relevant to each phase, plus its required feature
tests and the [repository validation contract](../../AGENTS.md).

```sh
git diff --check
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
make check-soc-topology check-user-extensions check-clock-reset-domains
make rtl-style-check-all rtl-readiness-check-all
make sw-format-check sw-policy-check sw-host-test
ruff check .
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk firmware
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR HAVE_SVA=YES rtl-lint
make CONFIG=configs/ci/ihp130.mk formal-doctor
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite nightly --pdk IHP130 --dry-run
```

The committed profile defaults to CSR-disabled LP firmware. Once the future
NPU interrupt-acceptance scenario is integrated into a supported application,
its actual ISR-entry/return run MUST explicitly enable the existing CSR flag:

```sh
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES SIMU=VERILATOR firmware sim
```

This is an existing flag/command combination for that future acceptance
scenario, not a claim that the current firmware exercises NPU interrupts.
CSR-disabled builds remain compatibility checks and cannot establish ISR
qualification.

P6 additionally runs the full IHP130 flow and the affected committed PDK
matrix. A boot-only netlist run can provide boot evidence while dedicated
synthesized NPU transactions provide functional evidence:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
make regress-pr
make regress-nightly
```

The above full-flow command omits `--behavioral-only` deliberately. Current
[hosted regression](../../.github/workflows/_regression.yml) uses
`--behavioral-only`; its optional formal stage runs `formal-doctor`, not NPU
properties. Hosted green status therefore cannot supply missing physical or
formal evidence. `Hello retroSoC!` from boot-only netlist simulation is not an
NPU transaction verdict. New `tests/test_npu*.py`, NPU formal targets, corpus
qualification commands and FPGA runners are **future implementation
deliverables**; each phase MUST document its actual invocation when adding
them. Do not cite a future command as an already available passing gate.

Simulation acceptance requires successful process exit, the specified success
marker, and no `FAILED`, `FATAL`, `assertion failed`, `%Error`, `SIM_TEST_FAIL`
or `SIM_TEST_TIMEOUT`. Integrated automated firmware MUST use SYSCTRL
`TEST_STATUS` and the repository `SIM_TEST_PASS` verdict. UART timing alone
does not establish success or failure.

Store generated evidence under the selected
`build/<profile>-<YYYY-MM-DD-HH-MM>-<config-hash>/` output tree, with caches
under `.cache/`. Each report MUST record revision/config/lock digest, phase,
verification IDs, exact commands, tools/PDK, input/output hashes, seeds,
coverage/assumptions, pass/fail/blocked/skipped counts and retained logs.
Required qualification tests have zero permitted missing-input/tool skips.
Report unrun gates and hardware/vendor/simulator gaps explicitly. Warning
baseline regeneration remains separate reviewed work; metrics remain in
observe mode. No NPU report changes global quality policy or claims silicon
readiness from functional simulation.
