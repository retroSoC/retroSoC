# Dependency and environment routing

Read [reproducible inputs](../../../../docs/engineering.md), the
[dependency guide](../../../../dependencies/README.md), and
[development environment guide](../../../../docs/development-environment.md).
Use [dependencies.lock.json](../../../../dependencies/dependencies.lock.json)
and the current helper implementations as the source of truth. Do not duplicate
their versions or schemas in a skill.

## Choose the smallest affected entrypoint

| Input | Existing ownership and entrypoint | Checks to consider |
| --- | --- | --- |
| Tool bundles and Python environment | [development_environment.py](../../../../scripts/development_environment.py), pinned requirements | Environment stamp, installed binaries, Python consistency, affected tool consumers |
| OCI and Nix inputs | [Dockerfile](../../../../docker/Dockerfile), [flake.nix](../../../../flake.nix), [flake.lock](../../../../flake.lock) | Dependency-lock agreement, affected Docker build or Nix check on a supported host |
| Managed RTL, PDK, application sources | Selected setup targets in the [root Makefile](../../../../Makefile) and subsystem guides | Checkout revision/integrity, selected profile's doctor and affected tests/regression |
| Publication media, fonts, packages, Typst | [publication setup](../../../../publications/README.md), selected book adapter | Assets/package hashes and offline closure, source and PDF checks where affected |

The shared development environment prepares tools, not every PDK or managed
source. Its current host contract is Linux x86_64; a Windows workspace does not
by itself provide that runtime. Use an available supported environment without
installing a new OS/container system as an implicit repair.

Read-only inspection may use the lock validator and the environment `check`
command after verifying their current side effects. Do not execute a generic
Make doctor/setup recipe in inspect mode simply because its name sounds safe.

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
python3 scripts/development_environment.py check
```

For an authorized restore, the documented tool bootstrap is:

```sh
python3 scripts/development_environment.py bootstrap
python3 scripts/development_environment.py check
```

Use only the needed Make setup targets for profile inputs. Inspect available
update flags per helper; restoring a checkout to its locked revision is not
permission to change that revision. Review dirty checkouts and any modified
cache before an update operation. Never use broad cache deletion as a retry.

## Upgrade and verification

Locate all declarations of the requested dependency and its consumers before
editing. Verify upstream release identity and full revision/digests. Keep
related OCI/Nix/Python/publication records consistent without refreshing
unrelated dependencies. Changing publication media upstream is a separate
repository action; consuming a reviewed revision does not authorize making,
committing, or pushing upstream asset changes.

Run lock validation, affected setup/update and doctor, Python lint/tests where
required, and the affected environment or product validation. Docker/bootstrap
changes need the documented image/runtime checks; Nix changes need their
corresponding Linux checks. Shared inputs need the affected existing product
matrix, not an assumed Mini-only run. Inspect the current workflow when
describing CI coverage.

Record exact old/new identifiers, source of integrity evidence, installed-state
checks, affected consumers, and unrun gates. Separate missing permissions or
host prerequisites from an invalid dependency, and do not turn either into a
passing restore or a speculative version upgrade.
