// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module data_plane_fault_cdc (
    // verilog_format: off -- preserve the HP/PCLK fault-mailbox boundary columns
    input  logic        clk_hp_i,
    input  logic        rst_hp_n_i,
    input  logic        fault_valid_i,
    input  logic [ 3:0] fault_master_i,
    input  logic [ 2:0] fault_target_i,
    input  logic [31:0] fault_addr_i,
    input  logic        fault_write_i,
    input  logic [ 3:0] fault_reason_i,
    output logic        fault_ready_o,
    input  logic        clk_pclk_i,
    input  logic        rst_pclk_n_i,
    output logic        fault_valid_o,
    output logic [ 3:0] fault_master_o,
    output logic [ 2:0] fault_target_o,
    output logic [31:0] fault_addr_o,
    output logic        fault_write_o,
    output logic [ 3:0] fault_reason_o
    // verilog_format: on
);
  localparam int unsigned FaultPayloadWidth = 44;

  logic                         s_fault_mailbox_ready;
  logic                         s_fault_mailbox_valid;
  logic [FaultPayloadWidth-1:0] s_fault_mailbox_data;
  logic [FaultPayloadWidth-1:0] s_fault_payload;

  assign fault_valid_o = s_fault_mailbox_valid;
  assign fault_ready_o = s_fault_mailbox_ready;
  assign s_fault_payload = {
    fault_master_i, fault_target_i, fault_addr_i, fault_write_i, fault_reason_i
  };
  assign {fault_master_o, fault_target_o, fault_addr_o, fault_write_o, fault_reason_o} =
      s_fault_mailbox_data;

  // The HP producer holds valid and this payload until fault_ready_o accepts it.
  async_reqack #(
      .DATA_WIDTH(FaultPayloadWidth)
  ) u_fault_mailbox (
      .src_clk_i  (clk_hp_i),
      .src_rst_n_i(rst_hp_n_i),
      .src_valid_i(fault_valid_i),
      .src_ready_o(s_fault_mailbox_ready),
      .src_data_i (s_fault_payload),
      .dst_clk_i  (clk_pclk_i),
      .dst_rst_n_i(rst_pclk_n_i),
      .dst_valid_o(s_fault_mailbox_valid),
      .dst_ready_i(1'b1),
      .dst_data_o (s_fault_mailbox_data)
  );
endmodule
