---
name: retrosoc-mini-feature-design
description: Research, architect, and freeze a new or substantially extended retroSoC Mini SoC/IP feature before RTL implementation. Use this skill whenever a request asks for commercial SoC/IP comparison, technology selection, AXI4/APB4/DMA/interrupt architecture, MVP definition, commercial-grade roadmap, or an authoritative docs/ip specification. Do not use it to implement RTL, fix CI, or review an existing diff.
---

# retroSoC Mini Feature Design

Create repository-grounded feature architecture without allowing research or a
generic reference design to override the current retroSoC contract.

## Inputs

Require:

- a lowercase feature slug;
- the requested stage: `research` or `freeze`;
- the product scope, normally retroSoC Mini;
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
- `docs/lp-hp-architecture.md`, the active interconnect and DMA documents, and
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
- ideas worth reusing and ideas that do not fit retroSoC Mini.

Separate statements into these evidence classes:

- `CONFIRMED FROM REPOSITORY`
- `CONFIRMED FROM EXTERNAL REFERENCE`
- `RECOMMENDATION`
- `ASSUMPTION`
- `OPEN QUESTION`

Then compare feasible alternatives and recommend one Mini architecture. Keep
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
- AXI4 data access and APB4 configuration semantics;
- DMA, interrupt, register, reset, and error behavior;
- clock domains, reset ownership, CDC/RDC, and lifecycle behavior;
- software-visible ABI and handwritten RTL/C register parity;
- observability, counters, recovery, and security or safety claim boundaries;
- MVP module hierarchy and stable phase IDs/titles for the development order;
- verification, firmware, synthesis, timing, and physical evidence required;
- post-MVP commercial alignment and delivery gaps.

Update `docs/README.md` and any relevant subsystem guide when adding a new
document. Verify links and commands, then run `git diff --check`. Do not modify
RTL, firmware, build configuration, warning baselines, or metrics policy.

## Handoff

End with:

- the frozen document paths;
- the exact approved phase names;
- unresolved deferred work;
- the first implementation phase;
- a complete, copyable, single-stage English prompt that invokes
  `$retrosoc-mini-feature-implementation` in `preflight` mode and includes the
  feature slug, exact phase ID/title, specification path, and approved extra
  constraints.
