# GitHub Automation

This directory owns repository automation metadata: pull-request templates,
CODEOWNERS, Dependabot configuration, reusable actions, and CI/release
workflows.

The default [pull request template](pull_request_template.md) captures scope,
interface impact, validation evidence, and remaining risks. Follow the
[contribution process](../CONTRIBUTING.md) and
[Git workflow](../docs/git-workflow.md): ordinary PRs target `dev` and default
to merge-commit integration. Workflow definitions do not prove that remote
branch or tag protection is enabled.

## Change selection and quality

`workflows/_change-impact.yml` uses `scripts/agent_control.py` and
`quality/change_impact.json` to select jobs conservatively. Unknown paths and
classification errors fail closed to the full matrix. Push, scheduled, and manual
full-flow events do not use PR path skipping. Each heavy workflow retains an
always-run gate so a skipped job cannot silently satisfy a required check.

`workflows/quality.yml` is split into `fast`, `fixtures`, and `quality-gate`:

- `fast` runs dependency, formatting, C policy, host, agent, YAML/Actions, and
  regression-definition checks without restoring PDKs or accelerator corpora.
- `fixtures` restores the locked IHP130 and Tiny ICS55 PDKs, third-party models,
  and APU/NPU references, then runs the complete Pytest suite with JUnit and
  duration reports. It is skipped only for classifications that do not need it.
- `quality-gate` accepts an intentional fixtures skip but never hides an impact,
  fast, fixtures, or cancellation failure.

The quality checkout retains repository history. After preparing current RTL
dependencies, `python3 tests/publication_history.py prepare` fetches missing
immutable dependency commits without changing active dependency HEADs or locks.

`workflows/contribution.yml` validates PR base/head/title, new commit subjects,
and CODEOWNERS consistency. `quality/ownership.json` records backup-owner gaps;
an empty backup is a warning for organizational follow-up, not permission for
agent self-approval.

While only `@maksyuki` can review PRs, `review_policy.mode` is
`sole_maintainer`: GitHub does not require a peer approval count, because an
author cannot approve their own PR. `auto_merge` allows CI-green PRs to merge
with merge commits and safe cleanup, while design and architecture approvals
remain manual. The helper checks every required protected context before
enabling GitHub's native auto-merge. Failed or pending checks, dirty worktrees,
and non-canonical branches always block merging and cleanup. Peer CODEOWNERS
approval is restored when another eligible reviewer is available.

## Regression and evidence

`workflows/regression-smoke.yml`, `regression-ihp130.yml`,
`regression-gf180.yml`, `regression-ics55.yml`, `regression-sky130.yml`, and
`nightly.yml` call `_regression.yml`. PR invocations remain behavioral-only:
SoC Yosys synthesis, OpenSTA, and netlist simulation are filtered while the JPEG
synthesis-memory issue remains. `scripts/ci_summary.py` marks those stages
`NOT_RUN` and filters out artifacts older than the current run start.

PR regressions keep the Icarus assembly self-test but exclude the multi-hour
Tiny P7 Icarus command by default. `nightly.yml` runs that same command in
independent IHP130 and ICS55 jobs with their existing acceptance and timeout
contracts. This preserves coverage without holding every PR open for hours.

`workflows/full-flow.yml` is an explicit manual full-flow entrypoint. Its runner
input allows a provisioned high-memory runner; no such capacity is inferred from
the default `ubuntu-22.04` label. A full-flow summary requires synthesis, netlist,
and STA evidence and retains failed attempts. `scripts/yosys_progress.py`
provides read-only phase-step, executing-pass, rerun-marker, and elapsed-time
analysis before any timeout increase. Missing subsequent phases are not treated
as proof of an infinite loop or insufficient memory.

`workflows/formal.yml` runs the explicit per-proof targets except GA2D as
bounded parallel jobs on its weekly schedule or manual dispatch. GA2D remains a
local acceptance target because its diagnostic peak RSS was about 121 GiB;
hosted attempts lacked a proof verdict. Its local bounds and 7200s task budget
are unchanged. A hosted success does not cover GA2D, and missing local evidence
is not a proof pass. See [Formal Protocol Proofs](../docs/engineering.md#formal-protocol-proofs)
for the exact local command and evidence requirements. Smoke `formal_checks`
still runs only `formal-doctor`; SV2V conversion alone is not a proof pass.

`workflows/development-environment.yml` verifies Docker and Nix for environment,
dependency, build-entry, scheduled, and full-matrix changes instead of repeating
both environments for every unrelated PR. The `locked-tools` action bounds apt
updates to 180 seconds and installs to 600 seconds per attempt, with at most
three attempts and a bounded 120-second dpkg lock wait, so network failures and
concurrent package-manager activity cannot stall a job indefinitely.
`workflows/engineering-metrics.yml` collects weekly delivery and CI metadata
artifacts for engineering improvement, not individual performance evaluation.
`workflows/skill-evals.yml` is a manual entrypoint for a runner with a configured
Codex CLI and approved model access. It fails explicitly when that capability is
absent and never converts static corpus validation into a behavior pass.

After a new required-check context exists on the integration branch, a repository
administrator should enable it in branch protection. Do not configure contexts
before the corresponding workflow is merged and available. Current intended
contexts are `quality-gate`, `contribution-gate`, `environment-gate`, and each
PDK caller's `regression-gate`; release/full-flow/formal schedules are evidence
inputs rather than per-PR required contexts.

## Release

`workflows/release.yml` requires a tracked `quality/release-candidate.json` at
the immutable `vMAJOR.MINOR.PATCH` tag. The candidate declares the target `main`
branch, dependency-lock digest, approved release PR, required stages, workflow
names, and any accepted non-required gaps. The validator resolves the tag and
successful workflow runs dynamically, so the candidate does not attempt the
impossible task of embedding its own future commit SHA or run IDs.

A release requires a merge commit matching the tag and current `origin/main`,
successful required workflow runs, and valid hashes for required local
artifacts. Optional `local_checks` allow revision-matched local formal evidence
instead of a hosted proof job. The validator requires a clean manifest and
passing prove/cover results; it does not embed self-referential summary hashes.
In `sole_maintainer` mode, a merged release PR with the named maintainer's
approval record is sufficient; peer mode instead requires an APPROVED review by
that maintainer. Existing release assets are not overwritten on rerun. See
`quality/release-candidate.schema.json` and `scripts/check_contribution.py`.

Keep Actions pinned by commit ID and use the dependency lock rather than adding
ad-hoc downloads. Validate workflow changes with `yamllint .github .yamllint.yml`,
`actionlint`, and both regression dry-runs. See the root
[agent contract](../AGENTS.md).
