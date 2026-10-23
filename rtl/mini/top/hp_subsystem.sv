// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module hp_subsystem (
    // verilog_format: off -- preserve the HP integration boundary alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        core_reset_i,
    input  logic [63:0] time_i,
    input  logic [15:0] plic_src_i,
    input  logic        jtag_tck_i,
    input  logic        jtag_tms_i,
    input  logic        jtag_tdi_i,
    input  logic        jtag_trst_n_i,
    output logic        jtag_tdo_o,
    output logic        debug_reset_req_o,
    axi4_if.master      mem_axi4,
    axi4_if.master      mmio_axi4
    // verilog_format: on
);
  hp_core_wrapper u_hp_core_wrapper (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .core_reset_i     (core_reset_i),
      .time_i           (time_i),
      .plic_src_i       (plic_src_i),
      .jtag_tck_i       (jtag_tck_i),
      .jtag_tms_i       (jtag_tms_i),
      .jtag_tdi_i       (jtag_tdi_i),
      .jtag_trst_n_i    (jtag_trst_n_i),
      .jtag_tdo_o       (jtag_tdo_o),
      .debug_reset_req_o(debug_reset_req_o),
      .mem_axi4         (mem_axi4),
      .mmio_axi4        (mmio_axi4)
  );
endmodule
