# Tiny R2-P1 reproducible baseline

This runbook implements the measurement boundary of
[TINY-R2-P1](tiny-soc.md#tiny-r2-p1---reproducible-baseline-constraints-and-measurements).
It does not implement the later R2 architecture. Actual results and open gates
belong in the [verification ledger](tiny-soc-verification.md). The approved
starting revision is `bfdc3ffaf6cb0a134314272ac1b0f8b504d0b09c`; uncommitted
implementation runs identify that parent **and** their retained input contents,
not a fictional clean implementation commit.

## Configuration and ownership

Use `configs/ci/ihp130-tiny.mk`, `SOC=TINY`, `PDK=IHP130`, no PLL, 24 MHz,
128 KiB macro SRAM, CSR-enabled RV32IM firmware and `ld2_all_sram`. The current
hart uses `hazard3_cpu_1port`, has C/debug enabled and A disabled, and shares a
globally serialized AXI32 fabric with four-channel central DMA. Ordinary
`bringup`/`ci_smoke` firmware and their ArchInfo identity checks are unchanged.

The separate `tiny-r2-baseline-image` target substitutes only the application
entrypoint, using the existing Tiny-selected CRT, effective `-Os`,
`-march=rv32im_zicsr -mabi=ilp32` and flat linker script. A linker map is added
as evidence, not a placement experiment. No new APP, register, SDK API, DMA
request, interrupt or capability is introduced. No managed source is edited.

QFN64/IO assignments, 128 KiB main storage and the six private Crypto banks
specified for future integration remain protected. The current Tiny source
closure has 32 main-SRAM macros and no Crypto instance; tied-off stream ports
are not Crypto integration. No CPU, banking, reset, interconnect, RCU, PSRAM,
DVP, SPI, PIO-lite or PPALite implementation is included here. Compiler/LTO
and bank-placement experiments belong to R2-P3 and later work.

## Workload and measurement contract

The image executes these seven cases in order, without enabling interrupts or
starting other DMA clients. It owns channel 3 and uses bounded waits. Each
simulator replays the **same retained HEX**, from cold reset, three times.

| ID | Case | Fixed work |
| ---: | --- | --- |
| 0 | `empty` | Empty-window instrumentation calibration; no automatic subtraction. |
| 1 | `cpu` | 4096 xorshift32 iterations, seed `0x12345678`, shifts 13/17/5; expected `0xf6e37410`. |
| 2 | `memory` | Copy 1024 words to each of 16 destinations; source word `i` is `0xa519c300 XOR i`. |
| 3 | `dma1` | Sixteen 4096-byte direct memory copies, one-beat bursts. |
| 4 | `dma16` | The same copies with up-to-16-beat bursts. |
| 5 | `contention` | The same burst-16 jobs, each with one fixed CPU kernel after START and before bounded polling. |
| 6 | `tcd` | Sixteen finite jobs, each with four linked 1024-byte hardware descriptors and the same concurrent CPU kernel. |

The source and each destination have 64-byte alignment and 16 guard words on
each side. Sixteen distinct destinations retain every job's data until full
readback after the measured window. This uses existing SRAM; the linker map
and symbol check require at least 4 KiB of remaining stack headroom. No buffer
is assigned to a particular physical macro or future 32 KiB arbitration group.

Every destination and source word is compared, and every guard is checked.
The diagnostic word-wise FNV-style unsigned modulo-2^32 hash is `0xbc5f5dc5`
over the complete 65536-byte result; it does not replace full comparison.
Descriptors are 64-byte aligned. The existing convenience TCD HAL waits for
individual descriptors in software; this image uses the existing handwritten
register ABI for one finite four-descriptor hardware submission. Hardware
`BYTES_DONE` is per descriptor: the final value is 1024, while the observed
chain payload is 4096. No scheduler or HAL semantics are changed.

Initialization, descriptor construction, full readback, hashing and all UART
reporting occur outside the seven performance windows. DMA configuration,
START, bounded polling and status checks are inside the workload envelope;
CPU kernel cycles are also reported separately. UART must drain before the
terminal status is written.

The image clears the existing performance counters, enables PERF_CTRL, reads
cycle/instruction counters using stable RV32 high/low/high reads, executes the
case, then disables/snapshots counters. Report raw cycle and instruction
deltas, CPI, kernel calls/cycles, payload bytes, CPU/DMA admission waits and
SRAM requests/beats/stalls/errors. The CSR interval and PERF_CTRL interval
have different endpoints; neither silently subtracts the other.

The testbench's `+tiny_r2_baseline` observers report:

- AXI address handshakes, accepted-address-to-B/RLAST maximum latency,
  accepted payload bytes and longest consecutive `VALID && !READY` interval
  for each of AW/W/B/AR/R, separately for CPU and DMA.
- Descriptor read bytes, using the address range taken from the retained ELF
  symbol rather than a new hardware register. For case 6, descriptor reads
  total 4096 bytes in addition to 65536 payload read and write bytes.
- AHB address acceptance and terminal data completion, separated by HPROT's
  instruction/data bit. The existing single port is not an independent I/D
  local-SRAM path. The future three-cycle local budget is not asserted here.

CPU transactions can straddle PERF_CTRL boundaries. Pending counts identify
right-censored AXI transactions; their unknown terminal latency is not zero.
DMA must have no pending transaction at each completed window. Request/response
accounting is checked. Observed maximum stalls are workload observations,
not universal service bounds. Independent-bank conflicts are unavailable on
this serialized architecture. Monitors drive no design signal and are excluded
from netlist elaboration. Icarus's optional UART decoder only observes the pad;
Verilator retains the existing accepted-TX-byte diagnostic output.

## Reproducibility and verdicts

Tool installation uses the unchanged dependency lock and an isolated cache.
Activate it before invoking the new targets:

```sh
python3 scripts/development_environment.py \
  --cache .cache/retrosoc/development/tiny-r2-p1 \
  --tool verilator --tool verible --tool sv2v --tool iverilog \
  --tool yosys --tool opensta --tool riscv_gnu bootstrap
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
```

The runner verifies archive SHA-256, installation markers and selected binary
paths, records tool versions/binary hashes, and checks the seven managed Tiny
dependencies against their clean locked revisions. A checksum mismatch is a
failure, not permission to replace the lock. Existing user installations stay
untouched. The Python requirement files are included in the input digest.

For Icarus, the selected `VVP` must resolve to `vvp` beside the verified
`iverilog` executable. A name, absolute path or symlink to that same runtime
is accepted; another installation or missing executable is rejected before
model compilation or simulation. The attempt records the runtime's absolute
path, version, binary hash and locked archive identity, launches that absolute
path, and rechecks the binary before each cold run and at final validation.
Aggregation also checks the retained runtime and each actual launch command.
Historical attempts without this identity remain historical evidence; they
cannot satisfy the repaired collector's Icarus aggregation requirement.

New image manifests retain `compiler_command` independently of disassembly,
symbol and size commands. It must match the associated `compile.json` command.
The original `image-ozwo38_b` manifest incorrectly stored the final size command
in this convenience field; its hashed `compile.json` retains the actual GCC
command. That historical manifest is not rewritten. The original image remains
usable for matched-binary replay with its original artifacts and source identity.

Use one timestamp for a source snapshot; use a new timestamp after executable
inputs change. From the repository root:

```sh
export BUILD_TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 tiny-r2-baseline-image
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 \
  SIMU=VERILATOR tiny-r2-baseline-sim
stdbuf -oL -eL make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 \
  SIMU=IVERILOG SOC_SIM_TIME=14400 tiny-r2-baseline-sim
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 tiny-r2-baseline-report
```

The image target builds normal firmware first to prepare the unchanged runtime
and linker inputs, then always compiles a new retained measurement image. The
simulation target builds a fresh model once before its three runs. Ordinary
`make --dry-run` prints these commands without executing the evidence driver.
The measurement-only cycle limit is `TINY_BASELINE_MAX_CYCLES=100000000`;
the existing `SOC_SIM_TIME` bounds each run in wall seconds (default 1800).
The pin-level Icarus command above explicitly allows 14400 seconds. The first
10800-second campaign reached the last UART result line after all seven cases
and readbacks, then timed out before terminal acceptance. Those attempts remain
failed. The larger host budget preserves the workload and binary; `stdbuf`
only makes host log output line buffered. Its GNU coreutils 8.32 executable
and preload-library hashes are retained in the timeout diagnosis. Neither the
host budget nor output buffering is a hardware operating point. Up to `min(JOBS, 3)` independent
cold-reset simulator processes run concurrently, sharing only immutable model
and firmware files. Logs and verdicts remain separate. These limits are retained
in the attempt and do not change normal Tiny acceptance or workload cycles.

Generated evidence stays under the approved variant:

```text
build/ihp130-tiny-<timestamp>-<config-hash>/
  meta/tiny-r2-p1/
    binaries/image-*/       ELF/BIN/HEX, linker map, symbols, disassembly, size
      inputs/               input hashes, source archive, worktree patch
    workloads/<simulator>/attempt-*/
      inputs/               actual RTL/generated/model inputs and source snapshot
      run-*.log             full output, flow JSON and strict verdict JSON
      attempt.json          firmware identity separate from RTL identity
    validation/             exact command logs and structured gate results
    baseline-report.json    both simulators, same image, all six successful runs
```

Attempts are never reused. A latest-attempt pointer is changed before work
starts, so a new failure cannot expose an old successful attempt as current.
Input contents are checked before/after compilation and simulation; archives
include new untracked implementation files. Reports revalidate logs, hashes,
terminal verdicts, actual runtime input contents and compiled-model identity.
All cold-start repetitions and both simulators must agree on the measured
records. A missing/failed run leaves the report incomplete and returns failure.

For later matched-binary comparisons, supply
`TINY_BASELINE_HEX=/absolute/path/to/binaries/image-.../tiny_baseline.hex` to
the simulation target. Preserve its adjacent original `image.json` and
artifacts. The image validates stable SRAM/ISA requirements, not equality to
the candidate RTL's source ID. Its original source/configuration stays recorded
separately from the new RTL source. Normal Tiny acceptance remains responsible
for candidate ArchInfo/build-identity verification. Do not rebuild and relabel
a binary as the old baseline.

Successful execution requires command exit zero, valid passing SYSCTRL
TEST_STATUS, `SIM_TEST_PASS Tiny`, complete validated workload/observer records,
and absence of the repository's forbidden markers: `FAILED`, `FATAL`,
`assertion failed`, `%Error`, `SIM_TEST_FAIL`, `SIM_TEST_TIMEOUT`. UART alone
cannot pass. The usual `check_simulation.py` verdict is retained separately.
No baseline report is a timing, power or physical qualification result.

## Clock, reset, macro and exception audit

The source-bound baseline consumes Tiny's clock inventory, not Mini's.
`u_clock_buffer/clk_o` feeds the CPU, SRAM, AXI/APB, RTC and watchdog at 24 MHz.
CLINT uses a divide-by-24 tick enable. There is no dynamic SYS/MEM/PCLK
transition, main-SRAM divider, or main-SRAM CDC in this executable baseline.
CPU WFI clock gating is not enabled by the current wrapper's XH3POWER setting.

The 32 main macros bind through
`u_soc.u_sram.gen_memory.gen_bank[0..31].u_ram.u_mem` to
`RM_IHPSG13_1P_1024x32_c2_bm_bist`, with `A_CLK` on the system clock.
The locked PDK supplies Verilog/LEF/GDS and typical 1.20 V/25 C, slow
1.08 V/125 C and fast 1.32 V/-55 C SRAM Liberty views. The physical adapter
pairs the last view with the standard-cell fast -40 C corner; record this
actual pairing, not an assumed common temperature.

The SRAM views contain setup/hold, clock-to-output and pulse-width information;
no explicit `minimum_period`/`min_period` entry was found in the selected views.
This is a characterization gap for a qualified macro maximum frequency, not
proof of a failed or supported rate. Icarus RTL uses `-gno-specify`; behavioral
results do not evaluate those timing arcs.

| Reset path | Current source behavior and endpoint |
| --- | --- |
| External reset -> `u_por_rst_sync` | Common default STAGE=3, async assertion/synchronous release; POR domain includes watchdog functional timer. |
| POR and watchdog request -> `u_system_rst_sync` | Default STAGE=3; resets fabric, SRAM control, peripherals, tick logic and debug wrapper. SRAM payload has no reset clear. |
| System/hart request -> `u_mgmt_debug_reset.u_core_rst_sync` | Default STAGE=3; waits for CPU AHB/AXI adapter idle, resets the hart/adapter and acknowledges release. |
| TRST_N -> `u_jtag_rst_sync` | Default STAGE=3 in buffered TCK domain. |
| DMI hard reset -> synchronizer -> `u_dmi_rst_sync` | System-domain default STAGE=3; Hazard3's existing async APB bridge owns the DMI crossing. |

The JSON inventory lists only system/JTAG domains and debug DMI/hard-reset
crossings. It omits the POR, hart and DMI release endpoint detail above and
the broader external-input synchronizer inventory. Passing its checker is
structural metadata evidence, not exhaustive CDC/RDC or reset-release proof.
P1 records these omissions; it does not implement the later five-local-edge,
CPU-last/domain-barrier reset contract or reduce FIFO reset load.

Core STA's generator creates a 41.666666667 ns clock at
`u_clock_buffer/clk_o` and a 100 ns JTAG port clock, declares asynchronous
groups, applies 0.2/0.1 ns setup/hold uncertainty and 0.1 ns transition, then
false-paths external reset ports and all inputs/outputs. There is no extra
generated system clock in this core-STA inventory. Its broad port exceptions
exclude board/pad and external reset timing; do not extend them to hide an
internal reset path.

The separate physical SDC creates external/JTAG clocks at pad p2c pins and
a divide-by-one generated system clock at `u_clock_buffer.u_sg13g2_buf_1/X`.
It uses 20%-period IO delay assumptions, 0.006 output load, early/late derates
0.95/1.05 and fanout 10. These assumptions are not a qualified board contract.
The historical adapter has 52 signal and 84 placed PADs; it does not qualify
the frozen QFN64 package. P1 does not run place/route or change that adapter.

After approved synthesis/STA, retain the actual consumed SDC, netlist/config,
library hashes, macro count, cell/area reports, reset-path endpoints, fanout
and setup/hold WNS/TNS. Keep tool completion separate from timing closure.
Historical -455.18 ns reset-path WNS must retain its original attribution.

The frozen future CPU/main-SRAM SYS targets remain 96/192/240 MHz, including
actual macro periods of approximately 5.208/4.167 ns at 192/240 MHz. Joint
macro/system qualification needs minimum period/pulse widths, setup/hold,
clock-to-output, bank/return paths, CTS/skew, extracted PVT and reset evidence.
XPI keeps its divided MEM ceiling and Crypto storage remains PCLK. P1 enables
none of these rates; a half-rate main-SRAM fallback is forbidden.

## Validation and acceptance boundary

Run focused baseline/parser tests and existing Tiny protocol, shared debug
reset, SRAM-capacity and register-parity tests before software/style gates,
firmware and both RTL simulators. A skipped/no-op RTL fixture is unrun coverage.

```sh
python3 -m pytest -q tests/test_tiny_r2_baseline.py tests/test_tiny.py \
  tests/test_mgmt_debug.py tests/test_dma_register_parity.py \
  tests/test_onchip_sram_register_parity.py \
  'tests/test_onchip_ram.py::test_onchip_ram_axi4_capacity_protocol_and_performance[128]'
make CONFIG=configs/ci/ihp130-tiny.mk sw-format-check sw-policy-check sw-host-test
ruff check .
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk IHP130 --dry-run
python3 -m pytest -q
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
```

The Tiny PR matrix includes SVA Verilator, full SDK Icarus, Yosys,
`netsim-boot` and OpenSTA; Tiny-filtered nightly currently adds no distinct
case. Preserve the 10800-second Yosys allowance. A failed synthesis prevents
dependent netlist/STA acceptance. Compact netlist boot is not full C netlist
coverage. Hosted `--behavioral-only` CI supplies none of these physical stages.

P1 accepts a reproducible measurement baseline and explicit attempted-gate
results, not an automatically passing product. Negative timing, external
Tiny JTAG, exhaustive reset/CDC/RDC, package, PLL/Pad, extracted PVT and silicon
qualification remain downstream gates. The current testbench ties TCK low;
shared debug-reset tests must not be relabeled external Tiny debug acceptance.
Existing warning baselines and observational metrics policy are unchanged.
No Required-rule MISRA deviation is added; formatting/policy/host tests remain
partial checks, not certification. Review is required before accepting P1 or
authorizing a new phase.
