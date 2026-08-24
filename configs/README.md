# Reproducible Build Profiles

This directory contains committed Make configuration profiles. Each profile
selects SoC, PDK, ISA, CSR support, application, linker layout, and the
supported validation tier. The management core is fixed to Hazard3 with its
JTAG Debug Module enabled. The user-extension fabric exposes C0-C3 slots for
KianV RV32I, SERV, FemtoRV32, and DarkRISCV.

`ci/` contains pull-request profiles, `cluster/` contains configurations
requiring site tools or PDKs, and `benchmark/` contains fixed-workload baseline
profiles. The `ihp130-hazard3-coremark.mk` profile is the automated SRAM
CoreMark quick measurement; its `-standard` counterpart is reserved for a
10-second hardware run. The nightly workflow reuses the IHP130 CI profile and
runs the quick CoreMark profile.
`ci/ihp130-xpi-flash-loader.mk` builds the SRAM-only XPI NOR service image used
by GDB/OpenOCD; it is a programming utility, not a normal boot application.
Start builds from a committed profile rather than setting an unreviewed mix of
variables on the command line.

`PDK_BEHAV=YES` selects technology-wrapper functional models for behavioral
simulation. It is a simulation-only setting, participates in the build variant
key, and is invalid with Yosys synthesis. Profiles that execute from an SRAM
macro must select either this mode or a qualified macro timing model.

For supported profiles and commands, see the root [README](../README.md) and
[agent contract](../AGENTS.md).
