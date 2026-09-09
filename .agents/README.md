# Repository Agent Skills

This directory owns repository-scoped agent skills for the retroSoC Mini
engineering workflow. The root [`AGENTS.md`](../AGENTS.md), executable build
configuration, and subsystem guides remain authoritative; skills route work
through those sources rather than replacing them.

See [Manual Feature Development Prompts](feature-development-prompts.md) for
copyable English prompts covering every human-triggered stage.

## Available Skills

| Skill | Primary host | Responsibility |
| --- | --- | --- |
| `retrosoc-mini-feature-design` | ChatGPT Work | Research commercial references, define the Mini architecture, and freeze an implementation-ready IP specification. |
| `retrosoc-mini-feature-implementation` | Codex | Map one approved phase onto the repository, implement it, and run proportionate validation. |
| `retrosoc-mini-feature-review` | ChatGPT Work or Codex | Diagnose failures, review a diff against the frozen specification, and produce the evidence-based final hand-off. |

Invoke a skill explicitly when handing work between stages:

```text
@retrosoc-mini-feature-design Research and freeze the audio-processing-unit architecture.
$retrosoc-mini-feature-implementation Preflight Phase 1 of audio-processing-unit.
$retrosoc-mini-feature-review Review PR 123 against docs/ip/audio-processing-unit.md.
```

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
GitHub-hosted regression remains behavioral-only. A hardware-facing final
acceptance run uses:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

The boot-only option may stop the Icarus netlist simulation only after
`Hello retroSoC!` is observed; the runner continues the remaining STA, warning,
and metric stages.

## Validation

Skill metadata, references, and eval corpora are checked by Pytest. Changes to
this directory require the applicable documentation, JSON, Pytest, and
whitespace checks listed in the root agent contract. Hardware gates remain
proportionate to the feature work performed through the skills.
