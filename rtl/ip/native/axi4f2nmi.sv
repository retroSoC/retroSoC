// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module axi4f2nmi (
    // verilog_format: off
    input  logic        aclk_i,
    input  logic        aresetn_i,
    input  logic [31:0] awaddr_i,
    input  logic        awvalid_i,
    output logic        awready_o,
    input  logic [31:0] wdata_i,
    input  logic [ 3:0] wstrb_i,
    input  logic        wvalid_i,
    output logic        wready_o,
    output logic [ 1:0] bresp_o,
    output logic        bvalid_o,
    input  logic        bready_i,
    input  logic [31:0] araddr_i,
    input  logic        arvalid_i,
    output logic        arready_o,
    output logic [31:0] rdata_o,
    output logic [ 1:0] rresp_o,
    output logic        rvalid_o,
    input  logic        rready_i,
    nmi_if.master       nmi
    // verilog_format: on
);

endmodule
