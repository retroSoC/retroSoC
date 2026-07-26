# Build and Quality Scripts

This directory contains the Python implementation of setup, dependency locking,
build manifests, flow execution, simulation checks, regression orchestration,
quality checks, metrics, packaging, and cleanup.

Scripts are part of the build contract. Prefer existing helpers over ad-hoc
shell behavior, preserve structured JSON results, and keep setup/download
behavior controlled by `config/dependencies.lock.json`.

`publish_fatfs_artifact.sh` is the manual release helper for the lock-pinned
FatFs R0.16 archive. It verifies the archive, GitHub authentication, release
absence, and the published asset checksum before reporting the checksum-pinned
URL.

Update or add tests in [`../tests`](../tests) for script behavior. Run
`ruff check .` and `python3 -m pytest -q`; build-flow changes also require the
relevant dry-run or regression profile from [`AGENTS.md`](../AGENTS.md).
