# Shared agent task contract

Use this reference with the repository `AGENTS.md` and the executable build and
quality configuration. It does not replace a frozen SoC/IP specification or a
human approval.

## Host-neutral invocation

Skills are repository capabilities, not ChatGPT-, Codex-, or Kimi-specific
prompts. Use the host's explicit Skill invocation syntax when available. Plan
mode or a read-only permission profile is required for research, preflight,
diagnosis, and review; execution modes never override host permissions.

Ordinary documentation edits, small fixes, and Git tasks do not require a
feature slug, design freeze, or phase ID. Do not route them through the feature
workflow merely because they touch a repository used for SoC development.

## Structured handoff

Use [`../../task.schema.json`](../../task.schema.json) for a durable handoff.
A task packet carries its schema and task IDs, base revision, targets, exact
phase and specification when applicable, scope and non-goals, allowed and
forbidden paths, acceptance criteria, profiles/PDKs, execution permissions,
approval, worktree, artifacts, status, and evidence. Keep schema definitions in
Git and run-specific packets below `build/`. Use the optional `resolves_gaps`
list only when this task intentionally resolves a named entry in
`quality/validation-gaps.json`; otherwise do not use it to bypass validation.
Generate the durable [handoff](../../handoff.schema.json) with the current task
packet, retained evidence, and an explicit next action.

A copied Prompt can be generated from the packet, but it is not the only source
of truth. A plan's existence is not approval. Feature or high-risk writes need
an explicit human approval reference and the approved plan digest. Approval for
one target, phase, specification revision, or product does not authorize another.

The [Skill registry](../registry.json) records ownership, entrypoints, contract
versions, and eval corpora. The Git revision is the actual Skill version. Follow
the [shared engineering playbook](engineering-playbook.md) for operational
recovery, delivery, reuse thresholds, and contract migrations. Additive guidance
and eval changes do not require a new contract version; incompatible inputs or
outputs require a reviewed migration record.

## Task graph coordination

Use [`../../dag.schema.json`](../../dag.schema.json) for an optional task graph.
The task's `coordination` field declares dependencies, input/output artifacts,
write-set, lease owner/TTL, idempotency key, timeout and runner budgets, bounded
retry policy, attempt, resume reference, parallel eligibility, and the unique
integrator. `make agent-dag GRAPH=<graph.json>` validates the graph and emits a
plan only; it never starts agents. Read-only work may run in parallel only when
the host authorizes it. Write tasks additionally need explicit parallel
eligibility, disjoint write-sets, and distinct canonical worktrees/artifact
roots. Overlapping writes, baselines, releases, and merges remain serial under
the single integrator. `agent-lease` is dry-run by default; `EXECUTE=1` requires
graph authorization. Lease identity, dependencies, attempt and expiry are
checked before acquire, heartbeat, or release.

## Resolve inputs and targets

Resolve inputs in this order:

1. explicit fields in the current request;
2. an unambiguous action in the current request;
3. the current conversation and its explicitly approved handoff;
4. an explicit specification path;
5. one unique matching repository specification.

Ask only when more than one interpretation remains. Preserve an existing feature
slug and phase ID verbatim; do not infer the next phase or create aliases.

Resolve `Target SoCs` from the request, approved handoff, frozen specification,
or an unambiguous selected profile. Do not default to MINI or interpret a missing
target as every series. Recheck committed profiles and executable configuration
for each task. Planned targets can be researched and preflighted, but their
missing platform and validation inputs must remain explicit.

For shared IP, separate the common contract from product integration. Identify
all affected existing consumers without treating compatibility work as approval
to roll out a feature to another product.

## Constraint vocabulary

Normalize additional constraints as:

- `MUST`: required for the task;
- `MUST NOT`: prohibited;
- `PREFER`: select only when compatible with stronger requirements;
- `DEFER`: outside the current stage;
- `ACCEPTANCE`: objectively verifiable completion condition.

Repository policy takes precedence, followed by an approved frozen specification
and then approved task constraints. A temporary constraint cannot override an
architecture, ABI, safety, or verification contract. Expose conflicts instead of
silently weakening them.
