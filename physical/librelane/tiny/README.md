# Tiny LibreLane IHP130 Chip Flow

This directory owns the Tiny product line's open-source IHP130 implementation
entry point: `librelane-chip` implements the bare-die `retrosoc_tiny_asic`
MCU, including its pad ring, bondpads, fillers, corners, seal ring, and the
32 on-chip SRAM bank macros.

The pad counts, 24 MHz constraints and observations below describe the
committed initial implementation. The [Tiny Gen1 R2 target](../../../docs/ip/tiny-soc.md)
preserves the frozen QFN64 package. `TINY-R2-P4` updates macro hierarchy and
SYS-clock constraints, `TINY-R2-P7` updates dynamic clock/reset inputs, and
`TINY-R2-P11` performs final CPU/main-SRAM physical qualification. This guide and an existing flow run
do not qualify the R2 pad mapping or faster CPU/SRAM profiles.

The flow consumes the committed `configs/ci/ihp130-tiny.mk` profile, the
canonical Tiny pin map (`rtl/tiny/pin_map/pin_map.json`), the Tiny clock/reset
inventory (`rtl/tiny/integration/clock_reset_domains.json`), and the
IHP-Open-PDK revision in `dependencies/dependencies.lock.json`. LibreLane reads
the upstream `ihp-sg13g2/libs.tech/librelane` configuration directly through
manual-PDK mode. Generated RTL, SDC, configuration, run databases, reports, and
final views are written below `build/<variant>/physical/librelane/tiny/chip/`.

Use the LibreLane 3.0.5 development shell (`~/squashfs-root/AppRun`) and put
the locked OpenSTA 3.0.0 first on `PATH`:

```sh
~/squashfs-root/AppRun bash -c 'export PATH=/nfs/home/miaoyuchi/artifact-opensta/bin:$PATH; cd <repo>'
make CONFIG=configs/ci/ihp130-tiny.mk librelane-doctor
make CONFIG=configs/ci/ihp130-tiny.mk librelane-chip
make CONFIG=configs/ci/ihp130-tiny.mk librelane-package
```

## Pad Ring

The Tiny pin map declares 52 signal PADs (external clock/reset, JTAG, two
UARTs, 32 GPIOs, and the quad-XPI NOR flash interface). Tiny ships a reduced
supply set of 8 VDD + 8 VSS + 8 IOVDD + 8 IOVSS (two pairs of each per side),
84 placed PADs in total. The reduction from the Mini line's 24/24/16/16 follows
the taped-out Basilisk IHP SG13G2 SoC pad frame (68 signals with 24/24/16/16
supplies feeding a Linux-capable CVA6 at a much higher clock and IO rate):
Tiny's 24 MHz Hazard3 core draws a few mA, and even with all 52 4 mA outputs
switching simultaneously each IO supply pair carries only ~26 mA.

The side assignment is south = clock/reset/JTAG/UART, north = XPI,
east = GPIO[15:0], west = GPIO[31:16]; the `power_pads` counts come from
`rtl/tiny/pin_map/pin_map.json` and must match `pad_cfg.tcl`.

## Constraints

The SDC constrains the external clock at 24 MHz and JTAG at 10 MHz, defines a
generated system clock at the top-level clock buffer, and keeps the two groups
asynchronous. Mid-PnR timing report passes are skipped because LibreLane 3.0.5
emits 1000 expanded paths per group; final post-RCX multi-corner STA remains
enabled.

A successful open-source run is evidence for implementation development, not a
foundry production-signoff claim. Release review still requires qualified
foundry decks, package and bond planning, electrical/ESD review, and approved
waivers.
