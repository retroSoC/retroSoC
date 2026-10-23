# TINY-R2-P4 local CPU/SRAM implementation

## Approved throughput repair (2026-10-10; validated, review pending)

The maintainer approved the eight-file P4 throughput-repair preflight after
the read-only review identified the external frontend's per-beat bubbles.
This follow-up remains P4; it does not enable P5 target concurrency.
The initial implementation and its measurements below are retained historical
evidence for the pre-repair snapshot, not qualification of the changed RTL.
Fresh evidence is under
`build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/`.

The group now reserves two response slots for its external client, counting
both queued completions and a macro read still in flight. A response pop may
free capacity on the same edge as the next issue. The macro's saved owner/bank
still selects the captured read value; FIFO data cannot be overwritten by
later local accesses. A same-client pending read prevents a simultaneous write
commit into the single-push response FIFO. Local I/D keep one operation each
and their original completion pipeline.

The external frontend separates issued and retired read positions. W uses a
two-entry Common FIFO containing captured address, data and byte strobes.
Only captured legal beats enter arbitration. Invalid strobes or LAST retain
the existing error policy, including earlier committed beats and later legal
beats after an invalid strobe. B waits for all queued legal writes and their
commit responses. External transaction ownership still lasts through B/RLAST.
These are small register queues, not additional user SRAM or new macros.

Acceptance adds consecutive 16-beat read/write handshakes at one SYS cycle per
beat after startup, without local competition or bus backpressure. Logs retain
first-beat latency, total transfer time and final-W-to-B delay. Directed checks
fill/drain queues, stop READY, interleave local service, retain old read values
across local writes, exercise buffered malformed writes and drop stale queued
responses on system reset. Induction checks response conservation/capacity in
addition to held-response stability and the existing service-count fairness.
The unchanged CPU debug/reset, discovery/counters and both real-PDK macro
fixtures remain required.

Use the same immutable P3 flat/banked images and parameters. Each selected
Verilator image runs once; banked Icarus runs once. Compare both with their P3
samples and the pre-repair P4 report. The repair requires burst-16 cycles below
36713/36489 respectively, truthful reporting of all other workload deltas and
identical banked results across simulators. It does not promise P3 cycle parity
or change compiler/layout settings. Existing shared Mini debug inputs are
unchanged by this repair; matching prior compatibility evidence is retained.

### Repair results and provenance

The campaign is complete for review. `source.json`, `report.json`, `audit.py`
and `evidence.json` in the fresh evidence root bind 1972 technical inputs,
six fresh Tiny regression simulations, three matched-image executions,
six real/behavioral SRAM fixtures, two CPU fixtures and control induction.
The combined ICS55/IHP130 input digest is
`58daf68fbb9dee199b3085a73ef07d22eb3de6d00ba875c462e85b76b6091a0d`;
the ICS55 replay input digest is
`a96a129ffc02d0d38fd2eee7ed8fb62893828db3602bbd4459e0a71ffce0c35f`.
Only the approved six technical files differ from the preceding P4 snapshot;
the other two changes are this runbook and the ledger. No commit or staging
operation is part of this campaign.

All six SRAM runs record `read_gap_max=1 write_gap_max=1 beats=16`, with first
R at three cycles after AR and final R at cycle18; W begins one cycle after
AW, final B is at cycle20, four cycles after final W. These are standalone
uncontended protocol measurements, not end-to-end DMA or physical timing.
All six retain `local_latency_max=3`. The new queue checks cover full-response
backpressure, local writes to already captured read addresses, W contention,
buffered malformed writes, and both queued-R and accepted-but-uncommitted-W
system resets. CPU debug/patch/hart-reset and induction pass in the final suite.

| Gate | Result under the fresh evidence root | Outcome |
| --- | --- | --- |
| Final Ruff, diff, RTL format/style/readiness | `quality-pass.{json,log}` | Pass |
| Full Pytest | `pytest-full.{json,log}` | 1659 passed, one optional `pypdf` skip; 3903.061 s |
| Tiny ICS55 PR | `regress-tiny-ics55.{json,log}` | Pass; 3396.035 s |
| Tiny IHP130 PR | `regress-tiny-ihp130.{json,log}` | Pass; 2340.150 s |
| Verilator, both immutable images once | `replay-verilator.{json,log}` | Pass; 390.698 s |
| Icarus, immutable banked image once | `replay-iverilog.{json,log}` | Pass; 5154.223 s |
| Cross-simulator report | `report-result.{json,log}`, `report.json` | Complete; all banked observations identical |
| Source/artifact audit | `evidence.json`, `audit.py` | Pass; review/phase acceptance pending |

The initial `quality-final.{json,log}` is a retained failed development attempt:
the style gate required `s_req_accept`/`s_resp_accept` abbreviations. The names
were corrected before the final source snapshot and all long gates. The first
29 focused checks and additional queued-W-reset check also passed; final-suite
logs qualify the final technical snapshot. No failed attempt is relabeled.

| Workload | Flat pre-repair P4 → repaired P4 | Banked pre-repair P4 → repaired P4 |
| --- | ---: | ---: |
| Empty | 69 → 69 | 66 → 66 |
| CPU | 73911 → 73911 | 73914 → 73914 |
| CPU copy | 102568 → 102568 | 86214 → 86214 |
| DMA burst1 | 91306 → 91306 | 89365 → 89365 |
| DMA burst16 | 36713 → 17897 | 36489 → 17317 |
| CPU/DMA contention | 303493 → 299881 | 299633 → 299633 |
| TCD contention | 303702 → 299878 | 299645 → 299645 |
| Chunk256 | 377705 → 361285 | 376970 → 359570 |

Burst16 cycles decrease 51.25%/52.54%, satisfying the approved repair criterion.
They remain 8.34%/4.81% above the original P3 16520/16523 cycles. Burst1 still
retains the earlier P4 overhead versus P3; this repair does not claim universal
baseline parity. Flat local maximum is four cycles in contended windows, with
17697 eligible bank-conflict cycles; banked maximum is three with zero conflicts.
Uncontended local latency is still checked independently. Firmware checksums,
parameters and each image's compiler/layout identity remain unchanged.

Fresh physical variants are
`build/ics55-tiny-2026-10-10-15-15-42d5beccb726/` and
`build/ihp130-tiny-2026-10-10-15-15-bff91e3529ba/`.
Both pass synthesis, netlist boot and common-SYS/32-macro binding checks.
Their `meta/metrics.json`, `sta/opensta/timing_metrics.rpt`,
`sta/opensta/p4-clock-bindings.rpt` and `sta/opensta/retrosoc_sta.log` retain
the matching observations:

| PDK | Cells | Library area | Setup WNS / TNS (ns) | Hold WNS / TNS (ns) |
| --- | ---: | ---: | ---: | ---: |
| ICS55 | 207029 | 1805809.700799 | -36.88 / -489807.34 | 0 / 0 |
| IHP130 | 218773 | 9245382.228597 | -97.37 / -1640251.62 | 0 / 0 |

Setup remains unclosed; library area is not die area and zero observed hold
slack violations are not physical signoff. Lint comparisons to the unchanged
baselines report 468/412 new signatures for ICS55/IHP130, zero increased and
zero resolved. Relative to pre-repair P4 there are exactly two additional
signatures: intentionally unused FIFO `cnt_o`, and `s_full`, which is consumed
by the verification assertions but unused in synthesis-oriented lint. No new
width/latch warning is attributed to the repair. Warning and metrics policy
remain observational and no baseline was edited.

Commands below used the same timestamp, with `scripts/run_flow.py` retaining
outer command/result/log records. Standalone test artifacts use distinct
`tests-focused`, `tests-reset` and `tests-full` directories under this variant.

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
export BUILD_TIMESTAMP=2026-10-10-15-15 JOBS=3
python3 -m pytest -q tests/test_tiny_r2_p4.py --basetemp=build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/tests-focused
python3 -m pytest -q 'tests/test_tiny_r2_p4.py::test_four_group_local_memory[BEHAV-iverilog]' --basetemp=build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/tests-reset
ruff check .
git diff --check
make rtl-format-check rtl-style-check-all rtl-readiness-check-all
python3 -m pytest -q --basetemp=build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/tests-full
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 SIMU=VERILATOR SOC_SIM_TIME=21600 \
  TINY_P4_REFERENCE=build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json \
  TINY_P4_CASES=perf-o2-plain-flat,perf-o2-plain-banked tiny-r2-p4-replay
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 SIMU=IVERILOG SOC_SIM_TIME=21600 \
  TINY_P4_REFERENCE=build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json \
  TINY_P4_CASES=perf-o2-plain-banked tiny-r2-p4-replay
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 tiny-r2-p4-report
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 APP=ci_smoke SYNTH=YOSYS STA=OPENSTA metrics
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 APP=ci_smoke SYNTH=YOSYS STA=OPENSTA metrics
PYTHONDONTWRITEBYTECODE=1 python3 build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/audit.py
```

Tiny PR/nightly dry-runs match; no duplicate nightly execution was needed.
The six fresh ordinary simulations all require `SIM_TEST_PASS`, including
Tiny netlist boot, together with command success and no forbidden error marker.
Mini's two prior behavioral results retain their original source attribution;
the audit verifies that changed technical inputs are confined to Tiny and its
tests. Mini synthesis/STA, the P3 compiler matrix, additional cold repetitions,
C format/policy/host reruns, PDF generation, PVT/MMMC, CDC/RDC and place/route
were not run for this repair. No C/H code or MISRA deviation changed. The
full-suite optional PDF retrieval check remains skipped for missing `pypdf`.
No new frequency, physical qualification or P5 authorization is claimed.

## Original implementation snapshot

This implements the approved [P4 contract](tiny-soc.md#tiny-r2-p4---dual-port-hazard3-and-four-bank-local-sram)
from `4db27524a6282ca40d76b935415b89f043d6ea83`, specification blob
`7e19de49d49efaafacccfa85671e314d53dd15a4`. The maintainer approved the preflight
and implementation. No P5 execution, dependency update, publication release or
physical-frequency qualification is implied. Historical phase evidence remains
in the [ledger](tiny-soc-verification.md).

## Architecture and lifecycle

Tiny uses locked `hazard3_cpu_2port`, preserving ISA, IRQ, debug, multiply and
branch-prediction settings; A remains disabled. Separate I/D AHB frontends decode
SRAM before the tagged slow-path merge. One accepted D operation spans all
targets. Write data is captured in its AHB data phase; local stores complete
after macro commit. Uncontended local completion is at most three SYS cycles.
Slow errors retain two-cycle AHB completion. Instruction origin reaches the
existing fabric fault path: only NOR boot/NSS0 may be fetched externally, and
peripheral fetches cannot trigger register reads.

Four 32 KiB groups cover `0x30000000..0x3001ffff`, each with eight existing
4 KiB macros and I/D/external round robin advancing only on macro issue.
Per-client registers capture read responses before macro outputs change.
External W waits and R/B backpressure do not lock local macro service.
Continuously eligible requests wait for at most two other issues, conditional
on progress rather than a wall-clock bound for stopped peers.

Each external frontend retains one transaction through B/RLAST and alternates
read/write preference. A direction-tagged demux preserves the existing external
fabric attachment. Whole-product different-target DMA read/write concurrency
remains P5; standalone frontend concurrency is not that product qualification.

Hart reset requests debug halt, prevents new debug instruction injection, drains
accepted local/slow operations and responses, then resets the hart/frontends.
A terminal-cycle AHB overlap must still drain. SRAM/external frontends and
unrelated DMA stay active. System reset invalidates pending responses without
clearing SRAM payload. Five-edge release and Mini's default single-port reset
behavior are preserved; shared debug only adds a pending-state output.

## ABI, physical bindings and observations

Shared SRAM register definitions are unchanged: 128 KiB, `BANK_COUNT=32`,
`BANK_BYTES=4096`. Public counters count external AXI events, saturating sums
of simultaneous events; stall cycles use OR across groups. Local CPU traffic
is not silently added. `R2_AHB` observes the separate I/D ports. `R2_P4_LOCAL`
records local completions, latency and address-admission waits; `R2_P4_BANK`
records macro issues, eligible-client waits and conflict cycles (two or more
eligible clients in a group). These are verification-only observations.

Macro `g,b` is `u_soc.u_sram.gen_group[g].u_group.gen_bank[b].u_ram.u_mem`,
physical index `8*g+b`. IHP130 placement coordinates stay fixed while instance
and supply hooks track both indices. CPU and all 32 macros remain directly on
SYS24; ICS55 PLL stays off and IHP130 remains no-PLL compatibility. Mapping
checks reject stale single-port/flat-bank hierarchies. STA remains observational,
with no 96/192/240 MHz or physical signoff claim.

The Tiny publication extractor and affected draft prose/diagram follow the new
bindings. No reviewed publication SHA, delivered PDF or release status advances.

## Acceptance and matched images

`tests/test_tiny_r2_p4.py` uses real IHP130/ICS55 macro models and a behavioral
model on both simulators: all macro/group boundaries, byte masks, back-to-back
AHB, independent groups, held responses, W-before-AW, bursts/malformed writes,
discovery/counter semantics and reset payload retention. Deterministic readback
uses seed `0x12345678`, 4096 write/read pairs per group. The actual CPU fixture
checks mixed 16/32-bit cross-group fetch, FENCE.I, instruction faults, JTAG
patch/resume, and reset with a held slow response plus an unrelated held B.
Yosys induction proves group control fairness and retained responses with only
macro payload abstracted. Normal Tiny firmware additionally executes code
copied through the real DMA, then CPU-patched code, after completion/FENCE.I.
Its helper is private acceptance assembly, not a new SDK API.

`tiny-r2-p4-replay` validates retained P3 images/logs, builds a fresh P4 model,
and executes each selected image once. Image source/compiler/layout and new
RTL/model identities are separate; hardware settings must match. Original P3
same-source/three-cold-start rules are unchanged. `tiny-r2-p4-report` revalidates
artifacts and requires identical banked-image results across the two simulators.

The reference is
`build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json`.
Select `perf-o2-plain-flat` and `perf-o2-plain-banked` for Verilator and the banked
image for Icarus. Parameters remain 1024 words, four jobs, 4096 CPU iterations,
seed `0x12345678`, burst-1/16 DMA, TCD and chunk-256. Compare each unchanged
binary with its own historical samples, not with a different compiler/layout.
No fixed speedup is predeclared; latency/fairness requirements remain gates.

Development evidence begins under
`build/ics55-tiny-2026-10-10-10-05-b4aa59f3e5d9/meta/tiny-r2-p4/`.
Early fixture failures and corrected runs are retained separately. The final
campaign below completes planned functional validation and measurements; human
review/phase acceptance remain pending, including the DMA throughput tradeoff.

## Executed campaign and provenance

The evidence root above contains `source.json`, `evidence.json`, `audit.py` and
`report.json`. The campaign snapshot contains 1972 unchanged technical inputs,
base commit `4db27524a6282ca40d76b935415b89f043d6ea83` plus the retained patch and
new-file archive, and locked tool/executable/archive identities. Its combined
ICS55/IHP130 digest is
`9fa311a5500711c99b006eacd95cdff04a74659d52b5b46640c42c49773a7f66`.
The ICS55-only replay source set has digest
`2f0d285186f84d41422d8381d09b0a01a2afc066dbd011a11ec7a8a85433ad0d`;
these are different declared input sets, not conflicting identities.

The final audit rechecks all captured inputs, eight ordinary regression
simulations, the three matched-image executions, six standalone memory runs,
two actual-CPU runs and the group-control induction log. Ordinary firmware and
model artifacts are hashed post-run; the campaign source hashes were captured
before execution and rechecked afterward. Image/model identities and original
P3 phase attribution are retained separately.

| Gate | Retained result under the evidence root | Outcome |
| --- | --- | --- |
| Format/style/readiness, C policy/host, Ruff/diff | `quality-final.{json,log}` | Pass; no new MISRA deviation; partial checks, not MISRA certification |
| Full Pytest | `pytest-full.{json,log}` | 1659 passed, one optional `pypdf` environment skip; 3856.630 s |
| Tiny ICS55 PR | `regress-tiny-ics55.{json,log}` | Pass; 3295.064 s |
| Tiny IHP130 PR | `regress-tiny-ihp130.{json,log}` | Pass; 2297.373 s |
| Mini ICS55 behavioral-only PR | `regress-mini-ics55.{json,log}` | Pass; 3093.379 s; no Mini physical evidence |
| P4 Verilator replay | `replay-verilator.{json,log}` | Both selected images once; 357.537 s including build/audit |
| P4 Icarus replay | `replay-iverilog.json`, `replay-iverilog.json.log` | Banked image once; 5214.736 s including build/audit |
| Matched-image aggregation | `report-result.json`, `report.log`, `report.json` | `measurement_complete`; all banked samples match across simulators |

The six standalone memory logs report `local_latency_max=3`, with real
simultaneous group issues. Those protocol fixtures use a 10 ns verification
clock; product replays and timing checks use SAFE24. The banked product replay
also observes three-cycle maximum local latency and zero eligible bank-conflict
cycles. No physical frequency qualification follows from functional models.

Commands were run through `scripts/run_flow.py` for retained logs/results:

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
export BUILD_TIMESTAMP=2026-10-10-10-05
export JOBS=3
make rtl-format-check rtl-style-check-all rtl-readiness-check-all
make sw-format-check sw-policy-check sw-host-test
ruff check .
git diff --check
python3 -m pytest -q --basetemp=build/ics55-tiny-2026-10-10-10-05-b4aa59f3e5d9/meta/tiny-r2-p4/tests-full
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
JAVA_TOOL_OPTIONS=-Dsbt.server.forcestart=true python3 scripts/regress.py \
  --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 SIMU=VERILATOR SOC_SIM_TIME=21600 \
  TINY_P4_REFERENCE=build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json \
  TINY_P4_CASES=perf-o2-plain-flat,perf-o2-plain-banked tiny-r2-p4-replay
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 SIMU=IVERILOG SOC_SIM_TIME=21600 \
  TINY_P4_REFERENCE=build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json \
  TINY_P4_CASES=perf-o2-plain-banked tiny-r2-p4-replay
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 tiny-r2-p4-report
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 APP=ci_smoke SYNTH=YOSYS STA=OPENSTA metrics
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 APP=ci_smoke SYNTH=YOSYS STA=OPENSTA metrics
```

Tiny PR and nightly expand to the same commands; nightly was not duplicated.
Each simulation requires command success, its configured terminal marker and
no forbidden-error marker. All selected ordinary targets require SIM_TEST_PASS,
including Tiny netlist boot. UART text alone is insufficient. Development
attempts are not counted as extra qualifying cold starts.

## Measurements and remaining qualification

Raw cycles below compare each immutable binary with its own P3 baseline.
The report also retains retired instructions, CPI inputs, empty calibration,
local waits, macro issues/conflicts and external traffic accounting.

| Workload | Flat P3 → P4 cycles | Banked P3 → P4 cycles |
| --- | ---: | ---: |
| CPU | 73951 → 73911 | 73954 → 73914 |
| CPU copy | 127157 → 102568 | 114875 → 86214 |
| DMA burst 1 | 64577 → 91306 | 64583 → 89365 |
| DMA burst 16 | 16520 → 36713 | 16523 → 36489 |
| CPU/DMA contention | 310368 → 303493 | 310383 → 299633 |
| TCD contention | 310665 → 303702 | 310683 → 299645 |
| Chunk 256 | 373812 → 377705 | 374016 → 376970 |

CPU-copy cycles decrease by about 19%/25%, while isolated burst-16 DMA takes
about 2.2 times the baseline cycles. The current external frontend processes
issue, completion and bus response separately for each beat; preserving local
response isolation costs streaming throughput. This regression is retained for
review, not hidden by the CPU-copy result or a changed compiler/layout. P5's
external target concurrency alone does not remove these per-beat waits. No
fixed speedup was an acceptance gate, but the tradeoff needs explicit assessment
before phase acceptance or a throughput claim.

Actual synthesis/STA variants are
`build/ics55-tiny-2026-10-10-10-05-42d5beccb726/` and
`build/ihp130-tiny-2026-10-10-10-05-bff91e3529ba/`.
Both emit `TINY_R2_P4_BINDING_PASS` and pass netlist boot. Their raw reports are
`sta/opensta/timing_metrics.rpt`, `p4-clock-bindings.rpt`, `retrosoc_sta.log` and
`meta/metrics.json`.

| PDK | Cells | Reported library area | Max WNS / TNS (ns) | Min WNS / TNS (ns) |
| --- | ---: | ---: | ---: | ---: |
| ICS55 | 206311 | 1803352.980799 | -40.55 / -518700.31 | -0.02 / -11.85 |
| IHP130 | 216216 | 9218095.882797 | -97.46 / -1626503.88 | -0.17 / -142.67 |

Timing is not closed. Library area is not placed/routed die area. Lint baseline
comparisons remain non-blocking observations: Tiny ICS55 466 new signatures,
Tiny IHP130 410 new, Mini ICS55 1537 new / 118 resolved, all with zero increased.
Compared with the preceding P3 lint runs, newly observed signatures are intentional
empty named output connections: Tiny's unused master IDs, exclusive/power/fence
outputs, plus Mini's ignored `reset_pending_o`. Tiny is cacheless with committed
stores, no A/SBA and no Xh3Power, so these outputs do not add interfaces or clock
gating. Baselines and metric policy were not edited. The logs retain the known
generated-file clock skew and successful ABC Liberty fallback observations.

The P3 eight-configuration matrix and three-cold-start campaign were not rerun.
No place/route, extracted/PVT/CDC/RDC signoff, high-rate qualification, new PDK
rollout or PDF build/visual check was performed. Publication snapshot enforcement
remains enabled; the reviewed PDF source revision was not advanced. Mini
DMA-to-WS2812 stays unsupported under option A, and product DMA/IRQ budgets
remain for a supported integration. P5 and later features are not implemented.
