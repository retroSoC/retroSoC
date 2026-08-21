# GitHub Automation

This directory owns repository automation metadata: pull-request templates,
CODEOWNERS, Dependabot configuration, reusable actions, and CI/release
workflows.

`workflows/quality.yml` runs the fast quality gate. `workflows/regression-smoke.yml`,
`workflows/regression-ihp130.yml`, `workflows/regression-gf180.yml`,
`workflows/regression-ics55.yml`, `workflows/regression-sky130.yml`, and
`workflows/nightly.yml` call the reusable regression workflow. Nightly splits the IHP130 PR matrix from the extra CoreMark and Yosys recipes. `workflows/release.yml` packages tagged releases. `actions/locked-tools/`
installs the locked open-source tools used by CI.

Keep Actions pinned by commit ID and use the dependency lock rather than adding
ad-hoc downloads. Validate workflow changes with `yamllint .github .yamllint.yml`,
`actionlint`, and both regression dry-runs. See the root
[agent contract](../AGENTS.md).
