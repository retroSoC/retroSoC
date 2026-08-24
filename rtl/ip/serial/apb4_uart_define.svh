// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_UART_DEFINE_SVH
`define APB4_UART_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define APB4_UART_BAUD_INT          8'h00
`define APB4_UART_BAUD_FRAC         8'h04
`define APB4_UART_LINE_CTRL         8'h08
`define APB4_UART_CTRL              8'h0C
`define APB4_UART_TXDATA            8'h10
`define APB4_UART_RXDATA            8'h14
`define APB4_UART_STATUS            8'h18
`define APB4_UART_FIFO_LEVEL        8'h1C
`define APB4_UART_FIFO_CTRL         8'h20
`define APB4_UART_TX_WATERMARK      8'h24
`define APB4_UART_RX_WATERMARK      8'h28
`define APB4_UART_RX_TIMEOUT_BITS   8'h2C
`define APB4_UART_ERROR_STATUS      8'h30
`define APB4_UART_INTR_STATE        8'h34
`define APB4_UART_INTR_ENABLE       8'h38
`define APB4_UART_INTR_STATUS       8'h3C
`define APB4_UART_INTR_TEST         8'h40
`define APB4_UART_DMA_CTRL          8'h44
`define APB4_UART_FLOW_CTRL         8'h48
`define APB4_UART_RTS_WATERMARK     8'h4C
`define APB4_UART_IP_VERSION        8'hF8
`define APB4_UART_CAPABILITY        8'hFC

`define UART_LINE_DATA_BITS         0
`define UART_LINE_STOP2             2
`define UART_LINE_PARITY            3

`define UART_CTRL_TX_ENABLE         0
`define UART_CTRL_RX_ENABLE         1
`define UART_CTRL_LOOPBACK          2
`define UART_CTRL_TX_BREAK          3

`define UART_FIFO_CTRL_TX_FLUSH     0
`define UART_FIFO_CTRL_RX_FLUSH     1

`define UART_STATUS_TX_ENABLED      0
`define UART_STATUS_RX_ENABLED      1
`define UART_STATUS_TX_BUSY         2
`define UART_STATUS_RX_ACTIVE       3
`define UART_STATUS_TX_EMPTY        4
`define UART_STATUS_TX_FULL         5
`define UART_STATUS_RX_EMPTY        6
`define UART_STATUS_RX_FULL         7
`define UART_STATUS_CONFIG_VALID    8
`define UART_STATUS_BREAK_ACTIVE    9
`define UART_STATUS_TX_DMA_REQ      10
`define UART_STATUS_RX_DMA_REQ      11
`define UART_STATUS_CTS_ASSERTED    12
`define UART_STATUS_RTS_ASSERTED    13
`define UART_STATUS_TX_FLOW_BLOCKED 14

`define UART_RXDATA_PARITY_ERROR    8
`define UART_RXDATA_FRAME_ERROR     9
`define UART_RXDATA_BREAK           10
`define UART_RXDATA_NOISE           11

`define UART_ERROR_OVERRUN          0
`define UART_ERROR_PARITY           1
`define UART_ERROR_FRAME            2
`define UART_ERROR_BREAK            3
`define UART_ERROR_NOISE            4
`define UART_ERROR_CONFIG           5
`define UART_ERROR_COMMAND          6

`define UART_INTR_RX_WATERMARK      0
`define UART_INTR_RX_TIMEOUT        1
`define UART_INTR_TX_WATERMARK      2
`define UART_INTR_TX_DONE           3
`define UART_INTR_RX_ERROR          4
`define UART_INTR_BREAK             5
`define UART_INTR_CTS_CHANGE        6

`define UART_DMA_TX_ENABLE          0
`define UART_DMA_RX_ENABLE          1

`define UART_FLOW_AUTO_CTS_ENABLE   0
`define UART_FLOW_AUTO_RTS_ENABLE   1

`define UART_RTS_ASSERT_LEVEL       0
`define UART_RTS_DEASSERT_LEVEL     16
// verilog_format: on

`endif
