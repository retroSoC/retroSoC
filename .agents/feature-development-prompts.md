# retroSoC Manual Feature Development Prompts

Use these English prompts for any retroSoC series. Choose the target products
before starting product-specific work; a series name is not proof that an
executable platform exists. The root [agent contract](../AGENTS.md) and current
build configuration govern validation.

## Contents

- [Inputs and target selection](#common-fields-and-target-selection)
- [Research](#1-research-a-feature), [freeze](#2-freeze-the-approved-specification),
  [preflight](#3-preflight-one-frozen-phase), and [implementation](#4-implement-and-continue)
- [Tiny and shared IP](#5-tiny-and-shared-ip-examples), [planned series](#6-planned-series)
- [Diagnosis and fixes](#7-diagnose-and-fix), [review](#8-review-the-implementation)
- [Acceptance matrix](#9-run-the-selected-acceptance-matrix), [finalize](#10-finalize-evidence)

## Invocation and stages

In ChatGPT Work select `@retrosoc-feature-design` or
`@retrosoc-feature-review`. In Codex use `$retrosoc-feature-design`,
`$retrosoc-feature-implementation`, or `$retrosoc-feature-review`.
The review examples below use Codex syntax; replace `$` with `@` when running
the review skill in ChatGPT Work.

| Stage or mode | Skill | Plan mode | File changes | Human decision |
| --- | --- | --- | --- | --- |
| `research` | `retrosoc-feature-design` | Yes | None | Approve architecture |
| `freeze` | `retrosoc-feature-design` | No | Documentation | Approve target contract |
| `preflight` | `retrosoc-feature-implementation` | Yes/read-only | None | Approve implementation plan |
| `implement` | `retrosoc-feature-implementation` | No | Approved phase | Accept phase evidence |
| `diagnose` | `retrosoc-feature-review` | No/read-only | None | Resolve root cause or missing evidence |
| `review` | `retrosoc-feature-review` | No/read-only | None | Resolve findings |
| `finalize` | `retrosoc-feature-review` | No/read-only | None | Accept delivery evidence |

## Common fields and target selection

Use `Stage` for design/implementation and `Mode` for review. The following is a
field template, not a literal command to execute:

```text
Stage or Mode: <selected stage or mode>
Feature slug: <lowercase-kebab-case>
Target SoCs: <one series or an explicit comma-separated list>
Phase: <existing frozen phase ID and title, when applicable>
Specification: docs/ip/<feature-slug>.md
Profiles: <existing per-target profiles, if already selected>
PDKs: <the PDKs selected by those profiles>

Additional constraints:
- MUST: <required behavior>
- MUST NOT: <prohibited behavior>
- PREFER: <choice compatible with the frozen contract>
- DEFER: <work outside this phase>
- ACCEPTANCE: <verifiable completion condition>
```

- `Target SoCs: TINY` and `Target SoCs: TINY, MINI` select different scopes.
  An explicit specification/profile or approved hand-off can provide an
  unambiguous target. Missing or contradictory targets need resolution; there
  is no Mini default and no implicit all-products rollout.
- Keep the existing feature slug and specification path. A shared IP can keep
  one specification with per-series integration sections; do not duplicate its
  register ABI into conflicting documents.
- Copy frozen phase IDs/titles verbatim. `TINY-P4`, `APU-P4`, and
  `Phase 1 - APB4 CSR and interrupt skeleton` illustrate valid stable schemes.
  Do not rename or renumber an existing phase or guess "next phase" in a new task.
- Select profiles from [configs](../configs/README.md) and verify their SOC/PDK
  and supported features. Mini LP/HP, AXI widths, DMA channels, IRQ numbers and
  clock/reset assumptions do not transfer automatically to Tiny or other series.
- Check [product positioning](../docs/soc-family-positioning.md) and current
  executable configuration. Tiny/Mini currently have profiles; Std/Pro remain
  roadmap targets. Design and preflight can describe platform prerequisites,
  but implementation may create them only within an approved enablement phase.

## 1. Research a feature

Host: ChatGPT Work, Plan mode. This example is an illustrative new Mini IP;
replace the feature and target fields for another product.

```text
@retrosoc-feature-design

Stage: research
Feature slug: audio-processing-unit
Target SoCs: MINI

Research and design this feature for the selected product.
Additional constraints:
- MUST: Support 16-bit, 24-bit, and 32-bit PCM samples.
- MUST: Define AXI4/APB4, DMA and interrupt integration for this product.
- MUST NOT: Add floating-point processing to the MVP.
- PREFER: Reuse compatible Common components.
- DEFER: Sample-rate conversion to the commercial roadmap.
- ACCEPTANCE: Recommend an MVP, target architecture and ordered phases.
Do not modify repository files.
```

Expected output: repository/commercial evidence, target-specific architecture,
shared-IP boundaries, selected profiles/PDKs or missing prerequisites, phases,
and open questions. Human Gate 1 approves this design before `freeze`.

## 2. Freeze the approved specification

Host: ChatGPT Work, outside Plan mode; documentation only.

```text
@retrosoc-feature-design

Stage: freeze
Feature slug: audio-processing-unit
Target SoCs: MINI
Specification: docs/ip/audio-processing-unit.md

Freeze the design approved in this conversation. Preserve its target scope,
profile/PDK mapping, ABI and stable phase IDs. Separate common IP behavior
from product integration and planned capabilities from implemented evidence.
Update the documentation index. Do not implement RTL.
```

Expected output: frozen contract and optional verification companion, plus a
preflight prompt containing the target SoCs, phase, profile/PDK and constraints.

## 3. Preflight one frozen phase

Host: Codex, Plan mode or read-only. The phase below is illustrative; use the
ID/title in the actual frozen specification.

```text
$retrosoc-feature-implementation

Stage: preflight
Feature slug: audio-processing-unit
Target SoCs: MINI
Phase: Phase 1 - APB4 CSR and interrupt skeleton
Specification: docs/ip/audio-processing-unit.md

Map only this phase to the repository and supported profile/PDK matrix.
Additional constraints:
- MUST: Preserve the approved register and interrupt ABI.
- MUST NOT: Change existing DMA allocation outside this phase.
- DEFER: FIFO and DMA datapaths to their frozen phases.
Do not modify files.
```

Human Gate 2 approves an `IMPLEMENTABLE` result. Resolve `SPEC_CONFLICT`,
`ARCH_CHANGE_REQUIRED`, or `BLOCKED` before implementation. A plan approved
for Mini does not authorize substituting Tiny or adding a second series.

## 4. Implement and continue

Host: Codex, outside Plan mode. In the same task, explicitly approve the
preflight and implement only that phase:

```text
$retrosoc-feature-implementation

Stage: implement
Feature slug: audio-processing-unit
Target SoCs: MINI
Phase: Phase 1 - APB4 CSR and interrupt skeleton
Specification: docs/ip/audio-processing-unit.md
Approved preflight source: the plan above, which I approve for this target.

Implement this phase, preserve handwritten SVH/C parity, and run the approved
focused and product-specific gates. Report commands, profile/PDK mappings,
evidence and unrun checks. Do not implement later phases early.
```

In a new task, supply the same target/phase fields and the approved plan:

```text
Approved preflight source: pasted below; approved for the stated Target SoCs.
[PASTE THE APPROVED PLAN, PROFILE/PDK MAPPING AND ACCEPTANCE CRITERIA]
```

Alternatively name an existing maintainer-approved document. A plan's existence
alone is not approval. Implementation returns a copyable next-step prompt;
start the next frozen phase manually:

```text
$retrosoc-feature-implementation
Stage: preflight
Feature slug: audio-processing-unit
Target SoCs: MINI
Phase: <copy the next approved phase ID and title>
Specification: docs/ip/audio-processing-unit.md
Do not modify files.
```

## 5. Tiny and shared-IP examples

Tiny already uses product-specific phase IDs. This example inspects the
existing baseline qualification phase, not a claim that a newer Tiny target
has been implemented:

```text
$retrosoc-feature-implementation
Stage: preflight
Feature slug: tiny-soc
Target SoCs: TINY
Phase: TINY-P4
Specification: docs/ip/tiny-soc.md
Profiles: configs/ci/ihp130-tiny.mk
PDKs: IHP130
Check the exact frozen phase scope and current evidence. Do not modify files.
```

For an approved shared-IP change, enumerate the selected products:

```text
$retrosoc-feature-implementation
Stage: preflight
Feature slug: uart
Target SoCs: TINY, MINI
Phase: <copy the approved shared-IP phase ID and title>
Specification: docs/ip/uart.md
Profiles: configs/ci/ihp130-tiny.mk, configs/ci/ihp130.mk
PDKs: IHP130
MUST preserve the common UART ABI and each product's default behavior.
Identify shared RTL/HAL consumers and each target's affected checks.
Do not add peripherals to either product or modify files during preflight.
```

Even a single-target patch to shared RTL must check affected existing consumers;
compatibility testing does not authorize new integration into those products.

## 6. Planned series

Research can target a product that has no executable profile yet:

```text
@retrosoc-feature-design
Stage: research
Feature slug: coherent-accelerator
Target SoCs: STD, PRO
Research the selected products' architecture and shared-IP boundaries.
Separate roadmap requirements from implemented support. Identify platform,
profile, software and validation prerequisites. Do not modify files.
```

Preflight must report missing platform support. It may plan profile/top-level
creation when the frozen phase explicitly authorizes platform enablement;
otherwise it reports the missing prerequisites or scope change. Do not invent
`--soc STD` or `--soc PRO` commands when the current runner does not support them.

## 7. Diagnose and fix

Host: Codex or ChatGPT Work; diagnosis is read-only.

```text
$retrosoc-feature-review
Mode: diagnose
Feature slug: tiny-soc
Target SoCs: TINY
Specification: docs/ip/tiny-soc.md
Profiles: configs/ci/ihp130-tiny.mk
PDKs: IHP130
Failing command: <exact command>
Log and structured result: <matching artifact paths>
Identify the first failure, root-cause boundary and acceptance test.
Do not modify files or treat a slow or silent tool as an RTL defect.
```

After diagnosis, use the implementation skill outside Plan mode:

```text
$retrosoc-feature-implementation
Stage: implement
Feature slug: tiny-soc
Target SoCs: TINY
Phase: <affected frozen phase ID>
Specification: docs/ip/tiny-soc.md
Approved preflight source: <approved plan or explicitly approved fix hand-off>
Confirmed root cause: <diagnosis>
Acceptance test: <exact test>
Fix only the confirmed cause. Rerun the failed and affected gates, including
other existing consumers if the fix touches shared IP.
```

## 8. Review the implementation

Host: Codex or ChatGPT Work; read-only. Replace `dev...HEAD` with the intended
commit range or `uncommitted changes` when the work is not committed.

```text
$retrosoc-feature-review
Mode: review
Feature slug: tiny-soc
Target SoCs: TINY
Specification: docs/ip/tiny-soc.md
Profiles: configs/ci/ihp130-tiny.mk
PDKs: IHP130
Review range: dev...HEAD
Review introduced changes against the frozen phase and approved constraints.
Check target/profile consistency, shared-IP compatibility, ABI, DMA/IRQ,
clocks/resets/CDC, validation and evidence. Report P0-P3 findings without edits.
```

## 9. Run the selected acceptance matrix

Inspect `scripts/regress.py`, the selected profiles and product build rules
before a long run. These are current IHP130 examples, not family-wide defaults.

Tiny only, including its dedicated netlist boot image:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY --dry-run
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc TINY
```

Mini only, using the applicable assembly boot-only shortcut:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI --netsim-boot-only --dry-run
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --soc MINI --netsim-boot-only
```

For other supported PDKs or feature profiles, derive the actual matrix and any
additional direct Make targets; do not merely replace a PDK name in an example.
A shared change requires affected checks for each supported consumer in scope.

Tiny `netsim-boot` requires `SIM_TEST_PASS`. The applicable Mini assembly
boot-only flow uses `Hello retroSoC!`. Respect each target's exit status and
failure-marker checks, and continue remaining STA/warning/metric stages.
Boot smoke does not establish full feature or firmware acceptance.

Keep the existing 180-minute Yosys wait rule unless the task or executable flow
sets another explicit budget. Poll long runs in short intervals and diagnose
failures before changing design. Preserve source revision, profile/PDK, build
variant and evidence paths. Read actual CI workflow invocations before claiming
coverage; `--behavioral-only` runs do not supply physical-flow evidence.

## 10. Finalize evidence

Host: Codex or ChatGPT Work; read-only. Missing physical results remain gaps.

```text
$retrosoc-feature-review
Mode: finalize
Feature slug: uart
Target SoCs: TINY, MINI
Specification: docs/ip/uart.md
Profiles: configs/ci/ihp130-tiny.mk, configs/ci/ihp130.mk
PDKs: IHP130
Evidence: <artifact paths for each target and current source revision>
Report validation and synthesis/STA metrics separately by SoC/profile/PDK,
source revision and build variant. Include commands, public-interface changes,
MISRA deviations and unrun gates. Do not use one target's results to qualify
another. Use NOT_RUN or not reported for absent measurements.
```

Human Gate 3 reviews unresolved findings and required evidence. End with one
next action: `MERGE`, `FIX_P0_P1`, `RUN_GATES`, `REFREEZE_SPEC`, or `INVESTIGATE`.
`MERGE` remains a human action. Other actions include a next-step prompt carrying
the target SoCs, phase, profile/PDK mapping and evidence references.

## Constraint conflicts

Research compares new constraints with repository and external evidence. Freeze
makes approved long-lived constraints normative. Preflight reports conflicting
target/profile or requirement choices instead of overriding the frozen contract.
Implementation follows the approved target/phase plan; review distinguishes
approved requirements from proposed changes. Existing frozen phase IDs stay intact.
