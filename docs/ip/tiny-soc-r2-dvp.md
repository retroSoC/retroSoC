# Tiny R2-P9 DVP camera integration

This runbook records the Tiny R2-P9 DVP implementation at the source revision
that supplies the evidence. It uses the shared DVP V2 ABI at `0x1000E000`,
IRQ15, request `DVP_RX=11`, and Tiny DMA channel 2. GPIO12-23 ALT1 is the
exclusive camera profile; GPIO23 is the existing RCU CLKOUT/CAM_XCLK output.

The first workflow is a single snapshot into initialized XPI NSS1 PSRAM,
followed by complete readback and guard checks. RGB565 and YUV422 use exact
`2 * width * height` byte counts. Even active widths use DMA; odd widths use
the DVP RXDATA PIO helper. A successful frame requires DVP frame completion,
DMA completion with the exact byte count, drained destination responses and no
DVP, DMA or XPI error. The success path does not abort or flush the final FIFO
tail.

The deterministic camera model is `rtl/tiny/dv/tiny_dvp_camera.sv`. Its
dimensions, pixel pattern, PIXCLK loss and frame timing are recorded with each
run. Verification observers record accepted/delivered words, pending FIFO
high-water, longest backpressure and the tested service deadline. These values
are simulation observations, not hardware counters or a continuous-FPS claim.

Use the explicit profile commands below after generating the firmware and
filelists. Set `P9_MONITOR_LOG` to an absolute file in the selected new
variant's `meta/tiny-r2-p9/` evidence directory; create its parent first.
Use distinct files for separate attempts/profiles:

```sh
make CONFIG=configs/ci/ics55-tiny.mk APP=ci_smoke \
  TINY_P9_ACCEPTANCE=YES SIMU=VERILATOR \
  SOC_SIM_TIME=10800 TINY_SIM_TIMEOUT=40000000 \
  TINY_SIM_ARGS="+tiny_psram +tiny_p9_camera +tiny_p9_half_ns=500 +tiny_p9_monitor +tiny_p9_monitor_log=${P9_MONITOR_LOG:?set an evidence log path}" firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke \
  TINY_P9_ACCEPTANCE=YES SIMU=VERILATOR \
  SOC_SIM_TIME=10800 TINY_SIM_TIMEOUT=40000000 \
  TINY_SIM_ARGS="+tiny_psram +tiny_p9_camera +tiny_p9_half_ns=500 +tiny_p9_monitor +tiny_p9_monitor_log=${P9_MONITOR_LOG:?set an evidence log path}" firmware sim
```

`tiny_psram` populates the shared NSS1 device without enabling P8's workload
verdict. The legacy `tiny_p8_psram` still populates it and requires P8's four
performance windows and mapped-write evidence; keep that flag for P8 runs.
Both modes retain the shared active-CS timing check and `p8_absent` wiring.
Do not use `tiny_p8_psram` for P9 acceptance.

`tiny_p9_monitor` reports native-domain cumulative counters every 100000 REF
cycles without terminating the simulation. It is mutually exclusive with
`tiny_p9_diag*` and legacy serial-UART `tiny_p9_progress`. Diagnostic runs
stop early (including the 5000000-cycle guard) and cannot qualify a full
capture. The monitor reports camera VSYNC, DVP frame events and FIFO words,
DMA2 confirmed bytes/remaining/error, XPI handshakes/errors and CPU bus
completions. Samples carry their REF timestamps; they are not an atomic CDC
snapshot, retired-instruction count or physical measurement. XPI read counts
include boot NOR traffic; use interval deltas and frame readback for attribution.
Progress is written to the required `tiny_p9_monitor_log` file, never to the
character-stream UART console. Missing/unwritable log paths fail closed.

At the 1 MHz camera rate, QVGA VSYNC spacing is 153843 pixel clocks. A capture
armed around 107 ms cannot finish before approximately 308 ms; the old 172 ms
diagnostic window was insufficient. The 40000000-cycle/10800-second caps
reserve startup/frame alignment, capture, 12000000 cycles for full readback,
two further camera periods for PIO alignment/completion, and drain margin.
Readback is a planning allowance, not measured throughput. Run one explicit
profile once, retain any failure and diagnose before retrying; listing the
compatibility command above does not require another long replay. Keep one
fresh BUILD_TIMESTAMP through preparation, build and run and capture source
identity before compilation.

The full long-running Icarus Tiny firmware campaign remains deferred to the
final Tiny qualification phase. Focused DVP tests may run in both simulators;
full firmware results must retain command status, `TEST_STATUS`,
`SIM_TEST_PASS`, and the forbidden-error-marker scan. CPU-less focused benches
use command status, their explicit `SIM_TEST_PASS` and the same error scan;
they do not supply TEST_STATUS or replace firmware acceptance. UART text alone
is not acceptance evidence.

The short `tests/rtl/tiny_r2_p9_dma_tb.sv` fixture bypasses NOR boot and reuses
the production DVP/DMA blocks, including Tiny's actual DMA parameters. It
checks an even-width DMA frame, delayed final word/AXI response, late SLVERR,
odd-width PIO and consecutive toggle events. The sink is a controllable AXI
memory at an NSS1-window address, not the XPI controller or serial PSRAM.
Each simulator compiles once and reuses its executable for the SLVERR case:

The remediation adds a second backend using `apb4_xpi` and the pin-level
`ESP_PSRAM64H` model. It initializes the device through APB commands, writes
canaries through mapped AXI, captures a 16x8 RGB565 frame through the production
DVP and DMA2, then reads all 256 bytes and both canaries through serial PSRAM.
The shared fixture also checks a 7x3 PIO frame. The controlled backend retains
the delayed response/error and stopped-high/low pixel-clock recovery cases.
These benches bypass CPU boot, product pads, fabric and RCU; they are not a
full-SoC or physical result.

The top-level camera model now defaults to a 500 ns half-period (1 MHz input),
with `+tiny_p9_half_ns=<positive integer>` available for explicitly recorded
experiments. This is a candidate model rate, not a sensor qualification.
The external P6 codec drivers release GPIO15 (DIN loopback) and GPIO17
(audio reference) to high impedance when `+tiny_p9_camera` selects the camera
population. The audio oscillator/startup checks remain unchanged for other
workloads. GPIO ALT selection inside the SoC cannot disconnect these external
testbench drivers, so both board population and internal routing are required.

`tests/test_tiny_p9_pad_isolation.py` extracts the actual audio startup/drivers,
camera assignments and generated pad/DVP bindings into a small fixture. It
uses the production `tc_io_tri_full_pad` and `dvp_core`, with native ICS55 IO
in Icarus and the existing functional IO model in Verilator. Each backend
compiles once for an audio compatibility case, a 512-combination byte/audio
sweep, a 16x8 camera frame and negative legacy-driver collisions (combined
codec wiring and audio-clock-only injection). The frame
checks all 64 words and first word `0x02030001`. The fixture does not instantiate
the CPU, full GPIO controller, DMA, XPI or PSRAM, and does not qualify the
full-frame memory readback or physical pad timing.

Every frame uses byte `(column_byte + 3 * row) & 255`, independent of frame
sequence. The odd-width firmware case crops 7x3 from the same sensor geometry.
Firmware checks every payload word and guards. `tiny_p9_observers.svh` emits
separate `P9_OBSERVATION` records from real FIFO handshakes, including PIO
pops; firmware no longer prints zero-valued measurement placeholders.
`measurements()` parses records only; `validate_run()` additionally requires
successful command status, matching log digest and captured source/configuration
identity before a result can be accepted. Missing observations are an error.

The review follow-up adds same-configuration rearm, pending-control/armed RCU
admission, native reset confirmation and paired/repeated error-notification
cases to the same controlled binary. The native-reset fixture extracts the
actual global boot expression and generated DVP local-reset binding; it holds
other boot prerequisites satisfied. This checks independence from PIXCLK,
not a full-SoC boot session. The C MMIO model delays control application and
checks repeated Tiny/Mini DMA/PIO calls plus side-effect-free busy rejection.

The START/ABORT ordering follow-up reuses that binary with `+abort_order`,
`+abort_active` and `+abort_applied`. It checks stopped-high/low PIXCLK, an
in-flight START and a START queued behind W1C, repeated/coalesced commands,
the configuration application pipeline, and ABORT progress while an active
frame blocks a pending configuration. A subsequent START queued after ABORT
must still work. Each scenario checks that old requests cannot restart frame
events or leave FIFO payload, then verifies complete PIO readback after rearm.
These remain focused behavioral checks, separate from full firmware acceptance.

For firmware evidence, call `prepare_build()` before compilation into a new
variant, retain the before/after source snapshots and successful command
results, then call `capture_build()` to freeze ELF, HEX and simulator hashes.
`validate_run(..., build=...)` requires that build record, checks the current
artifact bytes, and matches the simulator and `+firmware=` launch paths. A new
source dictionary cannot relabel an old compiled artifact. A build record
without a passing simulation remains build evidence only.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q \
  tests/test_dvp.py tests/test_tiny_r2_p9.py tests/test_tiny_r2_p9_evidence.py \
  tests/test_tiny_r2_p6.py \
  -k 'not p6 or dma_sdk_request_matrix or reset_and_macro_policy'
make sw-format-check sw-policy-check sw-host-test \
  rtl-format-check rtl-style-check-all rtl-readiness-check-all
make CONFIG=configs/ci/ics55-tiny.mk APP=ci_smoke TINY_P9_ACCEPTANCE=YES \
  BUILD_TIMESTAMP=2026-10-15-15-25 firmware
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke TINY_P9_ACCEPTANCE=YES \
  BUILD_TIMESTAMP=2026-10-15-15-25 firmware
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
```

See the [verification ledger](tiny-soc-verification.md#p9-focused-integration-follow-up-2026-10-15-uncommitted-worktree)
for actual results, failed probes and remaining P9 acceptance gaps. These
focused tests do not qualify sensor rates or full camera-to-PSRAM transport.

The word-count correction uses a 32-bit counter and a 144-bit statistics
mailbox while preserving the V2 ABI, 512-byte FIFO and 128-bit configuration
channel. `tests/test_dvp_stats.py` checks real pixel input through the shared
DVP wrapper, CDC and APB at 65535, 65536 and 153600 words, including an
odd-width 65536-word frame, a stopped/resumed host clock and a subsequent
small frame. These CPU-less boundary tests do not replace the full VGA/YUV422
PSRAM campaign. Retain the earlier QVGA pass with its original source identity;
do not relabel it as a full-SoC pass for the widened statistics path.

Evidence belongs under `build/<profile>-<timestamp>-<config-hash>/meta/tiny-r2-p9/`.
Physical sensor, package, PVT, IO timing, PLL characterization and continuous
video qualification remain outside this phase.

## Row-size remediation

The source checks every complete row against the configured source width,
including rows outside a crop. The directed `+row_geometry` case sends
6+2 and 2+6 pixel rows for a 4x2 configuration, then short/long rows inside
and outside an 8x4 source's crop, in both wire formats. It checks SIZE and
the error IRQ, clears/rearms, and verifies a complete good PIO frame after
each of the twelve faults. Host tests separately reject SIZE even with
otherwise matching DMA/PIO completion counts on Tiny and Mini bindings.
The statistics fixture includes a legal 65535-pixel source row, odd-width
padding and full 640x480 capture.

This RTL change requires fresh synthesis and netlist-function evidence;
previous binaries/netlists remain tied to their original source. The approved
reduced follow-up runs RECOVERY and QVGA once per PDK and current-RTL full-size
focused tests. Earlier full-SoC VGA remains historical, not a new-source run.
See the verification ledger for actual command outcomes and open gates.

## Source-bound VGA/YUV422 campaign

`TINY_P9_WORKLOAD=VGA_YUV422` selects 640x480, format 1, 307200 pixels,
153600 words and 614400 bytes. The default QVGA_RGB565 and optional quick
path remain available; QUICK cannot be combined with VGA. The application
uses the existing SRAM-resident boot and initializes NSS1 PSRAM before writing
the frame at 0x54010000. It checks the exact HAL completion, every payload
word, both guards and XPI error state, then rearms for the existing 7x3 RGB565
PIO crop from the VGA sensor geometry. That second capture checks format
change/rearm and odd-row padding, not another full DMA frame.

The unchanged camera emits `(column_byte + 3 * row) & 255` at the selected
pixel clock. This is deterministic raw YUV422 byte transport, not sensor color
calibration or image-quality qualification. The parser requires the selected
format/geometry, exact WORD_COUNT/PIXEL_COUNT, zero XPI error, full readback,
guards, matching FIFO observations and the strict terminal verdict. The launch
must include the matching camera geometry and half-period; quick, stopped-clock
and early-stop diagnostics cannot qualify this workload.

The following entrypoint builds fresh artifacts and executes exactly once:

```sh
P9_STAMP="$(date +%Y-%m-%d-%H-%M)"
python3 scripts/tiny_r2_p9.py run \
  --pdk ICS55 --workload VGA_YUV422 --timestamp "$P9_STAMP" \
  --jobs 4 --pixel-half-ns 500 --max-cycles 160000000 --wall-timeout 43200
python3 scripts/tiny_r2_p9.py run \
  --pdk IHP130 --workload VGA_YUV422 --timestamp "$P9_STAMP" \
  --jobs 4 --pixel-half-ns 500 --max-cycles 160000000 --wall-timeout 43200
```

Each invocation selects its committed Tiny profile, SOC=TINY, explicit PDK,
APP=ci_smoke, TINY_P9_ACCEPTANCE=YES, TINY_P9_QUICK=NO, SIMU=VERILATOR and
SAFE24. It refuses an existing evidence directory or pre-existing build outputs.
After filelist/manifest generation it archives inputs before compilation,
captures ELF/HEX/model identities, then launches through run_flow.py with
durable result JSON and a separate passive progress log. Input and artifact
checks run again at completion. Tool executable hashes are retained; this
entrypoint does not claim a fresh verification of downloaded tool archives.
It does not retry a failure or accept the whole P9 phase.

Results are under the new variant's `meta/tiny-r2-p9/full-frame/`: source,
prepared-build.json, build-identity.json, tool-identity.json, launch.json,
console.log, progress.log, result-sim.json, result-sim-check.json,
bound-result.json and assessment.json. A running/interrupted record is not
a pass. Keep the timestamp and source unchanged throughout both campaigns.

At a 500 ns half-period VGA VSYNC spacing is 614883 pixel clocks, about
0.615 seconds. The limits above reserve multiple alignment/capture intervals,
complete serial readback and the PIO follow-up; they are execution ceilings,
not measured duration. A completely empty 512-byte FIFO would fill in about
512 microseconds at this byte rate without service. Use actual occupancy and
native-clock backpressure observations to report tested margins, not a
worst-case guarantee. Observe long-run progress every 30 minutes; preserve
and diagnose any failed attempt before deciding on another execution.

These runs do not replace current-source QVGA replay, the remaining P9
product-level error/recovery matrix, broader regression, synthesis/mapping,
netlist-function checks or physical qualification. Pre-final STA remains
observational. Full long Icarus stays deferred to final Tiny qualification.

## Remaining-acceptance campaign

`TINY_P9_WORKLOAD=RECOVERY` selects the new small validation application and
its own digest. The campaign uses `--workload RECOVERY`, adding
`+tiny_p9_small +tiny_p9_recovery`. The opt-in board observer consumes
`P9_CTRL` UART writes to select external camera/audio population and stop or
resume the camera model clock. It does not force DUT registers or internal
clocks. With recovery absent, existing camera/audio population behavior is
unchanged. The parser requires all seven cases, six validated captures and
IRQs, both stopped-clock rejection diagnostics, eight board controls and two
decoded audio sessions. The verification ledger records passing full firmware
executions on both PDKs, including the initial failed attempts and their
validation-firmware/observer corrections.

The new `netsim-dvp` target uses `app/asm/tiny_p9_netlist.S` to route GPIO
camera inputs, check the DVP ABI, capture 16x8 via PIO, verify all 64 words
and statistics, then write TEST_STATUS. It shares the mapped netlist with
`netsim-boot` but writes separate `netl/dvp/` logs and uses a 300000-cycle guard.
`TINY_P9_NETLIST_WALL_TIMEOUT` defaults to 14400 seconds for ICS55 and 7200
for IHP130, matching this campaign's explicit measured-speed budgets. The
original 1800-second IHP130 attempt timed out, while the identical compact image
passes a Verilator diagnostic in 177716 cycles. Mapped DVP completion is
recorded as passing for both PDKs in the verification ledger; this check does
not substitute for full frame DMA. Use `SIMU=IVERILOG SYNTH=NONE` for netlist simulation so ICS55
selects functional PDK models, retaining the same timestamp and synthesized
netlist. `SYNTH=YOSYS` is the synthesis-stage selection.

The new `+xpi_protection` focused case exposed a shared XPI first-error
event/metadata cycle mismatch in both simulators. The verification ledger
records the failure and the subsequent reviewed correction, followed by the
completed RECOVERY/QVGA, synthesis/netlist and observational STA campaign.
Keep
historical VGA evidence under its original identity and document the impact
of subsequent error-report-only RTL and opt-in board-control changes.

The `+service_budget +pixel_half_ns=500` controlled fixture exercises a
480-byte interval without consumer service and then checks every retained
word and the frame tail. At the pause boundary one word is still in the
source output register; it is verified after the external pixel clock
resumes, not misread from an empty FIFO. A second frame exceeds FIFO capacity
without service and must report overflow, followed by bounded cleanup.
The fixture reserves a conservative 16-byte margin for the source output
word, byte/pixel packing and clock-domain observation skew. No DMA buffering
is credited as extra FIFO capacity. The nominal empty-FIFO admission limit
is therefore 496 us at 1 MHz active input; the positive case uses 480 us.
This finite directed test and the full-frame high-water/backpressure records
support the selected no-contention model workload, not arbitrary competing
XPI traffic, a physical sensor rate, or a continuous-FPS guarantee.

The RECOVERY image is deliberately small (16x8 source with a nonzero 8x4
crop), preserving the original serial PSRAM model and full CPU/pad/fabric
path. Each profile uses one campaign invocation:

```sh
python3 scripts/tiny_r2_p9.py run --pdk ICS55 --workload RECOVERY --timestamp YYYY-MM-DD-HH-MM --jobs 4 --pixel-half-ns 500 --max-cycles 20000000 --wall-timeout 7200
python3 scripts/tiny_r2_p9.py run --pdk IHP130 --workload RECOVERY --timestamp YYYY-MM-DD-HH-MM --jobs 4 --pixel-half-ns 500 --max-cycles 20000000 --wall-timeout 7200
```

Replace the timestamp placeholder with one new concrete timestamp. This is
the accepted execution plan, not a statement that either run has passed;
the verification ledger and source-bound assessment own the actual verdict.
