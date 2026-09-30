# retroSoC Engineering Workflow Prompts

Use these English prompts for publication, dependency, and physical-flow work.
Use the [feature handbook](feature-development-prompts.md) for IP design and
approved implementation phases. The [agent contract](../AGENTS.md), current
subsystem guides, executable configuration, and permissions remain authoritative.

## Invocation and scope

Use an explicit skill mention and a clear action. Field labels are optional
when intent and the target are unambiguous; do not invent a feature slug or
phase for maintenance. Replace example artifact paths and version identifiers
with real inputs. Do not run placeholder commands literally.

| Skill / mode | Plan mode | Allowed work | Expected delivery |
| --- | --- | --- | --- |
| Datasheet `inspect` | Recommended | Read sources and existing evidence | Gaps and proposed update scope |
| Datasheet `update` | No | Requested publication edits, build and checks | PDF, manifest, comparison and gaps |
| Datasheet `validate` | No for executing checks; Plan for a check plan | Checks and build-local reports, no source edits | Source/PDF verdict and missing checks |
| Dependency `inspect` | Recommended | Read locks and installed state | Mismatches and impact |
| Dependency `restore` | No | Prepare current locked inputs | Installed-state evidence; unchanged pins |
| Dependency `upgrade` | No | Authorized pin and necessary consumer changes | Old/new identities and validation |
| Physical `preflight` | Recommended | Static input/environment assessment | Supported plan and prerequisites |
| Physical `run` / `resume` | No | Authorized stages and build artifacts | Stage results and traceable reports |
| Physical `summarize` | Recommended | Read existing artifacts | Per-run/corner results and gaps |

An execution request authorizes its normal in-scope steps, not a different
product, dependency upgrade, destructive recovery, remote publication, or
commit/push. There is no mandatory design-freeze gate for these workflows.
Inspection does not silently proceed to execution. Report blockers precisely
and continue independent safe work; ask only when a choice or authority is
missing. A prompt cannot switch the application's Plan mode off by itself.

Optional constraints use the existing vocabulary:

```text
Additional constraints:
MUST preserve the existing source identity and product scope.
MUST NOT modify hardware or dependency locks.
PREFER existing components and validation entrypoints.
DEFER unrelated cleanup.
ACCEPTANCE report exact checks, artifact paths, and all unrun gates.
```

Adapt those constraints to the requested mode: an approved dependency upgrade,
for example, necessarily changes its selected lock entries. Report conflicting
constraints rather than silently weakening repository policy.

## Datasheet

### Inspect the current Tiny book

```text
$retrosoc-datasheet Inspect the Tiny datasheet and its evidence gaps. Do not modify files.
```

Output is an assessment, not a newly generated PDF. Use current source/config
paths to resolve Tiny; no Mini LP/HP assumptions or hardware execution.

### Update a Mini publication

```text
$retrosoc-datasheet
Mode: update.
Target SoCs: MINI.
Scope: refresh the datasheet's technical content to the current local dev commit.
Source baseline: resolve dev to its full SHA and review the complete delta from mini.json.
Baseline PDF: build/<previous-mini-variant>/<delivered-filename>.pdf.
MUST preserve stable chapter/IP identifiers and retain the previous PDF and manifest.
MUST NOT modify RTL, firmware, locks, or quality baselines.
ACCEPTANCE build, check, visually review, and report changed pages and missing evidence.
```

For layout-only edits, replace the scope with the intended layout change and
explicitly retain the configured reviewed source SHA. If the source checkout
does not match, report the mismatch rather than advancing the book's identity.

### Validate a specific Tiny PDF

```text
$retrosoc-datasheet
Mode: validate.
Target SoCs: TINY.
PDF: build/<tiny-variant>/retrosoc-tiny-gen1-datasheet.pdf.
Check this PDF, its manifest, source bindings, and applicable visual/layout rules.
MUST NOT edit sources, fetch dependencies, or rebuild a replacement PDF.
Report actual check and visual coverage, plus anything unavailable.
```

Validation may write its existing build-local check reports. A Tiny change
comparison must use artifacts its adapter actually emits; do not assume Mini's
change-report contract. If no previous PDF is available, comparison is unrun.
For TINY and MINI together, name both explicitly and keep book identities,
outputs, hashes, and verdicts separate. Unsupported books require a separately
scoped adapter task, not copied product specifications.

## Dependency maintenance

### Inspect the development environment

```text
$retrosoc-dependency-maintenance Inspect the development environment against the current lock. Do not install or change anything.
```

This produces mismatches and a repair plan; a missing tool is not approval to
bootstrap or upgrade it.

### Restore current locked tools

```text
$retrosoc-dependency-maintenance
Mode: restore.
Scope: the repository's development tool environment on the existing supported Linux host.
Use the current committed dependency lock and pinned Python requirements.
MUST NOT change versions, lock files, dirty managed checkouts, or global packages.
ACCEPTANCE run the supported installation checks and report unchanged pins and remaining gaps.
```

### Upgrade an explicitly selected dependency

```text
$retrosoc-dependency-maintenance
Mode: upgrade.
Scope: <exact dependency-lock entry>.
Target version/revision: <reviewed upstream version or full commit SHA>.
Verify release identity and integrity, update the authorized pin and required consumers,
then run lock validation and affected setup, doctor, and tests.
MUST NOT update unrelated inputs, relax checks, commit, push, or publish.
Report old/new identities, affected products, and every unrun gate.
```

For version selection rather than a specified release, first request inspection
and candidate comparison. Restoring a managed checkout to its existing pin is
not an upgrade; a checksum failure or dirty checkout requires a recovery
decision, not bypassing verification or discarding work.

## Physical implementation

### Preflight Tiny LibreLane chip

```text
$retrosoc-physical-flow
Mode: preflight.
Target SoCs: TINY.
Profile: configs/ci/ihp130-tiny.mk.
PDK: IHP130. Flow: librelane. Stage: chip.
Assess input identity, environment, constraints, and missing prerequisites.
Do not install, generate inputs, launch EDA tools, or submit jobs.
```

### Run a selected Mini core flow

```text
$retrosoc-physical-flow
Mode: run.
Target SoCs: MINI.
Profile: configs/ci/ics55.mk.
PDK: ICS55. Flow: ecc. Stage: core.
Run the supported padless-core flow and its required checks in the prepared environment.
MUST NOT change RTL, constraints, dependency pins, or overwrite an existing run.
ACCEPTANCE retain input identity, logs, results, measured metrics, and explicit signoff gaps.
```

For Mini/IHP130 LibreLane, instead choose `configs/ci/ihp130.mk`, `Flow:
librelane`, and `Stage: core` or `chip`. Tiny has no Mini core target. Package
targets can depend on running the flow again; do not use them for a report-only
request without checking prerequisites and scope.

### Resume a commercial run

```text
$retrosoc-physical-flow
Mode: resume.
Target SoCs: MINI.
Profile: configs/cluster/ics55.mk.
PDK: ICS55. Flow: commercial. Stage: signoff.
Run ID: <existing-run-id>.
Local configuration: <existing ignored site-local configuration>.
Verify the original archive, configuration, inputs, stamps, and required outputs before resuming.
Continue only through the existing site submission mechanism with valid qualified I/O budgets.
MUST NOT clean, force rerun, relax thresholds, change inputs, or expose proprietary collateral.
If old stage evidence is invalid, stop and identify the precise recovery decision needed.
```

This requests the remaining supported stages, not license/site setup or a new
flow. LibreLane/ECC recovery is different: never assume commercial stamps or
an invented resume flag apply. Preserve old runs when recovery is unsupported.

### Summarize existing implementation evidence

```text
$retrosoc-physical-flow
Mode: summarize.
Run directory: build/commercial/ics55/<existing-run-id>.
Resolve the actual target, profile, input revision, and corners from its records.
Report stage verdicts, cell count, area, WNS/TNS, and qualification gaps separately.
MUST NOT rerun stages or infer missing values, Fmax, or production readiness.
Distinguish internal synthesis QoR from qualified I/O and post-route evidence.
```

If the run lacks identity records, keep that limitation visible rather than
assigning the current checkout's SHA. Summaries do not authorize cleanup,
repackaging, or publication of proprietary results.

## Validation versus evidence

The repository's Skill tests validate metadata, links, invocation examples,
and eval corpus structure. They do not execute these prompts or certify agent
behavior. Actual publication, restoration, upgrades, physical runs, and their
qualification require separately requested execution and matching artifacts.
