// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_I2S_DEFINE_SVH
`define APB4_I2S_DEFINE_SVH

// verilog_format: off -- preserve reviewed register and field alignment
`define APB4_I2S_CTRL                    12'h000
`define APB4_I2S_COMMAND                 12'h004
`define APB4_I2S_STATUS                  12'h008
`define APB4_I2S_STREAM_CTRL             12'h00C
`define APB4_I2S_FORMAT                  12'h010
`define APB4_I2S_CLK_DIV                 12'h014
`define APB4_I2S_FIFO_TH                 12'h018
`define APB4_I2S_TXDATA                  12'h01C
`define APB4_I2S_RXDATA                  12'h020
`define APB4_I2S_INTR_STATE              12'h024
`define APB4_I2S_INTR_ENABLE             12'h028
`define APB4_I2S_INTR_STATUS             12'h02C
`define APB4_I2S_INTR_TEST               12'h030
`define APB4_I2S_IP_VERSION              12'h0F8
`define APB4_I2S_CAPABILITY              12'h0FC

`define APB4_I2S__CTRL_ENABLE            0
`define APB4_I2S__CTRL_TX_ENABLE         1
`define APB4_I2S__CTRL_RX_ENABLE         2
`define APB4_I2S__CTRL_LOOPBACK          3
`define APB4_I2S__CTRL_CLK_PROG          4

`define APB4_I2S__COMMAND_TX_FLUSH       0
`define APB4_I2S__COMMAND_RX_FLUSH       1

`define APB4_I2S__STATUS_TX_FULL         0
`define APB4_I2S__STATUS_TX_EMPTY        1
`define APB4_I2S__STATUS_RX_FULL         2
`define APB4_I2S__STATUS_RX_EMPTY        3
`define APB4_I2S__STATUS_TX_STALL        4
`define APB4_I2S__STATUS_RX_STALL        5
`define APB4_I2S__STATUS_ENABLE          6
`define APB4_I2S__STATUS_BUSY            7
`define APB4_I2S__STATUS_TX_LEVEL_LSB    8
`define APB4_I2S__STATUS_RX_LEVEL_LSB    16
`define APB4_I2S__STATUS_TX_FLUSH_BUSY   24
`define APB4_I2S__STATUS_RX_FLUSH_BUSY   25

`define APB4_I2S__STREAM_TX              0
`define APB4_I2S__STREAM_RX              1

`define APB4_I2S__FORMAT_PRESET          1:0
`define APB4_I2S__FORMAT_BITMODE         2

`define APB4_I2S__CLK_SCLK_LSB           0
`define APB4_I2S__CLK_LRCK_LSB           8
`define APB4_I2S__CLK_MCLK_LSB           16

`define APB4_I2S__FIFO_UPBOUND_LSB       0
`define APB4_I2S__FIFO_LOWBOUND_LSB      8

`define APB4_I2S__INTR_TX_LOW            0
`define APB4_I2S__INTR_RX_HIGH           1
`define APB4_I2S__INTR_TX_UNDERRUN       2
`define APB4_I2S__INTR_RX_OVERRUN        3
`define APB4_I2S__INTR_ALL               4'hF

`define APB4_I2S__CFG_ENABLE             0
`define APB4_I2S__CFG_TX_ENABLE          1
`define APB4_I2S__CFG_RX_ENABLE          2
`define APB4_I2S__CFG_LOOPBACK           3
`define APB4_I2S__CFG_CLK_PROG           4
`define APB4_I2S__CFG_FORMAT             6:5
`define APB4_I2S__CFG_BITMODE            7
`define APB4_I2S__CFG_SCLK_LSB           8
`define APB4_I2S__CFG_LRCK_LSB           16
`define APB4_I2S__CFG_MCLK_LSB           24

`define I2S_16b_48K                      2'd0
`define I2S_16b_96K                      2'd1
`define I2S_24b_48K                      2'd2
`define I2S_24b_96K                      2'd3

`define I2S_IP_VERSION_VALUE             32'h0001_0000
`define I2S_CAPABILITY_VALUE             32'h0030_0707
// verilog_format: on

`endif
