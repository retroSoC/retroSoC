# USB 2.0 RTL

This directory owns the self-contained ULPI USB 2.0 dual-role controller RTL,
its APB4 ABI in `usb2_define.svh`, interfaces, link/SIE/transaction blocks,
packet store, scheduler, descriptor DMA, and top-level `apb4_usb2` wrapper.

Use Common register, CDC, FIFO, ECC, and AXI helpers. Technology-specific
packet RAM mapping belongs in `rtl/tech/tc_usb2_packet_ram.sv`; SoC address,
interrupt, AXI, and dedicated-pad integration belongs under `rtl/mini/`.
Register definitions are hand maintained and mirrored by
`crt/include/retrosoc/hal/usb2_regs.h`; do not introduce a register generator.

Validate focused behavior with `python3 -m pytest -q tests/test_usb2.py
tests/test_usb2_register_parity.py`, then run the selected firmware/simulator,
RTL quality checks, and the supported PR regression. The design and delivery
boundary are defined in `docs/ip/usb2.md`.
