// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "xpi_define.svh"

module xpi_reg (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    apb4_if.slave                   apb4,
    input  logic                    mm_busy_i,
    input  logic                    indirect_busy_i,
    input  logic                    core_busy_i,
    input  logic                    tx_fifo_full_i,
    input  logic                    tx_fifo_empty_i,
    input  logic [              6:0] tx_fifo_count_i,
    input  logic                    rx_fifo_full_i,
    input  logic                    rx_fifo_empty_i,
    input  logic [              6:0] rx_fifo_count_i,
    input  logic [             31:0] rx_fifo_data_i,
    input  logic                    indirect_done_event_i,
    input  logic                    poll_match_event_i,
    input  logic                    timeout_event_i,
    input  logic                    abort_done_event_i,
    input  logic                    error_event_i,
    input  xpi_pkg::xpi_error_e     error_code_i,
    input  logic [             31:0] error_addr_i,
    input  logic [              1:0] error_slot_i,
    input  logic [              2:0] error_pc_i,
    input  logic                    perf_read_byte_event_i,
    input  logic                    perf_write_byte_event_i,
    input  logic                    perf_phy_byte_event_i,
    input  logic                    perf_command_event_i,
    input  logic                    perf_stall_event_i,
    output logic                    controller_enable_o,
    output logic [             31:0] slot_ctrl_o [0:3],
    output logic [             31:0] slot_size_o [0:3],
    output logic [             31:0] slot_seq_o  [0:3],
    output logic [             31:0] slot_timing_o [0:3],
    output logic [             31:0] slot_timeout_o [0:3],
    output logic [             31:0] slot_boundary_o [0:3],
    output logic [             15:0] lut_o [0:15][0:7],
    output logic                    indirect_start_o,
    output logic                    poll_start_o,
    output logic                    abort_o,
    output logic [              1:0] indirect_slot_o,
    output logic [              3:0] indirect_seq_o,
    output logic [             31:0] indirect_addr_o,
    output logic [             15:0] indirect_count_o,
    output logic [              1:0] poll_slot_o,
    output logic [              3:0] poll_seq_o,
    output logic [             31:0] poll_mask_o,
    output logic [             31:0] poll_match_o,
    output logic [             31:0] poll_interval_o,
    output logic [             31:0] poll_timeout_o,
    output logic                    tx_fifo_push_o,
    output logic [             31:0] tx_fifo_data_o,
    output logic                    rx_fifo_pop_o,
    output logic                    fifo_flush_o,
    output logic                    dma_tx_stall_o,
    output logic                    dma_rx_stall_o,
    output logic                    irq_o
    // verilog_format: on
);

  import xpi_pkg::*;

  localparam logic [31:0] CTRL_MASK = 32'h0000_0001;
  localparam logic [31:0] SLOT_CTRL_MASK = 32'h0000_000F;
  localparam logic [31:0] DMA_CTRL_MASK = 32'h0000_0003;
  localparam logic [31:0] FIFO_CTRL_MASK = 32'h0003_FFFF;
  localparam logic [31:0] CONFIG_LOCK_MASK = 32'h0000_003F;

  logic        s_req;
  logic        s_write;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_busy;
  logic        s_access_err;
  logic [31:0] s_read_data;
  logic        s_ready_q;
  logic s_resp_err_d, s_resp_err_q;
  logic [31:0] s_rdata_d, s_rdata_q;

  logic       s_slot_access;
  logic [1:0] s_slot_index;
  logic [4:0] s_slot_offset;
  logic       s_lut_access;
  logic [5:0] s_lut_word_index;

  logic [31:0] s_ctrl_d, s_ctrl_q;
  logic [31:0] s_dma_ctrl_d, s_dma_ctrl_q;
  logic [31:0] s_fifo_ctrl_d, s_fifo_ctrl_q;
  logic [31:0] s_indirect_addr_d, s_indirect_addr_q;
  logic [15:0] s_indirect_count_d, s_indirect_count_q;
  logic [7:0] s_indirect_cfg_d, s_indirect_cfg_q;
  logic [7:0] s_poll_cfg_d, s_poll_cfg_q;
  logic [31:0] s_poll_mask_d, s_poll_mask_q;
  logic [31:0] s_poll_match_d, s_poll_match_q;
  logic [31:0] s_poll_interval_d, s_poll_interval_q;
  logic [31:0] s_poll_timeout_d, s_poll_timeout_q;
  logic [7:0] s_intr_state_d, s_intr_state_q;
  logic [7:0] s_intr_en_d, s_intr_en_q;
  logic [31:0] s_config_lock_d, s_config_lock_q;
  logic s_perf_en_d, s_perf_en_q;
  logic [31:0] s_perf_read_bytes_d, s_perf_read_bytes_q;
  logic [31:0] s_perf_write_bytes_d, s_perf_write_bytes_q;
  logic [31:0] s_perf_phy_bytes_d, s_perf_phy_bytes_q;
  logic [31:0] s_perf_commands_d, s_perf_commands_q;
  logic [31:0] s_perf_stall_cycles_d, s_perf_stall_cycles_q;
  logic [31:0] s_err_state_d, s_err_state_q;
  logic [31:0] s_err_addr_d, s_err_addr_q;
  logic [31:0] s_err_info_d, s_err_info_q;

  logic [ 31:0] s_slot_ctrl_d       [  0:3];
  logic [ 31:0] s_slot_ctrl_q       [  0:3];
  logic [ 31:0] s_slot_size_d       [  0:3];
  logic [ 31:0] s_slot_size_q       [  0:3];
  logic [ 31:0] s_slot_seq_d        [  0:3];
  logic [ 31:0] s_slot_seq_q        [  0:3];
  logic [ 31:0] s_slot_timing_d     [  0:3];
  logic [ 31:0] s_slot_timing_q     [  0:3];
  logic [ 31:0] s_slot_timeout_d    [  0:3];
  logic [ 31:0] s_slot_timeout_q    [  0:3];
  logic [ 31:0] s_slot_boundary_d   [  0:3];
  logic [ 31:0] s_slot_boundary_q   [  0:3];
  logic [  3:0] s_slot_ctrl_en;
  logic [  3:0] s_slot_size_en;
  logic [  3:0] s_slot_seq_en;
  logic [  3:0] s_slot_timing_en;
  logic [  3:0] s_slot_timeout_en;
  logic [  3:0] s_slot_boundary_en;

  logic [ 15:0] s_lut_d             [0:127];
  logic [ 15:0] s_lut_q             [0:127];
  logic [127:0] s_lut_en;

  logic         s_ctrl_en;
  logic         s_dma_ctrl_en;
  logic         s_fifo_ctrl_en;
  logic         s_indirect_addr_en;
  logic         s_indirect_count_en;
  logic         s_indirect_cfg_en;
  logic         s_poll_cfg_en;
  logic         s_poll_mask_en;
  logic         s_poll_match_en;
  logic         s_poll_interval_en;
  logic         s_poll_timeout_en;
  logic         s_intr_en_en;
  logic         s_config_lock_en;
  logic         s_perf_en_en;
  logic         s_perf_clear;
  logic [  7:0] s_intr_set;
  logic [  7:0] s_intr_clear;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] merged;
    begin
      merged = current;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe[byte_index]) merged[(byte_index*8)+:8] = value[(byte_index*8)+:8];
      end
      return merged;
    end
  endfunction

  function automatic logic [31:0] saturating_increment(input logic [31:0] value);
    return (&value) ? value : value + 1'b1;
  endfunction

  function automatic logic power_of_two_or_zero(input logic [31:0] value);
    return (value == 32'd0) || ((value & (value - 1'b1)) == 32'd0);
  endfunction

  assign s_req = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write = apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;
  assign s_busy = mm_busy_i || indirect_busy_i || core_busy_i;
  assign s_slot_access = (s_offset >= `APB4_XPI__SLOT_BASE) && (s_offset < 12'h180);
  assign s_slot_index = s_offset[6:5];
  assign s_slot_offset = s_offset[4:0];
  assign s_lut_access = (s_offset >= `APB4_XPI__LUT_BASE) && (s_offset <= `APB4_XPI__LUT_END);
  assign s_lut_word_index = s_offset[7:2];

  assign apb4.pready = s_ready_q;
  assign apb4.pslverr = s_resp_err_q;
  assign apb4.prdata = s_rdata_q;

  assign controller_enable_o = s_ctrl_q[`XPI_CTRL_ENABLE];
  assign slot_ctrl_o = s_slot_ctrl_q;
  assign slot_size_o = s_slot_size_q;
  assign slot_seq_o = s_slot_seq_q;
  assign slot_timing_o = s_slot_timing_q;
  assign slot_timeout_o = s_slot_timeout_q;
  assign slot_boundary_o = s_slot_boundary_q;
  assign indirect_slot_o = s_indirect_cfg_q[1:0];
  assign indirect_seq_o = s_indirect_cfg_q[7:4];
  assign indirect_addr_o = s_indirect_addr_q;
  assign indirect_count_o = s_indirect_count_q;
  assign poll_slot_o = s_poll_cfg_q[1:0];
  assign poll_seq_o = s_poll_cfg_q[7:4];
  assign poll_mask_o = s_poll_mask_q;
  assign poll_match_o = s_poll_match_q;
  assign poll_interval_o = s_poll_interval_q;
  assign poll_timeout_o = s_poll_timeout_q;
  assign dma_tx_stall_o = !s_dma_ctrl_q[0] || tx_fifo_full_i ||
                          ({1'b0, tx_fifo_count_i} >= s_fifo_ctrl_q[7:0]);
  assign dma_rx_stall_o = !s_dma_ctrl_q[1] || rx_fifo_empty_i ||
                          ({1'b0, rx_fifo_count_i} < s_fifo_ctrl_q[15:8]);
  assign irq_o = |(s_intr_state_q & s_intr_en_q);

  assign indirect_start_o = s_req && s_write && !s_access_err &&
                            (s_offset == `APB4_XPI__COMMAND) &&
                            apb4.pwdata[`XPI_COMMAND_INDIRECT_START];
  assign poll_start_o = s_req && s_write && !s_access_err &&
                        (s_offset == `APB4_XPI__COMMAND) &&
                        apb4.pwdata[`XPI_COMMAND_POLL_START];
  assign abort_o = s_req && s_write && !s_access_err &&
                   (s_offset == `APB4_XPI__COMMAND) &&
                   apb4.pwdata[`XPI_COMMAND_ABORT];
  assign tx_fifo_push_o = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__TXDATA);
  assign tx_fifo_data_o = merge_wstrb(32'd0, apb4.pwdata, apb4.pstrb);
  assign rx_fifo_pop_o = s_req && !s_write && !s_access_err && (s_offset == `APB4_XPI__RXDATA);
  assign fifo_flush_o = s_req && s_write && !s_access_err &&
                        (s_offset == `APB4_XPI__FIFO_CTRL) && (|apb4.pwdata[17:16]);

  always_comb begin
    s_access_err = !s_aligned;
    s_read_data  = '0;
    if (s_aligned) begin
      if (s_slot_access) begin
        unique case (s_slot_offset)
          5'h00: begin
            s_read_data = s_slot_ctrl_q[s_slot_index];
            s_access_err = s_write && (s_busy || controller_enable_o ||
                           s_config_lock_q[s_slot_index+1]);
          end
          5'h04: begin
            s_read_data = s_slot_size_q[s_slot_index];
            s_access_err = s_write && (s_busy || controller_enable_o ||
                           s_config_lock_q[s_slot_index+1] || (apb4.pwdata == 32'd0) ||
                           (apb4.pwdata > XPI_SLOT_SIZE));
          end
          5'h08: begin
            s_read_data = s_slot_seq_q[s_slot_index];
            s_access_err = s_write && (s_busy || controller_enable_o ||
                           s_config_lock_q[s_slot_index+1] || (|apb4.pwdata[31:8]));
          end
          5'h0C: begin
            s_read_data = s_slot_timing_q[s_slot_index];
            s_access_err = s_write && (s_busy || controller_enable_o ||
                           s_config_lock_q[s_slot_index+1]);
          end
          5'h10: begin
            s_read_data = s_slot_timeout_q[s_slot_index];
            s_access_err = s_write && (s_busy || controller_enable_o ||
                           s_config_lock_q[s_slot_index+1] || (apb4.pwdata == 32'd0));
          end
          5'h14: begin
            s_read_data = s_slot_boundary_q[s_slot_index];
            s_access_err = s_write && (s_busy || controller_enable_o ||
                           s_config_lock_q[s_slot_index+1] ||
                           !power_of_two_or_zero(apb4.pwdata) ||
                ((apb4.pwdata != 32'd0) && (apb4.pwdata < 32'd4)) || (apb4.pwdata > XPI_SLOT_SIZE));
          end
          default: s_access_err = 1'b1;
        endcase
      end else if (s_lut_access) begin
        s_read_data  = {s_lut_q[(s_lut_word_index*2)+1], s_lut_q[s_lut_word_index*2]};
        s_access_err = s_write && (s_busy || controller_enable_o || s_config_lock_q[5]);
      end else begin
        unique case (s_offset)
          `APB4_XPI__ID: begin
            s_read_data  = XPI_ID_VALUE;
            s_access_err = s_write;
          end
          `APB4_XPI__VERSION: begin
            s_read_data  = XPI_VERSION_VALUE;
            s_access_err = s_write;
          end
          `APB4_XPI__CAPABILITY: begin
            s_read_data  = XPI_CAPABILITY_VALUE;
            s_access_err = s_write;
          end
          `APB4_XPI__CTRL: begin
            s_read_data  = s_ctrl_q;
            s_access_err = s_write && s_busy;
          end
          `APB4_XPI__STATUS: begin
            s_read_data = {
              20'd0,
              rx_fifo_empty_i,
              rx_fifo_full_i,
              tx_fifo_empty_i,
              tx_fifo_full_i,
              4'd0,
              core_busy_i,
              indirect_busy_i,
              mm_busy_i,
              controller_enable_o
            };
            s_access_err = s_write;
          end
          `APB4_XPI__COMMAND: begin
            s_access_err = !s_write || !apb4.pstrb[0] || !controller_enable_o ||
                           (apb4.pwdata[2:0] == 3'd0) ||
                           (|(apb4.pwdata[2:0] & (apb4.pwdata[2:0] - 1'b1))) ||
                           ((|apb4.pwdata[1:0]) && indirect_busy_i);
          end
          `APB4_XPI__ERROR_STATE:    s_read_data = s_err_state_q;
          `APB4_XPI__ERROR_ADDR: begin
            s_read_data  = s_err_addr_q;
            s_access_err = s_write;
          end
          `APB4_XPI__ERROR_INFO: begin
            s_read_data  = s_err_info_q;
            s_access_err = s_write;
          end
          `APB4_XPI__INTR_STATE:     s_read_data = {24'd0, s_intr_state_q};
          `APB4_XPI__INTR_ENABLE:    s_read_data = {24'd0, s_intr_en_q};
          `APB4_XPI__INTR_STATUS: begin
            s_read_data  = {24'd0, s_intr_state_q & s_intr_en_q};
            s_access_err = s_write;
          end
          `APB4_XPI__INTR_TEST:      s_access_err = !s_write || !apb4.pstrb[0];
          `APB4_XPI__DMA_CTRL:       s_read_data = s_dma_ctrl_q;
          `APB4_XPI__FIFO_CTRL:      s_read_data = s_fifo_ctrl_q & 32'h0000_FFFF;
          `APB4_XPI__FIFO_STATUS: begin
            s_read_data = {
              11'd0,
              rx_fifo_count_i,
              3'd0,
              tx_fifo_count_i,
              rx_fifo_empty_i,
              rx_fifo_full_i,
              tx_fifo_empty_i,
              tx_fifo_full_i
            };
            s_access_err = s_write;
          end
          `APB4_XPI__TXDATA:         s_access_err = !s_write || tx_fifo_full_i || !(|apb4.pstrb);
          `APB4_XPI__RXDATA: begin
            s_read_data  = rx_fifo_data_i;
            s_access_err = s_write || rx_fifo_empty_i;
          end
          `APB4_XPI__INDIRECT_ADDR:  s_read_data = s_indirect_addr_q;
          `APB4_XPI__INDIRECT_COUNT: s_read_data = {16'd0, s_indirect_count_q};
          `APB4_XPI__INDIRECT_CFG:   s_read_data = {24'd0, s_indirect_cfg_q};
          `APB4_XPI__POLL_CFG:       s_read_data = {24'd0, s_poll_cfg_q};
          `APB4_XPI__POLL_MASK:      s_read_data = s_poll_mask_q;
          `APB4_XPI__POLL_MATCH:     s_read_data = s_poll_match_q;
          `APB4_XPI__POLL_INTERVAL:  s_read_data = s_poll_interval_q;
          `APB4_XPI__POLL_TIMEOUT:   s_read_data = s_poll_timeout_q;
          `APB4_XPI__PERF_CTRL:      s_read_data = {31'd0, s_perf_en_q};
          `APB4_XPI__PERF_AXI_READ_BYTES: begin
            s_read_data  = s_perf_read_bytes_q;
            s_access_err = s_write;
          end
          `APB4_XPI__PERF_AXI_WRITE_BYTES: begin
            s_read_data  = s_perf_write_bytes_q;
            s_access_err = s_write;
          end
          `APB4_XPI__PERF_PHY_BYTES: begin
            s_read_data  = s_perf_phy_bytes_q;
            s_access_err = s_write;
          end
          `APB4_XPI__PERF_COMMANDS: begin
            s_read_data  = s_perf_commands_q;
            s_access_err = s_write;
          end
          `APB4_XPI__PERF_STALL_CYCLES: begin
            s_read_data  = s_perf_stall_cycles_q;
            s_access_err = s_write;
          end
          `APB4_XPI__CONFIG_LOCK:    s_read_data = s_config_lock_q;
          default:                   s_access_err = 1'b1;
        endcase
      end
    end
  end

  assign s_ctrl_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__CTRL);
  assign s_dma_ctrl_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__DMA_CTRL);
  assign s_fifo_ctrl_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__FIFO_CTRL);
  assign s_indirect_addr_en = s_req && s_write && !s_access_err &&
                              (s_offset == `APB4_XPI__INDIRECT_ADDR);
  assign s_indirect_count_en = s_req && s_write && !s_access_err &&
                               (s_offset == `APB4_XPI__INDIRECT_COUNT);
  assign s_indirect_cfg_en = s_req && s_write && !s_access_err &&
                             (s_offset == `APB4_XPI__INDIRECT_CFG);
  assign s_poll_cfg_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__POLL_CFG);
  assign s_poll_mask_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__POLL_MASK);
  assign s_poll_match_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__POLL_MATCH);
  assign s_poll_interval_en = s_req && s_write && !s_access_err &&
                              (s_offset == `APB4_XPI__POLL_INTERVAL);
  assign s_poll_timeout_en = s_req && s_write && !s_access_err &&
                             (s_offset == `APB4_XPI__POLL_TIMEOUT);
  assign s_intr_en_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__INTR_ENABLE);
  assign s_config_lock_en = s_req && s_write && !s_access_err &&
                            (s_offset == `APB4_XPI__CONFIG_LOCK);
  assign s_perf_en_en = s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__PERF_CTRL);
  assign s_perf_clear = s_perf_en_en && apb4.pwdata[1];

  always_comb begin
    s_ctrl_d = merge_wstrb(s_ctrl_q, apb4.pwdata, apb4.pstrb) & CTRL_MASK;
    s_dma_ctrl_d = merge_wstrb(s_dma_ctrl_q, apb4.pwdata, apb4.pstrb) & DMA_CTRL_MASK;
    s_fifo_ctrl_d = merge_wstrb(s_fifo_ctrl_q, apb4.pwdata, apb4.pstrb) & FIFO_CTRL_MASK;
    s_indirect_addr_d = merge_wstrb(s_indirect_addr_q, apb4.pwdata, apb4.pstrb);
    s_indirect_count_d = 16'(merge_wstrb({16'd0, s_indirect_count_q}, apb4.pwdata, apb4.pstrb));
    s_indirect_cfg_d = 8'(merge_wstrb({24'd0, s_indirect_cfg_q}, apb4.pwdata, apb4.pstrb));
    s_poll_cfg_d = 8'(merge_wstrb({24'd0, s_poll_cfg_q}, apb4.pwdata, apb4.pstrb));
    s_poll_mask_d = merge_wstrb(s_poll_mask_q, apb4.pwdata, apb4.pstrb);
    s_poll_match_d = merge_wstrb(s_poll_match_q, apb4.pwdata, apb4.pstrb);
    s_poll_interval_d = merge_wstrb(s_poll_interval_q, apb4.pwdata, apb4.pstrb);
    s_poll_timeout_d = merge_wstrb(s_poll_timeout_q, apb4.pwdata, apb4.pstrb);
    s_intr_en_d = 8'(merge_wstrb({24'd0, s_intr_en_q}, apb4.pwdata, apb4.pstrb));
    s_config_lock_d = s_config_lock_q |
        (merge_wstrb(32'd0, apb4.pwdata, apb4.pstrb) & CONFIG_LOCK_MASK);
    s_perf_en_d = apb4.pwdata[0];
  end

  for (genvar slot_index = 0; slot_index < 4; slot_index++) begin : slot_register_block
    localparam logic [31:0] SlotCtrlReset = (slot_index == 0) ? 32'h0000_0003 : 32'd0;
    localparam logic [31:0] SlotSizeReset = (slot_index == 0) ? XPI_BOOT_SIZE : XPI_SLOT_SIZE;
    localparam logic [31:0] SlotSeqReset = 32'd0;
    localparam logic [31:0] SlotTimingReset = 32'h0200_0000;
    localparam logic [31:0] SlotTimeoutReset = 32'h0001_0000;

    assign s_slot_ctrl_en[slot_index] = s_req && s_write && !s_access_err && s_slot_access &&
                                        (s_slot_index == 2'(slot_index)) &&
                                        (s_slot_offset == 5'h00);
    assign s_slot_size_en[slot_index] = s_req && s_write && !s_access_err && s_slot_access &&
                                        (s_slot_index == 2'(slot_index)) &&
                                        (s_slot_offset == 5'h04);
    assign s_slot_seq_en[slot_index] = s_req && s_write && !s_access_err && s_slot_access &&
                                       (s_slot_index == 2'(slot_index)) &&
                                       (s_slot_offset == 5'h08);
    assign s_slot_timing_en[slot_index] = s_req && s_write && !s_access_err && s_slot_access &&
                                          (s_slot_index == 2'(slot_index)) &&
                                          (s_slot_offset == 5'h0C);
    assign s_slot_timeout_en[slot_index] = s_req && s_write && !s_access_err && s_slot_access &&
                                           (s_slot_index == 2'(slot_index)) &&
                                           (s_slot_offset == 5'h10);
    assign s_slot_boundary_en[slot_index] = s_req && s_write && !s_access_err && s_slot_access &&
                                            (s_slot_index == 2'(slot_index)) &&
                                            (s_slot_offset == 5'h14);
    assign s_slot_ctrl_d[slot_index] = merge_wstrb(
        s_slot_ctrl_q[slot_index], apb4.pwdata, apb4.pstrb
    ) & SLOT_CTRL_MASK;
    assign s_slot_size_d[slot_index] = merge_wstrb(
        s_slot_size_q[slot_index], apb4.pwdata, apb4.pstrb
    );
    assign s_slot_seq_d[slot_index] = merge_wstrb(
        s_slot_seq_q[slot_index], apb4.pwdata, apb4.pstrb
    );
    assign s_slot_timing_d[slot_index] = merge_wstrb(
        s_slot_timing_q[slot_index], apb4.pwdata, apb4.pstrb
    );
    assign s_slot_timeout_d[slot_index] = merge_wstrb(
        s_slot_timeout_q[slot_index], apb4.pwdata, apb4.pstrb
    );
    assign s_slot_boundary_d[slot_index] = merge_wstrb(
        s_slot_boundary_q[slot_index], apb4.pwdata, apb4.pstrb
    );

    dfferc #(
        .DATA_WIDTH(32),
        .RESET_VAL (SlotCtrlReset)
    ) u_slot_ctrl_dfferc (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_slot_ctrl_en[slot_index]),
        .dat_i  (s_slot_ctrl_d[slot_index]),
        .dat_o  (s_slot_ctrl_q[slot_index])
    );
    dfferc #(
        .DATA_WIDTH(32),
        .RESET_VAL (SlotSizeReset)
    ) u_slot_size_dfferc (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_slot_size_en[slot_index]),
        .dat_i  (s_slot_size_d[slot_index]),
        .dat_o  (s_slot_size_q[slot_index])
    );
    dfferc #(
        .DATA_WIDTH(32),
        .RESET_VAL (SlotSeqReset)
    ) u_slot_seq_dfferc (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_slot_seq_en[slot_index]),
        .dat_i  (s_slot_seq_d[slot_index]),
        .dat_o  (s_slot_seq_q[slot_index])
    );
    dfferc #(
        .DATA_WIDTH(32),
        .RESET_VAL (SlotTimingReset)
    ) u_slot_timing_dfferc (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_slot_timing_en[slot_index]),
        .dat_i  (s_slot_timing_d[slot_index]),
        .dat_o  (s_slot_timing_q[slot_index])
    );
    dfferc #(
        .DATA_WIDTH(32),
        .RESET_VAL (SlotTimeoutReset)
    ) u_slot_timeout_dfferc (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_slot_timeout_en[slot_index]),
        .dat_i  (s_slot_timeout_d[slot_index]),
        .dat_o  (s_slot_timeout_q[slot_index])
    );
    dffer #(
        .DATA_WIDTH(32)
    ) u_slot_boundary_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_slot_boundary_en[slot_index]),
        .dat_i  (s_slot_boundary_d[slot_index]),
        .dat_o  (s_slot_boundary_q[slot_index])
    );
  end

  for (genvar sequence_index = 0; sequence_index < 16; sequence_index++) begin : lut_sequence_block
    for (
        genvar instruction_index = 0; instruction_index < 8; instruction_index++
    ) begin : lut_instruction_block
      localparam int unsigned LutIndex = (sequence_index * 8) + instruction_index;
      localparam logic [15:0] LutReset = (LutIndex == 0) ? xpi_instr(
          XpiInstrCommand, 2'd0, 8'hEB
      ) : (LutIndex == 1) ? xpi_instr(
          XpiInstrAddress, 2'd2, 8'd24
      ) : (LutIndex == 2) ? xpi_instr(
          XpiInstrMode, 2'd2, 8'hF0
      ) : (LutIndex == 3) ? xpi_instr(
          XpiInstrDummy, 2'd0, 8'd4
      ) : (LutIndex == 4) ? xpi_instr(
          XpiInstrReceive, 2'd2, 8'd0
      ) : xpi_instr(
          XpiInstrStop, 2'd0, 8'd0
      );
      assign s_lut_en[LutIndex] = s_req && s_write && !s_access_err && s_lut_access &&
                                  (s_lut_word_index == 6'(LutIndex / 2)) &&
                                  ((LutIndex[0] && (|apb4.pstrb[3:2])) ||
                                   (!LutIndex[0] && (|apb4.pstrb[1:0])));
      assign s_lut_d[LutIndex] = LutIndex[0] ? apb4.pwdata[31:16] : apb4.pwdata[15:0];
      assign lut_o[sequence_index][instruction_index] = s_lut_q[LutIndex];
      dfferc #(
          .DATA_WIDTH(16),
          .RESET_VAL (LutReset)
      ) u_lut_dfferc (
          .clk_i  (clk_i),
          .rst_n_i(rst_n_i),
          .en_i   (s_lut_en[LutIndex]),
          .dat_i  (s_lut_d[LutIndex]),
          .dat_o  (s_lut_q[LutIndex])
      );
    end
  end

  always_comb begin
    s_intr_clear = '0;
    if (s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__INTR_STATE)) begin
      s_intr_clear = apb4.pwdata[7:0];
    end
    s_intr_set = '0;
    s_intr_set[`XPI_INTR_INDIRECT_DONE] = indirect_done_event_i;
    s_intr_set[`XPI_INTR_POLL_MATCH] = poll_match_event_i;
    s_intr_set[`XPI_INTR_TX_WATERMARK] = !tx_fifo_full_i &&
                                          ({1'b0, tx_fifo_count_i} < s_fifo_ctrl_q[7:0]);
    s_intr_set[`XPI_INTR_RX_WATERMARK] = !rx_fifo_empty_i &&
                                          ({1'b0, rx_fifo_count_i} >= s_fifo_ctrl_q[15:8]);
    s_intr_set[`XPI_INTR_AXI_ERROR] = error_event_i &&
                                      ((error_code_i == XpiErrorIllegal) ||
                                       (error_code_i == XpiErrorDisabled) ||
                                       (error_code_i == XpiErrorRange));
    s_intr_set[`XPI_INTR_SEQUENCE_ERROR] = error_event_i && (error_code_i == XpiErrorSequence);
    s_intr_set[`XPI_INTR_TIMEOUT] = timeout_event_i ||
                                    (error_event_i && (error_code_i == XpiErrorTimeout));
    s_intr_set[`XPI_INTR_ABORT_DONE] = abort_done_event_i;
    if (s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__INTR_TEST)) begin
      s_intr_set = s_intr_set | apb4.pwdata[7:0];
    end
    s_intr_state_d = (s_intr_state_q & ~s_intr_clear) | s_intr_set;
  end

  always_comb begin
    s_err_state_d = s_err_state_q;
    s_err_addr_d  = s_err_addr_q;
    s_err_info_d  = s_err_info_q;
    if (s_req && s_write && !s_access_err && (s_offset == `APB4_XPI__ERROR_STATE) &&
        apb4.pwdata[31]) begin
      s_err_state_d = '0;
      s_err_addr_d  = '0;
      s_err_info_d  = '0;
    end else if (error_event_i && !s_err_state_q[31]) begin
      s_err_state_d = {1'b1, 27'd0, error_code_i};
      s_err_addr_d  = error_addr_i;
      s_err_info_d  = {23'd0, error_pc_i, error_slot_i, error_code_i};
    end
  end

  always_comb begin
    s_perf_read_bytes_d   = s_perf_read_bytes_q;
    s_perf_write_bytes_d  = s_perf_write_bytes_q;
    s_perf_phy_bytes_d    = s_perf_phy_bytes_q;
    s_perf_commands_d     = s_perf_commands_q;
    s_perf_stall_cycles_d = s_perf_stall_cycles_q;
    if (s_perf_clear) begin
      s_perf_read_bytes_d   = '0;
      s_perf_write_bytes_d  = '0;
      s_perf_phy_bytes_d    = '0;
      s_perf_commands_d     = '0;
      s_perf_stall_cycles_d = '0;
    end else if (s_perf_en_q) begin
      if (perf_read_byte_event_i) s_perf_read_bytes_d = saturating_increment(s_perf_read_bytes_q);
      if (perf_write_byte_event_i)
        s_perf_write_bytes_d = saturating_increment(s_perf_write_bytes_q);
      if (perf_phy_byte_event_i) s_perf_phy_bytes_d = saturating_increment(s_perf_phy_bytes_q);
      if (perf_command_event_i) s_perf_commands_d = saturating_increment(s_perf_commands_q);
      if (perf_stall_event_i) s_perf_stall_cycles_d = saturating_increment(s_perf_stall_cycles_q);
    end
  end

  always_comb begin
    s_resp_err_d = s_access_err;
    s_rdata_d    = s_read_data;
  end

  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'h0000_0001)
  ) u_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_ctrl_en),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_dma_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_ctrl_en),
      .dat_i  (s_dma_ctrl_d),
      .dat_o  (s_dma_ctrl_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'h0000_1010)
  ) u_fifo_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fifo_ctrl_en),
      .dat_i  (s_fifo_ctrl_d),
      .dat_o  (s_fifo_ctrl_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_indirect_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_indirect_addr_en),
      .dat_i  (s_indirect_addr_d),
      .dat_o  (s_indirect_addr_q)
  );
  dffer #(
      .DATA_WIDTH(16)
  ) u_indirect_count_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_indirect_count_en),
      .dat_i  (s_indirect_count_d),
      .dat_o  (s_indirect_count_q)
  );
  dffer #(
      .DATA_WIDTH(8)
  ) u_indirect_cfg_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_indirect_cfg_en),
      .dat_i  (s_indirect_cfg_d),
      .dat_o  (s_indirect_cfg_q)
  );
  dffer #(
      .DATA_WIDTH(8)
  ) u_poll_cfg_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_poll_cfg_en),
      .dat_i  (s_poll_cfg_d),
      .dat_o  (s_poll_cfg_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_poll_mask_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_poll_mask_en),
      .dat_i  (s_poll_mask_d),
      .dat_o  (s_poll_mask_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_poll_match_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_poll_match_en),
      .dat_i  (s_poll_match_d),
      .dat_o  (s_poll_match_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_poll_interval_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_poll_interval_en),
      .dat_i  (s_poll_interval_d),
      .dat_o  (s_poll_interval_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'h0001_0000)
  ) u_poll_timeout_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_poll_timeout_en),
      .dat_i  (s_poll_timeout_d),
      .dat_o  (s_poll_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );
  dffer #(
      .DATA_WIDTH(8)
  ) u_intr_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_en_en),
      .dat_i  (s_intr_en_d),
      .dat_o  (s_intr_en_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_config_lock_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_config_lock_en),
      .dat_i  (s_config_lock_d),
      .dat_o  (s_config_lock_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_perf_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_en_en),
      .dat_i  (s_perf_en_d),
      .dat_o  (s_perf_en_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_read_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_read_bytes_d),
      .dat_o  (s_perf_read_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_write_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_write_bytes_d),
      .dat_o  (s_perf_write_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_phy_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_phy_bytes_d),
      .dat_o  (s_perf_phy_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_commands_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_commands_d),
      .dat_o  (s_perf_commands_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_stall_cycles_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_stall_cycles_d),
      .dat_o  (s_perf_stall_cycles_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_state_d),
      .dat_o  (s_err_state_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_addr_d),
      .dat_o  (s_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_info_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_info_d),
      .dat_o  (s_err_info_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_req),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );

endmodule
