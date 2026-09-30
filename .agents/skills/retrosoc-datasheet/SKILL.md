---
name: retrosoc-datasheet
description: Inspect, update, and validate retroSoC Typst datasheets using the repository's source-bound publication workflow. Use for technical content, diagrams, SDK examples, PDF checks, and publication handoff; not RTL fixes or hardware qualification.
---

# retroSoC Datasheet

Maintain an evidence-backed publication with the existing builders and checks.
Read [AGENTS.md](../../../AGENTS.md) and the
[publication guide](../../../publications/README.md) before taking action.

## Resolve the request

Accept `Mode: inspect`, `update`, or `validate`, `Target SoCs`, the content or
layout scope, and a source baseline when the request changes that baseline.
For a version comparison, identify the previous delivered PDF and its manifest.
Explicit fields and clear natural-language intent are equivalent. Infer a
unique target from a named publication configuration or artifact; otherwise
ask rather than defaulting to Mini. No feature slug or frozen IP phase is needed.

- `inspect`: read sources, configuration, existing reports, and coverage gaps;
  return an update or validation plan without changing files or running setup.
- `update`: perform the requested publication edits, build, validate, visually
  inspect, and deliver within the authorized scope.
- `validate`: check the selected existing sources or PDF without editing
  publication sources. Check reports may be written beside build artifacts;
  do not install dependencies, fetch inputs, or build a replacement PDF unless
  those actions are also requested.

For an ambiguous request, use `inspect` until intent is resolved. Continue an
authorized update through its relevant checks without asking at every step.
Pause only for missing choices, permissions, scope changes, or an unresolved
technical fact. Honor `MUST`, `MUST NOT`, `PREFER`, `DEFER`, and `ACCEPTANCE`
constraints without weakening source or evidence checks.

## Select the publication

Read the selected reference completely before using its commands:

- [Mini publication](references/mini.md).
- [Tiny publication](references/tiny.md).

For multiple targets, keep source identities, configuration, output directories,
PDF hashes, and reports separate. Shared layout does not imply shared hardware
facts or interchangeable command options. For Std, Pro, or a future product,
inspect current support and report missing publication/platform prerequisites;
do not invent an adapter or populate a book with another product's data.

## Preserve the source contract

1. Resolve the configured reviewed commit and the requested baseline. For a
   layout-only edit, retain the existing source identity. When explicitly
   refreshing to a branch or new commit, review the complete technical delta
   before changing the advertised full SHA and observation records. Recheck
   any subsequent branch advance at handoff; never relabel old artifacts.
2. Check for dirty technical sources and managed inputs. Preserve unrelated
   work. A source-drift failure requires reconciliation, not disabling checks
   or advancing the revision merely to silence the error.
3. Preserve frozen structure, stable chapter/IP identifiers, anchors, and
   integration coverage. Structural changes need an explicitly authorized
   scope and the repository's contract review, not automatic regeneration.
4. Reconcile the same fact across features, summaries, tables, detailed prose,
   diagrams, waveforms, register references, and SDK examples. Read executable
   RTL/configuration and canonical mapping inputs when prose disagrees.
5. Distinguish source support, available tests, executed validation, and
   hardware qualification. Preserve dated historical evidence as historical.
   Missing electrical, timing, package, software, or silicon evidence remains
   an explicit gap, never a guessed specification or a passing result.

## Update and validate

Use the selected product's style and content-review rules. Reuse its canonical
extractors, Typst components, and locked assets. Keep generated references and
PDFs under the existing build layout; do not introduce a register generator or
copy managed fonts/packages into tracked publication sources.

Retain the previous delivered PDF before rebuilding. Prepare missing locked
inputs only within an authorized update/setup request; a lock upgrade belongs
to `$retrosoc-dependency-maintenance`, not an ordinary publication build.
Follow the selected guide's source checks, example checks, focused tests,
compile/PDF checks, and color/grayscale visual review. Render and inspect at
the coverage and scale required by that guide; automated PDF checks alone do
not prove layout quality. If a renderer or checker is unavailable, complete
the independent checks and report the visual/checking gap rather than claiming
full acceptance.

Do not repair RTL, firmware, dependency locks, or warning/metric baselines as a
document workaround. Report the evidence and request the appropriate separate
engineering task. Never commit, push, publish, or create a remote review as an
implicit step of updating a datasheet.

## Deliver

Return a concise Markdown report with target/book, reviewed source SHA,
publication configuration, content/layout changes, exact commands and outcomes,
PDF and manifest paths/hashes, and unrun checks. Include the supported
change-page report or an explicitly labeled manual comparison, distinguishing
content changes from pagination. If the old PDF is unavailable, say that the
version comparison was not performed. Keep PDF validity and hardware readiness
as separate conclusions, and name the remaining action only when work remains.
