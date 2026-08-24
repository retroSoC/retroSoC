// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_SDRAM_DEFINE_SVH
`define APB4_SDRAM_DEFINE_SVH

// verilog_format: off -- preserve reviewed register and field alignment
`define APB4_SDRAM__CLKDIV                 12'h000
`define APB4_SDRAM__CTRL                   12'h004
`define APB4_SDRAM__COMMAND                12'h008
`define APB4_SDRAM__STATUS                 12'h00C
`define APB4_SDRAM__MODE                   12'h010
`define APB4_SDRAM__TIMING0                12'h014
`define APB4_SDRAM__TIMING1                12'h018
`define APB4_SDRAM__TIMING2                12'h01C
`define APB4_SDRAM__REFRESH                12'h020
`define APB4_SDRAM__POWERUP                12'h024
`define APB4_SDRAM__LAST_ERROR             12'h028
`define APB4_SDRAM__LAST_ERROR_ADDR        12'h02C
`define APB4_SDRAM__INTR_STATE             12'h080
`define APB4_SDRAM__INTR_ENABLE            12'h084
`define APB4_SDRAM__INTR_STATUS            12'h088
`define APB4_SDRAM__INTR_TEST              12'h08C
`define APB4_SDRAM__PERF_CTRL              12'h090
`define APB4_SDRAM__PERF_READ_BYTES        12'h094
`define APB4_SDRAM__PERF_WRITE_BYTES       12'h098
`define APB4_SDRAM__PERF_ROW_HIT           12'h09C
`define APB4_SDRAM__PERF_ROW_MISS          12'h0A0
`define APB4_SDRAM__PERF_REFRESH_STALL     12'h0A4
`define APB4_SDRAM__PERF_BANK_CONFLICT     12'h0A8
`define APB4_SDRAM__IP_VERSION             12'h0F8
`define APB4_SDRAM__CAPABILITY             12'h0FC

`define APB4_SDRAM__CTRL_ENABLE            0
`define APB4_SDRAM__CTRL_MEMORY_ENABLE     1
`define APB4_SDRAM__CTRL_AUTO_INIT         2
`define APB4_SDRAM__CTRL_OPEN_PAGE         3

`define APB4_SDRAM__COMMAND_INIT           0
`define APB4_SDRAM__COMMAND_REINIT         1
`define APB4_SDRAM__COMMAND_PRECHARGE_ALL  2
`define APB4_SDRAM__COMMAND_REFRESH        3

`define APB4_SDRAM__STATUS_INIT_BUSY       0
`define APB4_SDRAM__STATUS_AXI_BUSY        1
`define APB4_SDRAM__STATUS_PHY_BUSY        2
`define APB4_SDRAM__STATUS_READY           3
`define APB4_SDRAM__STATUS_ERROR           4

`define APB4_SDRAM__MODE_CAS_LSB           0
`define APB4_SDRAM__MODE_CAS_WIDTH         2
`define APB4_SDRAM__MODE_BL_LSB            2
`define APB4_SDRAM__MODE_BL_WIDTH          2
`define APB4_SDRAM__MODE_WR_BURST          4
`define APB4_SDRAM__MODE_BURST_TYPE        5
`define APB4_SDRAM__MODE_BL_2              2'd0
`define APB4_SDRAM__MODE_BL_8              2'd1

`define APB4_SDRAM__REFRESH_TREFI_LSB      0
`define APB4_SDRAM__REFRESH_TREFI_WIDTH    16
`define APB4_SDRAM__REFRESH_CREDIT_LSB     16
`define APB4_SDRAM__REFRESH_CREDIT_WIDTH   4

`define APB4_SDRAM__INTR_INIT_DONE         0
`define APB4_SDRAM__INTR_ERROR             1

`define APB4_SDRAM__PERF_ENABLE            0
`define APB4_SDRAM__PERF_FREEZE            1
`define APB4_SDRAM__PERF_CLEAR             2

`define APB4_SDRAM__CTRL_RESET             32'h0000_0007
`define APB4_SDRAM__MODE_RESET             32'h0000_0012
`define APB4_SDRAM__TIMING0_RESET          32'h0302_0101
`define APB4_SDRAM__TIMING1_RESET          32'h0202_0301
`define APB4_SDRAM__TIMING2_RESET          32'h0003_0201
`define APB4_SDRAM__REFRESH_RESET          32'h0007_0119
`define APB4_SDRAM__POWERUP_RESET          32'h0000_0E10
`define APB4_SDRAM__IP_VERSION_VALUE       32'h0002_0000
`define APB4_SDRAM__CAPABILITY_VALUE       32'h4010_10EF
// verilog_format: on

`endif
