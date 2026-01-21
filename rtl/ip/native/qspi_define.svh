// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NMI_QSPI_DEF_SV
`define NMI_QSPI_DEF_SV

// verilog_format: off
`define NATV_QSPI_CFGIDX  8'h00
`define NATV_QSPI_ACCMD   8'h04
`define NATV_QSPI_MMSTAD  8'h08
`define NATV_QSPI_MMOFFST 8'h0C
`define NATV_QSPI_MODE    8'h10
`define NATV_QSPI_NSS     8'h14
`define NATV_QSPI_CLKDIV  8'h18
`define NATV_QSPI_RDWR    8'h1C
`define NATV_QSPI_REVDAT  8'h20
`define NATV_QSPI_TXUPB   8'h24
`define NATV_QSPI_TXLOWB  8'h28
`define NATV_QSPI_RXUPB   8'h2C
`define NATV_QSPI_RXLOWB  8'h30
`define NATV_QSPI_FLUSH   8'h34
`define NATV_QSPI_CMDTYP  8'h38
`define NATV_QSPI_CMDLEN  8'h3C
`define NATV_QSPI_CMDDAT  8'h40
`define NATV_QSPI_ADRTYP  8'h44
`define NATV_QSPI_ADRLEN  8'h48
`define NATV_QSPI_ADRDAT  8'h4C
`define NATV_QSPI_ALTTYP  8'h50
`define NATV_QSPI_ALTLEN  8'h54
`define NATV_QSPI_ALTDAT  8'h58
`define NATV_QSPI_TDULEN  8'h5C
`define NATV_QSPI_RDULEN  8'h60
`define NATV_QSPI_DATTYP  8'h64
`define NATV_QSPI_DATLEN  8'h68
`define NATV_QSPI_DATBIT  8'h6C
`define NATV_QSPI_HLVLEN  8'h70
`define NATV_QSPI_TXDATA  8'h74
`define NATV_QSPI_RXDATA  8'h78
`define NATV_QSPI_START   8'h7C
`define NATV_QSPI_STATUS  8'h80

`define QSPI_TYPE_NONE    2'd0
`define QSPI_TYPE_SNGL    2'd1
`define QSPI_TYPE_DUAL    2'd2
`define QSPI_TYPE_QUAD    2'd3

`define QSPI_NSS_NUM      4
`define QSPI_LNS_NUM      $clog2(`QSPI_NSS_NUM)
// verilog_format: on

`endif