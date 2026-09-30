# Repository Agent Skills

This directory owns repository-scoped agent skills for all retroSoC series:
Tiny, Mini, Std, Pro, and future products. The root
[`AGENTS.md`](../AGENTS.md), executable build configuration, and subsystem
guides remain authoritative; skills route work through those sources rather
than replacing them.

See [Manual Feature Development Prompts](feature-development-prompts.md) for
copyable English prompts covering every human-triggered stage.

## Available Skills

| Skill | Primary host | Responsibility |
| --- | --- | --- |
| [retrosoc-feature-design](skills/retrosoc-feature-design/SKILL.md) | ChatGPT Work | Research and freeze the common IP contract and selected products' integration. |
| [retrosoc-feature-implementation](skills/retrosoc-feature-implementation/SKILL.md) | Codex | Preflight and implement one phase with target-specific validation. |
| [retrosoc-feature-review](skills/retrosoc-feature-review/SKILL.md) | ChatGPT Work or Codex | Diagnose failures, review changes, and report evidence separately by target. |

Invoke a skill explicitly when handing work between stages:

```text
@retrosoc-feature-design Research gpio-filter for TINY. Do not modify files.
$retrosoc-feature-implementation Preflight TINY-P4 of tiny-soc for TINY. Do not modify files.
$retrosoc-feature-review Review the tiny-soc diff for TINY against docs/ip/tiny-soc.md.
```

These names replace the former Mini-specific entrypoints; update older saved
prompts to the corresponding name above. There are no legacy alias skills.

## Target selection

Use `Target SoCs: TINY` or an explicit list such as `Target SoCs: TINY, MINI`.
An unambiguous specification, selected profile, or approved hand-off can supply
this field; the skills do not default to Mini. Each hand-off carries the target
SoCs, specifications, stable phase IDs, and profile/PDK mapping. Existing IDs
such as `TINY-P4` remain valid without renaming.

[Product positioning](../docs/soc-family-positioning.md) distinguishes Tiny/Mini
executable baselines from the currently planned Std/Pro targets. Recheck
[committed profiles](../configs/README.md) and executable configuration each
time. Planned series can be researched, specified, and preflighted; platform
creation must be part of the approved scope before it is implemented.

For shared IP, keep a common functional contract and explicit per-series
integration differences. Verify affected existing consumers without treating
that as permission to add the feature to other products.

ChatGPT Work uses Plan mode for the design `research` stage. After a maintainer
approves the design, run the `freeze` stage outside Plan mode to write the
specification. Codex uses Plan mode or a read-only permission profile for
`preflight`; `implement` runs outside Plan mode and handles one approved phase.
Review and diagnosis are read-only. Fixes return to the implementation skill.

## Human Gates

1. A maintainer reviews the research and freezes `docs/ip/<feature>.md`.
2. A maintainer resolves or approves any `ARCH_CHANGE_REQUIRED`,
   `SPEC_CONFLICT`, `BLOCKED`, or high-risk preflight result.
3. A maintainer reviews P0/P1 findings, CI, and local full-flow evidence before
   merge.

Every Work and Codex stage is started manually. The skills do not create pull
requests, post review comments, or advance a human gate on their own.

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

Skill metadata, references, and eval corpora are checked by Pytest. Changes to
this directory require the applicable documentation, JSON, Pytest, and
whitespace checks listed in the root agent contract. Hardware gates remain
proportionate to the feature work performed through the skills.
