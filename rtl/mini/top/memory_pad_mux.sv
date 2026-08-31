// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module memory_pad_mux (
    // verilog_format: off -- preserve the shared-pad contract columns
    input logic             [1:0] mode_i,
          psram_if.pad            controller_qpi,
          psram_if.dut            pads_qpi,
          opipsram_if.pad         controller_opi,
          opipsram_if.dut         pads_opi
    // verilog_format: on
);
  localparam logic [1:0] ModeQpi = 2'd1;
  localparam logic [1:0] ModeOpi = 2'd2;

  assign pads_qpi.sck_o         = (mode_i == ModeQpi) ? controller_qpi.sck_o : 1'b0;
  assign pads_qpi.nss_o         = (mode_i == ModeQpi) ? controller_qpi.nss_o : 4'hF;
  assign pads_qpi.io_oe_o       = (mode_i == ModeQpi) ? controller_qpi.io_oe_o : 4'd0;
  assign pads_qpi.io_do_o       = controller_qpi.io_do_o;
  assign pads_qpi.irq_o         = controller_qpi.irq_o;
  assign controller_qpi.io_di_i = pads_qpi.io_di_i;

  assign pads_opi.ck_o          = (mode_i == ModeOpi) ? controller_opi.ck_o : 1'b0;
  assign pads_opi.cs_n_o        = (mode_i == ModeOpi) ? controller_opi.cs_n_o : 1'b1;
  assign pads_opi.dq_oe_o       = (mode_i == ModeOpi) ? controller_opi.dq_oe_o : 8'd0;
  assign pads_opi.dq_o          = controller_opi.dq_o;
  assign pads_opi.rwds_oe_o     = (mode_i == ModeOpi) ? controller_opi.rwds_oe_o : 1'b0;
  assign pads_opi.rwds_o        = controller_opi.rwds_o;
  assign pads_opi.irq_o         = controller_opi.irq_o;
  assign controller_opi.dq_i    = pads_opi.dq_i;
  assign controller_opi.rwds_i  = pads_opi.rwds_i;

`ifdef HAVE_SVA
  assert property (@(*) !((|pads_qpi.io_oe_o) && (|pads_opi.dq_oe_o)));
`endif
endmodule
