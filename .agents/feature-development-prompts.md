# retroSoC Mini Manual Feature Development Prompts

This guide provides copyable English prompts for manually developing a new
retroSoC Mini IP. It uses `audio-processing-unit` as the example feature slug.
Replace that slug, specification path, and phase title with the values frozen
for the feature being developed.

## Invocation and stage matrix

Use `@retrosoc-mini-feature-design` in ChatGPT Work and use `$` when invoking
the implementation or review skill in Codex. Review examples below use Codex
syntax; when running the review skill in ChatGPT Work, replace
`$retrosoc-mini-feature-review` with `@retrosoc-mini-feature-review`.

| Stage or mode | Skill | Plan mode | May modify files | Human decision |
| --- | --- | --- | --- | --- |
| `research` | `retrosoc-mini-feature-design` | Yes | No | Approve architecture |
| `freeze` | `retrosoc-mini-feature-design` | No | Documentation only | Approve frozen contract |
| `preflight` | `retrosoc-mini-feature-implementation` | Yes/read-only | No | Approve implementation plan |
| `implement` | `retrosoc-mini-feature-implementation` | No | Yes | Accept phase evidence |
| `diagnose` | `retrosoc-mini-feature-review` | No/read-only | No | Confirm root cause |
| `review` | `retrosoc-mini-feature-review` | No/read-only | No | Resolve P0/P1 findings |
| `finalize` | `retrosoc-mini-feature-review` | No/read-only | No | Merge, fix, or run gates |

## Common prompt fields

Use the smallest set of fields required by the selected stage:

```text
Stage or Mode: <research|freeze|preflight|implement|diagnose|review|finalize>
Feature slug: <lowercase-kebab-case>
Phase: <stable Phase N - Title, when applicable>
Specification: docs/ip/<feature-slug>.md

Additional constraints:
- MUST: <required behavior>
- MUST NOT: <prohibited behavior>
- PREFER: <preferred choice when compatible with the frozen contract>
- DEFER: <work explicitly outside this stage or phase>
- ACCEPTANCE: <objectively verifiable completion condition>
```

The feature slug is a stable lowercase kebab-case identifier. Once the design
is frozen as `docs/ip/<feature-slug>.md`, use that path to recover the slug and
do not introduce an alias.

Every implementation phase has one stable heading in the frozen specification:

```text
Phase 1 - APB4 CSR and interrupt skeleton
Phase 2 - FIFO and PIO datapath
Phase 3 - AXI4 DMA integration
```

Do not rename or renumber a phase after freeze. Do not use "next phase" in a
new task unless the exact phase ID/title is also supplied.

## 1. Research the feature

Host: ChatGPT Work. Use Plan mode. This stage is read-only.

```text
@retrosoc-mini-feature-design

Stage: research
Feature slug: audio-processing-unit

Research and design this feature for retroSoC Mini.

Additional constraints:
- MUST: Support 16-bit, 24-bit, and 32-bit PCM samples.
- MUST: Use AXI4 data access and APB4 configuration.
- MUST: Support DMA and interrupts.
- MUST NOT: Add floating-point processing to the MVP.
- PREFER: Reuse compatible Common FIFO, CDC, and register components.
- DEFER: Sample-rate conversion to the commercial-grade roadmap.
- ACCEPTANCE: Produce a recommended MVP, target architecture, verification plan, and ordered development phases.

Do not modify repository files.
```

Expected output: repository and commercial evidence, selected architecture,
MVP/target split, stable proposed phases, open questions, and a design-freeze
decision package.

Human Gate 1: approve the feature slug, architecture, interfaces, register
model, DMA, interrupts, clock/reset boundaries, MVP, and phase list.

## 2. Freeze the approved specification

Host: ChatGPT Work. Leave Plan mode. Only documentation may change.

```text
@retrosoc-mini-feature-design

Stage: freeze
Feature slug: audio-processing-unit
Specification: docs/ip/audio-processing-unit.md

Freeze the architecture approved in this conversation as the authoritative
feature specification. Use stable Phase N - Title headings and do not implement
RTL.

Additional constraints:
- MUST: Preserve every approved architecture and software-visible requirement.
- MUST NOT: Retain rejected alternatives as normative behavior.
- DEFER: Keep explicitly approved post-MVP work outside implementation phases.
- ACCEPTANCE: The specification defines interfaces, ABI, errors, clocks/resets, CDC/RDC, software, verification, phases, PPA evidence, and commercial gaps.

Update the documentation index and relevant subsystem guide.
```

Expected output: `docs/ip/audio-processing-unit.md`, an optional verification
companion, documentation index updates, and a complete copyable preflight
prompt for the first phase.

## 3. Preflight one frozen phase

Host: Codex. Use Plan mode or a read-only permission profile.

```text
$retrosoc-mini-feature-implementation

Stage: preflight
Feature slug: audio-processing-unit
Phase: Phase 1 - APB4 CSR and interrupt skeleton
Specification: docs/ip/audio-processing-unit.md

Map only this frozen phase onto the current repository.

Additional constraints:
- MUST: Keep the register window within 4 KiB.
- MUST: Use sticky W1C interrupt state with event-wins precedence.
- MUST NOT: Change existing DMA channel allocation in this phase.
- PREFER: Reuse compatible Common register components.
- DEFER: FIFO and DMA datapaths to their frozen later phases.
- ACCEPTANCE: Return one preflight verdict, exact file impacts, reusable components, risks, commands, and objective completion criteria.

Do not modify files.
```

Human Gate 2:

- approve an `IMPLEMENTABLE` result before implementation;
- return `ARCH_CHANGE_REQUIRED` to design review;
- reconcile `SPEC_CONFLICT` with the frozen specification;
- resolve missing inputs or dependencies for `BLOCKED`.

## Approved preflight hand-off

In the same Codex task, approval can refer to the plan already visible in the
conversation:

```text
The preflight plan above is approved.
```

In a new Codex task, paste the approved plan or explicitly name a
maintainer-approved implementation document:

```text
Approved preflight source: pasted below

[PASTE THE APPROVED PREFLIGHT PLAN]
```

A plan's existence does not imply approval. State approval explicitly.

## 4. Implement the approved phase

Host: Codex. Leave Plan mode.

```text
$retrosoc-mini-feature-implementation

Stage: implement
Feature slug: audio-processing-unit
Phase: Phase 1 - APB4 CSR and interrupt skeleton
Specification: docs/ip/audio-processing-unit.md
Approved preflight source: the approved plan in this conversation

Implement only this phase.

Additional constraints:
- MUST: Preserve handwritten SystemVerilog/C register parity.
- MUST: Add focused APB4, interrupt, and register-parity tests.
- MUST NOT: Implement Phase 2 FIFO behavior in this phase.
- PREFER: Reuse components selected by the approved preflight.
- ACCEPTANCE: Applicable focused tests and repository quality gates pass, and every unrun gate is reported.
```

Expected output: one reviewable phase, exact commands and results, separated
code/configuration/public-interface changes, unrun gates, and a complete prompt
for the next preflight or required diagnosis/review.

## 5. Start the next phase

Use the exact frozen ID/title rather than "the next phase":

```text
$retrosoc-mini-feature-implementation

Stage: preflight
Feature slug: audio-processing-unit
Phase: Phase 2 - FIFO and PIO datapath
Specification: docs/ip/audio-processing-unit.md

Map only this frozen phase onto the current repository. Do not modify files.
```

## 6. Diagnose a confirmed failure

Host: Codex or ChatGPT Work. This mode is read-only.

```text
$retrosoc-mini-feature-review

Mode: diagnose
Feature slug: audio-processing-unit
Specification: docs/ip/audio-processing-unit.md

Failing command: <paste the exact command>
Log: <path to the failing log>
Structured result: <path to result JSON, when available>

Identify the first failing step, exact failure evidence, root-cause boundary,
and the acceptance test for a fix. Do not modify files and do not treat a slow
or silent tool as an RTL defect.
```

## 7. Implement a confirmed fix

Use this only after diagnosis establishes root cause and an acceptance test:

```text
$retrosoc-mini-feature-implementation

Stage: implement
Feature slug: audio-processing-unit
Phase: <the affected stable Phase N - Title>
Specification: docs/ip/audio-processing-unit.md

Confirmed root cause: <paste the confirmed root cause>
Acceptance test: <paste the exact test>

Fix only the confirmed cause, rerun the failed gate, and run the smallest
affected regression. Preserve unrelated behavior and files.
```

## 8. Review the implementation

Host: Codex or ChatGPT Work. This mode is read-only.

```text
$retrosoc-mini-feature-review

Mode: review
Feature slug: audio-processing-unit
Specification: docs/ip/audio-processing-unit.md
Review range: main...HEAD

Review only changes introduced by this range. Check the frozen requirements,
approved extra constraints, interfaces, register parity, DMA/interrupt corner
cases, clock/reset and CDC/RDC behavior, synthesis risks, tests, and evidence.
Report actionable findings as P0-P3. Do not modify files.
```

Route confirmed P0/P1 fixes through the implementation skill, then repeat the
review.

## 9. Run final local IHP130 acceptance

Start the full flow manually from a prepared Linux environment:

```sh
python3 scripts/regress.py \
  --root . \
  --suite pr \
  --pdk IHP130 \
  --netsim-boot-only
```

Allow Yosys up to 180 minutes before classifying it as timed out. A slow or
silent process is not a design failure. Netlist simulation may terminate only
after `Hello retroSoC!`; preserve the remaining STA, warning, metric, log, and
structured-result evidence.

## 10. Finalize the delivery evidence

Host: Codex or ChatGPT Work. This mode is read-only.

```text
$retrosoc-mini-feature-review

Mode: finalize
Feature slug: audio-processing-unit
Specification: docs/ip/audio-processing-unit.md

Use the implementation diff and all available validation artifacts to produce
the final hand-off. Report the profile, exact commands, changes, validation,
MISRA deviations, unrun gates, IHP130 synthesis/timing metrics, evidence paths,
and remaining hardware or commercial-delivery gaps.

Use NOT_RUN or not reported for missing evidence. Do not estimate PPA values or
claim timing, physical, CDC/RDC, or silicon signoff without matching evidence.
```

Human Gate 3: resolve P0/P1 findings, review all required evidence, and accept
exactly one next action: `MERGE`, `FIX_P0_P1`, `RUN_GATES`, `REFREEZE_SPEC`, or
`INVESTIGATE`. `MERGE` remains a human action; the review skill must not merge
or push.

## Constraint conflicts

- Research compares a new constraint with repository and commercial evidence.
- Freeze makes an approved long-lived constraint normative.
- Preflight returns `SPEC_CONFLICT` or `ARCH_CHANGE_REQUIRED` rather than
  overriding the frozen contract.
- Implement applies only constraints included in the approved preflight.
- Review treats unapproved temporary constraints as context, not requirements.
