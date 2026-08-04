// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_SOC_RIB_DEFS_SVH
`define RETROSOC_SOC_RIB_DEFS_SVH

`define SOC_RIB_RESP_OK 3'd0
`define SOC_RIB_RESP_DECERR 3'd1
`define SOC_RIB_RESP_PROTERR 3'd2
`define SOC_RIB_RESP_SLVERR 3'd3
`define SOC_RIB_RESP_TIMEOUT 3'd4
`define SOC_RIB_RESP_RESERVED 3'd5
`define SOC_RIB_RESP_BURSTERR 3'd6

`define SOC_RIB_LEN_INCR1 2'd0
`define SOC_RIB_LEN_INCR4 2'd3

`endif
