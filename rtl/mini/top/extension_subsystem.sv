// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module extension_subsystem (
    input  logic          clk_i,
    input  logic          rst_n_i,
           apb4_if.slave  ext_l_apb4,
           apb4_if.slave  ext_h_apb4,
           axi4_if.master ext_h_axi4,
    output logic          ext_l_irq_o,
    output logic          ext_h_irq_o
);
  logic s_ext_l_idle;
  logic s_ext_l_quiesce;
  logic s_ext_l_reset;
  logic s_ext_h_idle;
  logic s_ext_h_quiesce;
  logic s_ext_h_reset;

  extension_slot #(
      .SlotId  (0),
      .KindExtH(1'b0),
      .IrqCount(1)
  ) u_ext_l_slot (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .cfg_apb4 (ext_l_apb4),
      .irq_o    (ext_l_irq_o),
      .idle_o   (s_ext_l_idle),
      .quiesce_o(s_ext_l_quiesce),
      .reset_o  (s_ext_l_reset)
  );

  extension_slot #(
      .SlotId  (1),
      .KindExtH(1'b1),
      .IrqCount(1)
  ) u_ext_h_slot (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .cfg_apb4 (ext_h_apb4),
      .irq_o    (ext_h_irq_o),
      .idle_o   (s_ext_h_idle),
      .quiesce_o(s_ext_h_quiesce),
      .reset_o  (s_ext_h_reset)
  );

  assign ext_h_axi4.awid     = '0;
  assign ext_h_axi4.awaddr   = '0;
  assign ext_h_axi4.awlen    = '0;
  assign ext_h_axi4.awsize   = '0;
  assign ext_h_axi4.awburst  = '0;
  assign ext_h_axi4.awlock   = 1'b0;
  assign ext_h_axi4.awcache  = '0;
  assign ext_h_axi4.awprot   = '0;
  assign ext_h_axi4.awqos    = '0;
  assign ext_h_axi4.awregion = '0;
  assign ext_h_axi4.awuser   = '0;
  assign ext_h_axi4.awvalid  = 1'b0;
  assign ext_h_axi4.wdata    = '0;
  assign ext_h_axi4.wstrb    = '0;
  assign ext_h_axi4.wlast    = 1'b0;
  assign ext_h_axi4.wuser    = '0;
  assign ext_h_axi4.wvalid   = 1'b0;
  assign ext_h_axi4.bready   = 1'b1;
  assign ext_h_axi4.arid     = '0;
  assign ext_h_axi4.araddr   = '0;
  assign ext_h_axi4.arlen    = '0;
  assign ext_h_axi4.arsize   = '0;
  assign ext_h_axi4.arburst  = '0;
  assign ext_h_axi4.arlock   = 1'b0;
  assign ext_h_axi4.arcache  = '0;
  assign ext_h_axi4.arprot   = '0;
  assign ext_h_axi4.arqos    = '0;
  assign ext_h_axi4.arregion = '0;
  assign ext_h_axi4.aruser   = '0;
  assign ext_h_axi4.arvalid  = 1'b0;
  assign ext_h_axi4.rready   = 1'b1;

  logic [5:0] s_unused_status;
  assign s_unused_status = {
    s_ext_l_idle, s_ext_l_quiesce, s_ext_l_reset, s_ext_h_idle, s_ext_h_quiesce, s_ext_h_reset
  };
endmodule
