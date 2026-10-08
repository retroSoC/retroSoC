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
`ci/ihp130.mk` is the Mini PRODUCT IHP130 profile used by the NPU-P6 flow. At
root revision `d084002bfe99`, P0 numerical qualification and KWS/VWW corpus
generation passed, and the RV64 KWS/VWW bundles passed payload/header
validation. Stage-instrumented KWS shard 0 and shard 1 both stop in the pinned
portable-C reference at `reference-start`; no `NPU_P6_CASE` or P6
qualification report is claimed. See the [NPU verification contract](../docs/ip/npu-verification.md)
and retained logs under
`build/ihp130-2026-10-01-10-30-b2e490436ac7/npu/p6/`.
`ci/ihp130-hp.mk` is the asymmetric Linux application profile. It starts HP
from the external 72 MHz safe clock and LP from REF24, runs `hp_boot` entirely
from 32 KiB on-chip SRAM, enables VexiiRiscv `Zicbom` with 64-byte blocks, and
generates VexiiRiscv RTL only below the selected build variant. It is not part
of the supported PR matrix until Linux boot, HP performance, synthesis, and
timing evidence are qualified.
`ci/ihp130-rtthread.mk` selects the same RV64 HP hardware and LP loader for
the pinned RT-Thread M-mode selftest. Run `make setup-hp-rtthread`, then
`make CONFIG=configs/ci/ihp130-rtthread.mk SIMU=VERILATOR hp-rtthread-sim`.
`ci/ihp130-apu.mk` is the RV64 APU LP/HP evidence profile. It runs
`apu_release` from PSRAM, stages the embedded APUMC/APUM/WAV/KWS assets through
SDRAM, performs the LP-only image loads, hands APU ownership to HP, and checks
HP-submitted WAV/KWS jobs plus the LP-only register fault probe in the full-SoC
Verilator simulation via `hp-apu-sim`.
All PRODUCT profiles use `rv64imafdc_zicbom_max`; LP compiler/ISA remain RV32.
`ci/ihp130-xpi-flash-loader.mk` builds the SRAM-only XPI NOR service image used
by GDB/OpenOCD; it is a programming utility, not a normal boot application.
Start builds from a committed profile rather than setting an unreviewed mix of
variables on the command line.

`SRAM_SIZE_KIB` selects 4, 16, 32, 64, or 128 KiB of on-chip SRAM and is part
of the build variant key. IHP130, GF180, and SKY130 CI profiles select eight
4 KiB banks for 32 KiB total and enable both the interface and technology
macro. The committed ICS55 Mini profile now uses the locked OpenECOS SRAM
release; its PLL remains absent. Capacity is selected by each committed
profile: the executable IHP130 Tiny profile uses 128 KiB. Do not infer a
Tiny capacity or PLL setting from a Mini profile.

`local/ics55.example.mk` remains available for an optional PLL experiment.
The committed ICS55 SRAM models are downloaded and verified by the PDK setup
flow from the dependency lock; no local commercial SRAM path is needed.

`HAVE_SRAM_MACRO=YES` requires `HAVE_SRAM_IF=YES`. The generic manual defaults
enable 32 KiB for IHP130, GF180, SKY130, and ICS55; committed profiles remain
the supported reproducible entry points.

`PDK_BEHAV=YES` selects technology-wrapper functional models for behavioral
simulation. It is a simulation-only setting, participates in the build variant
key, and is invalid with Yosys synthesis. Profiles that execute from an SRAM
macro must select either this mode or a qualified macro timing model.

For supported profiles and commands, see the root [README](../README.md) and
[agent contract](../AGENTS.md).

## Tiny MCU

The [2026-10-07 Tiny refreeze](../docs/ip/tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07)
sets the default to ICS55 with `HAVE_PLL=YES` and SAFE24 boot.
`ci/ics55-tiny.mk` implements that entrypoint with the PLL held off; standalone
PLL backend tests do not enable RCU/SYS switching. `make SOC=TINY` selects this
committed profile, and `make SOC=TINY PDK=IHP130` selects explicit compatibility.
Do not substitute Mini's `ci/ics55.mk` for Tiny. Acceptance evidence belongs in
the Tiny ledger, and physical qualification remains pending.

`ci/ihp130-tiny.mk` selects `SOC=TINY`, one RV32IMC Hazard3 (A disabled),
128 KiB SRAM, AXI32/APB4, four DMA channels and the wired peripheral subset.
The profile uses 24 MHz, `HAVE_HP=NO`, `MINI_MODE=NONE`, CSR-enabled RV32IM
firmware and `ld2_all_sram`. Both `bringup` and `ci_smoke` select Tiny acceptance
firmware. Icarus and Verilator use the same pin-level Flash model. Other PDKs,
wireless, external RAM and HP applications are rejected by the Tiny config gate.
