# LibreLane implementation

Read the [flow overview](../../../../physical/librelane/README.md) and the
selected [Mini guide](../../../../physical/librelane/mini/README.md) or
[Tiny guide](../../../../physical/librelane/tiny/README.md), then inspect its
Makefile. The current supported technology is IHP130. Mini supports padless
`core` and pad-ring `chip`; Tiny supports `chip` only. Do not infer GF180,
SKY130, ICS55, Std, or Pro support from another regression profile.

Preflight inspects the locked LibreLane/OpenSTA/PDK requirements, source and
macro/pad collateral, clocks, constraints, and selected profile. Do not run
`librelane-doctor` as a read-only probe: its prerequisites generate inputs.

Execution entrypoints, from the repository root, are:

```sh
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY librelane-doctor
make CONFIG=configs/ci/ihp130-tiny.mk SOC=TINY librelane-chip
make CONFIG=configs/ci/ihp130.mk SOC=MINI LIBRELANE_TARGET=core librelane-doctor
make CONFIG=configs/ci/ihp130.mk SOC=MINI librelane-core
```

Select the relevant commands, not all products by default. For Mini chip use
`librelane-chip` with the matching profile. Preserve one `BUILD_TIMESTAMP`
across a sequence that must share a variant. The packaging targets are
`librelane-package` for chip and Mini-only `librelane-core-package` for core.
They depend on run targets, so packaging is not automatically artifact-only.

Inspect recovery before acting. Current run recipes use `--overwrite` and a
run tag; replaying a target is not proof of safe resume. Inspect existing run
state, exact input hashes, tool version, and the wrapper/CLI recovery support.
If a preserved-state resume is not exposed, stop and obtain authorization for
a separately identified fresh or forced run. Do not change Makefiles, overwrite
the only evidence, or invent a `--resume` option to satisfy the request.

Keep Mini results under `physical/librelane/mini/<target>` and Tiny results
under `physical/librelane/tiny/chip` inside the chosen build variant. Check
structured results, required final views, reports, logs, and configuration
identity. Report skipped stages and constraints as limitations. Even a
successful routed open-source flow is development evidence, not foundry
production signoff, board qualification, or silicon measurement.
