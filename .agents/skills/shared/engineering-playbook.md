# Shared engineering playbook

Use these operational rules through an existing domain Skill. This is a shared
playbook, not another registered Skill and not permission to execute a flow.
Apply the task's original scope, approval, host permissions, target profile,
source revision, and [evidence contract](evidence.md).

## Classify CI before recovery

1. Bind the PR head and branch-protection contexts with `pr_workflow.py`'s
   structured API. Pending, missing, cancelled, failed, and empty evidence are
   not PASS.
2. Run `python3 scripts/ci_recovery.py inspect --job <id> --output <json>` to
   classify the failed job and retain its step/resource evidence. Inspection is
   dry-run by default and must not print credentials.
3. Only an explicitly requested `--execute` may rerun a first-attempt, same-head,
   recognized infrastructure failure. Source/test, timeout, cancellation,
   integrity, and unknown failures are not automatically retried. Never weaken
   a test or mark a rerun as a fix without its new evidence.
4. Use the current shard/fan-in summaries for fixtures. Missing, duplicate, or
   unexpectedly skipped evidence fails closed; cache observations are not
   cached verdicts. For an opted-in parallel MINI run, retain
   `parallel-iverilog.json` and both isolated result trees; either group failure
   fails the regression. Never substitute this for nightly or full-flow evidence.

## Cancel, recover, and hand off long tasks

Start supported long commands through `run_flow.py` with a task ID, explicit
result/log paths, and a deadline. Use `--status` before deciding whether work is
active. Use `--cancel` only for that run identity; normal compiler descendants
receive their bounded grace period, while stale or over-limit descendants are
cleaned without signaling unrelated process groups.

Use `--resume` only with the same source, command, configuration, environment,
tool lock, and checkpoint/output digests. Active leases and changed or corrupted
state block reuse. Failed attempts are retained; interrupted work is not PASS.
Do not increase a timeout or resource scope without authorization and evidence.
Record the next action with `make agent-handoff TASK=<task.json> NEXT=<action>`.

## Deliver a short-lived PR

After scope approval and local validation, use `make agent-deliver PR=<number>`.
It checks canonical ownership, required contexts, repository capabilities, and
push permission before enabling GitHub native merge-commit auto-merge while
checks may be pending. Use `PREFLIGHT=1` for a read-only probe and `WATCH=1` when
live monitoring and immediate reconciliation are requested. Without `WATCH`,
perform `RECONCILE=1` after the merge.

GitHub is the only merge authority. Do not use `--admin`, squash/rebase
integration, direct protected-branch pushes, or self-approved architecture
waivers. Failed checks and externally disabled auto-merge stop the live watcher.

## Preserve evidence and clean safely

Use `make worktree-registry` for a dry-run inventory. Only clean, registered,
non-detached, canonical branches below `build/agent-worktrees/` and contained in
`origin/dev` are cleanup candidates. Move retained `build/` evidence to the main
worktree before removal. Dirty, unmerged, detached, orphaned, non-canonical, or
evidence-conflicting paths remain untouched.

Record deferred or blocked validation in `quality/validation-gaps.json` with an
owner and review date. `NOT_RUN`, `SKIPPED`, `DEFERRED`, and `BLOCKED` never
become PASS by handoff, behavior CI, optimization equivalence, or a later
summary. Mini Yosys synthesis/netlist/STA evidence remains separate.

## Reuse and version Skills

Promote a shared playbook into a registered Skill only after at least three task
classes reuse stable inputs/outputs, ownership is clear, and behavior evals
exist. Do not create one Skill per incident. The Git revision is the actual
Skill content version. Keep `contract_version=1` for additive guidance or eval
changes. Increase it only for incompatible input/output contracts and register
a `contract_migration` document explaining migration and compatibility evidence.

Static corpus validation is not behavior execution. Run live evals only in the
isolated read-only runner and retain its trace, runner/model, Skill SHA,
contract version, input snapshot, workspace tree, and grades. An unavailable
runner is NOT_RUN, not a behavior pass.
