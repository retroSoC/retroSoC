# Tiny R2-P7 clock/reset implementation and evidence

This phase starts at `43a3c8d453b6d41df3536719ebc6d1f4521bc7cd`, against frozen
specification blob `7e19de49d49efaafacccfa85671e314d53dd15a4`. Implementation
is authorized; phase acceptance still requires review of the completed gates.
At this historical P7 checkpoint no P8 implementation, commit, push, or
physical frequency qualification followed. P7 was later human-accepted on
2026-10-15; the separate P8 handoff and evidence ledger now govern subsequent
work.

## Product and ownership

`configs/ci/ics55-tiny.mk` remains the default: TINY, ICS55, PLL present,
SAFE24 boot. The single RCU-owned PLL starts off. Software may request the
functional PLL192/PLL240 profiles after draining clients. These are digital
simulation capabilities, not characterized silicon operating points.
`configs/ci/ihp130-tiny.mk` remains the explicit no-PLL 24 MHz compatibility
profile. `ihp130-tiny-xin48.mk` and `ihp130-tiny-xin96.mk` add declared external
input variants, both normalizing the boot/control reference to 24 MHz.

CPU, all 32 main SRAM macros, bank frontends, fabric and SDIO share active SYS.
Only the CPU leaf stops for WFI. XPI data/control use MEM. DMA, shared serial
and security IP and the six private Crypto macros use PCLK. Crypto capacity
and erasure policy are unchanged. AON owns RCU, CLINT and RTC/WDG functional
timekeeping; AUDIO is optional at boot. The historical ASIC wrapper and frozen
QFN64/pad contract are retained under the existing P6 qualification boundary.

Tiny owns the clock backend, admission holders, APB/AXI crossings, peripheral
lifecycle controller, CPU gate, CLKOUT and SYSCTRL ABI. Common clock mux,
divider, reset barrier, synchronizers and CDC primitives are reused without
editing managed sources. New optional shared-IP lifecycle outputs preserve
Mini defaults; the debug wrapper's separate system reset is opt-in. Managed
PWM/CRC lifecycle mirrors observe successful writes at their existing ABI.
The already approved PWM lock remains
`38efaf5e20f084a00148920087c60cadab61839b`.

RCU occupies `SYSCTRL+0x100..0x15c`, IRQ31. Handwritten SVH/C definitions
have a 24-register parity test. `rcu.h` supplies bounded Tiny-specific profile,
snapshot, gate, local/system reset, cause/fault and CLKOUT operations. Invalid,
unsupported, busy, timeout and hardware-error results are distinct. No new
MISRA Required-rule deviation is introduced. Future targets 14–17 remain
absent; no SPI, PIO-lite, DVP, PPALite or PSRAM rollout is included.

## Lifecycle and failure boundaries

Clock requests block new admissions after command acceptance, drain accepted
CPU/local/AXI/APB traffic, park on REF24, configure conservative divisors,
qualify the source, then commit rate snapshots before unblocking. Stalled
addresses already accepted into admission holders retain VALID/payload.
Unaccepted requests may remain pending and resume after switching. An
insufficient transition budget fails before changing the committed profile.
PLL lock timeout publishes the complete SAFE24 fallback. PLL stuck-low/high
requires a system/CDC reset before forced mux recovery; XIN loss needs source
restoration and external reset.

Local resets hold for five actual leaf edges and release through five-edge
synchronizers and bus barriers. I2S additionally requires actual AUDIO-side
reset readiness; missing AUDIO cannot manufacture RESET_DONE. Gate changes
wait for idle; CPU-only WFI permission does not pause unrelated DMA. Current
non-CPU lifecycle commands conservatively drain all central-DMA work before
changing the selected targets. This can reject a request while an unrelated
DMA stream remains active; it does not stop that stream by gating its clock.
Warm reset retains cause/fault/debug state, aborts interrupted debug commands,
restores SAFE24, resets functional RTC/WDG state and preserves main SRAM data.

The 2026-10-14 P7 review correction keeps the XPI fabric target and AXI bridge
source endpoint on SYS reset while the XPI/MEM endpoint uses its MEM leaf reset.
The later response-conservation correction uses source-owned response holders:
already presented B/R responses remain stable and retire once, while missing
read beats receive DECERR and aborted writes drain W before B. Admission allows
one outstanding request in each direction. Payload source reset uses the
five-edge link barrier; the response holders reset only with the source.
An unfinished warm clear holds isolation until destination reset so that late
responses cannot enter another transaction. Production DMA/XPI clear inputs
remain tied low. A failed drain does not trigger an invented autonomous AXI
timeout or peripheral reset. The focused tests now cover these protocol
boundaries in both simulators; earlier 36-case results did not establish them.

Source-only reset has a separate production precondition. The DMA source
may reset locally only after its engine and accepted admission/fabric work
drain. The controller blocks new admissions, waits at least 16 REF24 cycles
for the synchronized observations, and leaves the source running on drain
timeout. XPI has no independent SYS-source reset: the common system reset
also asserts its MEM endpoint reset. The standalone AXI bridge does not
cancel a live remote slave's work on an arbitrary source-only reset and must
not be reused with that assumption.

The focused `tiny_p7_source_reset_tb` extracts the production controller,
admission, bridge, synchronizers and reset bindings into its fixture and uses
the real DMA AXI master. It checks stalled addresses, partial writes, late
responses, held read responses, timeout, recovery and common reset at all five
declared domain ratios. A scoreboard independent of local reset detects the
deliberately broken-drain negative case. Unrelated clients and the completion
mailbox are idle; the target is a behavioral slave. This supplies executable
integration-contract coverage, not a general arbitrary-reset proof or physical
qualification. The new evidence is under `06-00.../meta/tiny-r2-p7-source-reset/`
as detailed in the verification ledger; production RTL and backend inputs are
unchanged by this follow-up.

The follow-up validation commands are:

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
p7_reset_evidence=build/ics55-tiny-2026-10-14-06-00-ff4b5cef6eb5/meta/tiny-r2-p7-source-reset
PYTHONDONTWRITEBYTECODE=1 python3 scripts/run_flow.py --tool pytest \
  --log "$p7_reset_evidence/directed.log" \
  --result "$p7_reset_evidence/result-directed.json" -- \
  python3 -m pytest -q tests/test_tiny_r2_p7.py \
  --basetemp="$p7_reset_evidence/directed-tests"
make --silent CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 \
  rtl-format-check rtl-style-check-all check-clock-reset-domains
ruff check .
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
git diff --check
```

These paths identify the retained execution, not an instruction to overwrite
it: use a fresh evidence directory for any retry. `source.json` binds the new
tests and `verification-update.json` compares them to the original `06-00`
snapshot. Only the two verification files differ; all 1728 other technical
inputs and tool identities match. No firmware, full-SoC, synthesis, netlist or
STA flow is repeated for this verification-only correction. The earlier
full-suite Pytest and full-Icarus limitations below remain explicit.

The first post-fix physical smoke campaign below is historical. Each PDK has
its own profile/configuration digest. These results precede the final response
holders; current source evidence is recorded in the verification ledger.

| PDK | Variant | Synthesis | Netlist boot | STA |
| --- | --- | --- | --- | --- |
| ICS55 | `build/ics55-tiny-2026-10-14-01-20-ff4b5cef6eb5` | PASS, 2122.685 s | PASS, 1656.024 s, `SIM_TEST_PASS Tiny netlist boot` | PASS observation; WNS max/min `-144.40/-0.31 ns`, TNS max/min `-4859636.50/-45.04` |
| IHP130 | `build/ihp130-tiny-2026-10-14-01-20-8232fa11e7f3` | PASS, 1925.337 s | PASS, 586.861 s, `SIM_TEST_PASS Tiny netlist boot` | PASS observation; WNS max/min `-257.81/-0.47 ns`, TNS max/min `-9807803.00/-100.68` |

The current frozen-source `06-00` campaign supersedes the historical table for
post-fix qualification:

| PDK | Variant | Synthesis | Netlist boot | STA |
| --- | --- | --- | --- | --- |
| ICS55 | `build/ics55-tiny-2026-10-14-06-00-ff4b5cef6eb5` | PASS, 2108.388 s | PASS, 1655.980 s, `SIM_TEST_PASS Tiny netlist boot` | PASS observation; WNS max/min `-152.03/-0.31 ns`, TNS max/min `-5622052.50/-44.14` |
| IHP130 | `build/ihp130-tiny-2026-10-14-06-00-8232fa11e7f3` | PASS, 1934.515 s | PASS, 578.869 s, `SIM_TEST_PASS Tiny netlist boot` | PASS observation; WNS max/min `-253.43/-0.49 ns`, TNS max/min `-10035324.00/-153.37` |

The STA markers explicitly identify SAFE24/observational analysis; neither
variant qualifies an active PLL, routed implementation, PVT corner or product
operating point. The `04-00` source candidate was later rejected by the
response-conservation tests. The `06-00` source-bound post-fix campaign is the
current qualification run and all requested synthesis, netlist and STA gates
pass. Its measured results are recorded in the ledger. Full firmware Icarus
remains deferred to the final Tiny phase.

Source/divisor/enable for CLKOUT are committed together, cross to the selected
source, and finish the current output high pulse before disabling. GPIO28 ALT0
and GPIO23 ALT1 consume the same generator. Illegal/live changes return
PSLVERR and leave the previous configuration unchanged.

## Validation sequence and commands

Activate the locked environment before these commands:

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 -m pytest -q tests/test_tiny_r2_p7.py tests/test_tiny.py tests/test_tiny_r2_p4.py tests/test_tiny_r2_p5.py
make sw-format-check sw-policy-check sw-host-test
make rtl-format-check rtl-style-check-all rtl-readiness-check check-clock-reset-domains
ruff check .
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
python3 -m pytest -q
git diff --check
```

The direct long-flow commands use the selected regression's targets with
larger explicit wall-time budgets. The identical Tiny nightly matrix does not
need a second execution. Every row below runs once per PDK, with
`CONFIG=configs/ci/<pdk>-tiny.mk SOC=TINY PDK=<PDK> APP=ci_smoke HAVE_SVA=YES`:

| Purpose | BUILD_TIMESTAMP | Remaining Make arguments |
| --- | --- | --- |
| P7 Verilator | `2026-10-13-17-05` | `TINY_P7_ACCEPTANCE=YES SIMU=VERILATOR SOC_SIM_TIME=3600 TINY_SIM_TIMEOUT=6000000 TINY_SIM_ARGS=+p7_monitor sim` |
| P7 Icarus | `2026-10-13-17-06` | `TINY_P7_ACCEPTANCE=YES SIMU=IVERILOG TINY_SIM_TIMEOUT=6000000 TINY_SIM_ARGS=+p7_monitor 'TINY_RUN=timeout --foreground 14400s $(VVP) $(SIM_BUILD_ROOT)/simv' sim` |
| Physical macro synthesis | `2026-10-13-17-15` | `HAVE_SVA=NO SYNTH=YOSYS YOSYS_TIMEOUT=10800 synth` |
| Full firmware/JTAG, P7 watchdog-cause adaptation, Verilator | `2026-10-13-18-25` | `SIMU=VERILATOR SOC_SIM_TIME=7200 TINY_SIM_TIMEOUT=30000000 TINY_SIM_ARGS=+tiny_jtag_smoke sim` |
| Full firmware/JTAG, P7 watchdog-cause adaptation, Icarus | `2026-10-13-18-26` | `SIMU=IVERILOG TINY_SIM_TIMEOUT=30000000 TINY_SIM_ARGS=+tiny_jtag_smoke 'TINY_RUN=timeout --foreground 36000s $(VVP) $(SIM_BUILD_ROOT)/simv' sim` |
| Netlist boot, after synthesis | `2026-10-13-17-15` | `HAVE_SVA=NO SIMU=IVERILOG netsim-boot` |
| Observational core STA, after synthesis | `2026-10-13-17-15` | `HAVE_SVA=NO 'STA_BUILD_ROOT=$(VARIANT_ROOT)/sta/opensta-p7-v3' STA=OPENSTA sta` |

Warning/metric collection uses each corresponding variant. New EDA signatures
remain observations; no warning baseline or metric policy is edited. Compiler
warning policy and Tiny functional verdicts remain required.

After correcting the external-input POR reference, the actual-SoC P7 image is
also run with `CONFIG=configs/ci/ihp130-tiny-xin48.mk` and
`CONFIG=configs/ci/ihp130-tiny-xin96.mk`, `SOC=TINY PDK=IHP130 APP=ci_smoke
TINY_P7_ACCEPTANCE=YES HAVE_SVA=YES TINY_SIM_ARGS=+p7_monitor
TINY_SIM_TIMEOUT=24000000`. Verilator uses timestamp `2026-10-13-18-40`,
`SIMU=VERILATOR SOC_SIM_TIME=7200 sim`; final Icarus uses `2026-10-13-20-05`,
`SIMU=IVERILOG 'TINY_RUN=timeout --foreground 21600s $(VVP) $(SIM_BUILD_ROOT)/simv' sim`.
The larger cycle budget counts raw XIN edges, not SYS/REF24 cycles. These are
additional source configurations, not repetitions of a single benchmark.

The initial XIN48/96 Icarus attempts (`18-41`) produced a premature terminal
write but failed the independent P7 lifecycle coverage checks, so they remain
FAIL. A short actual-SoC comparison reproduced unknown RCU cause/fault state
with the old reset declaration initialized low at time zero. REF24 has no edges
while its input divider is reset; an explicit external RESET_N assertion at
1 ns, before the first XIN edge, initializes the asynchronous state correctly.
Both old-stimulus negative probes fail and both asserted-reset probes pass,
under `20-05.../meta/cold-reset/`. The testbench now checks exact known cold
state and rejects an unknown terminal pass/code. This is a verification-stimulus
repair, with no forced DUT state or synthesizable RTL change. The Verilator
source cases and existing 24 MHz runs are retained separately; only the two
failed Icarus source cases are replayed, with the same firmware hashes.

## Workloads and provenance

The separate `TINY_P7_ACCEPTANCE=YES` configuration key selects the short P7
firmware without replacing the original acceptance application. It exercises
all supported profile selections for the chosen backend, 128-word SRAM
retention, atomic rate readback, PWM rate readback, CLINT monotonicity and an
independent PCLK timer measurement over at least 200 CLINT ticks. The timer
check allows bounded APB read skew but rejects /2 or /4 domain mistakes.
It gates/ungates/resets timer0, copies 1024 words through DMA while CPU WFI is
armed, wakes on CLINT, and requests software reset with a retained `.noinit`
sentinel. The observer must see actual CPU gated cycles, DMA responses during
that interval, supported profile commits and exactly one software reset.

Tiny PASS requires command success, TEST_STATUS/SIM_TEST_PASS, and absence of
FAILED/FATAL/assertion failed/%Error/SIM_TEST_FAIL/SIM_TEST_TIMEOUT. P7 also
requires `P7_LIFECYCLE_PASS`. The old full firmware additionally retains its
P6 peripheral/wire/AXI records and JTAG checks. UART output is diagnostic only.

The completed P7 firmware results below match between Verilator and Icarus.
All eight images use the same retained binary. Cycles count raw XIN edges and
must not be compared as CPU cycles across different XIN configurations.

| Source/profile | Terminal cycles in each simulator | Actual gated SYS cycles | DMA responses while gated |
| --- | ---: | ---: | ---: |
| ICS55 XIN24, PLL192/240/SAFE24 | 3,525,681 | 71,614 | 64 |
| IHP130 XIN24, external/SAFE24 | 3,521,913 | 71,623 | 64 |
| IHP130 XIN48, external/SAFE24 | 7,038,466 | 71,635 | 64 |
| IHP130 XIN96, external/SAFE24 | 14,071,429 | 71,615 | 64 |

Each run also records exactly one software reset and verifies SRAM retention.

The source record is
`build/ics55-tiny-2026-10-13-17-05-f3e42d54c18b/meta/tiny-r2-p7/source.json`.
It retains repository state, the exact specification, locked tool identities,
source hashes, patch and a source archive, including untracked implementation
files. `scripts/tiny_r2_p7.py verify-source` checks the retained source set.
The Make formatter subsequently changed only the terminal newline in eight
Make/configuration files. `make-format-equivalence.json` checks every changed
file byte-for-byte except that final newline; RTL, firmware, tests and tool
scripts are identical. `formatted/source.json` retains the final formatting
snapshot separately, without overwriting the source consumed by running jobs.
Subsequent validation corrections update the commercial six-domain SAFE24
adapter/test and connect the top-level POR counter to normalized REF24. The
external-source fixture now requires five actual REF24 edges at 24/48/96 MHz
and compares old/new reset-tree outputs at 24 MHz in both simulators (seven
checks pass). For every retained long-flow configuration, XIN is 24 MHz and
the backend directly wires XIN to REF24, so that one port reconnection is an
exact alias substitution. The original source remains the provenance of those
runs; the documented equivalence and focused higher-input-rate tests cover
the correction without repeating default-profile simulations.
Build variants retain effective configuration, generated filelists, firmware
ELF/bin/hex/map, simulator binaries, command logs and structured terminal
results. Match binaries by SHA-256 across simulators, and retain flags and
plusargs with results; do not mix these images with compiler/layout experiments.

The four P7 binaries (both PDKs and both simulators) have SHA-256
`0a536fbbae9832de7ba5a82f7688a147b96a57435a66249b5e8de18bad1c01c5`.
The initial full ICS55 firmware matched between simulators at
`e4cb5965b9b9ddb1135a0a672327113ed8b378ace56e1a4ee771374309c18a15`;
the initial full IHP130 firmware matched at
`048bd15221fcbd25986abaa2d973e74d101f3a8ac8f328a6169442ba8acabacb`.
The corrected watchdog-acceptance full images match between simulators at
ICS55 `69b8582099c8735e81014b9c3f5685d9212a58c18b820a8c9a611a6f64a2f6c4`
and IHP130 `efc0b403f32669332e942cb63ee9bb2b035a6e462e68e0a5a1524dea01c6c298`.

P7 has its own structural netlist audit. It requires 32 main and six private
Crypto physical SRAM macros, main-SRAM/CPU SYS equality, the CPU-only gate,
Crypto PCLK binding and exactly one real ICS55 PLL driving the SYS mux.
The audit binds configuration digest, netlist/JSON and audit-script hashes.
The strict historical P1 parked-PLL/direct-SYS audit is unchanged.

Core STA analyzes SAFE24 boot, with explicit mux/PLL case analysis. Retain
clocks, setup/hold, coverage, recovery/removal and constraint-violation reports.
It excludes pad/board/routed/PVT and active-PLL qualification. Negative slack
is observational before the final combined product campaign, not evidence of
qualification and not permission to omit synthesis or netlist functionality.
The commercial adapter mirrors the same six-domain SAFE24 inventory and
requires explicit mux/PLL case selections; its host tests pass. Internal /2,
/4 and CLKOUT-source clocks supplement the six root domains. Settled mux gate
state is constrained because a select request alone does not propagate through
the mux's sequential handshake in static analysis. The initial and second STA
attempts remain under `sta/opensta` and `sta/opensta-p7-v2`; the final observation
is under `sta/opensta-p7-v3`. No licensed
commercial execution, active-PLL SDC, routed extraction, board IO or package
qualification is supplied by those host tests.

Historical `2026-10-13-17-15` SAFE24 observations, in ns, are ICS55 setup/hold WNS −147.48/−0.31,
TNS −4758121.50/−45.30; IHP130 WNS −275.45/−0.50,
TNS −9958118.00/−102.84. The worst setup cone begins at the fabric reset leaf,
whose direct fanout is over 10,000; no reset false path was added to hide it.
The v3 coverage reports retain excluded pad IO budgets, 42 unclocked ICS55 PLL
monitor/mux pins while that source is off, and 5 ICS55 / 6 IHP130 control pins
with multiple clock tags. These are explicit limits of this settled SAFE24
observation, not complete-mode timing coverage or signoff. These values and
coverage counts belong to that historical netlist; the current `06-00` WNS/TNS
are in the table above, with their own retained coverage reports.

The single full Pytest attempt records 1696 passed, 6 failed, 60 setup errors
and one optional `pypdf` skip. Two failures were the commercial domain policy;
60 setup errors and one failure shared the missing `RS_EBUSY=-8` SDK return
entry in the publication's source-checked table. Both are corrected; the
commercial/STA tests pass and the publication subset records 110 passed/one
skip. The remaining three Icarus failures used a test module collected before
the external-reset fixture acquired its `tiny_reset_tree` dependency; the
updated test command explicitly supplies it and all seven external-source/reset
checks pass. Keep that original full-suite result and these focused reruns;
do not report an unexecuted clean full-suite pass. Only the shared return-code
table changes in the publication; no source identity, PDF, edition or release
qualification is advanced.

## Interrupted and historical attempts

Earlier October 13 build directories are development snapshots. In particular,
the `15-45-f3e42d54c18b` Verilator attempt passed at 3,281,032 cycles and observed
71,612 gated cycles, 64 DMA responses while gated and one warm reset. Later
corrections mean that result is not final-source acceptance. Earlier synthesis
attempts failed obsolete P1 checks; a temporary weakened P1 audit is invalid
evidence and was restored. No current physical result may be inferred from it.

The first final-campaign synthesis attempt (`17-07`, SVA enabled) failed during
Slang elaboration on unsupported temporal assertion syntax. It did not run
mapping. The `17-15` retry uses the existing regression's `HAVE_SVA=NO` synthesis
configuration; behavioral/SVA verification remains separate and unchanged.

The `17-08` complete Verilator runs passed all first-boot peripherals, then
incorrectly repeated the firmware after watchdog reset and failed recovery
code 26 on the second pass. The old firmware inferred warm boot from the
watchdog's functional `reset_count`; P7 intentionally resets that state. The
corrected firmware checks retained RCU cause bit 2, verifies that watchdog
functional state was cleared and SAFE24 restored, and requires an SRAM `.noinit`
cookie set only after all first-boot tests. This preserves the complete test
sequence and watchdog acceptance rather than restoring obsolete retention.
The corresponding `17-09` Icarus runs were cancelled as obsolete; controller
exit 130 is retained in `controller-cancellation.json`, separately from any
unfinished child result. Corrected full runs use `18-25` / `18-26` and source
evidence under `build/ics55-tiny-2026-10-13-18-25-f3e42d54c18b/meta/tiny-r2-p7/`.

The corrected full Icarus attempts under `18-26` reached the watchdog-reset
stage after reporting all first-boot peripherals, but both exhausted the
36,000-second wall-clock budget with exit 124 and no terminal PASS. Those
results remain FAIL. A focused test uses the real WDG APB wrapper, command
mailboxes, Tiny APB bridge, clock backend, reset tree and RCU, and verifies two
successive hardware watchdog resets, retained RCU cause and cleared functional
state in both simulators. It does not replace the full firmware gate.
The exact retained `simv` and firmware were replayed under
`sim/iverilog/attempt-2026-10-14-04-50/` with `timeout --foreground 72000s vvp -i`,
the same `+max_cycles=30000000 +tiny_jtag_smoke` and firmware path. The
maintainer then intentionally interrupted both replays with exit 130 and moved
this long-running full-Icarus gate to the final Tiny phase. The logs and
interrupted `result-sim.json` records are retained as unrun/partial evidence;
they cannot satisfy the P7 terminal verdict. `-i` enabled unbuffered standard
IO; it did not change the design or acceptance workload. No synthesis,
simulator compilation or firmware build was repeated for the replay.

PIDs are diagnostics in a particular execution namespace. Absence from another
tool invocation's process list does not prove termination. Keep long commands
attached to their execution sessions and use terminal result JSON plus strict
log checks. `run_flow.py` records child/parent PIDs and closes results on caught
exceptions; SIGKILL or host loss can still leave a running record. Such a record
never counts as PASS. NFS clock-skew warnings are retained in the build logs.
Cancellation now writes an interrupted checkpoint before process-group cleanup
and ignores a second termination signal during that cleanup. The final result
records the child's exit code and whether cleanup remains pending; the repeated
signal/TERM-ignoring-child regression passes. An external executor can still
kill a process before it handles a signal, so controller cancellation evidence
must not be mistaken for a fabricated child exit result.

The ledger records the final pass/fail/unrun matrix. Human review of that matrix,
the diff and remaining qualification boundaries is the P7 acceptance gate.
The generated `audit.py` under the corrected full-run evidence directory reads
all source configurations' terminal results, strict Tiny markers, P7 lifecycle
observations, unchanged P6 workload/wire records, JTAG, paired firmware hashes,
macro audit, netlist boot and STA artifacts. It launches no hardware flow and
writes `acceptance.json`; a pending/missing/failed input cannot produce PASS.
