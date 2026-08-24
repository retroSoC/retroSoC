# LibreLane IHP130 Flows

This directory owns the open-source IHP130 implementation entry points for two
independent `retrosoc` deliverables:

- `librelane-core` hardens `retrosoc_core`, a padless logical macro with the
  canonical external pin contract and the three USB packet SRAM macros.
- `librelane-chip` implements the bare-die `retrosoc_asic` package-facing SoC,
  including its pad ring, bondpads, fillers, corners, seal ring, and the same
  SRAM macros.

These are separate single-level runs. The chip flow does not consume the core
run as a hierarchical macro, so either artifact can be developed and reviewed
without a two-level integration dependency.

The flow consumes the committed `configs/ci/ihp130.mk` profile, canonical SoC
pin map, and IHP-Open-PDK revision in `dependencies/dependencies.lock.json`.
LibreLane reads the upstream `ihp-sg13g2/libs.tech/librelane` configuration
directly through manual-PDK mode. Generated RTL, SDC, configuration, run
databases, reports, and final views are written below the selected
`build/<variant>/physical/librelane/{core,chip}/` directory.

Use the LibreLane 3.0.5 environment supplied by the development shell:

```sh
make CONFIG=configs/ci/ihp130.mk librelane-doctor
make CONFIG=configs/ci/ihp130.mk librelane-core
make CONFIG=configs/ci/ihp130.mk librelane-chip
make CONFIG=configs/ci/ihp130.mk librelane-core-package
make CONFIG=configs/ci/ihp130.mk librelane-package
```

The chip target places all 109 signal pads, 80 core/IO power and ground pads,
four corners, I/O fillers, and 70 um bondpads. It is a bare-die plan, not a
QFN/BGA package definition. The SDC constrains the external clock at 72 MHz;
mid-PnR timing report passes are skipped because LibreLane 3.0.5 emits 1000
expanded paths per group, while final post-RCX multi-corner STA remains enabled.

`PDK=GF180`, `PDK=SKY130`, and `PDK=ICS55` are intentionally rejected until
their technology-specific LibreLane adapters, pad cells, macro collateral, and
signoff decks are qualified. The target split is technology-neutral so those
adapters can reuse the core/chip interface when they are ready.

IHP SG13G2 does not currently provide pad cells implementing retroSoC's
programmable pull-up, pull-down, or Schmitt controls. The IHP implementation
uses input-only, 4 mA output, and 4 mA bidirectional cells; unsupported GPIO
pad-control features must not be represented as production-qualified behavior.

A successful open-source run is evidence for implementation development, not a
foundry production-signoff claim. Release review still requires qualified
foundry decks, package and bond planning, electrical/ESD review, and approved
waivers.
