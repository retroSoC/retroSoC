# Locked Configuration Inputs

`dependencies.lock.json` is the source of truth for external repositories,
archives, checksums, and CI tool bundles. Its digest contributes to every build
variant identity.

Do not add direct downloads to setup scripts or workflow YAML. Update the lock
with a full Git revision or verified SHA-256 checksum, validate it with:

```sh
python3 scripts/dependency_lock.py --lock config/dependencies.lock.json
```

Then run the affected setup, doctor, test, and regression flow described in
[Engineering Workflow](../docs/engineering.md).
