---
name: retrosoc-feature-review
description: Diagnose failures, review SoC/IP changes against frozen specifications, and summarize validation or PPA evidence for any retroSoC series. Use for root cause, spec compliance, P0-P3 findings, and delivery readiness. Keep review read-only and distinguish target-specific evidence.
---

# retroSoC Feature Review

Produce an evidence-backed verdict without turning review into an unapproved
implementation or architecture change.

## Inputs and modes

Require a feature slug, `Target SoCs` (one series or an explicit list), and one mode:

- `diagnose`: locate the first failing step and establish root cause;
- `review`: compare one PR or diff with its frozen specification;
- `finalize`: summarize verified delivery evidence and gaps.

For review, require a PR number, commit range, or explicit diff. For finalize,
require the relevant logs, structured results, and report paths. If evidence is
missing, report it as missing; do not reconstruct numbers from memory.

## Resolve inputs

Resolve input in this order:

1. explicit fields in the current prompt;
2. an unambiguous action in the current prompt;
3. the current conversation and its explicitly approved hand-off;
4. an explicit `docs/ip/<feature>.md` path;
5. one unique matching repository specification or evidence set.

Map `diagnose` or `root cause` to `diagnose`, `review` or `audit` to `review`,
and `finalize` or `final summary` to `finalize`. Ask the user only when more than
one interpretation remains. Derive the feature slug from an explicit field or
specification path and keep its frozen lowercase kebab-case value. Do not infer
approval, a diff range, or a failure artifact when multiple candidates exist.

## Resolve target SoCs and evidence

Resolve `Target SoCs` from the current request, approved hand-off, frozen
specification, or selected committed profiles. Do not default to Mini or
expand an ambiguous request to all products. Inspect the current product
contracts, profiles, and build/regression rules; ask only for unresolved target
ambiguity. Report a target/profile/specification conflict without silently
substituting another series.

Read `docs/soc-family-positioning.md` to distinguish supported baselines from
roadmap targets, and verify executable support in the repository. Std/Pro
planning can be reviewed without an executable platform, but missing profiles
and validation must remain explicit gaps. Do not infer support from a family
name or a proposed configuration.

Resolve each target's architecture, topology/address map, filelist, and software
composition. Mini LP/HP assumptions, bus widths, DMA/IRQ allocations, and
clock/reset behavior apply only where that product's contract requires them.
For shared-IP changes, inspect compatibility of affected existing consumers
as well as the requested integration; do not demand an unrelated feature rollout.

Bind every evidence claim to its target SoC, profile, PDK, source revision, and
build variant. Reports for another product, an older revision, or a different
configuration may provide labeled baseline comparisons but cannot prove the
current target passes. Preserve frozen phase IDs/titles, including `TINY-P4`,
and relate findings to the applicable target and phase where available.

## Additional constraints

Normalize prompt-specific constraints as `MUST`, `MUST NOT`, `PREFER`,
`DEFER`, and `ACCEPTANCE`. Review normative behavior against the frozen
specification and any extra constraints explicitly included in the approved
task hand-off. Treat an unapproved temporary constraint as context, not as a
new requirement. Report any conflict that requires specification refreeze or
architecture approval.

## Establish scope

Read `AGENTS.md`, `docs/ip/<feature>.md`, an optional verification companion,
relevant subsystem guides, and executable build/regression configuration.
Inspect only the change under review plus the minimum surrounding code required
to prove a finding. Preserve the distinction between pre-existing repository
debt and a regression introduced by the change.

All modes are read-only. Do not patch files, regenerate baselines, change
configuration, or start a broad refactor. Route confirmed fixes to
`$retrosoc-feature-implementation` with the exact root cause and
acceptance test.

When diagnosing regression failures or checking acceptance evidence, read the
[regression reference](../retrosoc-feature-implementation/references/regression.md).
For a style/naming/structural migration diff, also read the
[behavior-preserving migration reference](../retrosoc-feature-implementation/references/rtl-migration.md).
Use their evidence criteria in read-only mode; neither reference authorizes
running the implementation workflow, rewriting sources, or regenerating results.

## Diagnose mode

Identify:

1. the first failing command or gate;
2. the exact error, failure marker, timeout, or resource evidence;
3. whether earlier stages completed successfully;
4. whether the failure is deterministic;
5. the smallest repository or environment boundary that explains it;
6. the test that would prove a fix.

Do not treat missing terminal UART output, a silent Yosys process, formal
runtime, or a long Icarus netlist simulation as failure by itself. Respect the
known buffered Verilator output condition and use structured `result-*.json`,
logs, and configured verdict markers. Allow Yosys up to 180 minutes before
calling it timed out, with progress polling no longer than 60 seconds.

If root cause is not established, return `BLOCKED` or recommend a focused
diagnostic. Do not modify the design speculatively.

## Review mode

Review only the changes introduced by the selected range. Check:

- frozen requirements and explicit non-goals;
- target/profile consistency, shared-IP compatibility, and product-specific integration;
- AXI4/APB4 protocol and software-visible register semantics;
- DMA, interrupt, FIFO, timeout, abort, and error corner cases;
- clock/reset, unilateral reset, CDC/RDC, lifecycle, and isolation;
- handwritten SVH/C register parity and compatibility;
- synthesis behavior, widths/signs, state, inferred storage, and timing risk;
- assertions, simulation models, firmware, negative tests, and documentation;
- regression definitions, warning/metric policy, and truthful evidence claims.

Classify actionable findings:

- `P0`: data loss, security/safety boundary break, destructive behavior, or a
  release result that is fundamentally invalid;
- `P1`: functional/protocol/ABI failure, missing required verification, or a
  regression that blocks merge;
- `P2`: material robustness, maintainability, performance, or evidence gap that
  should be fixed but does not invalidate the core feature;
- `P3`: minor clarity, cleanup, or low-risk follow-up.

Every finding needs a tight file/line location when available, concrete
evidence, user-visible impact, and a required fix. Do not report preferences as
defects. If no actionable findings exist, say so and list remaining coverage
gaps separately.

Present the verdict, findings, specification coverage, validation evidence,
missing gates, and next action as a concise Markdown review that a maintainer
can inspect before sending fixes to the implementation skill.

## Finalize mode

Read [`references/final-summary-template.md`](references/final-summary-template.md)
completely and use it for the hand-off. Report the committed profile and exact
commands. Separate code, configuration, and public-interface changes.

For every target/profile/PDK in scope, extract only measured values from matching
artifacts. Do not restrict the summary to IHP130 or merge different series into
one PPA result:

- target SoC, source revision, build variant, clock target, and recipe/profile;
- synthesis status, cell count, and area;
- STA status, WNS, and TNS;
- netlist simulation verdict and success marker;
- warning and metric observations;
- evidence paths and limitations.

Use `not reported` or `NOT_RUN` for absent values. Do not claim timing closure,
CDC/RDC signoff, physical signoff, silicon qualification, or commercial IP
equivalence without the corresponding evidence.

Inspect the current workflows and exact invocation before crediting CI
coverage. A run using `--behavioral-only` is not synthesis, netlist, STA, or
synthesis-recipe metric evidence. Derive required local acceptance commands
from each supported product/profile/PDK and its frozen verification contract.
See the [prompt handbook](../../feature-development-prompts.md) for examples.

Check the selected simulation target's own verdict. Tiny's current
`netsim-boot` requires `SIM_TEST_PASS`; `Hello retroSoC!` is only sufficient
for the applicable Mini assembly boot-only target. Respect command exit status
and failure markers, confirm any early stop follows that target's rule, and
verify subsequent regression stages completed. Never treat boot smoke as the
full SDK, DMA, IRQ, or feature acceptance campaign.

## Handoff

End with one next action:

- `MERGE`
- `FIX_P0_P1`
- `RUN_GATES`
- `REFREEZE_SPEC`
- `INVESTIGATE`

Never combine a review verdict with an unreviewed patch. After the next action,
include one complete, copyable, single-stage English prompt for implementation,
diagnosis, review, missing gates, or specification refreeze. Include the
feature slug, target SoCs, exact phase when applicable, specification path,
profile/PDK mapping, diff range, and matching evidence paths. For `MERGE`,
provide a human-only merge checklist instead of an agent execution prompt;
do not merge or push.
