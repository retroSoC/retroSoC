# Final Feature Hand-off

## Verdict

State the review verdict and exactly one next action.

## Target SoCs, Profiles, and Commands

List the feature, target SoCs, specification revisions, and the committed
profile/PDK mapping for each target. Record exact commands actually run, source
revision, and build variant. Mark a missing platform/profile explicitly;
proposed Std/Pro or other future configurations are not executable support.
Do not list planned commands as completed evidence.

## Changes

### Code

Summarize RTL, firmware, testbench, model, and script changes.
Distinguish shared-IP changes from each product's integration and identify
other affected consumers whose compatibility was checked.

### Configuration

Summarize topology, address, filelist, build profile, CI, warning, metric, and
readiness changes.

### Public Interfaces

Summarize register ABI, HAL, DMA, interrupts, buses, clocks/resets, descriptors,
and compatibility behavior.

## Validation

Report each gate as PASS, FAIL, NOT_RUN, or BLOCKED per target/profile/PDK with
its command and evidence path. State applicable MISRA deviations and distinguish
mechanical policy checks from certification. Derive CI coverage from the actual
workflow invocation and retained reports.

## Synthesis and Timing by Target

Report SoC/profile/PDK/recipe, target frequency, synthesis status, cell count,
area, STA status, WNS, TNS, source revision, build variant, evidence paths, and
limitations. Keep different configurations separate, including historical
baselines. Use `not reported` for missing values; never credit Mini results as
Tiny qualification or treat a product target as a measurement.

State the selected simulation target's required success marker and observed
verdict, command exit status, absence/presence of failure markers, and whether
subsequent stages completed. Tiny `netsim-boot` currently requires
`SIM_TEST_PASS`; the applicable Mini assembly boot-only flow uses
`Hello retroSoC!`. Verify current executable rules rather than assuming either
marker applies to every target or proves full functional acceptance.

## Unrun Gates and Remaining Gaps

List every unrun gate with a reason. Record remaining hardware, timing, CDC/RDC,
DFT, PVT/MMMC, vendor-model, simulator, physical, qualification, and silicon
coverage gaps without overstating delivery maturity.
