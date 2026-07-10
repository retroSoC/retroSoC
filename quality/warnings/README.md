# Warning Baselines

Baselines are scoped by committed profile and tool. Each entry stores a normalized warning signature,
its accepted count, and one example. Path roots and source line numbers are removed before hashing.

Do not hand-edit signatures. Regenerate only from a successful flow using
`scripts/analyze_warnings.py baseline`, review the full diff, and run `make check-warnings`.
