// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "xpi_define.svh"

`ifdef SIMU_VERILATOR
`define APB4_XPI_CORE_MODULE xpi_core_verilator
`else
`define APB4_XPI_CORE_MODULE xpi_core
`endif

module apb4_xpi (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    input  logic  dma_xfer_done_i,
    output logic  dma_tx_stall_o,
    output logic  dma_rx_stall_o,
    output logic  irq_o,
    apb4_if.slave apb4,
    axi4_if.slave mem_axi4,
    xpi_if.dut    xpi
    // verilog_format: on
);

  import xpi_pkg::*;

  typedef enum logic [1:0] {
    OwnerNone,
    OwnerMm,
    OwnerIndirect
  } xpi_owner_e;

  logic              s_controller_en;
  logic       [31:0] s_slot_ctrl                [ 0:3];
  logic       [31:0] s_slot_size                [ 0:3];
  logic       [31:0] s_slot_seq                 [ 0:3];
  logic       [31:0] s_slot_timing              [ 0:3];
  logic       [31:0] s_slot_timeout             [ 0:3];
  logic       [31:0] s_slot_boundary            [ 0:3];
  logic       [15:0] s_lut                      [0:15] [0:7];

  logic              s_indirect_start;
  logic              s_poll_start;
  logic              s_abort;
  logic       [ 1:0] s_indirect_slot;
  logic       [ 3:0] s_indirect_seq;
  logic       [31:0] s_indirect_addr;
  logic       [15:0] s_indirect_count;
  logic       [ 1:0] s_poll_slot;
  logic       [ 3:0] s_poll_seq;
  logic       [31:0] s_poll_mask;
  logic       [31:0] s_poll_match;
  logic       [31:0] s_poll_interval;
  logic       [31:0] s_poll_timeout;
  logic              s_irq;

  logic              s_tx_fifo_push;
  logic              s_tx_fifo_pop;
  logic              s_tx_fifo_full;
  logic              s_tx_fifo_empty;
  logic       [31:0] s_tx_fifo_push_data;
  logic       [31:0] s_tx_fifo_pop_data;
  logic       [ 6:0] s_tx_fifo_count;
  logic              s_rx_fifo_push;
  logic              s_rx_fifo_pop;
  logic              s_rx_fifo_full;
  logic              s_rx_fifo_empty;
  logic       [31:0] s_rx_fifo_push_data;
  logic       [31:0] s_rx_fifo_pop_data;
  logic       [ 6:0] s_rx_fifo_count;

  logic              s_mm_busy;
  logic              s_mm_req_valid;
  logic              s_mm_req_ready;
  logic       [ 1:0] s_mm_req_slot;
  logic       [ 3:0] s_mm_req_seq;
  logic       [31:0] s_mm_req_addr;
  logic       [15:0] s_mm_req_len;
  logic              s_mm_tx_valid;
  logic              s_mm_tx_ready;
  logic       [ 7:0] s_mm_tx_data;
  logic              s_mm_rx_valid;
  logic              s_mm_rx_ready;
  logic       [ 7:0] s_mm_rx_data;
  logic              s_mm_core_done;
  logic              s_mm_core_err;
  logic              s_mm_axi_err_event;
  xpi_error_e        s_mm_err_code;
  logic       [31:0] s_mm_err_addr;
  logic       [ 1:0] s_mm_err_slot;
  logic       [ 2:0] s_mm_err_pc;
  logic              s_mm_perf_read_byte;
  logic              s_mm_perf_write_byte;
  logic              s_mm_perf_cmd;
  logic              s_mm_perf_split;
  logic              s_mm_perf_stall;

  logic              s_indirect_busy;
  logic              s_indirect_req_valid;
  logic              s_indirect_req_ready;
  logic       [ 1:0] s_indirect_req_slot;
  logic       [ 3:0] s_indirect_req_seq;
  logic       [31:0] s_indirect_req_addr;
  logic       [15:0] s_indirect_req_len;
  logic              s_indirect_tx_valid;
  logic              s_indirect_tx_ready;
  logic       [ 7:0] s_indirect_tx_data;
  logic              s_indirect_rx_valid;
  logic              s_indirect_rx_ready;
  logic       [ 7:0] s_indirect_rx_data;
  logic              s_indirect_core_done;
  logic              s_indirect_core_err;
  logic              s_indirect_done_event;
  logic              s_poll_match_event;
  logic              s_timeout_event;
  logic              s_indirect_err_event;
  logic              s_abort_done_event;
  xpi_error_e        s_indirect_err_code;
  logic       [31:0] s_indirect_err_addr;
  logic       [ 1:0] s_indirect_err_slot;
  logic       [ 2:0] s_indirect_err_pc;
  logic              s_indirect_perf_read_byte;
  logic              s_indirect_perf_write_byte;
  logic              s_indirect_perf_cmd;

  logic       [ 1:0] s_owner_bits_q;
  xpi_owner_e s_owner_d, s_owner_q;
  logic        s_selected_req_valid;
  logic        s_selected_req_ready;
  logic [ 1:0] s_selected_req_slot;
  logic [ 3:0] s_selected_req_seq;
  logic [31:0] s_selected_req_addr;
  logic [15:0] s_selected_req_len;

  logic [1:0] s_core_slot_d, s_core_slot_q;
  logic [3:0] s_core_seq_d, s_core_seq_q;
  logic [31:0] s_core_addr_d, s_core_addr_q;
  logic [15:0] s_core_len_d, s_core_len_q;
  logic s_core_mode3_d, s_core_mode3_q;
  logic [7:0] s_core_clkdiv_d, s_core_clkdiv_q;
  logic [7:0] s_core_cs_setup_d, s_core_cs_setup_q;
  logic [7:0] s_core_cs_hold_d, s_core_cs_hold_q;
  logic [7:0] s_core_cs_high_d, s_core_cs_high_q;
  logic [31:0] s_core_timeout_d, s_core_timeout_q;
  logic       [15:0] s_core_lut             [0:7];
  logic              s_core_start;
  logic              s_core_busy;
  logic              s_core_done;
  logic              s_core_err;
  xpi_error_e        s_core_err_code;
  logic       [ 2:0] s_core_err_pc;
  logic              s_core_tx_valid;
  logic              s_core_tx_ready;
  logic       [ 7:0] s_core_tx_data;
  logic              s_core_rx_valid;
  logic              s_core_rx_ready;
  logic       [ 7:0] s_core_rx_data;
  logic              s_core_phy_byte_event;

  logic              s_err_event;
  xpi_error_e        s_err_code;
  logic       [31:0] s_err_addr;
  logic       [ 1:0] s_err_slot;
  logic       [ 2:0] s_err_pc;
  logic              s_fifo_flush;
  logic              s_unused_dma_xfer_done;
  logic              s_unused_mm_perf_split;

  assign s_owner_q = xpi_owner_e'(s_owner_bits_q);
  assign s_selected_req_valid = s_mm_busy ? s_mm_req_valid :
                                (s_indirect_req_valid ? s_indirect_req_valid : s_mm_req_valid);
  assign s_selected_req_slot = s_mm_busy ? s_mm_req_slot :
                               (s_indirect_req_valid ? s_indirect_req_slot : s_mm_req_slot);
  assign s_selected_req_seq = s_mm_busy ? s_mm_req_seq :
                              (s_indirect_req_valid ? s_indirect_req_seq : s_mm_req_seq);
  assign s_selected_req_addr = s_mm_busy ? s_mm_req_addr :
                               (s_indirect_req_valid ? s_indirect_req_addr : s_mm_req_addr);
  assign s_selected_req_len = s_mm_busy ? s_mm_req_len :
                              (s_indirect_req_valid ? s_indirect_req_len : s_mm_req_len);
  assign s_selected_req_ready = (s_owner_q == OwnerNone) && !s_core_busy;
  assign s_core_start = s_selected_req_valid && s_selected_req_ready;
  assign s_mm_req_ready = s_selected_req_ready && s_mm_req_valid &&
                          (s_mm_busy || !s_indirect_req_valid);
  assign s_indirect_req_ready = s_selected_req_ready && s_indirect_req_valid && !s_mm_busy;

  always_comb begin
    s_owner_d = s_owner_q;
    if (s_core_done) begin
      s_owner_d = OwnerNone;
    end else if (s_core_start) begin
      s_owner_d = s_mm_req_ready ? OwnerMm : OwnerIndirect;
    end
  end

  always_comb begin
    s_core_slot_d     = s_core_slot_q;
    s_core_seq_d      = s_core_seq_q;
    s_core_addr_d     = s_core_addr_q;
    s_core_len_d      = s_core_len_q;
    s_core_mode3_d    = s_core_mode3_q;
    s_core_clkdiv_d   = s_core_clkdiv_q;
    s_core_cs_setup_d = s_core_cs_setup_q;
    s_core_cs_hold_d  = s_core_cs_hold_q;
    s_core_cs_high_d  = s_core_cs_high_q;
    s_core_timeout_d  = s_core_timeout_q;
    if (s_core_start) begin
      s_core_slot_d     = s_selected_req_slot;
      s_core_seq_d      = s_selected_req_seq;
      s_core_addr_d     = s_selected_req_addr;
      s_core_len_d      = s_selected_req_len;
      s_core_mode3_d    = s_slot_ctrl[s_selected_req_slot][`XPI_SLOT_CTRL_MODE3];
      s_core_clkdiv_d   = s_slot_timing[s_selected_req_slot][7:0];
      s_core_cs_setup_d = s_slot_timing[s_selected_req_slot][15:8];
      s_core_cs_hold_d  = s_slot_timing[s_selected_req_slot][23:16];
      s_core_cs_high_d  = s_slot_timing[s_selected_req_slot][31:24];
      s_core_timeout_d  = s_slot_timeout[s_selected_req_slot];
    end
  end

  for (genvar lut_index = 0; lut_index < 8; lut_index++) begin : selected_lut_block
    assign s_core_lut[lut_index] = s_lut[s_core_seq_q][lut_index];
  end

  assign s_core_tx_valid      = (s_owner_q == OwnerMm) ? s_mm_tx_valid : s_indirect_tx_valid;
  assign s_core_tx_data       = (s_owner_q == OwnerMm) ? s_mm_tx_data : s_indirect_tx_data;
  assign s_mm_tx_ready        = (s_owner_q == OwnerMm) && s_core_tx_ready;
  assign s_indirect_tx_ready  = (s_owner_q == OwnerIndirect) && s_core_tx_ready;
  assign s_mm_rx_valid        = (s_owner_q == OwnerMm) && s_core_rx_valid;
  assign s_indirect_rx_valid  = (s_owner_q == OwnerIndirect) && s_core_rx_valid;
  assign s_mm_rx_data         = s_core_rx_data;
  assign s_indirect_rx_data   = s_core_rx_data;
  assign s_core_rx_ready      = (s_owner_q == OwnerMm) ? s_mm_rx_ready : s_indirect_rx_ready;
  assign s_mm_core_done       = (s_owner_q == OwnerMm) && s_core_done;
  assign s_indirect_core_done = (s_owner_q == OwnerIndirect) && s_core_done;
  assign s_mm_core_err        = (s_owner_q == OwnerMm) && s_core_err;
  assign s_indirect_core_err  = (s_owner_q == OwnerIndirect) && s_core_err;

  assign s_err_event          = s_mm_axi_err_event || s_indirect_err_event || s_timeout_event;
  assign s_err_code           = s_mm_axi_err_event ? s_mm_err_code : s_indirect_err_code;
  assign s_err_addr           = s_mm_axi_err_event ? s_mm_err_addr : s_indirect_err_addr;
  assign s_err_slot           = s_mm_axi_err_event ? s_mm_err_slot : s_indirect_err_slot;
  assign s_err_pc             = s_mm_axi_err_event ? s_mm_err_pc : s_indirect_err_pc;
  assign irq_o                = s_irq;

  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(64)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i (s_tx_fifo_push),
      .full_o (s_tx_fifo_full),
      .dat_i  (s_tx_fifo_push_data),
      .pop_i  (s_tx_fifo_pop),
      .empty_o(s_tx_fifo_empty),
      .dat_o  (s_tx_fifo_pop_data),
      .cnt_o  (s_tx_fifo_count)
  );

  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(64)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i (s_rx_fifo_push),
      .full_o (s_rx_fifo_full),
      .dat_i  (s_rx_fifo_push_data),
      .pop_i  (s_rx_fifo_pop),
      .empty_o(s_rx_fifo_empty),
      .dat_o  (s_rx_fifo_pop_data),
      .cnt_o  (s_rx_fifo_count)
  );

  xpi_reg u_xpi_reg (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .apb4                   (apb4),
      .mm_busy_i              (s_mm_busy),
      .indirect_busy_i        (s_indirect_busy),
      .core_busy_i            (s_core_busy),
      .tx_fifo_full_i         (s_tx_fifo_full),
      .tx_fifo_empty_i        (s_tx_fifo_empty),
      .tx_fifo_count_i        (s_tx_fifo_count),
      .rx_fifo_full_i         (s_rx_fifo_full),
      .rx_fifo_empty_i        (s_rx_fifo_empty),
      .rx_fifo_count_i        (s_rx_fifo_count),
      .rx_fifo_data_i         (s_rx_fifo_pop_data),
      .indirect_done_event_i  (s_indirect_done_event),
      .poll_match_event_i     (s_poll_match_event),
      .timeout_event_i        (s_timeout_event),
      .abort_done_event_i     (s_abort_done_event),
      .error_event_i          (s_err_event),
      .error_code_i           (s_err_code),
      .error_addr_i           (s_err_addr),
      .error_slot_i           (s_err_slot),
      .error_pc_i             (s_err_pc),
      .perf_read_byte_event_i (s_mm_perf_read_byte || s_indirect_perf_read_byte),
      .perf_write_byte_event_i(s_mm_perf_write_byte || s_indirect_perf_write_byte),
      .perf_phy_byte_event_i  (s_core_phy_byte_event),
      .perf_command_event_i   (s_mm_perf_cmd || s_indirect_perf_cmd),
      .perf_stall_event_i     (s_mm_perf_stall),
      .controller_enable_o    (s_controller_en),
      .slot_ctrl_o            (s_slot_ctrl),
      .slot_size_o            (s_slot_size),
      .slot_seq_o             (s_slot_seq),
      .slot_timing_o          (s_slot_timing),
      .slot_timeout_o         (s_slot_timeout),
      .slot_boundary_o        (s_slot_boundary),
      .lut_o                  (s_lut),
      .indirect_start_o       (s_indirect_start),
      .poll_start_o           (s_poll_start),
      .abort_o                (s_abort),
      .indirect_slot_o        (s_indirect_slot),
      .indirect_seq_o         (s_indirect_seq),
      .indirect_addr_o        (s_indirect_addr),
      .indirect_count_o       (s_indirect_count),
      .poll_slot_o            (s_poll_slot),
      .poll_seq_o             (s_poll_seq),
      .poll_mask_o            (s_poll_mask),
      .poll_match_o           (s_poll_match),
      .poll_interval_o        (s_poll_interval),
      .poll_timeout_o         (s_poll_timeout),
      .tx_fifo_push_o         (s_tx_fifo_push),
      .tx_fifo_data_o         (s_tx_fifo_push_data),
      .rx_fifo_pop_o          (s_rx_fifo_pop),
      .fifo_flush_o           (s_fifo_flush),
      .dma_tx_stall_o         (dma_tx_stall_o),
      .dma_rx_stall_o         (dma_rx_stall_o),
      .irq_o                  (s_irq)
  );

  xpi_mm u_xpi_mm (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .accept_enable_i        (!s_indirect_busy),
      .controller_enable_i    (s_controller_en),
      .slot_ctrl_i            (s_slot_ctrl),
      .slot_size_i            (s_slot_size),
      .slot_seq_i             (s_slot_seq),
      .slot_boundary_i        (s_slot_boundary),
      .axi4                   (mem_axi4),
      .busy_o                 (s_mm_busy),
      .core_req_valid_o       (s_mm_req_valid),
      .core_req_ready_i       (s_mm_req_ready),
      .core_req_slot_o        (s_mm_req_slot),
      .core_req_seq_o         (s_mm_req_seq),
      .core_req_addr_o        (s_mm_req_addr),
      .core_req_len_o         (s_mm_req_len),
      .core_tx_valid_o        (s_mm_tx_valid),
      .core_tx_ready_i        (s_mm_tx_ready),
      .core_tx_data_o         (s_mm_tx_data),
      .core_rx_valid_i        (s_mm_rx_valid),
      .core_rx_ready_o        (s_mm_rx_ready),
      .core_rx_data_i         (s_mm_rx_data),
      .core_done_i            (s_mm_core_done),
      .core_error_i           (s_mm_core_err),
      .core_error_code_i      (s_core_err_code),
      .core_error_pc_i        (s_core_err_pc),
      .axi_error_event_o      (s_mm_axi_err_event),
      .error_code_o           (s_mm_err_code),
      .error_addr_o           (s_mm_err_addr),
      .error_slot_o           (s_mm_err_slot),
      .error_pc_o             (s_mm_err_pc),
      .perf_read_byte_event_o (s_mm_perf_read_byte),
      .perf_write_byte_event_o(s_mm_perf_write_byte),
      .perf_command_event_o   (s_mm_perf_cmd),
      .perf_split_event_o     (s_mm_perf_split),
      .perf_stall_event_o     (s_mm_perf_stall)
  );

  xpi_indirect u_xpi_indirect (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .indirect_start_i       (s_indirect_start),
      .poll_start_i           (s_poll_start),
      .abort_i                (s_abort),
      .indirect_slot_i        (s_indirect_slot),
      .indirect_seq_i         (s_indirect_seq),
      .indirect_addr_i        (s_indirect_addr),
      .indirect_count_i       (s_indirect_count),
      .poll_slot_i            (s_poll_slot),
      .poll_seq_i             (s_poll_seq),
      .poll_mask_i            (s_poll_mask),
      .poll_match_i           (s_poll_match),
      .poll_interval_i        (s_poll_interval),
      .poll_timeout_i         (s_poll_timeout),
      .tx_fifo_pop_o          (s_tx_fifo_pop),
      .tx_fifo_empty_i        (s_tx_fifo_empty),
      .tx_fifo_data_i         (s_tx_fifo_pop_data),
      .rx_fifo_push_o         (s_rx_fifo_push),
      .rx_fifo_full_i         (s_rx_fifo_full),
      .rx_fifo_data_o         (s_rx_fifo_push_data),
      .busy_o                 (s_indirect_busy),
      .core_req_valid_o       (s_indirect_req_valid),
      .core_req_ready_i       (s_indirect_req_ready),
      .core_req_slot_o        (s_indirect_req_slot),
      .core_req_seq_o         (s_indirect_req_seq),
      .core_req_addr_o        (s_indirect_req_addr),
      .core_req_len_o         (s_indirect_req_len),
      .core_tx_valid_o        (s_indirect_tx_valid),
      .core_tx_ready_i        (s_indirect_tx_ready),
      .core_tx_data_o         (s_indirect_tx_data),
      .core_rx_valid_i        (s_indirect_rx_valid),
      .core_rx_ready_o        (s_indirect_rx_ready),
      .core_rx_data_i         (s_indirect_rx_data),
      .core_done_i            (s_indirect_core_done),
      .core_error_i           (s_indirect_core_err),
      .core_error_code_i      (s_core_err_code),
      .core_error_pc_i        (s_core_err_pc),
      .indirect_done_event_o  (s_indirect_done_event),
      .poll_match_event_o     (s_poll_match_event),
      .timeout_event_o        (s_timeout_event),
      .error_event_o          (s_indirect_err_event),
      .abort_done_event_o     (s_abort_done_event),
      .error_code_o           (s_indirect_err_code),
      .error_addr_o           (s_indirect_err_addr),
      .error_slot_o           (s_indirect_err_slot),
      .error_pc_o             (s_indirect_err_pc),
      .perf_read_byte_event_o (s_indirect_perf_read_byte),
      .perf_write_byte_event_o(s_indirect_perf_write_byte),
      .perf_command_event_o   (s_indirect_perf_cmd)
  );

  `APB4_XPI_CORE_MODULE u_xpi_core (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (s_core_start),
      .abort_i         (s_abort),
      .slot_i          (s_core_slot_q),
      .mode3_i         (s_core_mode3_q),
      .clkdiv_i        (s_core_clkdiv_q),
      .cs_setup_i      (s_core_cs_setup_q),
      .cs_hold_i       (s_core_cs_hold_q),
      .cs_high_i       (s_core_cs_high_q),
      .timeout_i       (s_core_timeout_q),
      .address_i       (s_core_addr_q),
      .data_len_i      (s_core_len_q),
      .lut_i           (s_core_lut),
      .tx_valid_i      (s_core_tx_valid),
      .tx_ready_o      (s_core_tx_ready),
      .tx_data_i       (s_core_tx_data),
      .rx_valid_o      (s_core_rx_valid),
      .rx_ready_i      (s_core_rx_ready),
      .rx_data_o       (s_core_rx_data),
      .busy_o          (s_core_busy),
      .done_o          (s_core_done),
      .error_o         (s_core_err),
      .error_code_o    (s_core_err_code),
      .error_pc_o      (s_core_err_pc),
      .phy_byte_event_o(s_core_phy_byte_event),
      .xpi             (xpi)
  );

  dffrc #(
      .DATA_WIDTH(2),
      .RESET_VAL (OwnerNone)
  ) u_owner_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_owner_d),
      .dat_o  (s_owner_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_core_slot_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_slot_d),
      .dat_o  (s_core_slot_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_core_seq_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_seq_d),
      .dat_o  (s_core_seq_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_core_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_addr_d),
      .dat_o  (s_core_addr_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_core_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_len_d),
      .dat_o  (s_core_len_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_core_mode3_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_mode3_d),
      .dat_o  (s_core_mode3_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_core_clkdiv_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_clkdiv_d),
      .dat_o  (s_core_clkdiv_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_core_cs_setup_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_cs_setup_d),
      .dat_o  (s_core_cs_setup_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_core_cs_hold_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_cs_hold_d),
      .dat_o  (s_core_cs_hold_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_core_cs_high_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_cs_high_d),
      .dat_o  (s_core_cs_high_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_core_timeout_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_timeout_d),
      .dat_o  (s_core_timeout_q)
  );

  assign s_unused_dma_xfer_done = dma_xfer_done_i;
  assign s_unused_mm_perf_split = s_mm_perf_split;

endmodule

`undef APB4_XPI_CORE_MODULE
