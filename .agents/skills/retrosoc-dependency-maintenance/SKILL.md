---
name: retrosoc-dependency-maintenance
description: Inspect, restore, or upgrade locked retroSoC dependencies and development environments. Use for toolchains, managed sources, PDK inputs, Python locks, and publication resources; distinguish restoring the current lock from changing versions. Not feature implementation or ad hoc package installation.
---

# retroSoC Dependency Maintenance

Keep installed inputs and reproducible configuration consistent. Read
[AGENTS.md](../../../AGENTS.md), the
[dependency guide](../../../dependencies/README.md), and the applicable
[maintenance reference](references/maintenance.md) before acting.

## Resolve intent and scope

Accept `Mode: inspect`, `restore`, or `upgrade`, and `Scope` naming the dependency
entries or environment. An upgrade also needs a selected target version/full
revision or an authorized version-selection request. Infer these from clear
natural language and named lock entries; ask only when the choice remains
ambiguous. A global development-tool task does not require a SoC, feature slug,
specification, or phase. Identify target products/profiles when their inputs or
validation are affected.

- `inspect`: read locks, manifests, installed state, and helper implementations;
  report mismatches, impact, and next steps. Do not bootstrap, fetch, rewrite
  locks, or run setup/doctor targets with mutating prerequisites.
- `restore`: use repository helpers to prepare the currently locked inputs and
  validate the selected environment. Do not change any tracked lock or version.
- `upgrade`: verify the selected upstream identity and integrity, update only
  authorized lock entries and necessary consumers, then run their applicable
  setup and validation steps.

An installation failure is not permission to upgrade. A request to assess an
upgrade is inspection, not approval to apply it. Continue an explicit restore
or upgrade through its checks; do not add an IP design-freeze gate. Ask before
changing scope, choosing an unspecified release, overwriting user work, or
taking an external action not authorized by the task.

## Establish reproducible inputs

Inspect the exact dependency keys and their callers. Read the current lock
schema and helpers rather than assuming all inputs are Git repositories.
Check the applicable complete Git revisions, archive SHA-256 values, OCI
digests, Nix revision/NAR hashes, and hash-pinned Python requirements. Account
for side-by-side publication package versions instead of collapsing them.

Map the proposed change to managed checkouts, environment stamps, setup/doctor
entrypoints, generated products, and affected existing consumers. Shared
dependencies may require Tiny and Mini checks even if the initiating task names
one product; this does not authorize new product features.

For an upgrade, obtain version and checksum evidence from the upstream release
or repository and use the repository's locking workflow. Keep related lock
files and declared versions consistent. Do not invent a digest, replace a pin
with `latest`, add a direct download to a build/workflow, or bypass verification.
Runtime/bootstrap and PDK/managed-source installation are separate operations;
prepare only the inputs needed for the authorized task.

## Execute safely

Use the existing entrypoints identified in the reference, after checking their
current arguments and side effects. Preserve dirty managed checkouts, modified
asset inventories, unrelated worktree changes, and reusable user caches.

If integrity verification fails, the host is unsupported, or a helper would
overwrite dirty inputs, stop that mutation and retain the diagnostic evidence.
Do not reset repositories, purge broad caches, switch versions, disable a hash
check, or fetch an alternative archive as an automatic repair. Explain the
specific recovery choice needed; continue independent read-only checks.

When a compatible host or installed tool is missing, report it instead of
installing global packages or rewriting the environment architecture. Respect
network and filesystem permissions. Do not commit, push, release upstream
assets, or modify hosted workflows unless that action is part of the request.

## Validate and deliver

Derive validation from the changed consumers and root contract. Validate lock
consistency, installed versions and digests, and the affected setup/doctor,
tests, environment, and regression paths. Never use a changed warning baseline
or relaxed metric policy to hide an upgrade regression.

Report mode and scope, old/new pins (unchanged for restore), integrity evidence,
affected products/profiles, tracked versus cache-only changes, exact commands,
results, and unrun gates with reasons. Label a failed or partial installation
truthfully; a valid lock alone does not prove that the environment or hardware
flow works. Separate any required code fix from an unapproved dependency change.
