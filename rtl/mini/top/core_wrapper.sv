// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module core_wrapper (
    // verilog_format: off
    input logic     clk_i,
    input logic     rst_n_i,
    input logic [31:0] irq_i,
    soc_rib_if.master rib
    // verilog_format: on
);

  mgmt_core_wrapper u_mgmt_core_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .irq_i  (irq_i),
      .rib    (rib)
  );

endmodule
