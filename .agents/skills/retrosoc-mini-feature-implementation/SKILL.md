---
name: retrosoc-mini-feature-implementation
description: Preflight and implement one approved phase of a frozen retroSoC Mini SoC/IP feature. Use this skill whenever Codex must map docs/ip requirements to the current repository, reuse Common RTL, change AXI4/APB4/DMA/interrupt integration, maintain handwritten RTL/C register parity, add simulation or software tests, or run proportionate validation. Do not use it for commercial research, architecture selection, failure diagnosis before root cause is known, or broad PR review.
---

# retroSoC Mini Feature Implementation

Translate an approved architecture into one reviewable repository phase. The
frozen specification controls what to build; the current repository controls
how to integrate it.

## Inputs

Require:

- a lowercase feature slug;
- the stage: `preflight` or `implement`;
- one exact phase identifier from `docs/ip/<feature>.md`;
- the approved specification and any verification companion;
- for `implement`, an approved preflight result.

Do not combine multiple phases merely because they touch the same files. If the
specification is missing, ambiguous, or conflicts with repository truth, stop
with `SPEC_CONFLICT` or `BLOCKED` rather than designing a replacement.

## Resolve inputs

Resolve input in this order:

1. explicit fields in the current prompt;
2. an unambiguous action in the current prompt;
3. the current conversation and its explicitly approved hand-off;
4. an explicit `docs/ip/<feature>.md` path;
5. one unique matching repository specification.

Map `preflight` or `implementation plan` to `preflight`. Map `implement`,
`build`, or `fix` to `implement`; route `fix` to diagnosis first when no root
cause and acceptance test have been confirmed. Ask the user only when more than
one interpretation remains.

Derive the feature slug from an explicit field or specification path and keep
the frozen lowercase kebab-case value. Resolve a phase only from an explicit
stable `Phase N - Title` or an explicitly approved hand-off. Do not infer
"next phase" from repository state and do not rename or renumber a frozen
phase.

For `implement`, accept an approved preflight only from the current Codex
conversation, a plan pasted into the prompt, or a maintainer-approved document
explicitly named by the user. A plan's existence is not evidence of approval.

## Additional constraints

Normalize prompt-specific constraints as `MUST`, `MUST NOT`, `PREFER`,
`DEFER`, and `ACCEPTANCE`. Apply repository policy first, the frozen
specification second, and only then approved prompt-specific constraints that
do not conflict. Treat `MUST` and `MUST NOT` as mandatory, use `PREFER` only
when compatible, exclude `DEFER` work, and use `ACCEPTANCE` to verify the
result. A temporary constraint cannot override architecture, ABI, DMA,
interrupt, clock/reset, CDC/RDC, or verification requirements in the frozen
contract.

During preflight, return `SPEC_CONFLICT` when a temporary constraint contradicts
the frozen contract, or `ARCH_CHANGE_REQUIRED` when satisfying it needs an
unapproved architecture change. During implementation, apply only constraints
included in the approved preflight. Route a new long-lived requirement back to
the design skill for freeze.

## Establish repository truth

Read `AGENTS.md` completely, then read the frozen feature contract,
`docs/rtl-coding-style.md`, `docs/rtl-coding-style-compliance.md`, and every
relevant top-level or subsystem README. Inspect executable build, topology,
filelist, profile, test, warning, metric, and CI sources before naming files or
commands.

Inspect `rtl/managed/clusterip/common` and its active filelist before proposing
new infrastructure. Reuse Common interfaces, registers, FIFOs, arbiters, CDC,
reset, ECC, and utility modules only when their exact reset, enable, latency,
and backpressure semantics fit. Never edit a managed subtree as an ordinary
project source.

## Preflight stage

Run `preflight` in Plan mode or under a read-only permission profile. Do not
modify files, run rewriting formatters, update generated artifacts, or change
architecture.

Map the approved phase onto:

- existing modules and Common components to reuse;
- files to create and modify;
- address, interrupt, DMA, clock/reset, CDC/RDC, and lifecycle integration;
- handwritten SystemVerilog and C register definitions plus a parity test;
- standalone, integration, formal, firmware, regression, and documentation
  evidence;
- exact acceptance criteria and the smallest useful validation order.

Return exactly one verdict:

- `IMPLEMENTABLE`: the phase maps cleanly to current repository truth;
- `ARCH_CHANGE_REQUIRED`: implementation requires an unapproved architecture,
  address, clock/reset, CDC/RDC, DMA, interrupt, or compatibility change;
- `SPEC_CONFLICT`: the frozen contract disagrees with executable repository
  behavior or another authoritative contract;
- `BLOCKED`: required input, dependency, tool, or evidence is unavailable.

Treat clock/reset, CDC/RDC, AXI/interconnect, address maps, CPU or memory
subsystems, DMA architecture, interrupt architecture, and power/clock gating as
high risk and require a human plan gate.

Present the verdict and the same repository mapping as a concise Markdown plan.
Keep file paths, commands, risks, human gates, and acceptance criteria explicit
so a maintainer can approve the phase before implementation.

## Implement stage

Run `implement` outside Plan mode only after an `IMPLEMENTABLE` result or
explicit human approval of a high-risk result. Preserve unrelated worktree
changes and implement only the approved phase.

Follow these invariants:

- use AXI4 for the approved high-bandwidth data path and APB4 for approved
  configuration/control behavior;
- implement DMA and interrupts exactly as frozen, including backpressure,
  sticky events, W1C precedence, abort, timeout, and error recovery;
- keep the existing manual SVH/C register flow; update both sides together and
  add or extend a deterministic parity test;
- never introduce a register generator or hide ABI drift behind generated
  output;
- follow project naming, state, reset, width, signedness, connection, and
  synthesis rules;
- rely on the root Verible configuration for normal alignment; use the
  smallest `// verilog_format: off -- <reason>` / `// verilog_format: on`
  region only when the formatter cannot preserve a reviewed macro or port
  table;
- add simulation models, assertions, software tests, and documentation when
  the new behavior needs them;
- do not weaken tests, remove verification, edit baselines by hand, or change
  design merely to shorten a tool run.

Review new behavior for latches, combinational loops, multiple drivers,
width/sign errors, reset and unilateral-reset behavior, CDC/RDC, AXI/APB
protocol violations, FIFO conservation, DMA tail/alignment cases, interrupt
races, error containment, and synthesis hazards.

## Validation and long-running tools

Derive the minimum gates from `AGENTS.md`; do not preserve command lines copied
from an older conversation when executable configuration differs. Run focused
tests first, then format/style/policy, firmware, behavioral integration, and
the affected regression in that order.

For hardware-facing final acceptance, use the committed IHP130 profile and:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

The boot-only option may terminate the Icarus netlist simulation only after
`Hello retroSoC!`; allow the runner to continue STA, warning, and metric stages.
GitHub-hosted regression is currently behavioral-only, so it cannot be cited as
synthesis, netlist, STA, or synthesis-recipe metric evidence.

Allow a Yosys synthesis up to 180 minutes before classifying it as timed out.
Keep the user informed and poll long jobs at intervals no longer than 60
seconds. A slow or silent tool is not evidence of an RTL defect. Modify design
only after a concrete error, timeout, resource failure, or reproducible root
cause has been established.

## Handoff

Report:

- the selected profile and exact commands run;
- code, configuration, and public-interface changes separately;
- validation results and applicable MISRA deviations;
- every unrun gate and why it was not run;
- remaining hardware, timing, vendor, simulator, and commercial-delivery gaps.

Route unresolved failures to `$retrosoc-mini-feature-review` in `diagnose`
mode. Do not diagnose and silently redesign within the implementation stage.
End with one complete, copyable, single-stage English prompt for the next
approved phase, diagnosis, review, or finalization action. Include the feature
slug, exact phase when applicable, specification path, and evidence paths.
