# Mini SoC Integration

This directory is the Mini SoC integration boundary. Tiny owns a separate
[MCU integration](../tiny/README.md). Shared CPU/debug, memory, bus helpers and
software build logic are owned outside Mini. Filelists, build rules and tests
reference their canonical shared paths directly.

- address_map contains the canonical Mini address-map input. Its generator
  lives in `scripts/rtl/generate_memory_map.py`.
- core contains self-owned Mini core wrappers.
- dv contains behavioural testbench, device models, and Verilator harness
  sources.
- filelist contains canonical ordered .fl templates. `commonip.fl` is the full
  behavioral/synthesis Common source set; `netlist_support.fl` is the explicit
  allowlist of testbench dependencies not already present in a synthesized
  netlist.
- mk contains Mini simulator and formal make fragments; shared firmware rules
  live in `rtl/mk/software.mk`.
- script contains Mini filelist generation and simulator-binding helpers.
  Shared parsing/conversion helpers live in `scripts/rtl`.
- top contains SoC integration RTL, including `apb4_system` for the APB4
  platform block and `apb4_periph` for the APB4 peripheral container.

Generated filelists, address-map products, and MPW output belong in the
configured build variant, not under this directory.

The [frozen NPU contract](../../docs/ip/npu.md) reserves a future independent
AXI64 master/resource 9, APB4 window `0x1001b000`, and LP vector 33 / HP PLIC
source 12. Its PCLK control shell and HP-native compute/DMA require explicit
clock-pause, drain and epoch integration. These are phased design allocations,
not currently wired or qualified functionality; use the specification and
[verification contract](../../docs/ip/npu-verification.md) before implementation.

Verilator normally retains the pin-level QSPI flash model. The explicit
`--fast-flash` emulator option replaces only the reset slot-0 `0xEB` read PHY
with a byte-wide DPI backend; unsupported slots, writes, or LUTs fail rather
than silently falling back. `hp-linux-sim` uses this mode so TCD, DMA, AXI,
XPI memory-map, CRC, SDRAM, HP release, and Linux userspace remain in the
acceptance path without spending hours shifting the boot payload over QSPI.
`hp-smoke-sim` remains the pin-level protocol reference.
