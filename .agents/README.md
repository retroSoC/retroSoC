# Repository Agent Skills

This directory owns repository-scoped agent skills for all retroSoC series:
Tiny, Mini, Std, Pro, and future products. The root
[`AGENTS.md`](../AGENTS.md), executable build configuration, and subsystem
guides remain authoritative; skills route work through those sources rather
than replacing them.

See [Manual Feature Development Prompts](feature-development-prompts.md) for
IP phases and [Engineering Workflow Prompts](engineering-workflow-prompts.md)
for publication, dependency, and physical-flow tasks. Both contain copyable
English prompts. Skills reuse existing scripts; they are not a new build or
execution framework.

## Available Skills

| Skill | Primary use | Responsibility |
| --- | --- | --- |
| [retrosoc-feature-design](skills/retrosoc-feature-design/SKILL.md) | Architecture | Research and freeze the common IP contract and selected products' integration. |
| [retrosoc-feature-implementation](skills/retrosoc-feature-implementation/SKILL.md) | Delivery | Preflight and implement one phase with target-specific validation. |
| [retrosoc-feature-review](skills/retrosoc-feature-review/SKILL.md) | Assurance | Diagnose failures, review changes, and report evidence separately by target. |
| [retrosoc-datasheet](skills/retrosoc-datasheet/SKILL.md) | Publication | Inspect, update, or validate source-bound Typst publications and PDFs. |
| [retrosoc-dependency-maintenance](skills/retrosoc-dependency-maintenance/SKILL.md) | Dependencies | Inspect, restore, or upgrade locked inputs without confusing restoration with a version change. |
| [retrosoc-physical-flow](skills/retrosoc-physical-flow/SKILL.md) | Physical evidence | Preflight, run, resume, or summarize supported physical implementation flows. |

The [Skill registry](skills/registry.json) records owners, entrypoints, and eval
suites. Use the [agent task schema](task.schema.json) for durable, host-neutral
handoffs and the [shared task contract](skills/shared/task-contract.md) and
[evidence contract](skills/shared/evidence.md) for common rules.

Invoke a skill explicitly when handing work between stages:

```text
@retrosoc-feature-design Research gpio-filter for TINY. Do not modify files.
$retrosoc-feature-implementation Preflight TINY-P4 of tiny-soc for TINY. Do not modify files.
$retrosoc-feature-review Review the tiny-soc diff for TINY against docs/ip/tiny-soc.md.
```

The three feature names replace the former Mini-specific entrypoints; update older saved
prompts to the corresponding name above. There are no legacy alias skills.

## Target selection

Use `Target SoCs: TINY` or an explicit list such as `Target SoCs: TINY, MINI`.
An unambiguous specification, selected profile, or approved hand-off can supply
this field; the skills do not default to Mini. Each hand-off carries the target
SoCs and applicable configuration/evidence identities. Feature hand-offs also
carry specifications, stable phase IDs, and profile/PDK mapping. Existing IDs
such as `TINY-P4` remain valid without renaming.

[Product positioning](../docs/soc-family-positioning.md) distinguishes Tiny/Mini
executable baselines from the currently planned Std/Pro targets. Recheck
[committed profiles](../configs/README.md) and executable configuration each
time. Planned series can be researched, specified, and preflighted; platform
creation must be part of the approved scope before it is implemented.

For shared IP, keep a common functional contract and explicit per-series
integration differences. Verify affected existing consumers without treating
that as permission to add the feature to other products.

Use the host's Plan mode or a read-only permission profile for design `research`
and implementation `preflight`. After maintainer approval, run `freeze` or
`implement` outside Plan mode with the minimum required write scope. Review and
diagnosis are read-only. Fixes return to the implementation skill.

## Feature Human Gates

1. A maintainer reviews the research and freezes `docs/ip/<feature>.md`.
2. A maintainer resolves or approves any `ARCH_CHANGE_REQUIRED`,
   `SPEC_CONFLICT`, `BLOCKED`, or high-risk preflight result.
3. A maintainer reviews P0/P1 findings, CI, and local full-flow evidence before
   merge.

Feature stages retain their design and architecture approval gates. Once a PR's
checks are all green, `scripts/pr_workflow.py` may merge it with a merge commit
and clean the merged local and remote topic branches. It must not merge pending
or failed checks, dirty worktrees, or non-canonical branches.

## Engineering workflows

Start an engineering task with its relevant skill and the requested mode.
Inspection, preflight, and report-only requests remain read-only. An explicit
update, restore, upgrade, run, or resume request proceeds through its in-scope
checks and delivery without per-step confirmation. Ask only for a missing
decision, permission, scope change, or recovery action that needs approval.
Plan mode never authorizes mutations, regardless of the mode in the prompt.

Maintenance tasks do not require feature slugs, frozen specifications, or phase
IDs. Resolve targets from explicit inputs or unambiguous publication/profile
context; global tool maintenance needs product selection only where affected
consumers require it. Publication adapters and physical flows are usable only
for configurations they actually support, not every planned series.

Restore keeps the current lock; upgrade changes approved pins. A doctor, status,
or package target may have mutating prerequisites: inspect the recipe before
treating it as a read-only check. Preserve existing artifacts on resume and do
not substitute another product, weaken checks, or infer missing evidence.

Keep regression and behavior-preserving RTL migration inside the existing
implementation/review responsibilities through their linked references.
Ordinary prose edits, small script fixes, and Git tasks do not require a new
skill or an IP design freeze. No workflow here introduces a scheduled trigger
or an automatic commit, push, or publication step.

## Product-specific validation

Select supported regressions and success markers from each product's executable
configuration. The [prompt handbook](feature-development-prompts.md) gives
separate Tiny/Mini IHP130 examples with explicit SoC selectors. Do not treat
those examples as the acceptance matrix for every series or PDK.

Tiny `netsim-boot` currently requires `SIM_TEST_PASS`; the applicable Mini
assembly boot-only target uses `Hello retroSoC!`. Check exit codes, failure
markers, and completion of subsequent STA/warning/metric stages. Discover CI
coverage from the current workflow and invocation, and never credit a
behavioral-only run as physical-flow evidence. Keep reported results tied to
the target, profile, PDK, source revision, and build variant.

## Validation

Skill metadata, references, the registry, and eval corpora are checked by
`make skill-eval-static` and Pytest. Changes to this directory require the
applicable documentation, JSON, Pytest, and whitespace checks listed in the root
agent contract. Hardware gates remain proportionate to the feature work.

Static corpus validation does not prove agent behavior. `make skill-eval-smoke`
executes three read-only Codex scenarios in isolated Git workspaces and retains
traces and deterministic grades. The runner and model are recorded explicitly;
a static result is never described as a completed behavior, hardware, or
publication run. Other hosts can emit the same trace schema for grading.
