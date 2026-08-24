// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_XPI_DEFINE_SVH
`define RETROSOC_XPI_DEFINE_SVH

// verilog_format: off -- software ABI table is intentionally column aligned
`define APB4_XPI__ID                    12'h000
`define APB4_XPI__VERSION               12'h004
`define APB4_XPI__CAPABILITY            12'h008
`define APB4_XPI__CTRL                  12'h00C
`define APB4_XPI__STATUS                12'h010
`define APB4_XPI__COMMAND               12'h014
`define APB4_XPI__ERROR_STATE           12'h018
`define APB4_XPI__ERROR_ADDR            12'h01C
`define APB4_XPI__ERROR_INFO            12'h020
`define APB4_XPI__INTR_STATE            12'h024
`define APB4_XPI__INTR_ENABLE           12'h028
`define APB4_XPI__INTR_STATUS           12'h02C
`define APB4_XPI__INTR_TEST             12'h030
`define APB4_XPI__DMA_CTRL              12'h034
`define APB4_XPI__FIFO_CTRL             12'h038
`define APB4_XPI__FIFO_STATUS           12'h03C
`define APB4_XPI__TXDATA                12'h040
`define APB4_XPI__RXDATA                12'h044
`define APB4_XPI__INDIRECT_ADDR         12'h048
`define APB4_XPI__INDIRECT_COUNT        12'h04C
`define APB4_XPI__INDIRECT_CFG          12'h050
`define APB4_XPI__POLL_CFG              12'h054
`define APB4_XPI__POLL_MASK             12'h058
`define APB4_XPI__POLL_MATCH            12'h05C
`define APB4_XPI__POLL_INTERVAL         12'h060
`define APB4_XPI__POLL_TIMEOUT          12'h064
`define APB4_XPI__PERF_CTRL             12'h068
`define APB4_XPI__PERF_AXI_READ_BYTES   12'h06C
`define APB4_XPI__PERF_AXI_WRITE_BYTES  12'h070
`define APB4_XPI__PERF_PHY_BYTES        12'h074
`define APB4_XPI__PERF_COMMANDS         12'h078
`define APB4_XPI__PERF_STALL_CYCLES     12'h07C
`define APB4_XPI__CONFIG_LOCK           12'h080

`define APB4_XPI__SLOT_BASE             12'h100
`define APB4_XPI__SLOT_STRIDE           12'h020
`define APB4_XPI__SLOT_CTRL             12'h000
`define APB4_XPI__SLOT_DEVICE_SIZE      12'h004
`define APB4_XPI__SLOT_SEQ_CFG          12'h008
`define APB4_XPI__SLOT_TIMING           12'h00C
`define APB4_XPI__SLOT_TIMEOUT          12'h010
`define APB4_XPI__SLOT_BOUNDARY         12'h014

`define APB4_XPI__LUT_BASE              12'h200
`define APB4_XPI__LUT_END               12'h2FC

`define XPI_CTRL_ENABLE                 0

`define XPI_COMMAND_INDIRECT_START      0
`define XPI_COMMAND_POLL_START          1
`define XPI_COMMAND_ABORT               2

`define XPI_SLOT_CTRL_ENABLE            0
`define XPI_SLOT_CTRL_MM_READ_ENABLE    1
`define XPI_SLOT_CTRL_MM_WRITE_ENABLE   2
`define XPI_SLOT_CTRL_MODE3             3

`define XPI_INTR_INDIRECT_DONE          0
`define XPI_INTR_POLL_MATCH             1
`define XPI_INTR_TX_WATERMARK           2
`define XPI_INTR_RX_WATERMARK           3
`define XPI_INTR_AXI_ERROR              4
`define XPI_INTR_SEQUENCE_ERROR         5
`define XPI_INTR_TIMEOUT                6
`define XPI_INTR_ABORT_DONE             7

`define XPI_NSS_NUM                     4
`define XPI_LNS_NUM                     2
// verilog_format: on

`endif
