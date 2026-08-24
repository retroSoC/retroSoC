// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_TIMER_DEFINE_SVH
`define APB4_TIMER_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define APB4_TIMER_CTRL                      12'h000
`define APB4_TIMER_LOAD                      12'h004
`define APB4_TIMER_VALUE                     12'h008
`define APB4_TIMER_BGLOAD                    12'h00C
`define APB4_TIMER_PRESCALE                  12'h010
`define APB4_TIMER_COMPARE0                  12'h014
`define APB4_TIMER_COMPARE1                  12'h018
`define APB4_TIMER_STATUS                    12'h01C
`define APB4_TIMER_INTR_STATE                12'h020
`define APB4_TIMER_INTR_ENABLE               12'h024
`define APB4_TIMER_INTR_STATUS               12'h028
`define APB4_TIMER_INTR_TEST                 12'h02C
`define APB4_TIMER_IP_VERSION                12'h0F8
`define APB4_TIMER_CAPABILITY                12'h0FC

`define TIMER_CTRL_ENABLE                    0
`define TIMER_CTRL_MODE                      1
`define TIMER_CTRL_DIRECTION                 3
`define TIMER_CTRL_DEBUG_FREEZE              4
`define TIMER_CTRL_COMPARE0_ENABLE           5
`define TIMER_CTRL_COMPARE1_ENABLE           6
// verilog_format: on

`endif
