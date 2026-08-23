# LibreLane Full-Chip Flow

This directory owns the open-source, single-level IHP130 pad-ring implementation
for `retrosoc_asic`. It does not harden or deliver a separate digital-core macro.
The three USB packet SRAMs remain PDK macros inside the single chip run.

The flow consumes the committed `configs/ci/ihp130.mk` profile, the canonical
SoC pin map, and the IHP-Open-PDK revision in
`dependencies/dependencies.lock.json`. LibreLane reads the upstream
`ihp-sg13g2/libs.tech/librelane` configuration directly through manual-PDK
mode. Generated RTL, SDC, configuration, run databases, reports, and final
views are written below the selected `build/<variant>/physical/librelane/chip/`
directory.

Use the LibreLane 3.0.5 environment supplied by the development shell:

```sh
make CONFIG=configs/ci/ihp130.mk librelane-doctor
make CONFIG=configs/ci/ihp130.mk librelane-chip
make CONFIG=configs/ci/ihp130.mk librelane-package
```

The initial bare-die plan contains all 109 signal pads, 80 core/IO power and
ground pads, four corners, I/O fillers, 70 um bondpads, and a seal ring. It is
not a QFN/BGA package definition. `PDK=GF180`, `PDK=SKY130`, and `PDK=ICS55`
remain explicit future adapter work and are rejected by this flow.

IHP SG13G2 does not currently provide pad cells implementing retroSoC's
programmable pull-up, pull-down, or Schmitt controls. The IHP implementation
uses input-only, 4 mA output, and 4 mA bidirectional cells; unsupported GPIO
pad-control features must not be represented as production-qualified behavior.

A successful open-source run is evidence for implementation development, not a
foundry production-signoff claim. Release review still requires qualified
foundry decks, package and bond planning, electrical/ESD review, and approved
waivers.
