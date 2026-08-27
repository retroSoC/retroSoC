# Locked Configuration Inputs

`dependencies.lock.json` is the source of truth for external repositories,
archives, OCI base images, Nix inputs, checksums, and CI tool bundles. Its digest
contributes to every build variant identity. `flake.lock` resolves the pinned Nix
inputs and is validated against this lock.

Do not add direct downloads to setup scripts or workflow YAML. Update the lock
with a full Git revision or verified SHA-256 checksum, validate it with:

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
```

Then run the affected setup, doctor, test, and regression flow described in
[Engineering Workflow](../docs/engineering.md).

The locked SKY130 OpenRAM SRAM archive is generated and published by the
`retroSoC/artifact` workflow. `physical/pdk/setup.py` verifies its SHA-256,
manifest, geometry, source revisions, generated-file hashes, and TT/SS views
before materializing it below `.cache/retrosoc/pdk/sky130/openram/`. Generated
Verilog, Liberty, LEF, GDS, and SPICE views are never committed here.

The HP profile additionally locks VexiiRiscv, OpenSBI, Linux stable, and
Buildroot source revisions. `make setup-hp-linux` installs the software sources
below `.cache/retrosoc/sources/`; VexiiRiscv may be supplied through
`VEXIIRISCV_ROOT`, but its revision is still checked before generated RTL is
accepted. No generated CPU RTL or Linux build output belongs in Git.
