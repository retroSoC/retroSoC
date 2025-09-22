// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


module user_mstr_design (
    (* keep *) input  logic        clk_i,
    (* keep *) input  logic        rst_n_i,
    (* keep *) output logic        core_valid_o,
    (* keep *) output logic [31:0] core_addr_o,
    (* keep *) output logic [31:0] core_wdata_o,
    (* keep *) output logic [ 3:0] core_wstrb_o,
    (* keep *) input  logic [31:0] core_rdata_i,
    (* keep *) input  logic        core_ready_i,
    (* keep *) input  logic [31:0] irq_i
);

  // balabala
  assign core_valid_o = '0;
  assign core_addr_o  = '0;
  assign core_wdata_o = '0;
  assign core_wstrb_o = '0;
endmodule
