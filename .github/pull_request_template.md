## Purpose and scope

<!-- Explain the problem, resulting behavior, and what is included/excluded.
Link the related issue and specification/phase, or write N/A.
Ordinary contributions target dev; retain meaningful commits for merge-commit integration.
See CONTRIBUTING.md and docs/git-workflow.md in the repository. -->

## Interfaces and compatibility

<!-- Describe public API/register, configuration, dependency, or compatibility
changes and any migration needed. Write N/A if none. -->

## Validation

<!-- Record actual results; a dry-run is not a simulation pass.
Include relevant tool versions and links or paths to logs/artifacts. -->

| Profile / environment | Command or check | Result | Evidence |
| --- | --- | --- | --- |
| | | PASS / FAIL / SKIPPED / NOT_RUN | |

Checks not run and why:

<!-- Explain applicable missing gates and what remains to run.
For documentation-only changes, report link/command checks and git diff --check;
state that hardware validation is not applicable. -->

## Risks and follow-up

<!-- List known limitations, regressions, or follow-up issues, or write None.
Do not imply synthesis, timing, or silicon signoff from behavioral CI alone. -->

## Checklist

- [ ] The base is `dev`, or a maintainer has identified this as release integration.
- [ ] The scope, related issues/specifications, and compatibility impact are clear.
- [ ] Relevant documentation and tests are updated; validation and missing gates are reported.
- [ ] No unintended generated files, credentials, or managed-source edits are included; dependency changes use the lock and shared setup flow.
- [ ] Applicable MISRA deviations and warning-baseline changes are identified for review, or explicitly marked N/A above.
