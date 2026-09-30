# Target-specific regression and evidence

Use this reference when planning, running, diagnosing, or reviewing acceptance.
It does not authorize execution from a read-only preflight or review. Read
[engineering policy](../../../../docs/engineering.md),
[profiles](../../../../configs/README.md), the selected product's build rules,
and [regress.py](../../../../scripts/regress.py) before choosing the matrix.

## Choose and execute the matrix

Map each approved target/profile/PDK to its required focused tests, firmware,
simulation, formal, synthesis, netlist, and timing checks. Shared changes need
the affected existing consumers, not an unrelated feature rollout. Check the
current CLI's supported selectors and suite coverage; use a direct profile
target when the runner cannot represent the requested configuration.

Inspect current CI definitions and invocation filters. Hosted behavioral-only
results do not prove local full-flow acceptance. Do not hard-code that CI will
always remain behavioral-only.

These are current IHP130 PR examples, not a universal acceptance matrix:

```sh
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --netsim-boot-only
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk IHP130 --netsim-boot-only
```

Choose only the requested/affected products and run the full commands only
when execution is authorized. Capture the dry-run matrix first. Keep related
Make commands in the same variant, including a stable `BUILD_TIMESTAMP` where
needed, without mixing artifacts across later source or configuration changes.

Allow Yosys up to 180 minutes and poll/report progress at intervals no longer
than 60 seconds. Do not treat silence, buffered UART, long formal work, or a
slow Icarus run as proof of failure. Preserve concrete timeout/resource/error
evidence and establish the cause before changing the design.

## Verify verdicts and evidence

Use each target's exit status, configured success marker, structured result,
and absence of failure markers. Tiny's current boot-only target requires
`SIM_TEST_PASS`; the applicable Mini assembly boot-only target uses
`Hello retroSoC!`. Neither is a substitute for the feature's complete firmware
acceptance. Let the existing early-stop target act on its configured marker;
do not kill the entire regression. Confirm that subsequent STA, warning, and
metric stages actually completed.

Record PASS, FAIL, and NOT_RUN by target/profile/PDK, source revision, effective
configuration, tool inputs, and build variant. Include exact commands, logs,
structured results, and metric/report paths. Review warnings and metrics using
their current executable policy; do not hand-edit signatures or silently
promote observations into passes or gates.

Old runs and other targets can be labeled comparisons, not current acceptance.
Missing cell count, area, WNS/TNS, clock/frequency, or signoff evidence stays
missing. Never attach current source hashes to earlier binaries. Diagnose the
first failed step before retrying dependent stages. Physical implementation
beyond smoke synthesis/STA belongs to the separately requested
[physical-flow skill](../../retrosoc-physical-flow/SKILL.md).
