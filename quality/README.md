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
- `ownership.json` records primary and backup review ownership plus the current
  `sole_maintainer` policy. Missing backups are reported explicitly rather than
  assigned to an agent; the human maintainer retains approval and merge duties.
- `release-candidate.schema.json` defines the evidence required from the tracked
  `quality/release-candidate.json` supplied for an actual release.

Do not hand-edit generated warning signatures or promote metric gates without
the review process in [Engineering Workflow](../docs/engineering.md). Run the
corresponding check after changing quality policy.
