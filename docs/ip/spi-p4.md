# SPI-P4 Display and Snapshot Application Qualification

SPI-P4 covers the frozen display path on top of the committed SPI-P3
integration: a project-owned ST7789VI-style four-wire adapter in
`app/board/`, an independent pin-level panel oracle in the Tiny testbench,
and the `TINY_SPI_P4_ACCEPTANCE` image covering the display-pattern and
snapshot stages. Camera/PSRAM-source display and sequential SD snapshot
evidence are sub-stage B; R2-P8/R2-P9/P10 human acceptance is recorded in
[tiny-soc-verification.md](tiny-soc-verification.md) on 2026-10-25.

## Interface contract

- Panel wiring: SCK=GPIO27 ALT0, MOSI=GPIO28 ALT1, CS_N=GPIO31 ALT1,
  D/C=GPIO30 as an ordinary push-pull software output; no MISO. CS is
  retained across each command/data boundary through held-CS segments; D/C
  changes only at clean boundaries with a GPIO readback before the next START.
- Commands are 8-bit MSB-first frames with D/C low; parameters and RGB565
  pixels are byte streams with D/C high; pixels occupy two ordinary data
  bytes, big-endian. The reference geometry is 320x240 landscape with zero
  address offsets for full-screen windows.
- Init order (sub-stage A constants for the selected panel): SWRESET, 120 ms,
  SLPOUT, 120 ms, COLMOD=0x05, MADCTL=rotation, INVON, NORON, DISPON, 20 ms.

## Stages and evidence

Sub-stage A runs discovery, GPIO/SPI configuration, acquire with GPIO_READY,
panel init, stage 1 color bars and stage 2 gradient (full 320x240), stage 3-5
odd rectangles, stage 6 rotation variant (MADCTL=0x60), and an abort/recover
case with a truncated full-frame followed by a clean final window. The QUICK
Icarus variant reduces only these A delays/full-window geometries.

Sub-stage B then releases SPI and runs, in order:

1. NSS1 PSRAM initialization/capacity validation, native-SD initialization,
   and QVGA DVP capture into `0x54010000` with prefix/suffix guards.
2. Exact DVP/DMA completion checks, camera stop, full PSRAM readback against
   the independent `(column_byte + 3 * row) & 255` camera pattern, and a
   byte-normalized RGB565 FNV-1a record.
3. SPI/DMA3 reacquisition and a direct immutable-PSRAM display, followed by an
   SRAM-source display of the same frame using 150 bounded chunks in one
   held-CS panel window and one 1024-byte workspace. The final chunk releases
   CS normally. The source remains immutable; no 150 KiB SRAM frame
   exists. Each source has cycle, instruction, utilization, FIFO and stall
   records plus passive DMA transaction/latency observations.
4. Native SD save/readback at LBA16..315 in 150 two-sector chunks with bounded
   aligned transmit/receive buffers and full comparison against both PSRAM and
   the independent camera words. SD and panel checksums use the same logical
   big-endian pixel normalization, not the different P10 word-wise checksum.
5. A bound-DMA abort after partial PSRAM display, complete drain, RECOVER,
   release/reacquire, final resource release, and TEST_STATUS before the UART
   summary. New B failures use distinct result codes 9..18.

The A abort is exactly 544 pixels and the B abort is exactly 143 pixels. The
checker rejects every other aborted prefix length, including zero and other
nonzero values, with an explicit window/actual/expected problem message.

The SPI HAL exposes checked 64-bit transport arithmetic, single-beat DMA
bind/start/wait operations, exact completion checks, and separate wire-abort
versus bound-job abort/drain operations. It reads the existing CLOCK_HZ, DIV,
FIFO and stall registers; the register ABI is unchanged. The board adapter
binds TX DMA after the CPU RAMWR command and before pixel ARM. A timeout never
releases buffer or channel ownership implicitly.

The testbench panel model (`rtl/tiny/dv/tiny_st7789_panel.sv`, active with
`+tiny_spi_p4`) decodes the pins independently and emits SPI_P4_CMD,
SPI_P4_WINDOW (geometry, pixel count, FNV-1a, abort flag), SPI_P4_VIOLATION
and a terminal SPI_P4_PANEL summary. B adds two complete QVGA camera windows
and one aborted camera prefix to A's eight windows. `scripts/spi_p4.py check`
auto-detects A or A+B, independently recomputes all checksums and validates
capture, SD, measurement and P10 bus records. Archived A-only logs remain
supported with `--version a`, optionally with `--quick`. Verdicts remain
TEST_STATUS/`SIM_TEST_PASS` with no forbidden markers.

Focused checks:

```sh
make CONFIG=<profile> APP=ci_smoke TINY_SPI_P4_ACCEPTANCE=YES \
  spi-p4-lint spi-p4-rtl spi-p4-report
```

Full A+B Verilator example (budgets are execution ceilings, not performance
limits or FPS claims):

```sh
make CONFIG=<profile> APP=ci_smoke TINY_SPI_P4_ACCEPTANCE=YES \
  TINY_SIM_TIMEOUT=300000000 SOC_SIM_TIME=28800 \
  TINY_SIM_ARGS='+tiny_spi_p4 +tiny_psram +tiny_p9_camera +tiny_p9_half_ns=500 +tiny_p10_camera' \
  firmware sim
python3 scripts/spi_p4.py check --variant-root build/<variant> --pdk <PDK> \
  --log build/<variant>/sim/verilator/sim.log
```

The live SPI DMA admission repair and its focused evidence are recorded in
[spi-verification.md](spi-verification.md). Both Verilator A+B profiles pass
`SIM_TEST_PASS` and the independent checker with zero panel violations. This
establishes the V21/V22 functional result on those profile/simulator pairs only,
not the complete simulator matrix or physical qualification.

## Icarus QUICK-A/full-B execution

Icarus reduces only sub-stage A through the committed `RS_ST7789VI_QUICK`
path. Capture, both display sources, SD save/readback and abort handling retain
the full B workload. Use the separate P9 monitor when progress visibility is
required:

```sh
make CONFIG=<profile> APP=ci_smoke SIMU=IVERILOG \
  TINY_SPI_P4_ACCEPTANCE=YES \
  TINY_SIM_TIMEOUT=300000000 SOC_SIM_TIME=288000 \
  TINY_SIM_ARGS='+tiny_spi_p4 +tiny_psram +tiny_p9_camera +tiny_p9_half_ns=500 +tiny_p10_camera +tiny_p9_monitor +tiny_p9_monitor_log=<absolute-monitor-path>' \
  firmware sim
python3 scripts/spi_p4.py check --variant-root build/<variant> --pdk <PDK> \
  --quick --log build/<variant>/sim/iverilog/sim.log
```

`SOC_SIM_TIME=288000` records the extended wall budget; the cycle ceiling stays
at 300000000. Launch long simulations detached without an outer tool timeout,
and poll the structured result and logs. Silence or slow progress is not hang
evidence.

Prefer `+tiny_p9_monitor` over `+tiny_p9_progress` for strict acceptance. The
latter shares stdout with the character-at-a-time Icarus UART observer and can
split acceptance records. The checker losslessly reassembles only complete,
well-formed progress interruptions, including their newline, while preserving
all other characters in order. Malformed observer text and truncated/corrupted
SPI records are rejected; no check is relaxed. Never edit or filter the raw log.
The committed `tiny_p9_monitor` instead writes progress to its own file and never
calls `$finish`, avoiding the hazard at its source.

## Matrix checkpoint (2026-10-26)

The exact commands, checker records and regression evidence are in the
[sub-stage B matrix checkpoint](spi-verification.md#spi-p4-sub-stage-b-matrix-checkpoint-2026-10-26).
The current verdicts are:

- PASS: ICS55 Verilator at
  `build/ics55-tiny-2026-10-25-20-05-35b6184dae5c/`, 94425948 cycles.
- PASS: IHP130 Verilator at
  `build/ihp130-tiny-2026-10-26-01-16-995377fb20d0/`, 94425948 cycles.
- PASS: ICS55 Icarus at
  `build/ics55-tiny-2026-10-26-11-19-35b6184dae5c/` completed naturally with
  `SIM_TEST_PASS Tiny cycles=53810943`, exit 0 and 121321.334 s wall time. No
  forbidden marker is present. Lossless reassembly of the progress interruptions
  preserves the full B records, and the QUICK checker exits 0 with
  `problems=[]`. The original traceback and raw log remain retained as observer
  hazard evidence.
- PASS: IHP130 Icarus at
  `build/ihp130-tiny-2026-10-26-15-20-995377fb20d0/` completed naturally with
  `SIM_TEST_PASS Tiny cycles=53810943`, exit 0 and 114295.959 s wall time. No
  forbidden marker is present, and lossless reassembly lets the QUICK checker
  pass with `problems=[]`. The interrupted 04:43 attempt remains retained
  separately as exit 130 after its outer tool timeout, not as hang evidence.
- PASS: P3 Verilator on both profiles at 1050629 cycles, under
  `build/ics55-tiny-2026-10-26-01-19-d1eafd9db70e/` and
  `build/ihp130-tiny-2026-10-26-01-20-e29716f7754c/`.

The independent review's P1 variable-abort-length finding is closed by exact
544/143 enforcement and wrong-prefix negative tests. Its P3 coverage finding is
closed by complete-window odd-byte and non-pixel residual fixtures on both
simulators. The focused suite passes 22 tests; all four accepted logs still pass.
The final full host suite reports 2124 passed and one optional `pypdf` skip.
See the [review closure](spi-verification.md#independent-review-closure-2026-10-28)
for evidence. No long simulation was rerun.

Pre-final timing stays observational under the 2026-10-07 policy; SPI-P5
remains the final physical qualification phase. Full-A Icarus geometry, a
dedicated legacy-LCD/LVGL acceptance gate, complete netlist/STA/physical
qualification and human review remain open. `phase_accepted` is false.
