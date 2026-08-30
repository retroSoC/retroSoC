// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module extension_subsystem (
    // verilog_format: off -- preserve the slot control/data contract columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          ext_h_data_idle_i,
           apb4_if.slave  ext_l_apb4,
           apb4_if.slave  ext_h_apb4,
           axi4_if.master ext_h_axi4,
    output logic          ext_l_irq_o,
    output logic          ext_h_irq_o,
    output logic          ext_h_block_o,
    output logic [1:0]    ext_h_owner_o,
    output logic [31:0]   ext_h_read_base_o,
    output logic [31:0]   ext_h_read_limit_o,
    output logic [31:0]   ext_h_write_base_o,
    output logic [31:0]   ext_h_write_limit_o,
    output logic [31:0]   ext_h_timeout_o
    // verilog_format: on
);
  logic        s_ext_l_idle;
  logic        s_ext_l_quiesce;
  logic        s_ext_l_reset;
  logic        s_ext_h_idle;
  logic        s_ext_h_quiesce;
  logic        s_ext_h_reset;
  logic        s_ext_h_dma_busy;
  logic        s_ext_h_dma_done;
  logic        s_ext_h_dma_err;
  logic [31:0] s_ext_h_dma_fault_addr;
  logic        s_ext_h_dma_start;
  logic        s_ext_h_dma_abort;
  logic [31:0] s_ext_h_dma_src_addr;
  logic [31:0] s_ext_h_dma_dst_addr;
  logic [31:0] s_ext_h_dma_len;
  logic [ 1:0] unused_ext_l_owner;
  logic [31:0] unused_ext_l_read_base;
  logic [31:0] unused_ext_l_read_limit;
  logic [31:0] unused_ext_l_write_base;
  logic [31:0] unused_ext_l_write_limit;
  logic [31:0] unused_ext_l_timeout;
  logic        unused_ext_l_dma_start;
  logic        unused_ext_l_dma_abort;
  logic [31:0] unused_ext_l_dma_src_addr;
  logic [31:0] unused_ext_l_dma_dst_addr;
  logic [31:0] unused_ext_l_dma_len;

  extension_slot #(
      .SlotId  (0),
      .KindExtH(1'b0),
      .IrqCount(1)
  ) u_ext_l_slot (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .data_idle_i     (1'b1),
      .dma_busy_i      (1'b0),
      .dma_done_i      (1'b0),
      .dma_err_i       (1'b0),
      .dma_fault_addr_i(32'd0),
      .cfg_apb4        (ext_l_apb4),
      .irq_o           (ext_l_irq_o),
      .idle_o          (s_ext_l_idle),
      .quiesce_o       (s_ext_l_quiesce),
      .reset_o         (s_ext_l_reset),
      .owner_o         (unused_ext_l_owner),
      .read_base_o     (unused_ext_l_read_base),
      .read_limit_o    (unused_ext_l_read_limit),
      .write_base_o    (unused_ext_l_write_base),
      .write_limit_o   (unused_ext_l_write_limit),
      .timeout_o       (unused_ext_l_timeout),
      .dma_start_o     (unused_ext_l_dma_start),
      .dma_abort_o     (unused_ext_l_dma_abort),
      .dma_src_addr_o  (unused_ext_l_dma_src_addr),
      .dma_dst_addr_o  (unused_ext_l_dma_dst_addr),
      .dma_len_o       (unused_ext_l_dma_len)
  );

  extension_slot #(
      .SlotId  (1),
      .KindExtH(1'b1),
      .IrqCount(1)
  ) u_ext_h_slot (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .data_idle_i     (ext_h_data_idle_i),
      .dma_busy_i      (s_ext_h_dma_busy),
      .dma_done_i      (s_ext_h_dma_done),
      .dma_err_i       (s_ext_h_dma_err),
      .dma_fault_addr_i(s_ext_h_dma_fault_addr),
      .cfg_apb4        (ext_h_apb4),
      .irq_o           (ext_h_irq_o),
      .idle_o          (s_ext_h_idle),
      .quiesce_o       (s_ext_h_quiesce),
      .reset_o         (s_ext_h_reset),
      .owner_o         (ext_h_owner_o),
      .read_base_o     (ext_h_read_base_o),
      .read_limit_o    (ext_h_read_limit_o),
      .write_base_o    (ext_h_write_base_o),
      .write_limit_o   (ext_h_write_limit_o),
      .timeout_o       (ext_h_timeout_o),
      .dma_start_o     (s_ext_h_dma_start),
      .dma_abort_o     (s_ext_h_dma_abort),
      .dma_src_addr_o  (s_ext_h_dma_src_addr),
      .dma_dst_addr_o  (s_ext_h_dma_dst_addr),
      .dma_len_o       (s_ext_h_dma_len)
  );

  assign ext_h_block_o = s_ext_h_quiesce || s_ext_h_reset;

  extension_dma_master u_ext_h_dma (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (s_ext_h_dma_start),
      .abort_i     (s_ext_h_dma_abort || s_ext_h_reset),
      .quiesce_i   (s_ext_h_quiesce),
      .src_addr_i  (s_ext_h_dma_src_addr),
      .dst_addr_i  (s_ext_h_dma_dst_addr),
      .len_i       (s_ext_h_dma_len),
      .timeout_i   (ext_h_timeout_o),
      .busy_o      (s_ext_h_dma_busy),
      .done_o      (s_ext_h_dma_done),
      .err_o       (s_ext_h_dma_err),
      .fault_addr_o(s_ext_h_dma_fault_addr),
      .axi4        (ext_h_axi4)
  );

  logic [16:0] s_unused_status;
  assign s_unused_status = {
    s_ext_l_idle,
    s_ext_l_quiesce,
    s_ext_l_reset,
    s_ext_h_idle,
    s_ext_h_quiesce,
    s_ext_h_reset,
    ^unused_ext_l_owner,
    ^unused_ext_l_read_base,
    ^unused_ext_l_read_limit,
    ^unused_ext_l_write_base,
    ^unused_ext_l_write_limit,
    ^unused_ext_l_timeout,
    unused_ext_l_dma_start,
    unused_ext_l_dma_abort,
    ^unused_ext_l_dma_src_addr,
    ^unused_ext_l_dma_dst_addr,
    ^unused_ext_l_dma_len
  };
endmodule
