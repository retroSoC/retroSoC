# Reproducible Build Profiles

This directory contains committed Make configuration profiles. Each profile
selects SoC, PDK, ISA, CSR support, application, linker layout, and the
supported validation tier. `MINI_MODE=PRODUCT` fixes Hazard3 and VexiiRiscv as
LP/HP harts and exposes one fixed EXT-L plus one fixed EXT-H slot. The separate
`cluster/mini-mpw.mk` profile retains C0-C3 and the selectable user-IP mux.

`ci/` contains pull-request profiles, `cluster/` contains configurations
requiring site tools or PDKs, and `benchmark/` contains fixed-workload baseline
profiles. The `ihp130-hazard3-coremark.mk` profile is the automated SRAM
CoreMark quick measurement; its `-standard` counterpart is reserved for a
10-second hardware run. The nightly workflow reuses the IHP130 CI profile and
runs the quick CoreMark profile.
`ci/ihp130-hp.mk` is the asymmetric Linux application profile. It starts HP
from the external 72 MHz safe clock and LP from REF24, runs `hp_boot` entirely
from 32 KiB on-chip SRAM, and
generates VexiiRiscv RTL only below the selected build variant. It is not part
of the supported PR matrix until Linux boot, HP performance, synthesis, and
timing evidence are qualified.
`ci/ihp130-xpi-flash-loader.mk` builds the SRAM-only XPI NOR service image used
by GDB/OpenOCD; it is a programming utility, not a normal boot application.
Start builds from a committed profile rather than setting an unreviewed mix of
variables on the command line.

`SRAM_SIZE_KIB` selects 4, 16, 32, 64, or 128 KiB of on-chip SRAM and is part
of the build variant key. IHP130, GF180, and SKY130 CI profiles select eight
4 KiB banks for 32 KiB total and enable both the interface and technology
macro. Committed ICS55 profiles keep the memory and PLL absent. All committed
product and benchmark profiles use 32 KiB; larger capacities remain valid
manual values but are not selected by the product profiles.

`local/ics55.example.mk` is the only tracked local-profile artifact. Copy it to
the ignored `local/ics55.mk`, set `HAVE_PLL`, `HAVE_SRAM_IF`, and
`HAVE_SRAM_MACRO` to `YES`, and list the commercial SRAM model plus a local
`PLL_TOP` simulation adapter in `LOCAL_RTL_FILES`. Both the copied profile and
local `.sv` model are ignored so absolute commercial paths never enter Git.

`HAVE_SRAM_MACRO=YES` requires `HAVE_SRAM_IF=YES`. The generic manual defaults
enable 32 KiB for IHP130, GF180, and SKY130 and keep ICS55 disabled; committed
profiles remain the supported reproducible entry points.

`PDK_BEHAV=YES` selects technology-wrapper functional models for behavioral
simulation. It is a simulation-only setting, participates in the build variant
key, and is invalid with Yosys synthesis. Profiles that execute from an SRAM
macro must select either this mode or a qualified macro timing model.

For supported profiles and commands, see the root [README](../README.md) and
[agent contract](../AGENTS.md).
