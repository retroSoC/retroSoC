// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_USB2_DEFINE_SVH
`define RETROSOC_USB2_DEFINE_SVH

// verilog_format: off -- preserve the reviewed APB ABI column alignment
`define APB4_USB2__IP_ID                    12'h000
`define APB4_USB2__IP_VERSION               12'h004
`define APB4_USB2__CAPABILITY0              12'h008
`define APB4_USB2__CAPABILITY1              12'h00C
`define APB4_USB2__GLOBAL_CTRL              12'h010
`define APB4_USB2__GLOBAL_STATUS            12'h014
`define APB4_USB2__ROLE_CTRL                12'h018
`define APB4_USB2__ROLE_STATUS              12'h01C
`define APB4_USB2__PHY_CTRL                 12'h020
`define APB4_USB2__PHY_STATUS               12'h024
`define APB4_USB2__ULPI_VIEWPORT            12'h028
`define APB4_USB2__ULPI_VIEWPORT_DATA       12'h02C
`define APB4_USB2__TIMEOUT                  12'h030
`define APB4_USB2__FRAME                    12'h034
`define APB4_USB2__TEST_CTRL                12'h038
`define APB4_USB2__PIO_DATA                 12'h03C

`define APB4_USB2__IRQ_STATUS               12'h040
`define APB4_USB2__IRQ_ENABLE               12'h044
`define APB4_USB2__IRQ_TEST                 12'h048
`define APB4_USB2__ERROR_STATUS             12'h04C
`define APB4_USB2__ERROR_CODE               12'h050
`define APB4_USB2__ERROR_INFO               12'h054
`define APB4_USB2__ERROR_DESC_ADDR          12'h058
`define APB4_USB2__ERROR_BUFFER_ADDR        12'h05C
`define APB4_USB2__PERF_TX_BYTES            12'h060
`define APB4_USB2__PERF_RX_BYTES            12'h064
`define APB4_USB2__PERF_PACKETS             12'h068
`define APB4_USB2__PERF_RETRIES             12'h06C
`define APB4_USB2__PERF_AXI_STALL           12'h070
`define APB4_USB2__PERF_RAM_STALL           12'h074
`define APB4_USB2__PERF_IRQ_COUNT           12'h078
`define APB4_USB2__PERF_CTRL                12'h07C

`define APB4_USB2__DEVICE_CTRL              12'h100
`define APB4_USB2__DEVICE_ADDR              12'h104
`define APB4_USB2__DEVICE_STATUS            12'h108
`define APB4_USB2__SETUP0                   12'h10C
`define APB4_USB2__SETUP1                   12'h110
`define APB4_USB2__ENDPOINT_PENDING_IN      12'h114
`define APB4_USB2__ENDPOINT_PENDING_OUT     12'h118
`define APB4_USB2__ENDPOINT_COMPLETE_IN     12'h11C
`define APB4_USB2__ENDPOINT_COMPLETE_OUT    12'h120

`define APB4_USB2__ENDPOINT_BASE            12'h200
`define APB4_USB2__ENDPOINT_STRIDE          12'h040
`define APB4_USB2__ENDPOINT_CFG             12'h000
`define APB4_USB2__ENDPOINT_RAM_IN           12'h004
`define APB4_USB2__ENDPOINT_RAM_OUT          12'h008
`define APB4_USB2__ENDPOINT_DESC_IN          12'h00C
`define APB4_USB2__ENDPOINT_DESC_OUT         12'h010
`define APB4_USB2__ENDPOINT_COMMAND          12'h014
`define APB4_USB2__ENDPOINT_STATUS           12'h018
`define APB4_USB2__ENDPOINT_BYTES_IN         12'h01C
`define APB4_USB2__ENDPOINT_BYTES_OUT        12'h020

`define APB4_USB2__HOST_CTRL                12'h400
`define APB4_USB2__HOST_STATUS              12'h404
`define APB4_USB2__PORT_CTRL                12'h408
`define APB4_USB2__PORT_STATUS              12'h40C
`define APB4_USB2__SCHEDULE_CTRL            12'h410
`define APB4_USB2__SCHEDULE_STATUS          12'h414

`define APB4_USB2__CHANNEL_BASE             12'h500
`define APB4_USB2__CHANNEL_STRIDE           12'h040
`define APB4_USB2__CHANNEL_CFG              12'h000
`define APB4_USB2__CHANNEL_TARGET           12'h004
`define APB4_USB2__CHANNEL_INTERVAL         12'h008
`define APB4_USB2__CHANNEL_RAM              12'h00C
`define APB4_USB2__CHANNEL_DESC             12'h010
`define APB4_USB2__CHANNEL_COMMAND          12'h014
`define APB4_USB2__CHANNEL_STATUS           12'h018
`define APB4_USB2__CHANNEL_BYTES            12'h01C

`define APB4_USB2__RAM_CTRL                 12'h900
`define APB4_USB2__RAM_STATUS               12'h904
`define APB4_USB2__ECC_STATUS               12'h908
`define APB4_USB2__ECC_CORRECTED_COUNT      12'h90C
`define APB4_USB2__ECC_UNCORRECTABLE_COUNT  12'h910
`define APB4_USB2__RAM_BIST                 12'h914
`define APB4_USB2__DEBUG_STATUS             12'h918

`define APB4_USB2__GLOBAL_CTRL_ENABLE       0
`define APB4_USB2__GLOBAL_CTRL_SOFT_RESET   1
`define APB4_USB2__GLOBAL_CTRL_ABORT        2
`define APB4_USB2__GLOBAL_CTRL_IRQ_ENABLE   3
`define APB4_USB2__ROLE_CTRL_FORCE_LSB      0
`define APB4_USB2__ROLE_CTRL_AUTO           2
`define APB4_USB2__ROLE_IDLE                0
`define APB4_USB2__ROLE_DEVICE              1
`define APB4_USB2__ROLE_HOST                2
`define APB4_USB2__PHY_CTRL_RESET_N         0
`define APB4_USB2__PHY_CTRL_SUSPEND         1
`define APB4_USB2__PHY_CTRL_REMOTE_WAKE     2
`define APB4_USB2__PHY_CTRL_VIEWPORT_START  31
`define APB4_USB2__PHY_CTRL_VIEWPORT_WRITE  30
`define APB4_USB2__PHY_CTRL_VIEWPORT_ADDR_LSB 16
`define APB4_USB2__PHY_CTRL_VIEWPORT_DATA_LSB 0

`define APB4_USB2__IRQ_ROLE_CHANGE          0
`define APB4_USB2__IRQ_PORT_CHANGE          1
`define APB4_USB2__IRQ_BUS_RESET            2
`define APB4_USB2__IRQ_SUSPEND              3
`define APB4_USB2__IRQ_RESUME               4
`define APB4_USB2__IRQ_SETUP                5
`define APB4_USB2__IRQ_ENDPOINT             6
`define APB4_USB2__IRQ_CHANNEL              7
`define APB4_USB2__IRQ_DMA_DONE             8
`define APB4_USB2__IRQ_DMA_ERROR            9
`define APB4_USB2__IRQ_PHY_ERROR           10
`define APB4_USB2__IRQ_ULPI_ERROR          11
`define APB4_USB2__IRQ_ECC_CORRECTED       12
`define APB4_USB2__IRQ_ECC_UNCORRECTABLE   13
`define APB4_USB2__IRQ_TIMEOUT             14
`define APB4_USB2__IRQ_FATAL               15

`define APB4_USB2__ENDPOINT_CFG_IN_ENABLE           0
`define APB4_USB2__ENDPOINT_CFG_OUT_ENABLE          1
`define APB4_USB2__ENDPOINT_CFG_IN_STALL            2
`define APB4_USB2__ENDPOINT_CFG_OUT_STALL           3
`define APB4_USB2__ENDPOINT_CFG_TYPE_LSB             4
`define APB4_USB2__ENDPOINT_CFG_MAX_PACKET_LSB      16
`define APB4_USB2__ENDPOINT_COMMAND_PRIME_IN         0
`define APB4_USB2__ENDPOINT_COMMAND_ARM_OUT          1
`define APB4_USB2__ENDPOINT_COMMAND_CANCEL           2
`define APB4_USB2__ENDPOINT_COMMAND_RESET_TOGGLE     3

`define APB4_USB2__CHANNEL_CFG_ENABLE                0
`define APB4_USB2__CHANNEL_CFG_DIRECTION_IN          1
`define APB4_USB2__CHANNEL_CFG_TYPE_LSB              2
`define APB4_USB2__CHANNEL_CFG_LOW_SPEED             4
`define APB4_USB2__CHANNEL_CFG_SETUP                 5
`define APB4_USB2__CHANNEL_CFG_PING_ENABLE           6
`define APB4_USB2__CHANNEL_CFG_MAX_PACKET_LSB       16
`define APB4_USB2__CHANNEL_TARGET_ADDR_LSB           0
`define APB4_USB2__CHANNEL_TARGET_ENDPOINT_LSB       8
`define APB4_USB2__CHANNEL_TARGET_TOGGLE            12
`define APB4_USB2__CHANNEL_COMMAND_START             0
`define APB4_USB2__CHANNEL_COMMAND_CANCEL            1

`define APB4_USB2__RAM_REGION_BASE_LSB               2
`define APB4_USB2__RAM_REGION_LENGTH_LSB            16

`define APB4_USB2__DESC_OWN                 0
`define APB4_USB2__DESC_CHAIN               1
`define APB4_USB2__DESC_END                 2
`define APB4_USB2__DESC_IRQ                 3
`define APB4_USB2__DESC_SHORT_OK            4
`define APB4_USB2__DESC_ZERO_PACKET         5
`define APB4_USB2__DESC_DONE               16
`define APB4_USB2__DESC_SHORT              17
`define APB4_USB2__DESC_STALL              18
`define APB4_USB2__DESC_TIMEOUT            19
`define APB4_USB2__DESC_CRC_ERROR          20
`define APB4_USB2__DESC_PROTOCOL_ERROR     21
`define APB4_USB2__DESC_AXI_ERROR          22
`define APB4_USB2__DESC_ABORTED            23
// verilog_format: on

`endif
