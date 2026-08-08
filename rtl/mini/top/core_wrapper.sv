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
    input logic     jtag_tck_i,
    input logic     jtag_tms_i,
    input logic     jtag_tdi_i,
    input logic     jtag_trst_n_i,
    output logic    jtag_tdo_o,
    output logic    debug_halted_o,
    ribp_if.master ribp
    // verilog_format: on
);

  mgmt_core_wrapper u_mgmt_core_wrapper (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .irq_i         (irq_i),
      .jtag_tck_i    (jtag_tck_i),
      .jtag_tms_i    (jtag_tms_i),
      .jtag_tdi_i    (jtag_tdi_i),
      .jtag_trst_n_i (jtag_trst_n_i),
      .jtag_tdo_o    (jtag_tdo_o),
      .debug_halted_o(debug_halted_o),
      .ribp          (ribp)
  );

endmodule
