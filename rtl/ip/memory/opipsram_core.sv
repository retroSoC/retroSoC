// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module opipsram_core (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                       clk_i,
    input  logic                       rst_n_i,
    input  logic                       controller_enable_i,
    input  logic                       memory_enable_i,
    input  logic                       auto_init_i,
    input  logic                       line_buffer_i,
    input  logic                       protocol_hyper_i,
    input  logic [31:0]                device_size_i,
    input  logic [31:0]                powerup_cycles_i,
    input  logic [31:0]                timeout_cycles_i,
    input  logic [31:0]                opi_read_cmd_i,
    input  logic [31:0]                opi_write_cmd_i,
    input  logic [31:0]                opi_reg_read_cmd_i,
    input  logic [31:0]                opi_reg_write_cmd_i,
    input  logic [31:0]                opi_timing_i,
    input  logic [31:0]                hyper_timing_i,
    input  logic [31:0]                cs_timing_i,
    input  logic [31:0]                clk_config_i,
    input  logic [7:0]                 rx_delay_i,
    input  logic                       init_i,
    input  logic                       abort_i,
    input  logic                       soft_reset_i,
    input  logic                       train_i,
    input  logic                       indirect_start_i,
    input  logic                       indirect_write_i,
    input  logic                       indirect_register_i,
    input  logic [3:0]                 indirect_length_i,
    input  logic [31:0]                indirect_addr_i,
    input  logic [63:0]                indirect_wdata_i,
    input  logic                       axi_busy_i,
    input  logic                       mem_req_valid_i,
    output logic                       mem_req_ready_o,
    input  logic                       mem_req_write_i,
    input  logic [31:0]                mem_req_addr_i,
    input  logic [3:0]                 mem_req_len_i,
    input  logic [31:0]                mem_req_wdata_i,
    input  logic [3:0]                 mem_req_wstrb_i,
    output logic                       mem_rsp_valid_o,
    input  logic                       mem_rsp_ready_i,
    output logic                       mem_rsp_error_o,
    output logic [31:0]                mem_rsp_rdata_o,
    output logic                       phy_req_valid_o,
    input  logic                       phy_req_ready_i,
    output logic                       phy_req_profile_hyper_o,
    output logic                       phy_req_write_o,
    output logic                       phy_req_indirect_register_o,
    output logic [31:0]                phy_req_addr_o,
    output logic [3:0]                 phy_req_len_o,
    output logic [63:0]                phy_req_wdata_o,
    output logic [15:0]                phy_req_opi_cmd_o,
    output logic                       phy_req_opi_width16_o,
    output logic [31:0]                phy_req_opi_timing_o,
    output logic [31:0]                phy_req_hyper_timing_o,
    output logic [31:0]                phy_req_cs_timing_o,
    output logic [31:0]                phy_req_clk_config_o,
    output logic [7:0]                 phy_req_rx_delay_o,
    output logic [31:0]                phy_req_timeout_o,
    input  logic                       phy_rsp_valid_i,
    output logic                       phy_rsp_ready_o,
    input  logic                       phy_rsp_error_i,
    input  logic [63:0]                phy_rsp_rdata_i,
    output logic                       phy_abort_valid_o,
    input  logic                       phy_abort_ready_i,
    output logic                       busy_o,
    output logic                       init_busy_o,
    output logic                       indirect_busy_o,
    output logic                       quiesced_o,
    output logic                       initialized_o,
    output logic                       ready_o,
    output logic                       trained_o,
    output logic                       error_o,
    output logic                       profile_lock_o,
    output logic                       profile_hyper_o,
    output logic [31:0]                profile_status_o,
    output logic [31:0]                train_status_o,
    output logic [31:0]                train_window_o,
    output opipsram_pkg::opipsram_error_e last_error_o,
    output logic [31:0]                last_error_addr_o,
    output logic [63:0]                indirect_rdata_o,
    output logic                       init_done_event_o,
    output logic                       indirect_done_event_o,
    output logic                       train_done_event_o,
    output logic                       error_event_o,
    output logic                       timeout_event_o,
    output logic [3:0]                 perf_read_bytes_event_o,
    output logic [3:0]                 perf_write_bytes_event_o,
    output logic                       perf_command_event_o,
    output logic                       perf_cache_hit_event_o,
    output logic                       perf_error_event_o
    // verilog_format: on
);

  import opipsram_pkg::*;

  localparam logic [31:0] APERTURE_BASE = 32'h4800_0000;

  typedef enum logic [3:0] {
    CoreIdle           = 4'd0,
    CoreInit           = 4'd1,
    CoreMemIssue       = 4'd2,
    CoreMemWait        = 4'd3,
    CoreMemResponse    = 4'd4,
    CoreIndirectIssue  = 4'd5,
    CoreIndirectWait   = 4'd6,
    CoreAbortWait      = 4'd7,
    CoreFillIssueState = 4'd8,
    CoreFillWaitState  = 4'd9
  } opipsram_core_state_e;

  logic [3:0] s_state_bits_q;
  opipsram_core_state_e s_state_d, s_state_q;
  logic [31:0] s_count_d, s_count_q;
  logic s_initialized_d, s_initialized_q;
  logic s_profile_lock_d, s_profile_lock_q;
  logic s_profile_hyper_d, s_profile_hyper_q;
  logic s_trained_d, s_trained_q;
  logic s_err_d, s_err_q;
  logic s_abort_sent_d, s_abort_sent_q;
  logic s_abort_indirect_d, s_abort_indirect_q;
  logic s_soft_reset_pending_d, s_soft_reset_pending_q;
  logic s_mem_write_d, s_mem_write_q;
  logic [31:0] s_mem_addr_d, s_mem_addr_q;
  logic [3:0] s_mem_len_d, s_mem_len_q;
  logic [31:0] s_mem_wdata_d, s_mem_wdata_q;
  logic [31:0] s_mem_rsp_rdata_d, s_mem_rsp_rdata_q;
  logic s_mem_rsp_err_d, s_mem_rsp_err_q;
  logic s_indirect_write_d, s_indirect_write_q;
  logic s_indirect_register_d, s_indirect_register_q;
  logic [3:0] s_indirect_len_d, s_indirect_len_q;
  logic [31:0] s_indirect_addr_d, s_indirect_addr_q;
  logic [63:0] s_indirect_wdata_d, s_indirect_wdata_q;
  logic [63:0] s_indirect_rdata_d, s_indirect_rdata_q;
  logic [3:0] s_cache_valid_d, s_cache_valid_q;
  logic [26:0] s_cache_tag_d[4], s_cache_tag_q[4];
  logic [255:0] s_cache_data_d[4], s_cache_data_q[4];
  logic [1:0] s_fill_index_d, s_fill_index_q;
  logic [5:0] s_fill_offset_d, s_fill_offset_q;
  logic [31:0] s_fill_base_d, s_fill_base_q;
  logic [3:0] s_last_err_bits_q;
  opipsram_error_e s_last_err_d, s_last_err_q;
  logic [31:0] s_last_err_addr_d, s_last_err_addr_q;
  logic s_init_done_d, s_init_done_q;
  logic s_indirect_done_d, s_indirect_done_q;
  logic s_train_done_d, s_train_done_q;
  logic [7:0] s_train_tap_d, s_train_tap_q;
  logic s_err_evt_d, s_err_evt_q;
  logic s_timeout_evt_d, s_timeout_evt_q;
  logic [3:0] s_read_bytes_d, s_read_bytes_q;
  logic [3:0] s_write_bytes_d, s_write_bytes_q;
  logic s_cmd_evt_d, s_cmd_evt_q;
  logic s_cache_hit_d, s_cache_hit_q;
  logic s_perf_err_d, s_perf_err_q;

  logic        s_mem_req_accept;
  logic        s_phy_req_accept;
  logic        s_phy_rsp_accept;
  logic        s_abort_accept;
  logic        s_protocol_start;
  logic [31:0] s_local_addr;
  logic [31:0] s_req_local_addr;
  logic [31:0] s_req_line_base;
  logic [31:0] s_indirect_end_addr;
  logic [ 1:0] s_req_cache_index;
  logic        s_req_cache_hit;
  logic        s_req_fill_legal;
  logic        unused_mem_req_wstrb;
  logic        unused_opi_command_reserved;

  assign s_state_q    = opipsram_core_state_e'(s_state_bits_q);
  assign s_last_err_q = opipsram_error_e'(s_last_err_bits_q);

  function automatic logic [31:0] cache_word(input logic [255:0] line,
                                             input logic [4:0] byte_offset);
    return 32'(line >> (byte_offset * 8));
  endfunction

  assign s_mem_req_accept = mem_req_valid_i && mem_req_ready_o;
  assign s_phy_req_accept = phy_req_valid_o && phy_req_ready_i;
  assign s_phy_rsp_accept = phy_rsp_valid_i && phy_rsp_ready_o;
  assign s_abort_accept = phy_abort_valid_o && phy_abort_ready_i;
  assign s_local_addr = s_mem_addr_q - APERTURE_BASE;
  assign s_req_local_addr = mem_req_addr_i - APERTURE_BASE;
  assign s_req_line_base = {s_req_local_addr[31:5], 5'd0};
  assign s_indirect_end_addr = indirect_addr_i + {28'd0, indirect_length_i} - 32'd1;
  assign s_req_cache_index = s_req_line_base[6:5];
  assign s_req_cache_hit = line_buffer_i && !mem_req_write_i &&
      (s_cache_valid_q[s_req_cache_index]) &&
      (s_cache_tag_q[s_req_cache_index] == s_req_line_base[31:5]);
  assign s_req_fill_legal = line_buffer_i && !mem_req_write_i &&
      (s_req_line_base + 32'd32 <= device_size_i);
  assign s_protocol_start = init_i || (controller_enable_i && auto_init_i && !s_initialized_q);
  assign unused_mem_req_wstrb = ^mem_req_wstrb_i;
  assign unused_opi_command_reserved = ^{
    opi_read_cmd_i[31:17],
    opi_write_cmd_i[31:17],
    opi_reg_read_cmd_i[31:17],
    opi_reg_write_cmd_i[31:17]
  };

  assign busy_o = s_state_q != CoreIdle;
  assign init_busy_o = s_state_q == CoreInit;
  assign indirect_busy_o = (s_state_q == CoreIndirectIssue) || (s_state_q == CoreIndirectWait);
  assign quiesced_o = init_busy_o || indirect_busy_o;
  assign initialized_o = s_initialized_q;
  assign profile_lock_o = s_profile_lock_q;
  assign profile_hyper_o = s_profile_hyper_q;
  assign trained_o = s_trained_q;
  assign error_o = s_err_q;
  assign ready_o = controller_enable_i && memory_enable_i && s_initialized_q && !s_err_q;
  assign mem_req_ready_o = (s_state_q == CoreIdle) && !indirect_busy_o &&
      !indirect_start_i &&
      !init_i && !train_i && !soft_reset_i;
  assign mem_rsp_valid_o = s_state_q == CoreMemResponse;
  assign mem_rsp_error_o = s_mem_rsp_err_q;
  assign mem_rsp_rdata_o = s_mem_rsp_rdata_q;
  assign indirect_rdata_o = s_indirect_rdata_q;
  assign phy_rsp_ready_o = (s_state_q == CoreMemWait) ||
      (s_state_q == CoreIndirectWait) || (s_state_q == CoreAbortWait) ||
      (s_state_q == CoreFillWaitState);
  assign phy_abort_valid_o = (s_state_q == CoreAbortWait) && !s_abort_sent_q;

  assign phy_req_valid_o = (s_state_q == CoreMemIssue) ||
      (s_state_q == CoreIndirectIssue) || (s_state_q == CoreFillIssueState);
  assign phy_req_profile_hyper_o = s_profile_hyper_q;
  assign phy_req_write_o = (s_state_q == CoreMemIssue) ? s_mem_write_q :
      (s_state_q == CoreIndirectIssue ? s_indirect_write_q : 1'b0);
  assign phy_req_indirect_register_o = (s_state_q == CoreIndirectIssue) && s_indirect_register_q;
  assign phy_req_addr_o = (s_state_q == CoreMemIssue) ? s_local_addr :
      (s_state_q == CoreIndirectIssue ? s_indirect_addr_q :
       s_fill_base_q + {26'd0, s_fill_offset_q});
  assign phy_req_len_o = (s_state_q == CoreMemIssue) ? s_mem_len_q :
      (s_state_q == CoreIndirectIssue ? s_indirect_len_q : 4'd8);
  assign phy_req_wdata_o = (s_state_q == CoreMemIssue) ?
      {32'd0, s_mem_wdata_q} : (s_state_q == CoreIndirectIssue ? s_indirect_wdata_q : 64'd0);
  assign phy_req_opi_cmd_o = (s_state_q == CoreMemIssue) ?
      (s_mem_write_q ? opi_write_cmd_i[15:0] : opi_read_cmd_i[15:0]) :
      (s_state_q == CoreFillIssueState ? opi_read_cmd_i[15:0] :
      (s_indirect_write_q ?
        (s_indirect_register_q ? opi_reg_write_cmd_i[15:0] : opi_write_cmd_i[15:0]) :
        (s_indirect_register_q ? opi_reg_read_cmd_i[15:0] : opi_read_cmd_i[15:0])));
  assign phy_req_opi_width16_o = (s_state_q == CoreMemIssue) ?
      (s_mem_write_q ? opi_write_cmd_i[16] : opi_read_cmd_i[16]) :
      (s_state_q == CoreFillIssueState ? opi_read_cmd_i[16] :
      (s_indirect_write_q ? (s_indirect_register_q ? opi_reg_write_cmd_i[16] :
      opi_write_cmd_i[16]) : (s_indirect_register_q ? opi_reg_read_cmd_i[16] :
      opi_read_cmd_i[16])));
  assign phy_req_opi_timing_o = opi_timing_i;
  assign phy_req_hyper_timing_o = hyper_timing_i;
  assign phy_req_cs_timing_o = cs_timing_i;
  assign phy_req_clk_config_o = clk_config_i;
  assign phy_req_rx_delay_o = rx_delay_i;
  assign phy_req_timeout_o = timeout_cycles_i;
  assign profile_status_o = {28'd0, s_err_q, 1'b1, s_profile_lock_q, s_profile_hyper_q};
  assign train_status_o = {
    11'd0, (s_trained_q ? 5'd1 : 5'd0), 3'd0, s_train_tap_q[4:0], 6'd0, s_trained_q, 1'b0
  };
  assign train_window_o = {16'd0, s_train_tap_q, s_train_tap_q};
  assign last_error_o = s_last_err_q;
  assign last_error_addr_o = s_last_err_addr_q;
  assign init_done_event_o = s_init_done_q;
  assign indirect_done_event_o = s_indirect_done_q;
  assign train_done_event_o = s_train_done_q;
  assign error_event_o = s_err_evt_q;
  assign timeout_event_o = s_timeout_evt_q;
  assign perf_read_bytes_event_o = s_read_bytes_q;
  assign perf_write_bytes_event_o = s_write_bytes_q;
  assign perf_command_event_o = s_cmd_evt_q;
  assign perf_cache_hit_event_o = s_cache_hit_q;
  assign perf_error_event_o = s_perf_err_q;

  always_comb begin
    s_state_d              = s_state_q;
    s_count_d              = s_count_q;
    s_initialized_d        = s_initialized_q;
    s_profile_lock_d       = s_profile_lock_q;
    s_profile_hyper_d      = s_profile_hyper_q;
    s_trained_d            = s_trained_q;
    s_train_tap_d          = s_train_tap_q;
    s_err_d                = s_err_q;
    s_abort_sent_d         = s_abort_sent_q;
    s_abort_indirect_d     = s_abort_indirect_q;
    s_soft_reset_pending_d = s_soft_reset_pending_q;
    s_mem_write_d          = s_mem_write_q;
    s_mem_addr_d           = s_mem_addr_q;
    s_mem_len_d            = s_mem_len_q;
    s_mem_wdata_d          = s_mem_wdata_q;
    s_mem_rsp_rdata_d      = s_mem_rsp_rdata_q;
    s_mem_rsp_err_d        = s_mem_rsp_err_q;
    s_indirect_write_d     = s_indirect_write_q;
    s_indirect_register_d  = s_indirect_register_q;
    s_indirect_len_d       = s_indirect_len_q;
    s_indirect_addr_d      = s_indirect_addr_q;
    s_indirect_wdata_d     = s_indirect_wdata_q;
    s_indirect_rdata_d     = s_indirect_rdata_q;
    s_cache_valid_d        = s_cache_valid_q;
    s_fill_index_d         = s_fill_index_q;
    s_fill_offset_d        = s_fill_offset_q;
    s_fill_base_d          = s_fill_base_q;
    for (int cache_index = 0; cache_index < 4; cache_index++) begin
      s_cache_tag_d[cache_index]  = s_cache_tag_q[cache_index];
      s_cache_data_d[cache_index] = s_cache_data_q[cache_index];
    end
    s_last_err_d      = s_last_err_q;
    s_last_err_addr_d = s_last_err_addr_q;
    s_init_done_d     = 1'b0;
    s_indirect_done_d = 1'b0;
    s_train_done_d    = 1'b0;
    s_err_evt_d       = 1'b0;
    s_timeout_evt_d   = 1'b0;
    s_read_bytes_d    = 4'd0;
    s_write_bytes_d   = 4'd0;
    s_cmd_evt_d       = 1'b0;
    s_cache_hit_d     = 1'b0;
    s_perf_err_d      = 1'b0;

    if (init_i || soft_reset_i || abort_i || s_err_evt_q ||
        (s_profile_lock_d != s_profile_lock_q)) begin
      s_cache_valid_d = 4'd0;
    end

    if (soft_reset_i && (s_state_q == CoreIdle)) begin
      s_initialized_d  = 1'b0;
      s_profile_lock_d = 1'b0;
      s_trained_d      = 1'b0;
      s_err_d          = 1'b0;
      s_count_d        = 32'd0;
    end

    if (s_protocol_start && (s_state_q == CoreIdle) && controller_enable_i) begin
      s_profile_hyper_d = protocol_hyper_i;
      s_profile_lock_d  = 1'b1;
      s_initialized_d   = 1'b0;
      s_trained_d       = 1'b0;
      s_err_d           = 1'b0;
      s_count_d         = 32'd0;
      s_state_d         = CoreInit;
    end else if ((abort_i || soft_reset_i) &&
                 ((s_state_q == CoreMemIssue) || (s_state_q == CoreMemWait) ||
                  (s_state_q == CoreIndirectIssue) || (s_state_q == CoreIndirectWait) ||
                  (s_state_q == CoreFillIssueState) || (s_state_q == CoreFillWaitState))) begin
      s_last_err_d = OpipsramErrorAborted;
      s_last_err_addr_d = (s_state_q == CoreMemIssue || s_state_q == CoreMemWait) ?
          s_mem_addr_q : ((s_state_q == CoreIndirectIssue || s_state_q == CoreIndirectWait) ?
          s_indirect_addr_q : s_fill_base_q + {26'd0, s_fill_offset_q});
      s_err_d = 1'b1;
      s_err_evt_d = 1'b1;
      s_perf_err_d = 1'b1;
      s_abort_sent_d = 1'b0;
      s_abort_indirect_d = (s_state_q == CoreIndirectIssue) || (s_state_q == CoreIndirectWait);
      s_soft_reset_pending_d = soft_reset_i;
      if (((s_state_q == CoreMemIssue) || (s_state_q == CoreIndirectIssue) ||
           (s_state_q == CoreFillIssueState)) && !s_phy_req_accept) begin
        s_mem_rsp_err_d = 1'b1;
        s_state_d       = (s_state_q == CoreIndirectIssue) ? CoreIdle : CoreMemResponse;
        if (s_state_q == CoreIndirectIssue) s_indirect_done_d = 1'b1;
        if (soft_reset_i) begin
          s_initialized_d        = 1'b0;
          s_profile_lock_d       = 1'b0;
          s_trained_d            = 1'b0;
          s_err_d                = 1'b0;
          s_soft_reset_pending_d = 1'b0;
        end
      end else begin
        if ((s_state_q == CoreMemIssue) || (s_state_q == CoreIndirectIssue) ||
            (s_state_q == CoreFillIssueState)) begin
          s_cmd_evt_d = 1'b1;
        end
        s_state_d = CoreAbortWait;
      end
    end else begin
      unique case (s_state_q)
        CoreIdle: begin
          if (train_i && s_initialized_q) begin
            s_trained_d    = 1'b1;
            s_train_tap_d  = rx_delay_i;
            s_train_done_d = 1'b1;
          end else if (indirect_start_i && !axi_busy_i) begin
            s_indirect_write_d    = indirect_write_i;
            s_indirect_register_d = indirect_register_i;
            s_indirect_len_d      = indirect_length_i;
            s_indirect_addr_d     = indirect_addr_i;
            s_indirect_wdata_d    = indirect_wdata_i;
            if (!indirect_register_i && indirect_write_i) begin
              for (int cache_index = 0; cache_index < 4; cache_index++) begin
                if (s_cache_valid_q[cache_index] &&
                    ({s_cache_tag_q[cache_index], 5'd0} <= s_indirect_end_addr) &&
                    ({s_cache_tag_q[cache_index], 5'h1F} >= indirect_addr_i)) begin
                  s_cache_valid_d[cache_index] = 1'b0;
                end
              end
            end
            if (!indirect_register_i &&
                ((indirect_length_i == 4'd0) ||
                 ({1'b0, indirect_addr_i} + {29'd0, indirect_length_i} >
                  {1'b0, device_size_i}))) begin
              s_last_err_d      = OpipsramErrorBounds;
              s_last_err_addr_d = indirect_addr_i;
              s_indirect_done_d = 1'b1;
              s_err_evt_d       = 1'b1;
              s_perf_err_d      = 1'b1;
              s_cache_valid_d   = 4'd0;
            end else if (s_profile_hyper_q && indirect_register_i && indirect_write_i &&
                         (indirect_addr_i[0] || indirect_length_i[0])) begin
              s_last_err_d      = OpipsramErrorProtocol;
              s_last_err_addr_d = indirect_addr_i;
              s_indirect_done_d = 1'b1;
              s_err_evt_d       = 1'b1;
              s_perf_err_d      = 1'b1;
            end else if (!controller_enable_i || !memory_enable_i || !s_initialized_q) begin
              s_last_err_d      = OpipsramErrorUnavailable;
              s_last_err_addr_d = indirect_addr_i;
              s_indirect_done_d = 1'b1;
              s_err_evt_d       = 1'b1;
              s_perf_err_d      = 1'b1;
            end else begin
              s_state_d = CoreIndirectIssue;
            end
          end else if (s_mem_req_accept) begin
            s_mem_write_d     = mem_req_write_i;
            s_mem_addr_d      = mem_req_addr_i;
            s_mem_len_d       = mem_req_len_i;
            s_mem_wdata_d     = mem_req_wdata_i;
            s_mem_rsp_rdata_d = 32'd0;
            s_mem_rsp_err_d   = 1'b0;
            if (!controller_enable_i || !memory_enable_i || !s_initialized_q) begin
              s_mem_rsp_err_d   = 1'b1;
              s_last_err_d      = OpipsramErrorUnavailable;
              s_last_err_addr_d = mem_req_addr_i;
              s_err_evt_d       = 1'b1;
              s_perf_err_d      = 1'b1;
              s_cache_valid_d   = 4'd0;
              s_state_d         = CoreMemResponse;
            end else if (mem_req_addr_i < APERTURE_BASE ||
                         (mem_req_addr_i - APERTURE_BASE + {28'd0, mem_req_len_i}) >
                             device_size_i) begin
              s_mem_rsp_err_d   = 1'b1;
              s_last_err_d      = OpipsramErrorBounds;
              s_last_err_addr_d = mem_req_addr_i;
              s_err_evt_d       = 1'b1;
              s_perf_err_d      = 1'b1;
              s_cache_valid_d   = 4'd0;
              s_state_d         = CoreMemResponse;
            end else if (s_req_cache_hit) begin
              s_mem_rsp_rdata_d =
                  cache_word(s_cache_data_q[s_req_cache_index], s_req_local_addr[4:0]);
              s_cache_hit_d = 1'b1;
              s_state_d = CoreMemResponse;
            end else if (s_req_fill_legal) begin
              s_fill_index_d                     = s_req_cache_index;
              s_fill_offset_d                    = 6'd0;
              s_fill_base_d                      = s_req_line_base;
              s_cache_valid_d[s_req_cache_index] = 1'b0;
              s_cache_data_d[s_req_cache_index]  = 256'd0;
              s_state_d                          = CoreFillIssueState;
            end else begin
              if (mem_req_write_i) begin
                if (s_cache_valid_q[s_req_cache_index] &&
                    s_cache_tag_q[s_req_cache_index] == s_req_line_base[31:5]) begin
                  s_cache_valid_d[s_req_cache_index] = 1'b0;
                end
              end
              s_state_d = CoreMemIssue;
            end
          end
        end

        CoreInit: begin
          if (powerup_cycles_i == 32'd0 || s_count_q >= (powerup_cycles_i - 32'd1)) begin
            s_initialized_d = 1'b1;
            s_count_d       = 32'd0;
            s_init_done_d   = 1'b1;
            s_state_d       = CoreIdle;
          end else begin
            s_count_d = s_count_q + 32'd1;
          end
        end

        CoreMemIssue: begin
          if (s_phy_req_accept) begin
            s_cmd_evt_d = 1'b1;
            s_state_d   = CoreMemWait;
          end
        end

        opipsram_core_state_e'(CoreFillIssueState): begin
          if (s_phy_req_accept) begin
            s_cmd_evt_d = 1'b1;
            s_state_d   = CoreFillWaitState;
          end
        end

        opipsram_core_state_e'(CoreFillWaitState): begin
          if (s_phy_rsp_accept) begin
            if (phy_rsp_error_i) begin
              s_last_err_d      = OpipsramErrorTimeout;
              s_last_err_addr_d = s_fill_base_q + {26'd0, s_fill_offset_q};
              s_err_d           = 1'b1;
              s_err_evt_d       = 1'b1;
              s_timeout_evt_d   = 1'b1;
              s_perf_err_d      = 1'b1;
              s_cache_valid_d   = 4'd0;
              s_mem_rsp_err_d   = 1'b1;
              s_state_d         = CoreMemResponse;
            end else begin
              s_cache_data_d[s_fill_index_q][(s_fill_offset_q*8)+:64] = phy_rsp_rdata_i;
              if (s_fill_offset_q == 6'd24) begin
                s_cache_tag_d[s_fill_index_q] = s_fill_base_q[31:5];
                s_cache_valid_d[s_fill_index_q] = 1'b1;
                s_mem_rsp_rdata_d =
                    cache_word(s_cache_data_d[s_fill_index_q], s_req_local_addr[4:0]);
                s_state_d = CoreMemResponse;
              end else begin
                s_fill_offset_d = s_fill_offset_q + 6'd8;
                s_state_d       = CoreFillIssueState;
              end
            end
          end
        end

        CoreMemWait: begin
          if (s_phy_rsp_accept) begin
            s_mem_rsp_err_d   = phy_rsp_error_i;
            s_mem_rsp_rdata_d = phy_rsp_rdata_i[31:0];
            if (phy_rsp_error_i) begin
              s_last_err_d      = OpipsramErrorTimeout;
              s_last_err_addr_d = s_mem_addr_q;
              s_err_d           = 1'b1;
              s_err_evt_d       = 1'b1;
              s_perf_err_d      = 1'b1;
              s_timeout_evt_d   = 1'b1;
              s_cache_valid_d   = 4'd0;
            end else if (s_mem_write_q) begin
              s_write_bytes_d = s_mem_len_q;
            end else begin
              s_read_bytes_d = s_mem_len_q;
            end
            s_state_d = CoreMemResponse;
          end
        end

        CoreMemResponse: begin
          if (mem_rsp_valid_o && mem_rsp_ready_i) s_state_d = CoreIdle;
        end

        CoreIndirectIssue: begin
          if (s_phy_req_accept) begin
            s_cmd_evt_d = 1'b1;
            s_state_d   = CoreIndirectWait;
          end
        end

        CoreIndirectWait: begin
          if (s_phy_rsp_accept) begin
            s_indirect_rdata_d = phy_rsp_rdata_i;
            s_indirect_done_d  = 1'b1;
            if (phy_rsp_error_i) begin
              s_last_err_d      = OpipsramErrorTimeout;
              s_last_err_addr_d = s_indirect_addr_q;
              s_err_evt_d       = 1'b1;
              s_timeout_evt_d   = 1'b1;
              s_perf_err_d      = 1'b1;
              s_cache_valid_d   = 4'd0;
            end
            s_state_d = CoreIdle;
          end
        end

        CoreAbortWait: begin
          if (s_abort_accept) s_abort_sent_d = 1'b1;
          if (s_phy_rsp_accept) begin
            s_mem_rsp_err_d    = 1'b1;
            s_indirect_rdata_d = 64'd0;
            s_indirect_done_d  = s_abort_indirect_q;
            s_state_d          = s_abort_indirect_q ? CoreIdle : CoreMemResponse;
            s_abort_sent_d     = 1'b0;
            if (s_soft_reset_pending_q) begin
              s_initialized_d  = 1'b0;
              s_profile_lock_d = 1'b0;
              s_trained_d      = 1'b0;
              s_err_d          = 1'b0;
            end
            s_soft_reset_pending_d = 1'b0;
          end
        end

        default: s_state_d = CoreIdle;
      endcase
    end
  end

`ifndef SYNTHESIS
`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      if (s_state_q == CoreFillWaitState) assert (phy_rsp_ready_o);
      if ((s_state_q == CoreIndirectIssue) && phy_req_valid_o)
        assert (phy_req_write_o == s_indirect_write_q);
    end
  end
`endif
`endif

  dfferc #(
      .DATA_WIDTH(4),
      .RESET_VAL (CoreIdle)
  ) u_state_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_count_d),
      .dat_o  (s_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_initialized_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_initialized_d),
      .dat_o  (s_initialized_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_profile_lock_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_profile_lock_d),
      .dat_o  (s_profile_lock_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_profile_hyper_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_profile_hyper_d),
      .dat_o  (s_profile_hyper_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_trained_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_trained_d),
      .dat_o  (s_trained_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_train_tap_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_train_tap_d),
      .dat_o  (s_train_tap_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_sent_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_sent_d),
      .dat_o  (s_abort_sent_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_indirect_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_indirect_d),
      .dat_o  (s_abort_indirect_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_soft_reset_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_soft_reset_pending_d),
      .dat_o  (s_soft_reset_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_mem_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_write_d),
      .dat_o  (s_mem_write_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_mem_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_addr_d),
      .dat_o  (s_mem_addr_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_mem_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_len_d),
      .dat_o  (s_mem_len_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_mem_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_wdata_d),
      .dat_o  (s_mem_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_mem_rsp_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_rsp_rdata_d),
      .dat_o  (s_mem_rsp_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_mem_rsp_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_rsp_err_d),
      .dat_o  (s_mem_rsp_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_indirect_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_write_d),
      .dat_o  (s_indirect_write_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_indirect_register_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_register_d),
      .dat_o  (s_indirect_register_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_indirect_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_len_d),
      .dat_o  (s_indirect_len_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_indirect_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_addr_d),
      .dat_o  (s_indirect_addr_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_indirect_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_wdata_d),
      .dat_o  (s_indirect_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_indirect_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_rdata_d),
      .dat_o  (s_indirect_rdata_q)
  );
  dfferc #(
      .DATA_WIDTH(4),
      .RESET_VAL (OpipsramErrorNone)
  ) u_last_error_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_last_err_d),
      .dat_o  (s_last_err_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_last_error_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_err_addr_d),
      .dat_o  (s_last_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_init_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_done_d),
      .dat_o  (s_init_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_indirect_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_done_d),
      .dat_o  (s_indirect_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_train_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_train_done_d),
      .dat_o  (s_train_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_evt_d),
      .dat_o  (s_err_evt_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_timeout_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_evt_d),
      .dat_o  (s_timeout_evt_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_read_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_bytes_d),
      .dat_o  (s_read_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_write_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_bytes_d),
      .dat_o  (s_write_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_command_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_evt_d),
      .dat_o  (s_cmd_evt_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_cache_hit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cache_hit_d),
      .dat_o  (s_cache_hit_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_err_d),
      .dat_o  (s_perf_err_q)
  );

  dffr #(
      .DATA_WIDTH(4)
  ) u_cache_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cache_valid_d),
      .dat_o  (s_cache_valid_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_fill_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fill_index_d),
      .dat_o  (s_fill_index_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_fill_offset_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fill_offset_d),
      .dat_o  (s_fill_offset_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fill_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fill_base_d),
      .dat_o  (s_fill_base_q)
  );
  for (genvar cache_index = 0; cache_index < 4; cache_index++) begin : gen_cache_entry
    dffr #(
        .DATA_WIDTH(27)
    ) u_cache_tag_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_cache_tag_d[cache_index]),
        .dat_o  (s_cache_tag_q[cache_index])
    );
    dffr #(
        .DATA_WIDTH(256)
    ) u_cache_data_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_cache_data_d[cache_index]),
        .dat_o  (s_cache_data_q[cache_index])
    );
  end

endmodule
