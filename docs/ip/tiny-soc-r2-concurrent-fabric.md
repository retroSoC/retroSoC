# TINY-R2-P5 concurrent fabric

This implements the approved P5 preflight on
`3131762b35e0ebfcd196395f955e7c1005bd18e7`, using frozen specification blob
`7e19de49d49efaafacccfa85671e314d53dd15a4`. The default is Tiny/ICS55 SAFE24
with its present PLL parked off; IHP130/no PLL remains compatibility.
The [ledger](tiny-soc-verification.md) separates phase evidence from approval.
Functional validation and matched-image measurements are complete for review;
no P6, frequency or physical qualification is implied.

## Target-local reset repair (2026-10-11)

The P5 review found that a target reset was previously used only as an
admission enable while an accepted controller session remained live. The
fabric now carries the explicit per-target reset leaf into each controller.
Admission and downstream AXI VALID/W/RREADY are blocked while that leaf is
asserted. An accepted Address or Response session changes to an abort response
and returns one DECERR RLAST or B response with the saved owner and ID; the
response remains held until the upstream terminal handshake. Response spill
registers flush during the target reset, so an old downstream response cannot
be replayed. The normal terminal handshake releases the fabric owner credit
and records the reset termination as one fault event.

The focused reset-isolation fixture covers an accepted SRAM read held before
response and an accepted XPI/APB write held before W, under both Icarus and
Verilator. It checks DECERR termination, no stale response replay, and owner
credit release. These local reruns are separate from the earlier matched-image
campaign; the campaign evidence and PPA/STA attribution remain unchanged until
a new approved evidence capture is made. The retained focused test output is
under `build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/reset-repair-tests/`.

## Ownership and bounds

The three ingress slots are CPU slow path 0, central DMA 1 and reserved SDIO 2.
Only slots 0/1 have product producers. CPU has one combined read/write credit;
DMA and the reserved interface each have one read and one write credit.
The real DMA already reserves complete write data before starting a burst;
its shared scheduler and all request/channel assignments are unchanged.

Targets 0–3 directly attach the existing SRAM group frontends through Common
AXI connectors. Target 4 is XPI memory. Targets 5–20 follow the existing APB
peripheral order, with GPIO's two windows sharing its one branch. Targets 21/22
are the unchanged DECERR/SLVERR responders. The generator emits the decoder
and sixteen single-peripheral bridge instances from canonical topology.
There is no product-wide APB or external transaction lock.

Each target admits one combined transaction and saves owner, direction and
address attributes on the upstream address handshake. Admission reserves both
target and ingress direction, even while the downstream address is stalled.
Owner round robin advances on admission; the chosen owner's direction
preference alternates when both directions compete. W waits for saved AW
ownership and downstream AW acceptance, and stops after the terminal data beat.
Bounded Common response spill registers isolate held R/B values. Ownership and
ingress credit last through the upstream B/RLAST handshake, including buffered
terminal responses. A continuously eligible owner can be bypassed by at most
two other admissions; progress requires clocks and peer completion.

Local CPU I/D, group arbitration, P4 response reservations and main SRAM macro
paths are unchanged. The local uncontended bound remains three SYS cycles,
and the P4 external SRAM streaming fixture still requires one beat per cycle.
All new logic uses SYS; APB bridges follow their existing peripheral reset
leaves. Target reset must be released for admission. System reset invalidates
all buffered sessions without clearing SRAM payload. Hart reset drains CPU
work only. Runtime peripheral resets still require P7's quiescence controls.

## Faults and public compatibility

Each target retains its first failed captured read beat's address/response
until terminal upstream completion; a successful final beat cannot erase it.
Write errors retain the accepted AW address. Six external direction events and
two local CPU events feed the collector. CPU frontend errors carry SLVERR;
external errors propagated through AHB are not counted again locally.

The collector increments the existing count by every simultaneous event,
using four-bit multiplicity and a 33-bit saturating sum. It selects metadata
by ascending owner, CPU instruction before data, then read before write.
Equal keys use stable input order. SYSCTRL preserves a valid first snapshot;
W1C clears validity only and a simultaneous hardware event wins over clear.
FAULT_MASTER adds reserved owner 2 without changing offset or owner 0/1 meanings.
FAULT_DETAIL remains raw AXI response 2/3. The existing HAL byte-sized owner
field needs no change. No SDK API, register generator, interrupt, DMA channel,
capability or pad assignment is added.

The old CPU/DMA wait registers retain their predicate: a requesting owner with
no address handshake in that cycle counts once. R2_P5_FABRIC records separate
active-target maxima, DMA simultaneous read/write ownership and simultaneous
read/write beat handshakes. These are testbench observations. The original
P3/P4 record formats and evidence retain their own identities.

## Verification and reproducibility

Focused protocol tests use all three owner slots, saved-address perturbations,
W-before-AW, held addresses/data/responses, independent control branches,
same-target contention and 96 deterministic randomized reads. Mixed-response
bursts align two terminal faults while their final responses are OKAY.
SYSCTRL tests cover multi-event count, owner 2, hardware-over-W1C and saturation.
The saturation test seeds the Common counter register, then exercises the
real adder and readback; it does not simulate billions of events.

The system fixture instantiates production retrosoc_tiny, CPU, DMA, SRAM,
bridges and SYSCTRL. Only the XPI boundary is replaced with a controllable
verification endpoint and a fixture-only reset ROM. Real DMA copies B2 to B3
with concurrent read/write beats and CPU readback checks. With an XPI mapped
response held, SRAM code and SYSCTRL access continue. A held XPI APB write
then verifies independent controls and hart-reset isolation. Finally CPU aborts
a held DMA read, checks that BUSY survives accepted work, releases the response
and verifies ABORTED. Ordinary regressions retain real pin-level XPI/NOR models.
This fixture is neither a product Boot ROM nor an XPI-device qualification.

The first fixture attempted hart reset while holding the XPI memory response;
an accepted CPU instruction also needed that target, so reset correctly waited
for drain. The corrected isolation case retains DMA at the independent APB
branch and permits CPU progress. Other development attempts preserve sv2v
diagnostics separately from converted RTL and observe declared interface
instances rather than module-modport aliases for Icarus compatibility.

Yosys induction checks production target ownership, response retention,
terminal-fault attribution and service-count fairness. A combinational proof
checks the collector's count and lexicographic metadata selection for arbitrary
event vectors. These are scoped control proofs, not full-chip formal signoff.

The P5 replay entrypoint uses the unchanged P3 flat/banked images referenced by
the repaired P4 report:
`build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/report.json`.
The old reports retain their original 4db27524-based snapshot attribution;
preflight matched all 1972 technical inputs to the committed P5 starting point.
P5 report identity, source/configuration/tool hashes and observations are new.
Parameters stay 1024 words, four jobs, 4096 CPU iterations and seed 0x12345678.
Each Verilator image runs once and banked Icarus once; all banked observations
must agree. There is no frozen overall speedup requirement or compiler/layout
experiment. Different-bank concurrency is proved separately because the
retained banked placement concentrates DMA storage in B3.

Fresh development evidence begins at
`build/ics55-tiny-2026-10-10-18-25-b4aa59f3e5d9/meta/tiny-r2-p5/`.
The completed campaign and its monitor-only follow-up are recorded below.
Documentation remains here rather than in generated directories.
The Tiny draft/source extractor follows P5 routing and the fault field width;
its reviewed publication SHA and PDF status are not advanced.

## Completed campaign and monitor correction

The final evidence root is
`build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/`.
`source.json` binds the initial 2010-input campaign to combined ICS55/IHP130
digest `e85f4245883bf35f152d607480adf48edcf49debadb46d8b0bde92050a792b11`.
Both Tiny PR regressions, full Pytest and the first three image executions
passed on that snapshot. The initial aggregation in `report-result.{json,log}`
correctly failed: Icarus reported active-target maxima one greater than
Verilator in all eight banked windows, while every other sample was identical.

The locked Icarus 13 installation miscounts the temporary expression
`$countones(~a_23_bit_vector)`. `countones_probe.sv` and its retained log
demonstrate an expected count 1 returning 3/6, while a named vector and explicit
bit counting return 1. The correction counts the declared 23 bits explicitly,
rejects unknown target states, and adds an opt-in count 0..23 self-check. No
postprocessing subtraction, relaxed comparison, tool upgrade or DUT fix is used.

`monitor-source.json` captures the final combined digest
`0f3ed21f6fd6e932ff2532aab8c9964e71cf4b972e4c27e2c8ca6ab1f22c1015`.
Its only technical difference from the initial capture is
`rtl/tiny/dv/retrosoc_tiny_tb.sv`, inside P5 opt-in observation/self-check code.
The DUT, firmware, verification fixtures, policies and tool inputs are identical.
The ordinary regression commands do not enable this branch, and netlist boot
excludes it. Their results, full-suite results and PPA retain their original
snapshot attribution; they were not rerun or relabeled as new executions.
The audit checks this exact single-file delta and the original command flags.

Both Verilator images and banked Icarus were rebuilt/replayed after the fix,
and the monitor self-check passed on both new models. The final ICS55-only
replay input digest is
`df14713ed7177d988d0e3fa0a038984589584788eda994dd7480f01a8dfcab7c`.
`report-final.{json,log}` and `report.json` confirm exact equality of all banked
observations across simulators, including the corrected active-target statistic.
`monitor-diagnosis.json` preserves the original discrepancy, logs and input
identity. Final model copies are retained beside their attempt records and
bound by `model-backup-*.json`; the initial Icarus model is separately retained.

| Gate | Retained result | Scope/outcome |
| --- | --- | --- |
| Focused development suite | Earlier `18-25` root, `focused-final.{json,log}` | 106 passed before final campaign |
| Initial quality | `quality.{json,log}` | Ruff, diff, RTL format/style/readiness pass; 11.524 s |
| Full Pytest | `pytest-full.{json,log}` | 1679 passed, optional `pypdf` skip; 3867.891 s; original snapshot |
| Tiny ICS55 PR | `regress-tiny-ics55.{json,log}` | Pass; 4273.573 s; original snapshot |
| Tiny IHP130 PR | `regress-tiny-ihp130.{json,log}` | Pass; 3028.340 s; original snapshot |
| Initial image executions | `replay-verilator` / `replay-iverilog` results | Commands pass; 609.465/5952.278 s; cross-simulator aggregation fails as above |
| Monitor follow-up quality | `monitor-quality.{json,log}` | Pass; 11.714 s |
| Count self-checks | `monitor-check-{verilator,iverilog}.{json,log}` | Pass; instrumentation-only, not firmware acceptance |
| Final image executions | `replay-verilator-monitor` / `replay-iverilog-monitor` results | Pass; 618.974/5978.016 s; one run per selected image |
| Final report and audit | `report-final.{json,log}`, `report.json`, `evidence.json`, `audit.py` | Measurement complete; source-bound functional validation complete, review pending |

All six ordinary simulations satisfy command success, configured SIM_TEST_PASS
and absence of forbidden error markers. In the final full suite, six P4 SRAM
fixtures preserve three-cycle local latency and one-cycle streaming spacing;
two P4 CPU fixtures, two P5 fabric fixtures, two real-CPU/DMA system fixtures
and three scoped formal logs pass. The system fixture reports 13 simultaneous
DMA read/write beat cycles and 27 independent control completions on both tools,
with hart-reset isolation and abort drain. SYSCTRL tests additionally check
multiple faults, reserved owner 2, raw detail, clear precedence and saturation.
These are functional results, not physical or XPI-device qualification.

## Measurements and qualification limits

The final runs preserve the immutable P3 image identities and compare them
with repaired P4 measurements, without changing compiler or placement:

| Workload | Flat P4 → P5 cycles | Banked P4 → P5 cycles |
| --- | ---: | ---: |
| Empty | 69 → 69 | 66 → 66 |
| CPU | 73911 → 73911 | 73914 → 73914 |
| CPU copy | 102568 → 102568 | 86214 → 86214 |
| DMA burst1 | 91306 → 65527 | 89365 → 65502 |
| DMA burst16 | 17897 → 16974 | 17317 → 15802 |
| CPU/DMA contention | 299881 → 299990 | 299633 → 299738 |
| TCD contention | 299878 → 300027 | 299645 → 299750 |
| Chunk256 | 361285 → 361514 | 359570 → 361355 |

The flat burst16 window records a maximum of three active targets, 124 cycles
with simultaneous DMA read/write ownership and 48 simultaneous read/write beat
cycles. Banked DMA stays in B3 and has zero DMA read/write overlap; up to two
targets are active because independent CPU control can overlap that bank.
The separate system fixture establishes different-bank DMA concurrency.
CPU/copy cycles are unchanged. Small contention/TCD increases and the 0.50%
banked chunk256 increase remain visible; no universal speedup is claimed.

Synthesis/STA observations for the unchanged DUT use
`build/ics55-tiny-2026-10-10-18-58-42d5beccb726/` and
`build/ihp130-tiny-2026-10-10-18-58-bff91e3529ba/`.
Both pass synthesis, netlist boot and the existing 32-macro/direct-SYS binding
checks. Reports are `meta/metrics.json`, `sta/opensta/timing_metrics.rpt`,
`sta/opensta/p4-clock-bindings.rpt` and `sta/opensta/retrosoc_sta.log`.

| PDK | Cells | Library area | Max WNS / TNS (ns) | Min WNS / TNS (ns) |
| --- | ---: | ---: | ---: | ---: |
| ICS55 | 241309 | 1906156.940799 | -64.75 / -932689.50 | 0 / 0 |
| IHP130 | 256995 | 9888378.712794 | -111.93 / -2594456.50 | 0 / 0 |

Library area grows 5.56%/6.95% versus repaired P4. Max timing margins worsen;
timing remains unclosed and observational before the final product campaign.
Library area is not routed die area, and zero observed min violations is not
PVT/hold signoff. No new timing exception or rate is introduced.

The unchanged warning baselines report 469/413 new signatures for ICS55/IHP130,
zero increased and zero resolved. Relative to repaired P4, two new signatures
are intentional empty `owner_idle_o`/`target_idle_o` connections; their future
lifecycle use and verification visibility are documented at the instances.
The former unused interface `aresetn` signature disappears because target
admission now consumes it. There is no new width/latch signature. The known
NFS clock-skew warning and successful ABC Liberty-cache fallback remain logged.
No warning baseline or metrics policy was changed.

Mini behavioral compatibility retains its earlier P4 evidence and source
identity. The audit rechecks the unchanged shared/Mini/SDK/configuration inputs;
there is no new Mini execution or physical claim. No C/H implementation or
MISRA deviation changed. The P3 compiler matrix and three cold repetitions,
full C netlist campaign, PDF build/visual checks, CDC/RDC/PVT/MMMC, place/route,
high-rate qualification and P6+ work were not performed. Only the concretely
affected image measurements were repeated for the monitor defect.

## Executed commands

Commands used the locked activation and `BUILD_TIMESTAMP=2026-10-10-18-58`,
`JOBS=3`. `scripts/run_flow.py` retains the exact outer commands and JSON/log
results named above. New evidence is under `meta/tiny-r2-p5`; source snapshots,
tool identities, input digests, models, images and raw logs remain separate.

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
export BUILD_TIMESTAMP=2026-10-10-18-58 JOBS=3
make rtl-format-check rtl-style-check-all rtl-readiness-check-all
ruff check .
git diff --check
python3 -m pytest -q --basetemp=build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/tests-full
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 SIMU=VERILATOR SOC_SIM_TIME=21600 \
  TINY_P5_REFERENCE=build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/report.json \
  TINY_P5_CASES=perf-o2-plain-flat,perf-o2-plain-banked tiny-r2-p5-replay
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 SIMU=IVERILOG SOC_SIM_TIME=21600 \
  TINY_P5_REFERENCE=build/ics55-tiny-2026-10-10-15-15-b4aa59f3e5d9/meta/tiny-r2-p4/report.json \
  TINY_P5_CASES=perf-o2-plain-banked tiny-r2-p5-replay
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 tiny-r2-p5-report
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 APP=ci_smoke SYNTH=YOSYS STA=OPENSTA metrics
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 APP=ci_smoke SYNTH=YOSYS STA=OPENSTA metrics
PYTHONDONTWRITEBYTECODE=1 python3 build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/audit.py
```

Tiny PR/nightly definitions matched and were not executed twice. The first
report attempt failed; only the monitor-corrected executions qualify the final
cross-simulator report. The original cold executions are not a three-repeat
qualification campaign. No commit, staging, push, PR or automatic next-phase
transition belongs to this implementation.
