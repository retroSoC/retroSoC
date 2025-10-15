// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef ONEWIRE_DEF_SV
`define ONEWIRE_DEF_SV

// verilog_format: off
`define NATV_ONEWIRE_CLKDIV  8'h00
`define NATV_ONEWIRE_ZEROCNT 8'h04
`define NATV_ONEWIRE_ONECNT  8'h08
`define NATV_ONEWIRE_RSTCNT  8'h0C
`define NATV_ONEWIRE_TXDATA  8'h10
`define NATV_ONEWIRE_CTRL    8'h14
`define NATV_ONEWIRE_STATUS  8'h18
// verilog_format: on

`endif

module nmi_qspi (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    nmi_if.slave nmi,
    qspi_if.dut  qspi
    // verilog_format: on
);
endmodule
