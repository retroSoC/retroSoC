# Quality Policy and Baselines

This directory contains machine-readable quality policy and its supporting
documentation.

- `embedded_c_policy.json` defines self-owned embedded-C exclusions,
  compatibility files, and prohibited APIs.
- `misra/` records approved MISRA deviations; see
  [MISRA policy](../docs/misra-c-2012.md).
- `warnings/` stores reviewed EDA warning baselines.
- `metrics/` defines observational metric policy and future gate promotion.

Do not hand-edit generated warning signatures or promote metric gates without
the review process in [Engineering Workflow](../docs/engineering.md). Run the
corresponding check after changing quality policy.
