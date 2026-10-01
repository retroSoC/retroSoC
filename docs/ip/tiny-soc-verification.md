# Tiny MCU Verification Record

This record accompanies the [Tiny Gen1 contract](tiny-soc.md). It describes
local implementation evidence from 2026-09-25 for the initial 24 MHz/no-PLL
baseline, not a release or silicon signoff. The working tree was uncommitted
when that evidence was collected; its recorded readiness remains `prototype`.

The baseline has two UARTs, two I2C controllers and the legacy pad mapping.
These results do not validate the 2026-09-26 QFN64 package refreeze or the
2026-09-30 shared-IP/clock/reset refreeze. The no-PLL 96 MHz / PLL 240 MHz
targets, eight-channel DMA, RNG/CRC/WS2812/Crypto, Tiny RCU, I2S/SDIO and new
clock/reset/pad integration require separate current-revision evidence. The
historical results below are retained without promotion to Gen1 qualification.

## P6 freeze and pending Gen1 verification

P6 is documentation-only. The matrix below specifies required P7-P9 coverage;
it records no newly executed RTL, firmware, formal, synthesis or timing result.
The existing committed IHP130 Tiny profile remains the 24 MHz baseline until
the implementation phases introduce reviewed configurations.

| Area | Required cases / acceptance | Evidence status |
| --- | --- | --- |
| Addresses and software | Match Mini bases for RNG/CRC/WS2812/Crypto and the SYSCTRL control entry; one RCU decode; handwritten register parity; common drivers with product-selected clock/routing context. | Pending P7/P8 |
| Package and pinmux | Exactly 64 unique perimeter pins, 32 GPIO and 16 power/ground terminals; only GPIO26 ALT0 added for WS2812; GPIO26 alternate I2C exclusion; pad-safe reset and default-interface concurrency. | Document consistency in P6; RTL/Pad evidence pending |
| DMA and fabric | Eight channels, Crypto 4/5 and I2S 6/7 concurrently, serialized channel-3 clients, three AXI32 masters, target/page/alignment errors, backpressure, abort drain, omitted endpoint rejection and IRQ propagation. | Pending P7 |
| Shared IP lifecycle | RNG unqualified/fault/duplicate handling, CRC tails and FINISH after DMA, WS2812 pulse/reset timing, Crypto six-bank init/readback/lock, AES/SHA/RSA vectors, reset/abort/zeroize and no early erasure acknowledgement. | Pending Tiny P7/P9; standalone results remain separately scoped |
| Clock profiles | Safe24, external XIN24/48/96, PLL192/240 model cases; SYS/MEM/PCLK rates; 1 MHz CLINT continuity; SDIO init at <=400 kHz and 48/48/40 MHz target rates. | Pending P8 |
| Clock commands and failures | Invalid/unsupported profile, partial/unmapped access, busy rejection, drain/CDC timeout, lock timeout, PLL stopped high/low, no mixed profile commit and consistent safe fallback. | Pending P8 |
| Reference loss | Stop XIN and observe loss of REF24/WDG progress; restore the external source and RESET_N before restart; no autonomous recovery claim. | Pending P8/board evidence |
| Reset and gating | Cold/warm/watchdog/hart/peripheral reset; five-edge local release, CPU-last ordering, WFI/IRQ/debug ungating, gated MMIO error, unilateral CDC reset, missing AUDIO clock and Crypto READY not blocking CPU startup. | Pending P8 |
| Timing-aware shared software | UART/I2C/WS2812 configuration at PCLK24/48/60; PWM CLOCK_HZ matches committed rate; shared-IP upgrade and Mini consumer compatibility; no managed-tree patch or Tiny HAL fork. | Pending shared upgrade/P8 |
| Physical and security qualification | Characterized 96 MHz input receiver, oscillator/PLL/backend, SYS240/MEM120/PCLK60 timing, CDC/RDC, reset fanout, SRAM macros, PVT/post-layout, supply/package/IO integrity and qualified entropy source. | Pending P9; no current qualified PLL profile |

Each implementation result must identify its source revision, exact profile,
PDK/library corner and build variant. Use both supported RTL simulators with
the strict SIM_TEST_PASS/result-file policy, then the relevant netlist and
physical gates. Run affected Mini regressions for shared changes without
using those results as Tiny evidence. Do not remove PLL/STA guards or revise
warning/metric baselines to relabel an unsupported or failing flow as passing.

## Configuration and artifact roots

The selected profile is `configs/ci/ihp130-tiny.mk`: IHP130, 128 KiB SRAM,
24 MHz, RV32IM firmware on an RV32IMC hart with A disabled. Runs below used
`BUILD_TIMESTAMP=2026-09-25-12-00`:

- Default `bringup`: `build/ihp130-tiny-2026-09-25-12-00-d6009644a134/`.
- `APP=ci_smoke`: `build/ihp130-tiny-2026-09-25-12-00-044d45791ef7/`.
- `APP=ci_smoke HAVE_SVA=YES`:
  `build/ihp130-tiny-2026-09-25-12-00-6874f2ffdf11/`.

Configuration digests identify settings and the dependency lock, not a clean
source revision. A release requires rerunning from its reviewed commit.

## Functional and quality checks

| Check | Evidence/boundary |
| --- | --- |
| Tiny maps and source isolation | Generated address, IRQ, pad and clock/reset inputs validate; source closure excludes Mini product RTL, RIB/RIBP and HP generation. |
| AXI fabric, both simulators | Directed tests cover competing CPU/DMA requests, W-before-AW, delayed W, response backpressure, ID/RLAST, 16-beat bursts, 4 KiB crossing, alignment, reserved regions and continued operation after errors. |
| Tiny SYSCTRL, both simulators | APB tests cover unsupported controls, partial terminal writes, sticky first status, counter snapshots, first-fault retention, W1C, RTC wake and reset. |
| Verilator full firmware | `SIM_TEST_PASS`; the CI composition also passes with SVA enabled. Pin-level NOR, compressed instructions, disabled atomics, load faults, SRAM discovery, memory/UART DMA, external timer IRQ, CLINT time, RTC, GPIO, UART1 loopback, I2C NACK and watchdog reboot are exercised. |
| Icarus full firmware | Final expanded CI firmware passes at 3,705,751 cycles, matching the SVA-enabled Verilator run. |
| Icarus synthesized boot | `netsim-boot` passes at 29,362 cycles using the compact assembly image. Covers pin-level NOR, SRAM first/last words, byte writes, UART and terminal status; does not establish full C-firmware gate-level coverage. |
| SDK gates | C formatting, embedded-C policy and host tests pass, including Tiny channel/endpoint rejection compiled from the real DMA validator. No new Required-rule MISRA deviation is recorded; these partial checks do not certify MISRA conformance. |
| Focused Python tests | 112 tests passed across Tiny, address/pad generation and build/regression tooling. Shared debug-reset and SRAM/DMA register-parity checks also pass. After fixing parameterization/publication compatibility and preparing the existing MPW/device-model inputs, all 54 non-reference failures selected for rerun pass. |
| RTL policy | Changed RTL formatting, full owned RTL style audit and readiness metadata pass. Global formatting limitations are listed below. |
| Reproducibility | Dependency lock validation, Ruff, PR/nightly dry-runs and `git diff --check` pass. Tiny source packaging exports the Tiny top, actual filelist and its core timing SDC. |

The full-firmware verdict is authoritative only when both the tool result and
`result-sim-check.json` pass. UART text alone is not sufficient. Assembly netlist
acceptance uses the same strict terminal marker policy.

## Synthesis and timing

For the CI composition, Yosys completed with the IHP130 technology libraries
and 32 `tc_sram_1024x32` banks. The `balanced` report records 207,739 cells and
9,798,326.725198 square micrometers of library area. The area includes the
instantiated memory/pad hierarchy and is not a placed die-area estimate.

OpenSTA completed with the selected slow library corner and the 41.666666667 ns
system clock. Reported setup WNS is **-455.18 ns**, setup TNS is
**-13,049,600 ns**, and hold WNS/TNS are zero. The worst path starts at the
synchronized system-reset register and reaches peripheral FIFO storage through
the high-fanout reset distribution. This is an open physical/timing issue;
24 MHz is a functional target, not a timing-qualified operating point.

Reports reside under the CI variant's `syn/yosys/rpt/` and `sta/opensta/`.
The metric collector understands the Tiny top and timestamp-prefixed Yosys JSON
reports. Metrics remain in `observe` mode; no warning or metric baseline has
been edited to accept this feature.

## Commands and remaining coverage

The build/verification commands were run with the profile and timestamp above:

```sh
make CONFIG=configs/ci/ihp130-tiny.mk doctor firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke HAVE_SVA=YES firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke SIMU=IVERILOG firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke SIMU=IVERILOG netsim-boot
make CONFIG=configs/ci/ihp130-tiny.mk APP=ci_smoke STA=OPENSTA sta
make CONFIG=configs/ci/ihp130-tiny.mk metrics package
make sw-format-check sw-policy-check sw-host-test rtl-style-check-all rtl-readiness-check
python3 -m pytest -q tests/test_tiny.py tests/test_memory_map.py tests/test_pin_map.py tests/test_script_tools.py
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

The combined IHP130 regression stops in its Mini phase because the locked
VexiiRiscv checkout is absent. Tiny can be selected independently with
`--soc TINY`, or `make CONFIG=configs/ci/ihp130-tiny.mk regress-pr`.
The initial full Pytest run completed with 1,234 passed, 26 failed, 19 skipped
and 71 errors. Parameterization/format-sensitive expectations and the Mini
publication's constant/cast parsing were corrected; the affected cases were
rerun successfully. MPW/device-model inputs and a writable test ccache resolved
additional environment failures. The remaining 16 cases require the absent
locked FLAC corpus, MLPerf Tiny models or TensorFlow oracle sources. These are
not Tiny setup dependencies. The full suite was not rerun after the focused
corrections; it is not reported as a clean full-suite pass.

The initial run, focused results, combined-regression failure and remaining
reference-input case list are retained under the CI variant's
`meta/validation/`.
Global RTL/Make formatting checks encounter existing APU/accelerator files
outside this change. Changed-file formatting is checked independently.

Remaining qualification includes reset-tree/timing closure, placement/routing,
PVT/MMMC, CDC/RDC signoff, silicon and power measurements, full C netlist
acceptance, a Tiny-specific external OpenOCD session, positive external I2C
slave transactions and comprehensive pad-level PWM/RTC coverage. Wireless,
retention, secure boot and other PDKs remain explicit deferred features.

## Shared-path migration follow-up

Mini now references the canonical shared RTL, `scripts/rtl` helpers and
`rtl/mk/software.mk` directly. The 21 Mini compatibility links and seven Tiny
helper links have been removed. Filelists, simulator/formal/synthesis rules,
Python imports, tests, publication tooling and ownership documents use the new
paths. No Git file-type changes remain. Historical warning baselines are
unchanged.

The resolved Mini `commonip.fl`, `ip.fl` and `top.fl` retain the same 299
unique sources in the same order. `netlist_support.fl` retains its two sources;
`inc.fl` adds `rtl/ip/core`. All relocated shared RTL content hashes match the
pre-migration snapshot. This follow-up changes paths, not RTL behavior or the
public hardware/software interface.

Validation after removing the links:

- 245 focused tests passed: 144 build/generator/topology/style/Tiny tests,
  96 publication/LibreLane tests and five debug-reset/SRAM simulations.
  Full-suite collection succeeds with 1,356 tests; the full suite was not
  rerun because of the reference-input gaps documented above.
- Mini `configs/ci/ihp130.mk` address/pad/topology/clock-reset checks and firmware
  build pass. Its Verilator compile reaches HP generation and stops because
  the locked VexiiRiscv checkout is missing; full Mini simulation and the
  combined regression remain unverified.
- Tiny `configs/ci/ihp130-tiny.mk`, `APP=ci_smoke HAVE_SVA=YES`, firmware and
  Verilator simulation pass again at 3,705,751 cycles. Full Icarus, synthesis
  and STA were not repeated for this path-only follow-up.
- Eleven Python CLI entrypoints work outside the repository directory.
  Mini SRAM formal filelist generation, `sv2v` conversion, filelist combination
  and dependency generation pass using the canonical shared paths, including
  the relocated SRAM header. Formal proofs were not rerun.
- Ruff, owned RTL style, readiness metadata, 251 local Markdown links and
  `git diff --check` pass. The Make formatter still reports existing EOF and
  formal-command indentation differences in APU/GA2D/formal fragments; those
  unrelated differences were preserved.

Run logs, exact commands and path snapshots are retained under
`build/ihp130-2026-09-25-12-00-9903b3d112b7/meta/validation/shared-path-migration/`.
No C register/API change or additional MISRA deviation belongs to this
follow-up; the SDK gates from the implementation record above were not rerun.

## Next review

```text
Use $retrosoc-feature-review in review mode for feature tiny-soc with Target SoCs: TINY. Review the current worktree diff against docs/ip/tiny-soc.md and docs/ip/tiny-soc-verification.md. Verify Tiny isolation, default Mini compatibility, AXI/APB/error/reset behavior and the SDK ABI. Treat the observed reset-fanout timing deficit and missing APU/NPU/VexiiRiscv inputs as explicit qualification gaps; do not claim timing closure or alter warning/metric baselines.
```
