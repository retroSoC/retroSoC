# GitHub Automation

This directory owns repository automation metadata: pull-request templates,
CODEOWNERS, Dependabot configuration, reusable actions, and CI/release
workflows.

The default [pull request template](pull_request_template.md) captures scope,
interface impact, validation evidence, and remaining risks. Follow the
[contribution process](../CONTRIBUTING.md) and
[Git workflow](../docs/git-workflow.md): ordinary PRs target `dev` and default
to merge-commit integration. These documents do not configure branch protection.

`workflows/quality.yml` runs the quality gate. It restores the locked IHP130
PDK, third-party simulation models, and APU/NPU references and installs the
locked Verilator, Icarus, sv2v, and Yosys tools before the complete Pytest
suite. The reference cache includes the NPU MLPerf Tiny models, MFCC inputs,
TensorFlow/gemmlowp oracle sources, and decoded VWW corpus; setup still
verifies every locked revision and checksum before tests run.
`workflows/regression-smoke.yml`,
`workflows/regression-ihp130.yml`, `workflows/regression-gf180.yml`,
`workflows/regression-ics55.yml`, `workflows/regression-sky130.yml`, and
`workflows/nightly.yml` call the reusable regression workflow. Smoke enables
`formal_checks`, which runs `formal-doctor` only; it does not run `make formal`.
`workflows/development-environment.yml` builds the Docker environment and
installs the Nix environment in parallel, checks the resulting tool closure,
and runs the same hosted behavioral-only IHP130 PR regression in both.
The reusable workflow currently selects `--behavioral-only`: hosted CI skips SoC Yosys
synthesis, OpenSTA, and netlist simulation while the JPEG synthesis-memory
issue is being resolved.
The locked synthesis and timing tools are still installed and checked; only the
SoC synthesis and downstream execution stages are filtered. Local regression
commands retain those stages. `workflows/release.yml` packages tagged releases.
`actions/locked-tools/` installs the locked open-source tools used by CI.

Keep Actions pinned by commit ID and use the dependency lock rather than adding
ad-hoc downloads. Validate workflow changes with `yamllint .github .yamllint.yml`,
`actionlint`, and both regression dry-runs. See the root
[agent contract](../AGENTS.md).
