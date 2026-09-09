---
name: retrosoc-mini-feature-review
description: Diagnose a retroSoC Mini build, simulation, synthesis, timing, or CI failure; review a feature diff or pull request against its frozen docs/ip contract; or produce the final evidence-based IHP130 hand-off. Use this skill whenever the user asks for root cause, spec compliance, P0-P3 findings, verification gaps, PPA results, or merge readiness. Keep diagnosis and review read-only and return fixes to the implementation skill.
---

# retroSoC Mini Feature Review

Produce an evidence-backed verdict without turning review into an unapproved
implementation or architecture change.

## Inputs and modes

Require a feature slug and one mode:

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
`$retrosoc-mini-feature-implementation` with the exact root cause and
acceptance test.

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

For IHP130, extract only measured values from named artifacts:

- clock target and recipe/profile;
- synthesis status, cell count, and area;
- STA status, WNS, and TNS;
- netlist simulation verdict and success marker;
- warning and metric observations;
- evidence paths and limitations.

Use `not reported` or `NOT_RUN` for absent values. Do not claim timing closure,
CDC/RDC signoff, physical signoff, silicon qualification, or commercial IP
equivalence without the corresponding evidence.

GitHub-hosted regression currently uses `--behavioral-only`; it is not
synthesis, netlist, STA, or synthesis-recipe metric evidence. A local full
IHP130 acceptance run normally uses:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

Confirm that boot-only stopped the netlist simulation only after
`Hello retroSoC!` and that the remaining stages completed.

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
feature slug, exact phase when applicable, specification path, diff range, and
evidence paths. For `MERGE`, provide a human-only merge checklist instead of an
agent execution prompt; do not merge or push.
