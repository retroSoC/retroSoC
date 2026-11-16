# Shared validation and evidence contract

Bind every claim to the target SoC, committed profile, PDK, source revision,
effective configuration, dependency lock, and build variant. A result from
another target or an older revision can be a labeled comparison, not current
acceptance evidence.

Use `PASS`, `FAIL`, `SKIPPED`, and `NOT_RUN` consistently. A dry-run validates a
definition, not hardware behavior. Missing tools, logs, required markers, or
artifacts are not passes. Do not invent metrics or attach current source hashes
to old binaries.

`make check-fast` runs the common static, host, agent, and regression-definition
checks. `make validation-plan` writes the deterministic changed-file matrix.
Unknown paths and classification failures select the full matrix. Push,
scheduled, and manually dispatched full events do not use path-based skipping.

Hosted PR regressions remain behavioral-only unless their exact invocation says
otherwise. They do not provide synthesis, netlist simulation, OpenSTA, physical,
or silicon signoff evidence. `formal-doctor` checks the environment only. The
`formal` workflow runs the explicit per-proof targets; SV2V conversion alone is
not a proof pass. The manually dispatched `full-flow` workflow retains full-flow
attempts and requires the physical stages in its summary.

Use the selected testbench's exit status, configured terminal marker, structured
result, and absence of failure markers. Preserve failed and interrupted attempts.
Do not treat buffered UART, tool silence, or a long run as a failure without
process, timeout, resource, or log evidence.

Each CI summary is bound to its run start and current revision so historical
`build/` results cannot satisfy a current run. Accepted release gaps are explicit
human-reviewed exceptions and cannot include a stage marked required by the
release candidate.

Use `make agent-handoff TASK=<task.json> NEXT=<action>` for a revision-bound
[handoff](../../handoff.schema.json) that lists evidence, artifacts, process
state, known gaps, and the next action. Deferred or blocked validation gaps live
in `quality/validation-gaps.json`; their evidence cannot become PASS without the
listed resolution stages. Handoff is not approval or a replacement for CI.
