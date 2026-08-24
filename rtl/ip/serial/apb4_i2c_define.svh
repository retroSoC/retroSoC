// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_APB4_I2C_DEFINE_SVH
`define RETROSOC_APB4_I2C_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define APB4_I2C_CTRL                 8'h00
`define APB4_I2C_SCL_TIMING           8'h04
`define APB4_I2C_START_TIMING         8'h08
`define APB4_I2C_DATA_TIMING          8'h0C
`define APB4_I2C_STOP_TIMING          8'h10
`define APB4_I2C_FILTER               8'h14
`define APB4_I2C_STRETCH_TIMEOUT      8'h18
`define APB4_I2C_BUS_IDLE_TIMEOUT     8'h1C
`define APB4_I2C_COMMAND_TIMEOUT      8'h20
`define APB4_I2C_TARGET_ADDR          8'h24
`define APB4_I2C_DATA_CMD             8'h28
`define APB4_I2C_RXDATA               8'h2C
`define APB4_I2C_STATUS               8'h30
`define APB4_I2C_FIFO_LEVEL           8'h34
`define APB4_I2C_COMMAND              8'h38
`define APB4_I2C_CMD_WATERMARK        8'h3C
`define APB4_I2C_RX_WATERMARK         8'h40
`define APB4_I2C_ERROR_STATUS         8'h44
`define APB4_I2C_INTR_STATE           8'h48
`define APB4_I2C_INTR_ENABLE          8'h4C
`define APB4_I2C_INTR_STATUS          8'h50
`define APB4_I2C_INTR_TEST            8'h54
`define APB4_I2C_LINE_STATE           8'h58
`define APB4_I2C_IP_VERSION           8'hF8
`define APB4_I2C_CAPABILITY           8'hFC

`define I2C_CTRL_ENABLE               0

`define I2C_DATA_CMD_READ             8
`define I2C_DATA_CMD_RESTART          9
`define I2C_DATA_CMD_STOP             10
`define I2C_DATA_CMD_NACK_LAST        11

`define I2C_COMMAND_ABORT             0
`define I2C_COMMAND_RECOVER           1
`define I2C_COMMAND_CMD_FLUSH         2
`define I2C_COMMAND_RX_FLUSH          3

`define I2C_STATUS_ENABLE             0
`define I2C_STATUS_BUSY               1
`define I2C_STATUS_BUS_BUSY           2
`define I2C_STATUS_CMD_EMPTY          3
`define I2C_STATUS_CMD_FULL           4
`define I2C_STATUS_RX_EMPTY           5
`define I2C_STATUS_RX_FULL            6
`define I2C_STATUS_CONFIG_VALID       7
`define I2C_STATUS_RECOVERY_ACTIVE    8
`define I2C_STATUS_SCL                9
`define I2C_STATUS_SDA                10
`define I2C_STATUS_TX_DMA_REQ         11
`define I2C_STATUS_RX_DMA_REQ         12

`define I2C_ERROR_ADDR_NACK           0
`define I2C_ERROR_DATA_NACK           1
`define I2C_ERROR_ARB_LOST            2
`define I2C_ERROR_STRETCH_TIMEOUT     3
`define I2C_ERROR_BUS_TIMEOUT         4
`define I2C_ERROR_COMMAND_TIMEOUT     5
`define I2C_ERROR_COMMAND             6
`define I2C_ERROR_RX_OVERFLOW         7
`define I2C_ERROR_CONFIG              8
`define I2C_ERROR_ABORTED             9
`define I2C_ERROR_RECOVERY_FAILED     10

`define I2C_INTR_DONE                 0
`define I2C_INTR_CMD_WATERMARK        1
`define I2C_INTR_RX_WATERMARK         2
`define I2C_INTR_NACK                 3
`define I2C_INTR_ARB_LOST             4
`define I2C_INTR_TIMEOUT              5
`define I2C_INTR_ERROR                6
`define I2C_INTR_RECOVERY_DONE        7

`define I2C_LINE_SCL                  0
`define I2C_LINE_SDA                  1
`define I2C_LINE_BUS_FREE             2
// verilog_format: on

`endif
