// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_GPIO_DEFINE_SVH
`define APB4_GPIO_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define APB4_GPIO_NUM                         32

`define APB4_GPIO_USER_DATA_IN                12'h000
`define APB4_GPIO_USER_DATA_OUT               12'h004
`define APB4_GPIO_USER_OUT_SET                12'h008
`define APB4_GPIO_USER_OUT_CLEAR              12'h00C
`define APB4_GPIO_USER_OUT_TOGGLE             12'h010
`define APB4_GPIO_USER_INTR_STATE             12'h014
`define APB4_GPIO_USER_INTR_STATUS            12'h018
`define APB4_GPIO_USER_INTR_ENABLE            12'h01C
`define APB4_GPIO_USER_INTR_ENABLE_SET        12'h020
`define APB4_GPIO_USER_INTR_ENABLE_CLEAR      12'h024

`define APB4_GPIO_ADMIN_DATA_IN               12'h000
`define APB4_GPIO_ADMIN_DATA_OUT              12'h004
`define APB4_GPIO_ADMIN_OUT_SET               12'h008
`define APB4_GPIO_ADMIN_OUT_CLEAR             12'h00C
`define APB4_GPIO_ADMIN_OUT_TOGGLE            12'h010
`define APB4_GPIO_ADMIN_OUTPUT_ENABLE         12'h014
`define APB4_GPIO_ADMIN_OE_SET                12'h018
`define APB4_GPIO_ADMIN_OE_CLEAR              12'h01C
`define APB4_GPIO_ADMIN_OE_TOGGLE             12'h020
`define APB4_GPIO_ADMIN_OPEN_DRAIN            12'h024
`define APB4_GPIO_ADMIN_INPUT_CMOS            12'h028
`define APB4_GPIO_ADMIN_PULL_UP               12'h02C
`define APB4_GPIO_ADMIN_PULL_DOWN             12'h030
`define APB4_GPIO_ADMIN_ALT_ENABLE            12'h034
`define APB4_GPIO_ADMIN_ALT_SELECT            12'h038
`define APB4_GPIO_ADMIN_USER_SELECT           12'h03C
`define APB4_GPIO_ADMIN_USER_LOCK             12'h040
`define APB4_GPIO_ADMIN_USER_STATUS           12'h044
`define APB4_GPIO_ADMIN_USER_ACCESS_MASK      12'h048
`define APB4_GPIO_ADMIN_INTR_RISE_ENABLE      12'h04C
`define APB4_GPIO_ADMIN_INTR_FALL_ENABLE      12'h050
`define APB4_GPIO_ADMIN_INTR_HIGH_ENABLE      12'h054
`define APB4_GPIO_ADMIN_INTR_LOW_ENABLE       12'h058
`define APB4_GPIO_ADMIN_INTR_ENABLE           12'h05C
`define APB4_GPIO_ADMIN_INTR_STATE            12'h060
`define APB4_GPIO_ADMIN_INTR_STATUS           12'h064
`define APB4_GPIO_ADMIN_INTR_TEST             12'h068
`define APB4_GPIO_ADMIN_FILTER_ENABLE         12'h06C
`define APB4_GPIO_ADMIN_FILTER_DIV            12'h070
`define APB4_GPIO_ADMIN_FILTER_COUNT          12'h074
`define APB4_GPIO_ADMIN_CONFIG_LOCK           12'h078
`define APB4_GPIO_PAD_CAPABILITY              12'h0F4
`define APB4_GPIO_IP_VERSION                  12'h0F8
`define APB4_GPIO_CAPABILITY                  12'h0FC

`define GPIO_PAD_CAP_INPUT_CMOS               0
`define GPIO_PAD_CAP_PULL_UP                  1
`define GPIO_PAD_CAP_PULL_DOWN                2

`define GPIO_CAP_OPEN_DRAIN                   16
`define GPIO_CAP_FILTER                       17
`define GPIO_CAP_USER_HANDOFF                 18
`define GPIO_CAP_CONFIG_LOCK                  19
`define GPIO_CAP_ATOMIC_OUT                   20
`define GPIO_CAP_ATOMIC_OE                    21
`define GPIO_CAP_BOTH_EDGE_IRQ                22
// verilog_format: on

`endif
