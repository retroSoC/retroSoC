# Tiny R2-P10 system performance and regression qualification

This runbook implements the approved bounded campaign for
[TINY-R2-P10](tiny-soc.md#tiny-r2-p10---system-performance-and-regression-qualification).
The source starts at `5b81dea4fe0a68aabb51f42f01422068280192b2` plus the archived
implementation worktree. The frozen specification and dependency lock remain
unchanged. The [verification ledger](tiny-soc-verification.md) records actual
results; this document is not a passing qualification report.

## Configuration and ownership

Use `configs/ci/ics55-tiny.mk` (default ICS55, PLL present) and
`configs/ci/ihp130-tiny.mk` (no-PLL compatibility). All P10 application and
performance workloads stay on SAFE24: CPU and all main SRAM use SYS24,
XPI uses MEM24, and peripheral service uses PCLK24. The independent P6 audio
reference remains 18.432 MHz. No clock transition, additional SRAM, new
register, DMA allocation, pad route, shared HAL or dependency change is
introduced. P9's DMA2/request11 and IRQ15 remain unchanged; Mini is unaffected.

`TINY_P10_ACCEPTANCE=YES APP=ci_smoke` selects only the new camera application.
It has a distinct configuration digest and rejects simultaneous P7/P8/P9
acceptance selection. The default image and ordinary application keys remain
unchanged. The audio workload uses the existing complete P6 acceptance image.
The existing `FIRMWARE_NAME=retrosoc_p10_replay` build setting isolates the
replay model from application and backend variants; old binaries keep their
original compiler, source and configuration identity.

## Fixed workloads

The `matched` stage executes each retained image once on a fresh Verilator
model. ICS55 reuses the two P3 O2/no-LTO flat/banked images referenced by the
completed P5 report; IHP130 reuses the original P1 image referenced by its
repaired report. The P1 protocol has sixteen destinations and seven cases;
P3 has four destinations and eight cases, including chunked DMA. Never compare
P1 and P3 payloads as if they were identical work.

The ICS55-only `software` stage reuses that same compiled model and executes
the other six retained P3 images once. Together the stages cover COMPAT/Os,
TINY_PERF O2/O3/Os with and without LTO, and the O2/no-LTO banked placement.
No compiler default is changed, no old binary is rebuilt, and no historical
three-repetition protocol is weakened. These new single-run results are P10
observations. P5-to-current dependency changes include the PWM revision;
whole-platform differences are not attributed exclusively to CPU/fabric RTL.

The `audio` stage executes ordinary Tiny acceptance with `+tiny_p10_audio`.
It retains both 16/24-bit, 256-frame audio cases; 33/65-word WS frames with
watermark 8 and bounded finite refills; channel-2 background copies/TCDs;
the existing pad decoders, payload/guard checks, recovery cases and independent
SDIO/central-DMA contention. Channel 3 is owned until WS wire completion.
The existing 4800-PCLK-cycle WS service limit and exact wire checks remain
required. P10 adds passive windowed transaction/concurrency observations.

The `camera` stage uses RGB565 320x240 at a 500 ns pixel half-period and the
existing pin-level camera/NSS1 PSRAM. Capture writes 153600 bytes at
`0x54010000`, checks source/DMA completion, final responses, errors and guards,
then stops capture before any processing or SD operation. CPU processing
checks every word and computes the red-component 32-bin histogram and a
word-wise modulo-32-bit FNV-style checksum. The independent oracle expects
76800 pixels and checksum `2323003269`; hashes never replace full comparison.

The original frame is saved at LBA16..315 using 150 two-sector transactions.
Two guarded, 64-byte-aligned 1024-byte SRAM buffers provide the bounce/readback
storage. Every saved chunk is read back through SDIO and compared with the
independent camera pattern. The existing 1024-sector native-card model and
its two-block command/data stimulus are reused unchanged. This is application
save/readback evidence, not direct PSRAM-to-SDIO DMA, a filesystem, card
compliance, continuous video, or physical sensor qualification.
Each SDIO operation additionally fetches a 16-byte descriptor and writes back
its 4-byte status. The 300 operations therefore add 4800 read bytes and 1200
write bytes to the AXI totals; those bytes must be reported separately from
the saved/read-back pixel payload.

## Measurement and verdict

Camera phase records separate capture, CPU processing, bounce copying,
SDIO writing, and SDIO readback/verification. Stable RV32 high/low/high reads
provide cycle/instret deltas. Initialization and UART records are outside the
windows. Firmware counters and PERF_CTRL observer boundaries differ and are
reported without automatic calibration subtraction.

`tiny_p10_observer` records actual AXI accepts, B/RLAST completions, successful
read bytes, accepted write strobes, response errors and longest channel stalls.
Initial/final pending counts preserve transactions crossing a measurement
boundary; CPU censored transactions are not zero-latency completions. Bank
overlap counts cycles with actual issues in multiple groups, while DMA beat
overlap requires simultaneous real R/W handshakes. These are testbench
observations, not new hardware counters or universal worst-case guarantees.
P4's directed tests retain the conditional three-SYS-cycle local budget.

Camera acceptance also checks 38400 source/delivered words, pixel period,
FIFO high-water and longest backpressure. It reserves 16 bytes of the existing
512-byte payload FIFO and conservatively applies the measured high-water
occupancy to the no-service budget at 1 MB/s input. Per-frame equality and
full readback establish drainage for the exercised line/blanking pattern.

Every simulation needs exit zero, exactly one terminal `SIM_TEST_PASS Tiny`,
the complete workload records and no repository forbidden error marker. An
Icarus fatal that exits zero is still a failure. UART alone cannot pass.
Every stage retains its command/results, immutable binary/model identities,
source archives and lock/tool identity. Successful replay records keep image
provenance distinct from the candidate RTL snapshot.

## Execution and evidence

Activate the verified environment; use one new timestamp after executable
inputs change. Do not run the old baseline/matrix entrypoints, which retain
their historical three-run semantics.

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
export BUILD_TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
python3 scripts/tiny_r2_p10.py --root . --pdk ICS55 \
  --timestamp "$BUILD_TIMESTAMP" --jobs 4 --stage matched --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
```

After focused tests, software gates and the selected dry-runs, execute stages
in order: `matched`, `software` (ICS55 only), `audio`, `camera`, `backend`,
`report`. Replace the dry-run invocation above with the selected stage and
omit `--dry-run`; repeat the required stages with `--pdk IHP130`. Each stage
expands explicit Tiny/profile/PDK commands. Replay/application output roots
remain separate from the ordinary backend variant.

The backend runs Verilator lint, one balanced Yosys synthesis with its existing
10800-second allowance, compact boot and DVP netlist checks, OpenSTA and
warning/metric observations. DVP reuses the boot-compiled netlist executable
only after identity checking. No netlist function or synthesis failure is
waived by observational timing policy. No physical adapter is executed.

Evidence lives below each variant's `meta/tiny-r2-p10/<stage>/`. Existing
successful stages may be reused only with `--resume` and matching sources and
artifacts. Failed/interrupted stages never silently retry or inherit an older
PASS. Stage records and streaming Make logs preserve process IDs, commands,
start/end times and terminal state. A missing PID without a successful result
is incomplete evidence. PID values belong to the launcher's process namespace;
a later isolated shell's `ps` may not see a still-live execution session.
Use the retained execution session, logs and structured terminal results
together, not a cross-namespace PID lookup alone. Poll long simulations
roughly every 30 minutes.

The P10 collector correction separates SDIO descriptor/status traffic from
pixel payload before the first camera execution. It changes only
`scripts/tiny_r2_p10.py` and `tests/test_tiny_r2_p10.py`; the already completed
matched/software/audio/backend records keep their original source identity.
For final collection across this explicit correction, use a fresh camera
timestamp and name the original campaign with `--retained-timestamp`:

```sh
python3 scripts/tiny_r2_p10.py --root . --pdk ICS55 \
  --timestamp "$BUILD_TIMESTAMP" --stage report \
  --retained-timestamp 2026-10-17-15-56 --allow-collector-update
```

These options are report-only. The reader requires identical before/after
inputs in each original execution, checks all retained artifacts, and accepts
only the two named collector/test paths as a subsequent source delta. RTL,
firmware, Make, dependency or unrelated test changes are rejected. The report
lists the original execution digest and the new validation delta separately;
it never assigns the new collector hash to an older run. Repeat with IHP130
for that profile's separate report. The original full-Pytest failures remain
recorded, alongside the focused post-correction checks.

The selected campaign can finish while full P10 acceptance remains open.
Full long Icarus firmware is explicitly deferred to final Tiny qualification;
the current PR/nightly matrix also includes P7 clock-transition cases outside
this SAFE24 performance campaign. Preserve that complete matrix as unrun
coverage instead of claiming that a filtered run passes it. Global publication
and formatting failures, warning deltas, negative STA, fresh full-system VGA,
and physical/PVT/board/sensor gaps remain explicitly attributed. Metrics stay
in observe mode; no speedup threshold, new operating point, phase acceptance,
commit, push or later-phase advancement follows from the report.

## Completed selected campaign

The 2026-10-17 execution uses `2026-10-17-15-56` for the original stages and
`2026-10-17-21-20` for the first camera executions and final reports. Both
camera runs pass the full 153600-byte capture, CPU comparison/statistics and
300-sector save/readback workload. Each image runs once; the recorded wall
durations are 6966.317 seconds (ICS55) and 5002.673 seconds (IHP130).

The final collection commands are:

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
python3 scripts/tiny_r2_p10.py --root . --pdk ICS55 \
  --timestamp 2026-10-17-21-20 --stage report \
  --retained-timestamp 2026-10-17-15-56 --allow-collector-update
python3 scripts/tiny_r2_p10.py --root . --pdk IHP130 \
  --timestamp 2026-10-17-21-20 --stage report \
  --retained-timestamp 2026-10-17-15-56 --allow-collector-update
```

Reports are retained at
`build/ics55-tiny-2026-10-17-21-20-ff4b5cef6eb5/meta/tiny-r2-p10/report/report.json`
and
`build/ihp130-tiny-2026-10-17-21-20-8232fa11e7f3/meta/tiny-r2-p10/report/report.json`.
Both have `selected_gates_complete` and `phase_accepted=false`. The ICS55
report also indexes the shared validation attempts under
`build/ics55-tiny-2026-10-17-15-56-ff4b5cef6eb5/meta/tiny-r2-p10/validation/`;
the IHP130 report does not duplicate those common checks. Read these reports
with the [ledger](tiny-soc-verification.md#tiny-r2-p10-approved-implementation-campaign-2026-10-17),
which records the full Pytest and Make-format failures, warning/STA
observations, unrun coverage, exact measured results and human acceptance gate.
An empty per-report stage-gap list does not close those broader obligations.

## P7 and VGA follow-up

The approved 2026-10-18 follow-up adds only one P7 lifecycle and one full
VGA/YUV422 Verilator execution per PDK. It reuses the existing firmware,
monitors and P9 runner. P7 starts on SAFE24 and tests its existing logical
clock profiles; VGA remains on SAFE24. No production input changes or
automatic retries are included. The original P10 matched/software/audio/
camera/backend reports stay immutable.

Capture Tiny PR and nightly dry-runs for each PDK first. Their current
expansions are identical, so a future complete matrix can avoid duplicate
execution only after checking that equivalence again. This follow-up executes
only the selected P7 command, not the whole matrix. Full Icarus stays deferred.

The retained timestamp is `2026-10-18-09-20`; use a new timestamp for any
separately approved retry. The command shapes below are already executed:

```bash
# Set P10_FOLLOWUP_STAMP only for an approved fresh execution.
for p10_pdk in ICS55 IHP130; do
  p10_make=(make --no-print-directory
    "CONFIG=configs/ci/${p10_pdk,,}-tiny.mk" SOC=TINY "PDK=$p10_pdk"
    "BUILD_TIMESTAMP=$P10_FOLLOWUP_STAMP" JOBS=4 APP=ci_smoke
    SIMU=VERILATOR TINY_P7_ACCEPTANCE=YES TINY_P10_ACCEPTANCE=NO
    LINK_TYPE=ld2_all_sram HAVE_CSR=YES HAVE_SVA=YES
    SOC_SIM_TIME=3600 TINY_SIM_TIMEOUT=6000000 TINY_SIM_ARGS=+p7_monitor)
  "${p10_make[@]}" firmware comp manifest
  # Retain ELF/HEX/model identities before using the standard sim/check recipe.
  "${p10_make[@]}" -o comp -o firmware sim
  python3 scripts/tiny_r2_p9.py run --pdk "$p10_pdk" \
    --workload VGA_YUV422 --timestamp "$P10_FOLLOWUP_STAMP" --jobs 4 \
    --pixel-half-ns 500 --max-cycles 160000000 --wall-timeout 43200
done
```

P7 uses `tiny_r2_p7.py capture-source/verify-source` and snapshots of the
generated/runtime filelists. Its full acceptance needs command success,
`SIM_TEST_PASS Tiny`, `P7_LIFECYCLE_PASS`, the selected clock-profile coverage
and no forbidden marker. `P7_COLD_RESET_PASS` belongs only to the diagnostic
early-stop probe; the normal `+p7_monitor` path executes cold-reset assertions
without that marker. Never substitute the diagnostic for full acceptance.

Per-profile follow-up directories are
`build/ics55-tiny-2026-10-18-09-20-bea5da759fbb/meta/tiny-r2-p10/follow-up/`
and `build/ihp130-tiny-2026-10-18-09-20-3f1b609b0b86/meta/tiny-r2-p10/follow-up/`.
They retain preparation, dry-runs, source/tool/runtime snapshots, pre-launch
identities and original command/collection outcomes. P9 keeps its own
`meta/tiny-r2-p9/full-frame/` records and phase ID.

The P7 runs fail their stale `0x3fff` capability expectation against current
DVP-inclusive `0x7fff`; source/binary checks bind this real failure in
`p7-failure-evidence.json`. It is not a timeout or a physical timing result.
For both passing VGA runs, `vga-verification.json` corrects only the
generated wrapper's tuple/list JSON comparison, verifies all measurements
and hashes, and retains its original collection error. Do not reuse the
generated invocation wrapper unchanged for a future campaign. No successful
raw simulation is repeated to correct collection metadata, and no failed P7
simulation becomes a pass. See the [dated follow-up ledger](tiny-soc-verification.md#tiny-r2-p10-p7-and-vga-follow-up-2026-10-18)
for actual outcomes and remaining acceptance gates.

Both follow-up `report.json` files now record completed executions with
`status=incomplete` and `phase_accepted=false`: P7 fails and VGA passes for
each PDK. The VGA runs both finish at 73938869 simulator cycles; wall times
are 13598.239 seconds for ICS55 and 9269.826 seconds for IHP130. Their FIFO
high-water is four words and longest backpressure is 489 SAFE24 cycles
(20.375 us), within the 480-us no-service budget after the 16-byte margin.
These executions close the current candidate's Verilator VGA coverage only.
P7 fixture repair, deferred full Icarus/complete regression, separate quality
repairs and final physical qualification retain their existing boundaries.

## P7 capability correction

The approved subsequent correction changes only the P7 acceptance image,
its cross-source tests and these two P10 documents. Its private
`RS_P7_EXPECTED_TARGET_CAPABILITY` is exactly `0x00007FFF`, including DVP bit
14 and excluding later targets. The original strict startup comparison and
code-1 failure semantics remain. Production RTL/HAL, register ABI, dependency
versions, configuration defaults and warning/metric policy are unchanged.

Focused tests cover production/firmware parity, old or future target masks,
weakened/removed checks and missing/ambiguous definitions. The approved order
is the focused selection, software gates, Ruff, one full Pytest, selected
matrix dry-runs, then one P7 Verilator execution per PDK. The executed shared
checks are:

```bash
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
python3 -m pytest -q tests/test_tiny_r2_p7.py \
  -k 'target_capability or register_parity'
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 \
  sw-format-check sw-policy-check sw-host-test
ruff check .
python3 -m pytest -q
git diff --check
```

The retained runner adds fresh `--basetemp` paths and a JUnit output under
the evidence directory to the Pytest commands. It preserves the complete
command and exit status for each check. Full Pytest's existing publication
failures are compared by exact failed/error node set and missing path before
allowing the independent P7 executions; they never become a global PASS.

For this completed attempt the build timestamp is `2026-10-18-14-51`.
The P7 Make arguments and split `firmware comp manifest` / `-o comp -o firmware
sim` sequence are the same as the P7 branch of the preceding follow-up,
with the new timestamp and without its VGA command. Both PDKs retain explicit
Tiny PR/nightly dry-runs first. `tiny_r2_p7.py capture-source/verify-source`,
runtime snapshots and pre-launch hashes bind the actual binaries to the
corrected source. Do not reuse an existing variant or invoke the earlier
generated follow-up wrapper. The new `run_fix.py` is a retained one-shot
invocation record, not a general retry entrypoint.

Both P7 executions pass strict Tiny status/marker checks, full profile
coverage, DMA activity during WFI gating and exactly one warm reset. ICS55
runs profiles 2/3/0; IHP130 runs 1/0 with its configured 24-MHz external
source. Their behavioral results do not qualify physical operating points.
The [correction ledger](tiny-soc-verification.md#tiny-r2-p10-p7-capability-correction-2026-10-18)
records durations, counts, shared check outcomes and retained gaps.

Evidence is under each new P7 variant's
`meta/tiny-r2-p10/p7-capability-fix/`: ICS55 uses digest `bea5da759fbb`,
IHP130 uses `3f1b609b0b86`. The ICS55 directory also holds the shared
`validation/` and `pre-edit.json`. Final reports preserve the original failed
P7 attempts, new passing P7 executions and retained passing VGA executions
as separate records. Their status is `selected_followup_complete`, while
`phase_accepted` remains false.

VGA reuse is a separate consumed-input audit. Before editing, validate its
original source/build/launch/verdict and preserve all artifact identities.
After editing, check the exact source delta, actual GCC application sources,
unchanged shared headers/linker/build rules/metadata inputs, runtime filelists
and tool/binary identities. The only changed entry in VGA's broad input map
is the unconsumed P7 application C source. P7 tests and these documents are
outside its compilation. Keep the old execution digest; do not call the old
validator with fabricated current hashes, expand collector allowances or
overwrite previous reports. Any consumed-input change requires reassessment,
not an automatic long VGA replay. This correction performs no VGA replay.

## Quality-gate repair

This approved follow-up repairs the existing publication/Make quality gaps
without altering hardware or the passed P7 acceptance image. The publication
metadata uses the shared PSRAM model path and binds the current DVP channel
selector while preserving Mini's bulk allocation. The explicitly approved
two-file extension updates the DVP circuit's configuration packet/epoch and
applied register, plus focused tests. The historical publication SHA, document
identity, chapter structure, delivered PDFs and strict snapshot checks remain
unchanged. Source/extractor tests are not a refreshed PDF qualification.

The formatter is the locked mbake 1.4.6 with the existing `.bake.toml`.
Only one final LF is removed from each of `Makefile`,
`app/apps/ci_smoke/tiny.mk`, `rtl/mini/mk/verilator.mk` and
`rtl/mk/software.mk`; every other byte is preserved relative to the starting
worktree. `.editorconfig`'s differing final-newline setting is retained as a
separate policy issue. Never broaden this operation to all source files or
change the formatter policy to hide the original failure.

The recorded commands use the existing environment and timestamp
`2026-10-18-17-28`. This is a completed attempt; any separately approved new
execution needs a fresh variant. The focused publication selection was run
after each concrete correction, preserving its initial DVP binding failure
and the subsequent isolated-fixture dependency failure. Only one full Pytest
execution is performed, after the final focused checks pass:

```bash
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
mbake format --config .bake.toml Makefile app/apps/ci_smoke/tiny.mk \
  rtl/mini/mk/verilator.mk rtl/mk/software.mk
python3 -m pytest -q \
  tests/test_publication_{programming,system,dev_snapshot,diagrams,full_diagrams,retrieval,v05}.py
python3 -m pytest -q tests/test_script_tools.py \
  -k 'make_dry_run_and_validation_do_not_write_filelists or format_file_scope_is_tracked_and_self_owned'
python3 -m pytest -q tests/test_tiny.py -k rejects_incompatible_profiles
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 \
  format-check sw-policy-check sw-host-test
ruff check .
python3 -m pytest -q
git diff --check
```

The retained invocation records add the fixed build timestamp, build-local
Pytest `--basetemp` paths and a JUnit output. They include each command and
exit status; failed attempts stay failed. Both Tiny PDKs and the existing
Mini/IHP130 consumer retain explicit PR/nightly `scripts/regress.py --dry-run`
records with `--soc` and `--pdk`; no full matrix is started by those checks.

Capture `config` and `-n firmware` before and after the Make normalization
with the same timestamp/arguments and absent firmware outputs. Capture
`-n rtl-lint` for the Mini Verilator consumer as well. Require byte-identical
command output before executing these five firmware-only builds:

```bash
export BUILD_TIMESTAMP=2026-10-18-17-28
for pdk in ICS55 IHP130; do
  quality_make=(make --no-print-directory "CONFIG=configs/ci/${pdk,,}-tiny.mk"
    SOC=TINY "PDK=$pdk" "BUILD_TIMESTAMP=$BUILD_TIMESTAMP"
    JOBS=4 APP=ci_smoke SIMU=VERILATOR HAVE_CSR=YES
    LINK_TYPE=ld2_all_sram TINY_P8_ACCEPTANCE=NO
    TINY_P9_QUICK=NO TINY_P10_ACCEPTANCE=NO)
  "${quality_make[@]}" HAVE_SVA=YES TINY_P7_ACCEPTANCE=YES \
    TINY_P9_ACCEPTANCE=NO firmware
  "${quality_make[@]}" HAVE_SVA=NO TINY_P7_ACCEPTANCE=NO \
    TINY_P9_ACCEPTANCE=YES TINY_P9_WORKLOAD=VGA_YUV422 firmware
done
make --no-print-directory CONFIG=configs/ci/ihp130.mk SOC=MINI PDK=IHP130 \
  SIMU=VERILATOR APP=ci_smoke JOBS=4 \
  BUILD_TIMESTAMP="$BUILD_TIMESTAMP" firmware
```

The independent firmware builds finish while the publication issue is being
resolved. Its later approved diagram/test delta is recorded separately and
does not alter compiler inputs. All four Tiny HEX images match their retained
P7/VGA images byte-for-byte. New ELF/debug identities are retained separately;
old images and simulation reports are not overwritten or relabeled. Verify
the original simulator/runtime inputs and reports before recording reuse.
No P7/VGA simulator is rebuilt or rerun for this repair.

The aggregate output is
`build/ics55-tiny-2026-10-18-17-28-bea5da759fbb/meta/tiny-r2-p10/quality-repair/`.
`approved-extension.json` records the explicit ten-file authorization;
`command-equivalence.json`, per-variant `firmware-record.json`,
`retained-evidence-audit.json` and `report.json` bind the result. The scripts
there are immutable invocation/evidence records, not generic retry commands.
The [dated ledger](tiny-soc-verification.md#tiny-r2-p10-quality-gate-repair-2026-10-18)
records the final 2031-pass/one-optional-skip result and preserves earlier
failure attribution. `quality_repair_complete` does not accept P10: complete
hardware regression, final qualification and publication/PDF readiness retain
their separate boundaries. No commit, push or phase advancement follows.
