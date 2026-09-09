# Final Feature Hand-off

## Verdict

State the review verdict and exactly one next action.

## Selected Profile and Commands

List the committed profile and exact commands actually run. Do not list planned
commands as completed evidence.

## Changes

### Code

Summarize RTL, firmware, testbench, model, and script changes.

### Configuration

Summarize topology, address, filelist, build profile, CI, warning, metric, and
readiness changes.

### Public Interfaces

Summarize register ABI, HAL, DMA, interrupts, buses, clocks/resets, descriptors,
and compatibility behavior.

## Validation

Report each gate as PASS, FAIL, NOT_RUN, or BLOCKED with its command and evidence
path. State applicable MISRA deviations and distinguish mechanical policy
checks from certification.

## IHP130 Synthesis and Timing

Report profile/recipe, target frequency, synthesis status, cell count, area,
STA status, WNS, TNS, evidence paths, and limitations. Use `not reported` for
missing values. State whether netlist simulation observed `Hello retroSoC!` and
whether later regression stages completed.

## Unrun Gates and Remaining Gaps

List every unrun gate with a reason. Record remaining hardware, timing, CDC/RDC,
DFT, PVT/MMMC, vendor-model, simulator, physical, qualification, and silicon
coverage gaps without overstating delivery maturity.
