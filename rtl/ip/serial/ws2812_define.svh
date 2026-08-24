// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See the Mulan PSL v2 for more details.

`ifndef WS2812_DEFINE_SVH
`define WS2812_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define APB4_WS2812_BIT_CYCLES       8'h00
`define APB4_WS2812_T0H_CYCLES       8'h04
`define APB4_WS2812_T1H_CYCLES       8'h08
`define APB4_WS2812_RESET_CYCLES     8'h0C
`define APB4_WS2812_TXDATA           8'h10
`define APB4_WS2812_CTRL             8'h14
`define APB4_WS2812_STATUS           8'h18
`define APB4_WS2812_FRAME_WORDS      8'h1C
`define APB4_WS2812_FIFO_LEVEL       8'h20
`define APB4_WS2812_FIFO_WATERMARK   8'h24
`define APB4_WS2812_REMAINING_WORDS  8'h28
`define APB4_WS2812_ERROR_STATUS     8'h2C
`define APB4_WS2812_INTR_STATE       8'h30
`define APB4_WS2812_INTR_ENABLE      8'h34
`define APB4_WS2812_INTR_TEST        8'h38
`define APB4_WS2812_IP_INFO          8'h3C

`define WS2812_CTRL_START            0
`define WS2812_CTRL_ABORT            1
`define WS2812_CTRL_FIFO_FLUSH       2

`define WS2812_STATUS_BUSY           0
`define WS2812_STATUS_FIFO_EMPTY     1
`define WS2812_STATUS_FIFO_FULL      2
`define WS2812_STATUS_CONFIG_VALID   3
`define WS2812_STATUS_RESET_ACTIVE   4

`define WS2812_ERROR_CONFIG          0
`define WS2812_ERROR_UNDERFLOW       1
`define WS2812_ERROR_COMMAND         2

`define WS2812_INTR_DONE             0
`define WS2812_INTR_FIFO_LOW         1
`define WS2812_INTR_ERROR            2
`define WS2812_INTR_ABORTED          3
// verilog_format: on

`endif
