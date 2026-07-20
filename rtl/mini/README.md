# Mini SoC Integration

This directory is the active Mini SoC integration boundary.

- address_map contains the canonical address-map input and generator.
- core contains self-owned Mini core wrappers.
- dv contains behavioural testbench, device models, and Verilator harness
  sources.
- filelist contains canonical ordered .fl templates.
- mk contains simulator and software make fragments.
- script contains filelist, address-map, conversion, and setup helpers.
- top contains SoC integration RTL.

Generated filelists, address-map products, and MPW output belong in the
configured build variant, not under this directory.
