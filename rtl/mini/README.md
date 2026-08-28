# Mini SoC Integration

This directory is the active Mini SoC integration boundary.

- address_map contains the canonical address-map input and generator.
- core contains self-owned Mini core wrappers.
- dv contains behavioural testbench, device models, and Verilator harness
  sources.
- filelist contains canonical ordered .fl templates. `commonip.fl` is the full
  behavioral/synthesis Common source set; `netlist_support.fl` is the explicit
  allowlist of testbench dependencies not already present in a synthesized
  netlist.
- mk contains simulator and software make fragments.
- script contains filelist, address-map, conversion, and setup helpers.
- top contains SoC integration RTL, including `apb4_system` for the APB4
  platform block and `apb4_periph` for the APB4 peripheral container.

Generated filelists, address-map products, and MPW output belong in the
configured build variant, not under this directory.

Verilator normally retains the pin-level QSPI flash model. The explicit
`--fast-flash` emulator option replaces only the reset slot-0 `0xEB` read PHY
with a byte-wide DPI backend; unsupported slots, writes, or LUTs fail rather
than silently falling back. `hp-linux-sim` uses this mode so TCD, DMA, AXI,
XPI memory-map, CRC, SDRAM, HP release, and Linux userspace remain in the
acceptance path without spending hours shifting the boot payload over QSPI.
`hp-smoke-sim` remains the pin-level protocol reference.
