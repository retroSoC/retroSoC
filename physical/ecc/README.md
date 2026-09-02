# ECC ICS55 Core Hardening

This directory owns the on-demand ECOS Chip Compiler (ECC) hardening adapter
for the padless `retrosoc_core` macro on the committed
`configs/ci/ics55.mk` profile. It consumes the locked ECC
`v0.1.0-alpha.10` Linux CLI release, the locked ICS55 PDK checkout, the
cached H7CR slow Liberty view, and the canonical generated SoC sources and
clock-domain constraints.

The flow deliberately does not use `retrosoc_asic`, IO LEFs/Liberties, pad
cells, a pad ring, bondpads, package constraints, or board timing. Logical
ports remain macro pins. The generated SDC constrains the external, generated
system, audio, JTAG, DVP, and ULPI domains; ECC must accept that SDC through
its PDK overrides. A single-clock fallback is not permitted.

Run the flow through the root Makefile:

```sh
make CONFIG=configs/ci/ics55.mk ecc-setup
make CONFIG=configs/ci/ics55.mk ecc-doctor
make CONFIG=configs/ci/ics55.mk ecc-core
make CONFIG=configs/ci/ics55.mk ecc-package
```

Inputs, logs, the ECC workspace, reports, and packaged views live below
`build/<variant>/physical/ecc/core/`; the CLI archive and extracted tool live
below `.cache/retrosoc/`. They are generated evidence, not tracked source.

ECC hardening is development evidence only. The ICS55 preview PDK and this
padless flow do not establish foundry DRC/LVS, IR/EM, ESD, package, board, or
production-signoff closure.
