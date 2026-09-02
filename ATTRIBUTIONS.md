# Third-party attribution

This repository contains RTL source files that retain copyright and attribution information from third-party open-source projects in their original file headers. The following projects are explicitly referenced in the RTL sources currently present in this repository.

## 1. ETH Zurich and University of Bologna

Several RTL files retain the original copyright notice from ETH Zurich and University of Bologna, including files under the following paths:

- rtl/managed/clusterip/**
- rtl/managed/mpw/core/username7/ibex/**
- rtl/tech/tc_clk.sv
- rtl/ip/memory/opipsram_phy.sv
- rtl/ip/memory/opipsram_trx.sv
- rtl/tech/tc_opipsram_delay.sv

The `tc_clk.sv` header and the adapted OPI PSRAM PHY files state the
Solderpad Hardware License, Version 0.51 (`SHL-0.51`). The OPI PSRAM PHY
files are adapted from PULP Platform HyperBus v0.0.4 at commit
`80de8df600edc5d7956a94c9d42f911d6e61efd7`; each preserves the source-file
authors and records retroSoC's modifications. The exact license text is in
[`licenses/PULP_Platform-SHL-0.51`](licenses/PULP_Platform-SHL-0.51).

## 2. Ravenna / PicoRV32 in ASIC

The following RTL files retain the original header from the Ravenna example SoC project, which refers to a design using PicoRV32 in ASIC:

- rtl/ip/peripheral/gpio.sv
- rtl/ip/peripheral/timer.sv
- rtl/ip/serial/uart.sv

The preserved notice attributes the work to Clifford Wolf and Tim Edwards.

## 3. Hirosh Dabui

The SDRAM controller implementation in rtl/ip/memory/sdram_core.sv retains the original copyright notice attributed to Hirosh Dabui.

## 4. EmbedFire

Several SPI SD card related RTL files retain the original attribution to EmbedFire and refer to source files such as sd_init.v, sd_write.v, sd_read.v, and data_rw_ctrl.v:

- rtl/ip/storage/spisd_core.sv
- rtl/ip/storage/spisd_data.sv
- rtl/ip/storage/spisd_init.sv
- rtl/ip/storage/spisd_read.sv
- rtl/ip/storage/spisd_write.sv

These headers state that the original code was published on GitHub by EmbedFire, but that the original license was not specified in the retained header.

## 5. Device simulation models

The simulation-only models under `rtl/model/` retain their upstream notices
and source formatting. The AT24 model is imported from the retroSoC I2C
repository, the microphone model from the retroSoC I2S repository, and the
W25Q128JVxIM model from the retroSoC SPI repository. The Winbond model retains
its original Winbond Electronics Corporation copyright and "All Rights
Reserved" notice; its inclusion does not relicense it under Mulan PSL v2.

## 6. Notes on redistribution

The optional checksum-locked SKY130 SRAM artifact is generated with OpenRAM at
the revision recorded in its manifest. OpenRAM is distributed under the BSD
3-Clause License; the SkyWater-provided SRAM build-space used by the generator
is distributed under Apache License 2.0. The artifact retains both exact
license texts and is materialized only below the ignored `.cache/` tree.

The preserved third-party notices are included to maintain attribution for code that was adapted or reused in this repository. They do not replace the repository's main license declaration. The retroSoC project itself is distributed under the Mulan PSL v2 license.
