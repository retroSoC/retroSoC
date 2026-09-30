---
name: retrosoc-physical-flow
description: Preflight, run, resume, or summarize retroSoC physical implementation through the existing LibreLane, ECC, or commercial EDA adapters. Use for flow selection, constraints, stage recovery, and provenance-bound PPA reports; not RTL feature development or unsupported signoff claims.
---

# retroSoC Physical Flow

Operate the selected repository flow without silently changing the design,
technology, or evidence boundary. Read [AGENTS.md](../../../AGENTS.md),
[physical ownership](../../../physical/README.md), and the selected flow
reference before choosing commands.

## Resolve inputs and mode

Accept `Mode: preflight`, `run`, `resume`, or `summarize`, `Target SoCs`, a
committed `Profile`, `PDK`, `Flow`, and the requested `Stage` or deliverable.
Resume and summary requests also identify the original run/artifact directory;
the commercial flow needs its actual `Run ID` and site-local configuration.
Infer consistent values from explicit paths and clear task context. Ask when
multiple runs, profiles, or targets fit; never default to Mini or invent a
site path. No frozen feature specification or phase is required for flow work.

- `preflight`: inspect profiles, input identities, tool/environment availability,
  constraints, collateral, and existing reports. Return the executable plan
  and missing prerequisites without installing inputs, generating RTL,
  launching EDA tools, or submitting jobs. A target named `doctor` is not
  necessarily read-only; inspect its prerequisites before calling anything.
- `run`: execute the selected stages and their required prerequisites within
  the authorized scope, then check and summarize their outputs.
- `resume`: establish the original input/run identity, verify completed-stage
  evidence, and use only the selected flow's supported recovery mechanism.
- `summarize`: read existing reports and artifacts; do not rerun stages or
  rewrite their results merely to fill missing evidence.

Continue an authorized run through its requested endpoint without per-stage
confirmation. Ask only when a missing input, permission, scope change, or
destructive recovery decision prevents correct progress. Never reinterpret a
preflight/summary as permission to run. Honor additional constraints without
weakening timing, integrity, or signoff requirements.

## Route to an existing adapter

Load only the applicable reference, completely:

- [LibreLane](references/librelane.md): current IHP130 Mini core/chip and Tiny
  chip flows; Tiny has no Mini core target.
- [ECC](references/ecc.md): current ICS55 Mini padless-core hardening, not an
  IO-ring or full-chip flow.
- [Commercial EDA](references/commercial.md): current ICS55 Mini development
  package and site-side synthesis/implementation stages.

Verify support from current Makefiles, profile values, helpers, and tool locks.
For an unsupported product/PDK combination, report its missing adapter and
collateral instead of substituting a different flow or creating a profile.
Routine smoke synthesis/STA belongs to the existing
[regression guide](../retrosoc-feature-implementation/references/regression.md),
not a claim of routed implementation.

## Execution and recovery

Bind the run to the source revision and any dirty-input state, effective
configuration, dependency/tool identities, constraints, and input hashes.
Maintain a stable variant/timestamp or run ID across related commands. Never
reuse reports or completion stamps with mismatched inputs, and never claim a
dirty candidate satisfies a flow that requires a clean committed revision.

Run through the existing wrappers and submission mechanisms. Keep licensed
tools, proprietary collateral, site paths, and local configuration within the
documented execution boundary; do not copy them into tracked files or expose
their contents in a public handoff. Preserve generated results below the
selected flow's build root.

Poll long jobs at intervals no longer than 60 seconds and keep the user informed.
Use each flow's configured timeout; retain the existing 180-minute Yosys
allowance where Yosys is used. Silence alone is not a failure. On a concrete
error, retain the first failing stage, logs, exit code, and resource evidence.
Diagnose before proposing a design/constraint change; do not patch RTL or relax
constraints just to get a passing run.

For recovery, inspect the result contract, required outputs and upstream
dependencies, not just a stamp or folder name. Do not invent resume switches,
touch success stamps, or continue downstream of invalid evidence. Forced
reruns, cleanup, and expanded resource/stage scope require corresponding user
authorization. If no supported safe recovery exists, report the needed choice.

## Evidence handoff

Produce Markdown grouped by target, profile, PDK, source/input identity, run,
corner, and stage. Include exact commands, exit/verdict evidence, artifact
paths, tool/constraint identity, measured cell count/area/WNS/TNS when present,
and clock targets versus actually supported frequency claims. Do not derive
an unsupported Fmax from a single slack value.

Use `NOT_RUN` or `not reported` for missing stages/metrics. Separate internal
QoR from qualified I/O timing, core hardening from chip implementation, and
development results from production signoff. Report unconstrained paths,
missing corners, DRC/LVS/IR/EM/ESD, package, board, or silicon gaps according to
the selected flow. Do not merge results from different runs into one passing
result or publish, commit, or push as an implicit final step.
