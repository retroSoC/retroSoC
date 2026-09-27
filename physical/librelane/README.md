# LibreLane IHP130 Flows

This directory groups the open-source LibreLane/IHP130 implementation flows by
product line:

- [`mini/`](mini/README.md) hardens the Mini SoC deliverables (`retrosoc_core`
  padless macro and the bare-die `retrosoc_asic` pad-ring chip) for
  `SOC=MINI` profiles such as `configs/ci/ihp130.mk`.
- [`tiny/`](tiny/README.md) implements the bare-die Tiny MCU
  (`retrosoc_tiny_asic`, pad-ring chip only) for `SOC=TINY` with
  `configs/ci/ihp130-tiny.mk`.
- `bondpad/` holds the shared 70 um bondpad LEF collateral used by both chip
  flows.

The top-level `Makefile` includes `mini/Makefile` or `tiny/Makefile` according
to `SOC`, so the target names (`librelane-doctor`, `librelane-chip`,
`librelane-package`, and the Mini-only `librelane-core`) are uniform across
product lines.

Both lines require the LibreLane 3.0.5 development environment, the locked
IHP-Open-PDK checkout under `physical/pdk/`, and the locked OpenSTA 3.0.0.
`PDK=GF180`, `PDK=SKY130`, and `PDK=ICS55` are intentionally rejected until
their technology-specific LibreLane adapters, pad cells, macro collateral, and
signoff decks are qualified.

A successful open-source run is evidence for implementation development, not a
foundry production-signoff claim. Release review still requires qualified
foundry decks, package and bond planning, electrical/ESD review, and approved
waivers.
