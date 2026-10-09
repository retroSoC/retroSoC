# Tiny R2-P3 software and DMA scheduling

This implements only [TINY-R2-P3](tiny-soc.md#tiny-r2-p3---software-and-dma-scheduling).
The approved source is `bab01352f8f7c80e39546b04e3ed37a3d927f475`; actual runs
must also retain the implementation input snapshot and worktree diff. Results
and human acceptance belong in the [ledger](tiny-soc-verification.md).

The [P3 review-fix record](tiny-soc-r2-p3-review-fixes.md) documents a discovered
platform prerequisite: Mini PRODUCT central DMA has no APB/MMIO route. The
maintainer approved option A on 2026-10-08: retain the failed DMA integration
evidence, use the existing standalone DMA/WS2812 checks, and validate Mini's
supported PIO path. The Mini command below now selects explicitly labeled PIO
acceptance. It does not supply product-integrated DMA/IRQ service-budget evidence.

## Platform and experiment boundary

The primary profile is `configs/ci/ics55-tiny.mk`: Tiny, ICS55, HAVE_PLL=YES,
external SAFE24 with the PLL disabled. `configs/ci/ihp130-tiny.mk` remains the
explicit IHP130/no-PLL compatibility path. CPU and all 128 KiB main SRAM remain
on SYS24. Package, pads, IRQ/request/register ABIs and the private Crypto
storage contract are unchanged. WS2812/audio/Crypto are not added to Tiny here.

`configs/benchmark/ics55-tiny-performance.mk` inherits the primary platform
and selects `SW_ISA_PROFILE=TINY_PERF`, `SW_OPT=O2`, `SW_LTO=NO`. These are
experiment defaults, not promotion of a new CI baseline. The candidate is
`-march=rv32imc_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs -mabi=ilp32`.
The locked GNU compiler is used first. A tool replacement requires retained
failure evidence and the authorized dependency-maintenance workflow; changing
compiler identity invalidates an otherwise matched comparison.

`SW_ISA_PROFILE=COMPAT`, `SW_OPT=APP`, `SW_LTO=NO` preserve legacy selection,
including Tiny's effective `-Os`. Nondefault selections enter the canonical
variant key. No A, Zilsd, Zcb or Zcmp compiler selection, CPU parameter change,
faster operating point or half-rate SRAM is introduced.

## Placement and startup

`LINK_TYPE=ld2_all_sram` retains flat placement. `ld2_tiny_banked` partitions
the existing aperture for software experiments:

| Region | Address range | Placement |
| --- | --- | --- |
| B0/B1 | `0x30000000..0x3000ffff` | Code, interrupt paths and read-only data |
| B2 | `0x30010000..0x30017fff` | CPU data/BSS and a reserved 4 KiB stack |
| B3 | `0x30018000..0x3001ffff` | `.data.rs_dma*` and `.bss.rs_dma*` buffers/descriptors |

The banked startup walks explicit load/copy and zero tables, including DMA
initialized data and BSS. Copy boundaries are word aligned; TCDs/buffers are
64-byte aligned. Linker and ELF checks reject overflow, wrong placement and
stack overlap. The old flat linker naturally collects the annotated input
sections through its existing wildcards. These are placement regions, not
four hardware bank services; SRAM discovery still reports 32 physical macros.

Tiny performs FENCE.I after relocation. The explicit assembler extension scope
keeps compatible RV32IM compilation valid on the existing Hazard3. Known-answer
ISA probes exercise M, C and each selected bit-manipulation extension, plus
store/FENCE.I/execute on SRAM code. The ordinary acceptance faulting load is
forced to 32 bits because its trap handler advances MEPC by four bytes; a
compressed load would skip the following return. This does not change trap ABI.

## Shared ownership and finite service

`rs_dma_session_*` adds single-hart software channel leases. Keep the session
object alive until release. Conflicting acquisition, legacy channel mutation
while leased, and release while BUSY fail. The existing Mini LP/HP hardware
owner must already allow access; software leases do not provide cross-hart
isolation. Direct MMIO that bypasses the HAL remains the caller's responsibility.
START fences published source data; release fences completed DMA data. IRQ
state acknowledgement is distinct from sticky terminal channel status.

`rs_ws2812_dma_begin/service/status/cancel` operates one persistent transmitter
session in foreground context. IRQ handlers publish events; a periodic timer
also invokes service so an absent IRQ cannot disable the caller's deadline.
`now` and `deadline` are caller-defined monotonic 64-bit ticks without wrap.
RS_OK from service means progress; completion requires `status.active == false`
and `status.result == RS_OK`. The caller retains immutable pixels while active.

The session reserves channel 3 across the entire frame, temporarily selects
watermark 8, preloads at most 16 words and starts the exact frame length. On
service it reads FIFO level L and submits at most `min(remaining, 16-L)` words.
Remaining excludes preloaded and already submitted words; hardware
REMAINING_WORDS is not used as DMA credit. CPU pushes and competing frame
starts are rejected while the session owns the transmitter. DMA configuration
is fully initialized, uses the existing software request and one-beat fixed
TXDATA writes, and waits for terminal status with BUSY clear before reuse.

Channel 3 is released only after transmitter DONE, or after error recovery has
drained DMA including accepted write responses and completed transmitter abort
and reset-low. Cleanup never resets a busy channel. A stalled target returns
an error/timeout while persistent state retains ownership and buffer lifetime;
subsequent service calls may complete recovery. The blocking write_dma wrapper
uses this same engine with finite transfer and cleanup polling budgets.

Application budgets specify channel owners, maximum bursts/chunks, descriptor
count and competing targets. The fixtures use up-to-16-beat background bursts,
256-byte chunks and finite four-descriptor chains. Priority cannot preempt an
accepted AXI write, an APB FIFO wait, a 16-beat descriptor fetch or an active
XPI command. There is no cyclic/2D engine or autonomous WS2812 request sideband.
Camera/audio/XPI concurrency without a verified bound is not advertised.

## Measurements and evidence

Keep the original P1 image and provenance unchanged. It retains sixteen
destinations and cannot fit entirely in B3. P3 uses a separate compact protocol:
1024 words, four retained destinations, 4096 xorshift iterations and seed
`0x12345678`. Its complete word-wise payload hash is `0xc4a58dc5`; all source,
destination and guard words are also checked. CPU hash remains `0xf6e37410`.

The eight cases are empty-window calibration, CPU, CPU copy, DMA burst 1,
DMA burst 16, CPU/DMA contention, hardware TCD chain and 256-byte chunked DMA.
Each data case transfers 16384 bytes. Contention, TCD and chunked cases each
execute four CPU kernels, preserving CPU work when varying chunk size. The
TCD case fetches sixteen 64-byte descriptors in addition to payload bytes.
Initialization, full readback and UART reporting remain outside measurement
windows. No CPU accesses a DMA-owned destination.

Record cycles, instructions, CPI, kernel time, DMA bytes, CPU/DMA admission
waits, AHB terminal latency and AXI address-to-response latency, descriptor
bytes and longest observed backpressure. CPU transactions straddling a window
remain explicitly censored. Independent-bank conflicts are unavailable.
Retain map/ELF section sizes, stack-usage files and stack-canary observation;
observed stack depth is not a formal call-graph bound.

The compiler matrix comprises compatible Os/flat, performance O2/O3/Os with
and without LTO on flat placement, and performance O2/no-LTO/banked placement.
Every variant builds and runs ordinary Tiny acceptance, then runs its retained
P3 image for three Verilator cold starts. Compatible Os/flat, performance
O2+LTO/flat and performance O2/no-LTO/banked each additionally run three native
Icarus cold starts. Compare ISA-only, optimizer/LTO-only and placement-only
pairs explicitly; none is a matched-binary architectural improvement claim.

Shared WS2812 evidence has three explicitly different layers: production HAL
host-MMIO tests; the production-DMA/WS2812 16-entry finite-refill fixture
(33 words, occupancy credits and delayed B); and Mini PIO compatibility selected
by `WS2812_P3_ACCEPTANCE=YES`. The latter runs 4/16/33/65-word PIO frames, a real
DONE interrupt, deliberate underflow and bounded abort recovery. Its observer
checks exact word/bit order, 30-cycle symbols, 8/17-cycle high times and at least
7200 cycles of reset-low at PCLK24, and rejects any DMA START. Its verdict labels
are `WS2812_P3_MINI_PIO`, never DMA or Tiny integration acceptance.

The production crossbar diagnostic separately locks the current unsupported
Mini DMA-to-MMIO boundary. Original failed DMA firmware attempts and their
timing/descriptor observations remain historical failed evidence. At PCLK24,
eight words at 1.25 us/bit provide nominal 5760 cycles / 240 us slack; measured
product-integrated IRQ/scheduling/source/target budgets remain pending a platform
that actually supplies the DMA route, including Tiny R2-P6. Standalone BFM timing
is not CPU interrupt latency, and PIO success does not qualify that DMA budget.
No Mini fabric, DMA hardware or target-frequency change is authorized by option A.

Evidence belongs below `build/<variant>/meta/tiny-r2-p3/`: immutable attempt
directories, images with ELF/BIN/HEX/map/disassembly/symbols/stack files, normal
acceptance images, source archives and input hashes, locked tool identities,
runtime models, per-run logs/flow records, matrix records and `report.json`.
Image and model identities remain separate. The collector rejects missing,
duplicate, altered or mismatched samples; measurement_complete is not human
phase acceptance. Failed attempts and their actual budgets are retained.

## Execution

Use one timestamp for a fixed executable source; choose another after changes.
Run focused checks and software policy before long simulations. Missing tools
or skipped required fixtures cannot qualify a gate.

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
export BUILD_TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
python3 -m pytest -q tests/test_tiny_r2_p3.py tests/test_tiny.py \
  tests/test_tiny_r2_baseline.py tests/test_dma.py \
  tests/test_dma_register_parity.py tests/test_ws2812.py
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 \
  sw-format-check sw-policy-check sw-host-test \
  rtl-format-check rtl-style-check rtl-readiness-check
ruff check .
make CONFIG=configs/benchmark/ics55-tiny-performance.mk SOC=TINY PDK=ICS55 \
  SOC_SIM_TIME=21600 JOBS=3 tiny-r2-p3-matrix
make CONFIG=configs/benchmark/ics55-tiny-performance.mk SOC=TINY PDK=ICS55 tiny-r2-p3-report
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY PDK=IHP130 \
  SW_ISA_PROFILE=TINY_PERF SW_OPT=O2 SW_LTO=NO LINK_TYPE=ld2_tiny_banked \
  SIMU=VERILATOR firmware sim
make CONFIG=configs/ci/ics55.mk SOC=MINI PDK=ICS55 APP=ci_smoke \
  WS2812_P3_ACCEPTANCE=YES HAVE_CSR=YES LINK_TYPE=ld2_all_sram \
  SIMU=VERILATOR VERILATOR_SIM_ARGS=--fast-flash SOC_SIM_TIME=3600 firmware sim
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only --dry-run
python3 -m pytest -q
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --behavioral-only
git diff --check
```

For ICS55 synthesis/STA, follow the platform runbook's fresh capture/report
steps on the actual APP=ci_smoke variant. Those source-bound observations remain
separate from compiler workload variants. Tiny nightly currently expands to PR;
verify that before avoiding a duplicate long execution. Poll long Icarus groups
every 30 minutes. `TINY_P3_RESUME=YES` resumes only identical-source matrix work
after revalidating retained results; retries use new child attempts.

Tiny acceptance requires command success, TEST_STATUS/SIM_TEST_PASS and no
forbidden error markers. Mini assembly UART-only acceptance does not qualify
Tiny or these full C images. Keep warnings/metrics at their existing policy.
Pre-final negative timing is observational; no behavioral run qualifies a
physical frequency. Do not advance P4, stage/commit or publish automatically.
