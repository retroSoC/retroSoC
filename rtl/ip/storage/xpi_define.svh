// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_XPI_DEF_SV
`define APB4_XPI_DEF_SV

// verilog_format: off -- preserve reviewed column alignment
`define APB4_XPI_CFGIDX  8'h00
`define APB4_XPI_ACCMD   8'h04
`define APB4_XPI_MMSTAD  8'h08
`define APB4_XPI_MMOFFST 8'h0C
`define APB4_XPI_MODE    8'h10
`define APB4_XPI_NSS     8'h14
`define APB4_XPI_CLKDIV  8'h18
`define APB4_XPI_RDWR    8'h1C
`define APB4_XPI_REVDAT  8'h20
`define APB4_XPI_TXUPB   8'h24
`define APB4_XPI_TXLOWB  8'h28
`define APB4_XPI_RXUPB   8'h2C
`define APB4_XPI_RXLOWB  8'h30
`define APB4_XPI_FLUSH   8'h34
`define APB4_XPI_CMDTYP  8'h38
`define APB4_XPI_CMDLEN  8'h3C
`define APB4_XPI_CMDDAT  8'h40
`define APB4_XPI_ADRTYP  8'h44
`define APB4_XPI_ADRLEN  8'h48
`define APB4_XPI_ADRDAT  8'h4C
`define APB4_XPI_ALTTYP  8'h50
`define APB4_XPI_ALTLEN  8'h54
`define APB4_XPI_ALTDAT  8'h58
`define APB4_XPI_TDULEN  8'h5C
`define APB4_XPI_RDULEN  8'h60
`define APB4_XPI_DATTYP  8'h64
`define APB4_XPI_DATLEN  8'h68
`define APB4_XPI_DATBIT  8'h6C
`define APB4_XPI_HLVLEN  8'h70
`define APB4_XPI_TXDATA  8'h74
`define APB4_XPI_RXDATA  8'h78
`define APB4_XPI_XST     8'h7C
`define APB4_XPI_STATUS  8'h80

`define XPI_TYPE_NONE   2'd0
`define XPI_TYPE_SNGL   2'd1
`define XPI_TYPE_DUAL   2'd2
`define XPI_TYPE_QUAD   2'd3

`define XPI_NSS_NUM     4
`define XPI_LNS_NUM     $clog2(`XPI_NSS_NUM)
// verilog_format: on

`endif
