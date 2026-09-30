---
name: retrosoc-feature-design
description: Research, architect, and freeze SoC/IP features for any retroSoC series, including Tiny, Mini, Std, and Pro. Use for commercial comparisons, architecture choices, shared-IP integration contracts, MVPs, and phased specifications; not RTL implementation or diff review.
---

# retroSoC Feature Design

Create repository-grounded feature architecture without allowing research or a
generic reference design to override the current retroSoC contract.

## Inputs

Require:

- a lowercase feature slug;
- the requested stage: `research` or `freeze`;
- `Target SoCs`: one series or an explicit list of series;
- the corresponding specifications, profiles, and PDKs when already selected;
- user requirements that are stricter than repository defaults;
- the approved research result for `freeze`.

Resolve a missing feature slug or stage with the rules below. Ask for only the
remaining ambiguous input. Do not invent a feature name that could become a
software-visible ABI.

## Resolve inputs

Resolve input in this order:

1. explicit fields in the current prompt;
2. an unambiguous action in the current prompt;
3. the current conversation and its explicitly approved hand-off;
4. an explicit `docs/ip/<feature>.md` path;
5. one unique matching repository specification.

Map `research`, `design`, or `architect` to `research`. Map `freeze` or
`write spec` to `freeze`. Route implementation, diagnosis, and review actions
to their matching repository skills. Ask the user only when more than one
interpretation remains.

Treat a supplied feature slug as a stable lowercase kebab-case identifier. If
research starts without one, propose a slug and obtain approval before freeze.
Once `docs/ip/<feature>.md` is frozen, derive the slug from that path and do not
create aliases. Never infer design approval merely because a research result
exists.

## Resolve target SoCs

Resolve `Target SoCs` from the current request, approved hand-off, frozen
specification, or an explicitly selected committed profile. Normalize series
names such as Tiny/Mini/Std/Pro to TINY/MINI/STD/PRO for the hand-off; this does
not make those names valid build arguments. Do not default to Mini or interpret
an unspecified target as every series. Ask only if the target remains missing
or ambiguous; surface conflicting target, specification, or profile values.

Read `docs/soc-family-positioning.md` and the selected product contracts to
distinguish implemented baselines from planned targets. Tiny and Mini currently
have executable profiles; Std and Pro are roadmap targets. Recheck this status
in committed profiles and build rules rather than treating it as permanent.
Research and freeze remain useful without an executable platform: identify
missing integration, software, dependencies, and validation work explicitly.
Do not claim the proposed profile or platform already exists.

For each target, identify its product RTL, topology/address map, filelists,
SDK/application composition, and available configurations. Read Mini LP/HP
guidance only when Mini or that architecture is involved. Do not carry CPU
topology, bus widths, DMA channels, IRQ allocation, clocks, or memory assumptions
from one series into another.

For shared IP, separate the reusable IP contract from each series' integration
and capability differences. Freeze the requested target list and explicitly
deferred targets, without enlarging a single-series task into a family rollout.
Keep existing specification paths; do not clone a shared register contract into
conflicting per-series documents.

## Additional constraints

Normalize prompt-specific constraints as:

- `MUST`: required for the task;
- `MUST NOT`: prohibited;
- `PREFER`: select only when compatible with stronger requirements;
- `DEFER`: explicitly outside the current stage or phase;
- `ACCEPTANCE`: an objectively verifiable completion condition.

During research, classify constraints as confirmed, recommended, assumed, or
open. During freeze, write every approved long-lived `MUST`, `MUST NOT`,
`DEFER`, and `ACCEPTANCE` item into the normative specification. Record a
`PREFER` item only when the approved design selects it. Expose conflicts instead
of silently weakening a repository contract.

## Read repository truth first

Read the complete `AGENTS.md`, then inspect the sources that define the current
feature boundary. At minimum, inspect:

- `docs/README.md`, `docs/engineering.md`, `docs/rtl-coding-style.md`, and
  relevant `docs/ip/*.md` contracts;
- the selected product's architecture, interconnect and DMA documents, and
  topology/address-map sources when the feature touches them;
- relevant `rtl/README.md`, subsystem README files, filelists, tests, committed
  profiles, and executable CI/regression definitions;
- `dependencies/dependencies.lock.json` before making any claim about a managed
  component or dependency revision.

Do not assume an older `docs/design/` layout. The authoritative feature
contract belongs in `docs/ip/<feature>.md`; use
`docs/ip/<feature>-verification.md` only when the verification evidence is too
large to keep the main contract readable.

## Research stage

Run `research` in Plan mode. If Plan mode is unavailable, remain read-only and
state that design freeze requires a separate approved execution step.

Research current commercial SoCs and commercial IPs with similar behavior.
Prefer vendor product pages, reference manuals, standards, maintained upstream
drivers, and primary research. Check publication/update dates and current
maintenance status. Do not copy proprietary implementation details.

For each useful reference, record:

- the problem solved and supported functions;
- data path, control path, software-visible model, DMA, and interrupts;
- clock/reset, CDC/RDC, memory, coherency, and security dependencies;
- documented performance, area, power, and verification evidence;
- current activity and product support status;
- ideas worth reusing and ideas that do not fit the selected target SoCs.

Separate statements into these evidence classes:

- `CONFIRMED FROM REPOSITORY`
- `CONFIRMED FROM EXTERNAL REFERENCE`
- `RECOMMENDATION`
- `ASSUMPTION`
- `OPEN QUESTION`

Then compare feasible alternatives and recommend an architecture for the target
SoCs, with explicit shared-IP and product-specific boundaries. Keep
feasibility separate from recommendation. Define the MVP and show how it can
evolve into a commercial-quality target without silently expanding the MVP.
Do not modify repository files in this stage.

## Freeze stage

Run `freeze` only outside Plan mode after explicit design approval. Read
[`references/ip-spec-template.md`](references/ip-spec-template.md) completely
and create or update the authoritative feature document from that structure.

Remove rejected alternatives from the normative design. Retain concise
rationale and reference boundaries where they prevent future architecture
drift. Resolve every open question or mark it as an explicit deferred item that
does not block the approved phase.

The frozen contract must define:

- requirements and non-goals;
- target SoCs, implementation status, profiles/PDKs or missing platform inputs;
- AXI4 data access and APB4 configuration semantics for the selected products,
  including supported subsets and widths rather than inferred family defaults;
- DMA, interrupt, register, reset, and error behavior;
- clock domains, reset ownership, CDC/RDC, and lifecycle behavior;
- software-visible ABI and handwritten RTL/C register parity;
- observability, counters, recovery, and security or safety claim boundaries;
- MVP module hierarchy and stable phase IDs/titles for the development order;
- verification, firmware, synthesis, timing, and physical evidence required;
- post-MVP commercial alignment and delivery gaps.

Preserve existing frozen phase IDs and titles verbatim, including identifiers
such as `TINY-P4`. `Phase N - Title` is a convention for new phases, not a
requirement to rename existing ones. State each phase's target SoCs and record
platform-enablement prerequisites for targets without executable profiles.

Update `docs/README.md` and any relevant subsystem guide when adding a new
document. Verify links and commands, then run `git diff --check`. Do not modify
RTL, firmware, build configuration, warning baselines, or metrics policy.

## Handoff

Report the target SoCs, feature slug, specification paths, selected
profiles/PDKs or missing inputs, stable phase IDs/titles, and deferred work.
After research, provide a design decision package and a `freeze` prompt for use
after approval; do not imply the specification is already frozen. After freeze,
provide a complete English `$retrosoc-feature-implementation` preflight prompt
for the first approved phase. Carry the target SoCs, exact phase, specification,
profile/PDK mapping, and approved extra constraints into that prompt.
