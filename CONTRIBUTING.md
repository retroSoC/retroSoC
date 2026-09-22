# Contributing to retroSoC

Contributions to RTL, firmware, verification, documentation, and development
tools are welcome. This guide describes community collaboration; the
[Git workflow](docs/git-workflow.md) defines branch and commit practices.
Follow the [Code of Conduct](CODE_OF_CONDUCT.md) and respect the project
[license](LICENSE) and retained third-party [notices](NOTICE).

## Discuss the change

Search existing issues and pull requests before starting. A small bug fix,
test improvement, or documentation correction can go directly to a PR; an
issue is not mandatory for every contribution. For a bug report, include the
repository revision, committed configuration, tool versions, reproduction
command, expected behavior, and relevant logs without credentials or private
data. The existing issue templates provide a starting point.

Discuss new features and changes to architecture, register maps, public APIs,
clock/reset behavior, or compatibility with maintainers before implementation.
Agree on scope, non-goals, the applicable specification, and acceptance
evidence. For SoC/IP work, use the relevant specification under `docs/ip/`
and its approved phase boundaries. Split independently reviewable phases into
separate PRs and identify dependencies between them.

## Prepare and develop

1. Follow the [Git workflow](docs/git-workflow.md) to fork or clone, start a
   short-lived branch from `dev`, and configure the correct remotes.
2. Read the [repository contract](AGENTS.md), the relevant directory guide,
   and any affected specification. Executable configuration and quality
   policy remain the source of truth for technical requirements.
3. Prepare the [development environment](docs/development-environment.md).
   The supported open-source tool environment is Linux x86_64; use the
   documented Docker, Nix, or manual setup. Installing Python requirements
   alone does not install the EDA tools, managed sources, PDKs, or reference
   data required by all tests.
4. Keep the change focused. Add appropriate regression coverage for behavior
   changes and update affected public documentation. Preserve unrelated work.

For an IHP130 checkout, after preparing the documented tool environment:

```sh
make CONFIG=configs/ci/ihp130.mk setup
```

This is one profile's setup, not preparation for every regression or reference
corpus. Follow the affected flow's setup and doctor instructions before
running it. The full PR matrix uses `make setup-regression` followed by
`make regress-pr`; extended coverage uses `make regress-nightly`.

Keep generated build products and caches in their designated ignored roots.
Do not edit managed/vendor sources as ordinary project files. External
repositories, archives, and tools must use the
[dependency lock](dependencies/dependencies.lock.json) and shared setup
helpers with reviewed revisions or checksums. Do not introduce direct
downloads in workflows or bypass lock verification.

## Validate the contribution

Choose the applicable checks from
[Required Validation](AGENTS.md#required-validation) and the affected directory
guide. Changes spanning categories need the checks for each category. The
following table is a navigation aid, not a replacement for those requirements.

| Change | Validation to plan |
| --- | --- |
| Documentation | Check links, configuration paths, and commands; run `git diff --check`. |
| Python or build tooling | Run `ruff check .` and `python3 -m pytest -q`; validate the affected build flow. |
| Self-owned embedded C | Review applicable MISRA rules; run `make sw-format-check sw-policy-check sw-host-test` and build the affected committed firmware profile. |
| RTL, hardware configuration, or linker inputs | Run the affected firmware and simulation, formatting/style checks, and the applicable PR/extended regression from the repository contract. |
| Dependencies or setup | Validate the lock, exercise the affected setup/doctor flow, and run the applicable tests and regression. |
| CI definitions | Run YAML and Actions lint plus the required regression definition dry-runs. |

For example, an affected IHP130 firmware build uses:

```sh
make CONFIG=configs/ci/ihp130.mk firmware
```

For dependency changes, validate the lock with:

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
```

Record exact commands, profile, relevant tool versions, results, and log or
artifact locations in the PR. Distinguish `PASS`, `FAIL`, `SKIPPED`, and
`NOT_RUN`; explain every applicable check not completed and what remains to
run. A dry-run validates a definition, not hardware behavior. Missing tools
are not evidence of a passing test. CI is authoritative for the flows it
actually executes, not for unrun synthesis, timing, or silicon signoff.

Self-owned embedded C follows the documented
[MISRA baseline](docs/misra-c-2012.md). Mandatory rules cannot be waived;
Required-rule deviations need a reviewed
[deviation record](quality/misra/deviations.md). Automated checks cover only a
partial subset and do not establish complete MISRA certification.

Keep warning-baseline changes separate from implementation changes. Regenerate
only affected baselines from successful flows and explain every changed
signature. Metric promotion remains subject to the evidence and review rules
in [Engineering Workflow](docs/engineering.md).

## Open and revise a pull request

Open ordinary contribution PRs against `dev`. Use a Draft PR while design,
implementation, or validation is incomplete. Complete the
[PR template](.github/pull_request_template.md): explain the problem, scope,
behavior and compatibility changes, linked issues/specifications, validation,
and remaining risks. Use `N/A` for sections that do not apply. A small
documentation PR does not need hardware evidence, but should say so.

Authors are responsible for a reviewable diff, accurate evidence, and
responses to feedback. Request review when the scope is ready to evaluate;
identify any checks that still need a maintainer's environment. Link to
follow-up commits when addressing comments and rerun affected checks after
changes or conflict resolution. Do not rewrite shared branch history to
hide review feedback or drop another contributor's commits.

Reviewers check correctness, scope, compatibility, and evidence against the
applicable contract. Maintainers coordinate the owners in
[CODEOWNERS](.github/CODEOWNERS), resolve review decisions, and perform the
merge. Owner-controlled dependency, build, CI, quality, and release changes
need the relevant owners' review. Documented review expectations do not imply
that a particular GitHub branch-protection rule has been configured.

## Merge and follow up

Before merging, maintainers confirm that review concerns are resolved, the
required checks for the current revision are satisfied, and any accepted
coverage limits are explicit. Investigate failures rather than weakening a
check to obtain a green result.

The default is a **merge commit into `dev`**, preserving meaningful phase
commits. Maintainers own release integration into `main` and publication of
`v*` tags. After merging, confirm which linked issues can close, retain any
remaining follow-up work, and remove the topic branch only when it contains
no unmerged work. Use a reviewed revert PR if a shared change must be undone.
