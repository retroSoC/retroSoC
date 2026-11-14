# Quality Policy and Baselines

This directory contains machine-readable quality policy and its supporting
documentation.

- `embedded_c_policy.json` defines self-owned embedded-C exclusions,
  compatibility files, and prohibited APIs.
- `misra/` records approved MISRA deviations; see
  [MISRA policy](../docs/misra-c-2012.md).
- `warnings/` stores reviewed EDA warning baselines.
- `metrics/` defines observational metric policy and future gate promotion.
- `change_impact.json` defines conservative changed-file CI selection; unknown
  paths and classification failures select the full matrix.
- `pytest-shards.json` defines four deterministic fixture shards and the exact
  permitted optional-input skips. `pytest-durations.json` records source-bound
  JUnit timing history used only for scheduling, never for a PASS verdict.
- `incremental-ci.json` is shadow-only and disabled. It defines the fixture
  input closure, tool/configuration identities, and test-manifest requirements;
  it never skips a required job by itself.
- `validation-gaps.json` records owned deferred validation gaps, source scope,
  review dates, prohibited claims, and the evidence required for resolution.
- `ownership.json` records primary and backup review ownership plus the current
  `sole_maintainer` and `auto_merge` policies. Missing backups are reported
  explicitly rather than assigned to an agent. CI-green auto-merge uses merge
  commits and cleans merged branches only when the worktree is clean.
- `release-candidate.schema.json` defines the evidence required from the tracked
  `quality/release-candidate.json` supplied for an actual release. Optional
  `local_checks` bind local formal evidence to the same clean release revision,
  with semantic validation instead of self-referential summary hashes.

Do not hand-edit generated warning signatures or promote metric gates without
the review process in [Engineering Workflow](../docs/engineering.md). Run the
corresponding check after changing quality policy.
