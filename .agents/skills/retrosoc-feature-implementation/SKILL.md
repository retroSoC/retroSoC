---
name: retrosoc-feature-implementation
description: Preflight and implement a frozen retroSoC SoC/IP phase for one or more series. Use for RTL/HAL integration, shared-IP changes, register parity, and target-specific validation. Resolve the target products and profiles before implementation; not commercial research or broad review.
---

# retroSoC Feature Implementation

Translate an approved architecture into one reviewable repository phase. The
frozen specification controls what to build; the current repository controls
how to integrate it.

## Inputs

Require:

- a lowercase feature slug;
- `Target SoCs`: one series or an explicit list, resolved from the task context;
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
stable phase ID/title or an explicitly approved hand-off. Copy existing IDs
such as `TINY-P4` verbatim; `Phase N - Title` is only a new-phase example. Do not infer
"next phase" from repository state and do not rename or renumber a frozen
phase.

For `implement`, accept an approved preflight only from the current Codex
conversation, a plan pasted into the prompt, or a maintainer-approved document
explicitly named by the user. A plan's existence is not evidence of approval.

## Resolve target SoCs and configurations

Resolve `Target SoCs` from the current request, approved hand-off, frozen
specification, or an explicitly selected committed profile. Do not default to
Mini. Use a unique existing mapping without asking the user to repeat it;
otherwise resolve missing or ambiguous targets before product-specific work.
Check that each profile's SOC, PDK, variant, and feature capabilities agree
with the approved target. Return `SPEC_CONFLICT` for inconsistent selections
instead of changing the target or profile silently.

Read `docs/soc-family-positioning.md`, `configs/README.md`, the selected product
guides, and executable build/regression definitions. Discover the product RTL,
topology/address map, filelists, and software composition for each selected
series. Mini LP/HP architecture is relevant only when the target uses it; do not
assume its CPU topology, bus widths, DMA/IRQ allocations, memory, or clock/reset
domains apply to another series.

Std, Pro, or later series may lack executable profiles. Identify what is
missing. Preflight may plan creation of those inputs only when the frozen
phase explicitly includes platform enablement. Otherwise return `BLOCKED` for
missing prerequisites or `ARCH_CHANGE_REQUIRED` for a needed scope change.
Never invent a runnable profile, `--soc` value, or validation result.

For shared-IP changes, identify all existing consumers affected by the patch,
including consumers outside the requested integration target. Keep their ABI,
default parameters, reset semantics, and software behavior compatible, and
include their affected checks. This compatibility work does not authorize new
features or a rollout into other series. Keep shared IP and product-specific
integration changes distinguishable in the plan and hand-off.

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

For an approved style/naming/structural migration, read the
[behavior-preserving migration reference](references/rtl-migration.md) before
planning or editing. It adds consumer and equivalence checks without expanding
the frozen phase or granting permission for unrelated cleanup.

## Preflight stage

Run `preflight` in Plan mode or under a read-only permission profile. Do not
modify files, run rewriting formatters, update generated artifacts, or change
architecture.

Map the approved phase onto:

- target SoCs and their specification, committed profile, and PDK mappings;
- existing modules and Common components to reuse;
- files to create and modify;
- address, interrupt, DMA, clock/reset, CDC/RDC, and lifecycle integration;
- handwritten SystemVerilog and C register definitions plus a parity test;
- standalone, integration, formal, firmware, regression, and documentation
  evidence;
- exact acceptance criteria and the smallest useful validation order.

Bind the plan and its approval to this target set, phase, and specification
revision. A plan approved for one product does not approve a different product.

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

Read the [regression reference](references/regression.md) when mapping or
executing an acceptance matrix. During preflight use its planning and evidence
rules only; execution still requires the existing implementation approval.

Derive the minimum gates from `AGENTS.md`; do not preserve command lines copied
from an older conversation when executable configuration differs. Run focused
tests first, then format/style/policy, firmware, behavioral integration, and
the affected regression in that order.

For hardware-facing acceptance, select supported commands per target SoC,
committed profile, and PDK. Inspect `scripts/regress.py` before choosing a suite
or selector; use an explicit supported `--soc` to avoid an accidental combined
or default product matrix. Use direct profile-specific Make targets when the
suite does not cover the requested configuration. Verify the matrix with
`--dry-run` before a long regression. See the
[prompt handbook](../../feature-development-prompts.md) for labeled examples,
not universal acceptance commands.

Use the success/failure rules from each selected testbench and build target.
Tiny's current `netsim-boot` requires `SIM_TEST_PASS`. The applicable Mini
assembly boot-only target uses `Hello retroSoC!`; that marker is not sufficient
for Tiny or a full firmware acceptance test. Only use early termination where
the selected target implements it, and continue remaining STA, warning, and
metric stages. A success marker does not excuse a failing command or error log.

Inspect the current workflows before describing CI coverage. A run filtered
with `--behavioral-only` cannot supply synthesis, netlist, STA, or physical
evidence. Keep results separated by target SoC, profile, PDK, source revision,
and build variant; label old or unavailable evidence explicitly.

Allow a Yosys synthesis up to 180 minutes before classifying it as timed out.
Keep the user informed and poll long jobs at intervals no longer than 60
seconds. A slow or silent tool is not evidence of an RTL defect. Modify design
only after a concrete error, timeout, resource failure, or reproducible root
cause has been established.

## Handoff

Report:

- target SoCs, specifications, profile/PDK mappings, and exact commands run;
- code, configuration, and public-interface changes separately;
- validation results and applicable MISRA deviations;
- every unrun gate and why it was not run;
- remaining hardware, timing, vendor, simulator, and commercial-delivery gaps.

Route unresolved failures to `$retrosoc-feature-review` in `diagnose`
mode. Do not diagnose and silently redesign within the implementation stage.
End with one complete, copyable, single-stage English prompt for the next
approved phase, diagnosis, review, or finalization action. Include the feature
slug, target SoCs, exact phase when applicable, specification path, profile/PDK
mapping, and matching evidence paths. Do not substitute another series when a
target's validation remains unavailable.
