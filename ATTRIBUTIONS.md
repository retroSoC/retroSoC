# Third-party attribution

This repository contains RTL source files that retain copyright and attribution information from third-party open-source projects in their original file headers. The following projects are explicitly referenced in the RTL sources currently present in this repository.

## 1. ETH Zurich and University of Bologna

Several RTL files retain the original copyright notice from ETH Zurich and University of Bologna, including files under the following paths:

- rtl/clusterip/**
- rtl/mini/mpw/core/username7/ibex/**
- rtl/tech/tc_clk.sv

The header in rtl/tech/tc_clk.sv also states the Solderpad Hardware License, Version 0.51.

## 2. Ravenna / PicoRV32 in ASIC

The following RTL files retain the original header from the Ravenna example SoC project, which refers to a design using PicoRV32 in ASIC:

- rtl/ip/native/gpio.sv
- rtl/ip/native/timer.sv
- rtl/ip/native/uart.sv

The preserved notice attributes the work to Clifford Wolf and Tim Edwards.

## 3. Hirosh Dabui

The SDRAM controller implementation in rtl/ip/native/sdram_core.sv retains the original copyright notice attributed to Hirosh Dabui.

## 4. EmbedFire

Several SPI/I2C-related RTL files retain the original attribution to EmbedFire and refer to source files such as sd_init.v, sd_write.v, sd_read.v, data_rw_ctrl.v, and i2c_ctrl.v:

- rtl/ip/native/i2c_core.sv
- rtl/ip/native/spisd_core.sv
- rtl/ip/native/spisd_data.sv
- rtl/ip/native/spisd_init.sv
- rtl/ip/native/spisd_read.sv
- rtl/ip/native/spisd_write.sv

These headers state that the original code was published on GitHub by EmbedFire, but that the original license was not specified in the retained header.

## 5. Notes on redistribution

The preserved third-party notices are included to maintain attribution for code that was adapted or reused in this repository. They do not replace the repository's main license declaration. The retroSoC project itself is distributed under the Mulan PSL v2 license.
