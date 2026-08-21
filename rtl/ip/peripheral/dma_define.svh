// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_DMA_DEFINE_SVH
`define RETROSOC_DMA_DEFINE_SVH

// verilog_format: off -- software-visible register columns are manually mirrored in dma_regs.h.
`define APB4_DMA__IP_ID                12'h000
`define APB4_DMA__IP_VERSION           12'h004
`define APB4_DMA__CAPABILITY            12'h008
`define APB4_DMA__GLOBAL_CTRL           12'h00C
`define APB4_DMA__GLOBAL_STATUS         12'h010
`define APB4_DMA__IRQ_STATE             12'h014
`define APB4_DMA__IRQ_ENABLE            12'h018
`define APB4_DMA__IRQ_TEST              12'h01C
`define APB4_DMA__ERROR_SUMMARY         12'h020
`define APB4_DMA__REQUEST_STATUS        12'h024

`define APB4_DMA__CH_BASE               12'h100
`define APB4_DMA__CH_STRIDE             12'h080
`define APB4_DMA__CH_CTRL               7'h00
`define APB4_DMA__CH_CFG                7'h04
`define APB4_DMA__CH_SRC_ADDR           7'h08
`define APB4_DMA__CH_DST_ADDR           7'h0C
`define APB4_DMA__CH_BYTE_COUNT         7'h10
`define APB4_DMA__CH_REQUEST_SEL        7'h14
`define APB4_DMA__CH_BURST_CFG          7'h18
`define APB4_DMA__CH_EVENT_ENABLE       7'h1C
`define APB4_DMA__CH_STATUS             7'h20
`define APB4_DMA__CH_EVENT_STATUS       7'h24
`define APB4_DMA__CH_ERROR_STATUS       7'h28
`define APB4_DMA__CH_ERROR_ADDR         7'h2C
`define APB4_DMA__CH_CURRENT_SRC        7'h30
`define APB4_DMA__CH_CURRENT_DST        7'h34
`define APB4_DMA__CH_REMAINING          7'h38
`define APB4_DMA__CH_BYTES_DONE         7'h3C
`define APB4_DMA__CH_STALL_CYCLES_LO    7'h40
`define APB4_DMA__CH_STALL_CYCLES_HI    7'h44

`define APB4_DMA__GLOBAL_CTRL_RESET     0
`define APB4_DMA__CH_CTRL_START         0
`define APB4_DMA__CH_CTRL_SUSPEND       1
`define APB4_DMA__CH_CTRL_RESUME        2
`define APB4_DMA__CH_CTRL_ABORT         3
`define APB4_DMA__CH_CTRL_RESET         4

`define APB4_DMA__CH_CFG_KIND_LSB       0
`define APB4_DMA__CH_CFG_WIDTH_LSB      4
`define APB4_DMA__CH_CFG_SRC_INCREMENT  6
`define APB4_DMA__CH_CFG_DST_INCREMENT  7
`define APB4_DMA__CH_CFG_PRIORITY_LSB   8

`define APB4_DMA__EVENT_DONE             0
`define APB4_DMA__EVENT_HALF             1
`define APB4_DMA__EVENT_ERROR            2
`define APB4_DMA__STATUS_BUSY            0
`define APB4_DMA__STATUS_SUSPENDED       1
`define APB4_DMA__STATUS_DONE            2
`define APB4_DMA__STATUS_ABORTED         3
`define APB4_DMA__STATUS_ERROR           4
`define APB4_DMA__STATUS_STREAM_LAST     5
// verilog_format: on

`endif
