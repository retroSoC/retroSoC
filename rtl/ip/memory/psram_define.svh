// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`ifndef RIBP_PSRAM_DEFINE_SVH
`define RIBP_PSRAM_DEFINE_SVH

// verilog_format: off -- preserve reviewed register and field alignment
`define RIBP_PSRAM_CTRL                   12'h000
`define RIBP_PSRAM_COMMAND                12'h004
`define RIBP_PSRAM_STATUS                 12'h008
`define RIBP_PSRAM_CHIP_ENABLE            12'h00C
`define RIBP_PSRAM_CHIP_PRESENT           12'h010
`define RIBP_PSRAM_CHIP_READY             12'h014
`define RIBP_PSRAM_CHIP_MODE              12'h018
`define RIBP_PSRAM_CHIP_ERROR             12'h01C
`define RIBP_PSRAM_CLK_CONFIG             12'h020
`define RIBP_PSRAM_POWERUP_CYCLES          12'h024
`define RIBP_PSRAM_CS_SETUP_CYCLES         12'h028
`define RIBP_PSRAM_CS_HIGH_CYCLES          12'h02C
`define RIBP_PSRAM_CS_HOLD_CYCLES          12'h030
`define RIBP_PSRAM_CS_MAX_LOW_CYCLES       12'h034
`define RIBP_PSRAM_ACCESS_TIMEOUT_CYCLES   12'h038
`define RIBP_PSRAM_TIMING_STATUS           12'h03C
`define RIBP_PSRAM_INDIRECT_CTRL           12'h040
`define RIBP_PSRAM_INDIRECT_ADDR           12'h044
`define RIBP_PSRAM_INDIRECT_WDATA_LO       12'h048
`define RIBP_PSRAM_INDIRECT_WDATA_HI       12'h04C
`define RIBP_PSRAM_INDIRECT_RDATA_LO       12'h050
`define RIBP_PSRAM_INDIRECT_RDATA_HI       12'h054
`define RIBP_PSRAM_LAST_ERROR              12'h058
`define RIBP_PSRAM_LAST_ERROR_ADDR         12'h05C
`define RIBP_PSRAM_CHIP0_ID_LO             12'h060
`define RIBP_PSRAM_CHIP0_ID_HI             12'h064
`define RIBP_PSRAM_CHIP1_ID_LO             12'h068
`define RIBP_PSRAM_CHIP1_ID_HI             12'h06C
`define RIBP_PSRAM_CHIP2_ID_LO             12'h070
`define RIBP_PSRAM_CHIP2_ID_HI             12'h074
`define RIBP_PSRAM_CHIP3_ID_LO             12'h078
`define RIBP_PSRAM_CHIP3_ID_HI             12'h07C
`define RIBP_PSRAM_INTR_STATE              12'h080
`define RIBP_PSRAM_INTR_ENABLE             12'h084
`define RIBP_PSRAM_INTR_STATUS             12'h088
`define RIBP_PSRAM_INTR_TEST               12'h08C
`define RIBP_PSRAM_PERF_CTRL               12'h090
`define RIBP_PSRAM_PERF_READ_BYTES         12'h094
`define RIBP_PSRAM_PERF_WRITE_BYTES        12'h098
`define RIBP_PSRAM_PERF_COMMANDS           12'h09C
`define RIBP_PSRAM_PERF_SPLITS             12'h0A0
`define RIBP_PSRAM_PERF_STALL_CYCLES       12'h0A4
`define RIBP_PSRAM_PERF_ERROR_COUNT        12'h0A8
`define RIBP_PSRAM_IP_VERSION              12'h0F8
`define RIBP_PSRAM_CAPABILITY              12'h0FC

`define PSRAM_CTRL_ENABLE                  0
`define PSRAM_CTRL_MEMORY_ENABLE           1
`define PSRAM_CTRL_AUTO_INIT               2
`define PSRAM_CTRL_WRAP32                  3

`define PSRAM_COMMAND_INIT                 0
`define PSRAM_COMMAND_RECOVER              1
`define PSRAM_COMMAND_ABORT                2
`define PSRAM_COMMAND_CHIP_LSB              8

`define PSRAM_STATUS_INIT_BUSY             0
`define PSRAM_STATUS_AXI_BUSY              1
`define PSRAM_STATUS_INDIRECT_BUSY         2
`define PSRAM_STATUS_PHY_BUSY              3
`define PSRAM_STATUS_QUIESCED              4
`define PSRAM_STATUS_READY                 5

`define PSRAM_CLK_HALF_PERIOD_LSB          0
`define PSRAM_CLK_HALF_PERIOD_WIDTH        16
`define PSRAM_CLK_ABOVE_84MHZ              16

`define PSRAM_INDIRECT_COMMAND_LSB         0
`define PSRAM_INDIRECT_COMMAND_WIDTH       4
`define PSRAM_INDIRECT_CHIP_LSB            8
`define PSRAM_INDIRECT_LENGTH_LSB          16
`define PSRAM_INDIRECT_START               31

`define PSRAM_INTR_INIT_DONE               0
`define PSRAM_INTR_INDIRECT_DONE           1
`define PSRAM_INTR_ERROR                   2
`define PSRAM_INTR_TIMEOUT                 3

`define PSRAM_PERF_ENABLE                  0
`define PSRAM_PERF_FREEZE                  1
`define PSRAM_PERF_CLEAR                   2

`define PSRAM_IP_VERSION_VALUE             32'h0001_0000
`define PSRAM_CAPABILITY_VALUE             32'h2010_2043
// verilog_format: on

`endif
