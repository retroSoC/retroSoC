# SPI-P4 Display and Snapshot Application Qualification

SPI-P4 covers the frozen display path on top of the committed SPI-P3
integration: a project-owned ST7789VI-style four-wire adapter in
`app/board/`, an independent pin-level panel oracle in the Tiny testbench,
and the `TINY_SPI_P4_ACCEPTANCE` image covering the display-pattern stages.
Camera/PSRAM-source display and the sequential SD snapshot evidence are
sub-stage B; their frozen cases additionally require R2-P8/R2-P9 human
acceptance, which is pending at preflight time.

## Interface contract

- Panel wiring: SCK=GPIO27 ALT0, MOSI=GPIO28 ALT1, CS_N=GPIO31 ALT1,
  D/C=GPIO30 as an ordinary push-pull software output; no MISO. CS is
  retained across each command/data boundary through held-CS segments; D/C
  changes only at clean boundaries with a GPIO readback before the next START.
- Commands are 8-bit MSB-first frames with D/C low; parameters and RGB565
  pixels are byte streams with D/C high; pixels occupy two ordinary data
  bytes, big-endian. The reference geometry is 320x240 landscape with zero
  address offsets for full-screen windows.
- Init order (sub-stage A constants for the selected panel): SWRESET, 120 ms,
  SLPOUT, 120 ms, COLMOD=0x05, MADCTL=rotation, INVON, NORON, DISPON, 20 ms.

## Stages and evidence

The acceptance image (`app/apps/ci_smoke/tiny_spi_p4.c`) runs: discovery,
GPIO/SPI configuration, acquire with GPIO_READY, panel init, stage 1 color
bars and stage 2 gradient (full 320x240), stage 3-5 odd rectangles, stage 6
rotation variant (MADCTL=0x60), an abort/recover case (truncated full-frame
then a final clean window), release, and TEST_STATUS before the UART summary.
The testbench panel model (`rtl/tiny/dv/tiny_st7789_panel.sv`, active with
`+tiny_spi_p4`) decodes the pins independently and emits SPI_P4_CMD,
SPI_P4_WINDOW (geometry, pixel count, FNV-1a, abort flag), SPI_P4_VIOLATION
and a terminal SPI_P4_PANEL summary. `scripts/spi_p4.py check --log` recomputes
the golden geometry/pixel checksums and rejects any drift; verdicts remain
TEST_STATUS/`SIM_TEST_PASS` with no forbidden markers.

Focused checks: `make CONFIG=<profile> APP=ci_smoke TINY_SPI_P4_ACCEPTANCE=YES spi-p4-lint spi-p4-rtl spi-p4-report`.
Acceptance: `make CONFIG=<profile> APP=ci_smoke TINY_SPI_P4_ACCEPTANCE=YES TINY_SIM_ARGS=+tiny_spi_p4 firmware sim`.

Pre-final timing stays observational under the 2026-10-07 policy; SPI-P5
remains the final physical qualification phase. `phase_accepted` is false
until human review.
