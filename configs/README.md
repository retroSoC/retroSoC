# Reproducible Build Profiles

This directory contains committed Make configuration profiles. Each profile
selects SoC, PDK, ISA, CSR support, application, linker layout, and the
supported validation tier. The user-extension fabric is fixed; the management
core defaults to `HAZARD3` and may be set to `PICORV32` with `CORE`.

`ci/` contains pull-request profiles and `cluster/` contains configurations
requiring site tools or PDKs. The nightly workflow reuses the IHP130 CI profile.
Start builds from a committed profile rather than setting an unreviewed mix of
variables on the command line.

For supported profiles and commands, see the root [README](../README.md) and
[agent contract](../AGENTS.md).
