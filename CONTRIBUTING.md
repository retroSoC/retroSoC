# Contributing

Read [`AGENTS.md`](AGENTS.md) and the
[MISRA C:2012 Amendment 2 policy](docs/misra-c-2012.md) before changing
self-owned embedded C. Run the applicable quality gates before opening a pull
request:

```sh
python3 -m pip install --requirement requirements/ci.txt
make sw-format-check
make sw-policy-check
make sw-host-test
ruff check .
python3 -m pytest -q
yamllint .github .yamllint.yml
python3 scripts/regress.py --root . --suite pr --dry-run
```

The automated C checks enforce a partial subset of the documented MISRA
baseline. Required-rule deviations need reviewed records in
`quality/misra/deviations.md`; Mandatory rules are not waived.

For build changes, use a committed profile and keep generated files below `build/` or `.cache/`.
Do not add new downloads directly to workflow YAML or setup scripts. Add the source or archive to
`config/dependencies.lock.json`, use the shared dependency helpers, and include a full Git commit or
SHA-256 checksum.

The supported pull-request regression is:

```sh
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk setup
make regress-pr
```

Warning baseline changes must be reviewed separately from implementation changes. Regenerate only
the affected profile/tool file, inspect every normalized signature, and explain additions in the
pull request. Metrics remain observational until ten successful `main` runs have been collected and
promoted according to `docs/engineering.md`.

Changes to the dependency lock, CI workflows, warning policy, metrics policy, or release packaging
require the owners listed in `.github/CODEOWNERS`.
