# Reproducible Build Profiles

This directory contains committed Make configuration profiles. Each profile
selects SoC, CPU/IP, PDK, ISA, CSR support, application, linker layout, and
the supported validation tier.

`ci/` contains pull-request profiles, `nightly/` adds extended open-source
coverage, and `cluster/` contains configurations requiring site tools or PDKs.
Start builds from a committed profile rather than setting an unreviewed mix of
variables on the command line.

For supported profiles and commands, see the root [README](../README.md) and
[agent contract](../AGENTS.md).
