// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module psram_core (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    input  logic                     controller_enable_i,
    input  logic                     memory_enable_i,
    input  logic                     auto_init_i,
    input  logic                     wrap32_i,
    input  logic [3:0]               chip_enable_i,
    input  logic [31:0]              powerup_cycles_i,
    input  logic                     init_start_i,
    input  logic                     recover_start_i,
    input  logic [1:0]               recover_chip_i,
    input  logic                     abort_i,
    input  logic [3:0]               chip_error_clear_i,
    output logic                     init_busy_o,
    output logic                     indirect_busy_o,
    output logic                     quiesced_o,
    output logic                     global_ready_o,
    output logic [3:0]               chip_present_o,
    output logic [3:0]               chip_ready_o,
    output logic [3:0]               chip_qpi_o,
    output logic [3:0]               chip_wrap32_o,
    output logic [3:0]               chip_error_o,
    output logic [47:0]              chip0_id_o,
    output logic [47:0]              chip1_id_o,
    output logic [47:0]              chip2_id_o,
    output logic [47:0]              chip3_id_o,
    output psram_pkg::psram_error_e  last_error_o,
    output logic [1:0]               last_error_chip_o,
    output logic [31:0]              last_error_addr_o,
    output logic                     init_done_event_o,
    output logic                     indirect_done_event_o,
    output logic                     error_event_o,
    output logic                     timeout_event_o,
    input  logic                     indirect_start_i,
    input  psram_pkg::psram_cmd_e    indirect_command_i,
    input  logic [1:0]               indirect_chip_i,
    input  logic [22:0]              indirect_addr_i,
    input  logic [3:0]               indirect_length_i,
    input  logic [63:0]              indirect_wdata_i,
    output logic [63:0]              indirect_rdata_o,
    input  logic                     mem_req_valid_i,
    output logic                     mem_req_ready_o,
    input  logic                     mem_req_write_i,
    input  logic [1:0]               mem_req_chip_i,
    input  logic [22:0]              mem_req_addr_i,
    input  logic [2:0]               mem_req_len_i,
    input  logic [31:0]              mem_req_wdata_i,
    output logic                     mem_rsp_valid_o,
    input  logic                     mem_rsp_ready_i,
    output logic                     mem_rsp_error_o,
    output logic [31:0]              mem_rsp_rdata_o,
    output logic [2:0]               perf_read_byte_event_o,
    output logic [2:0]               perf_write_byte_event_o,
    output logic                     perf_command_event_o,
    output logic                     perf_error_event_o,
    input  logic                     axi_busy_i,
    output logic                     phy_req_valid_o,
    input  logic                     phy_req_ready_i,
    output psram_pkg::psram_cmd_e    phy_req_command_o,
    output logic [1:0]               phy_req_chip_o,
    output logic                     phy_req_qpi_o,
    output logic [22:0]              phy_req_addr_o,
    output logic [5:0]               phy_req_length_o,
    output logic [63:0]              phy_req_wdata_o,
    input  logic                     phy_busy_i,
    input  logic                     phy_done_i,
    input  logic                     phy_error_i,
    input  logic [255:0]             phy_rdata_i
    // verilog_format: on
);

  import psram_pkg::*;

  typedef enum logic [3:0] {
    CoreIdle          = 4'd0,
    CoreInitNext      = 4'd1,
    CoreInitIssue     = 4'd2,
    CoreInitWait      = 4'd3,
    CoreMemIssue      = 4'd4,
    CoreMemWait       = 4'd5,
    CoreMemResponse   = 4'd6,
    CoreIndirectIssue = 4'd7,
    CoreIndirectWait  = 4'd8
  } psram_core_state_e;

  typedef enum logic [2:0] {
    InitQpiResetEnable = 3'd0,
    InitQpiReset       = 3'd1,
    InitSpiResetEnable = 3'd2,
    InitSpiReset       = 3'd3,
    InitReadId         = 3'd4,
    InitEnterQpi       = 3'd5,
    InitToggleWrap     = 3'd6
  } psram_init_phase_e;

  logic              [  3:0] s_state_bits_q;
  logic              [  2:0] s_init_phase_bits_q;
  psram_core_state_e         s_state_q;
  psram_init_phase_e         s_init_phase_q;
  logic              [ 31:0] s_powerup_count_q;
  logic                      s_powerup_done_q;
  logic                      s_auto_init_started_q;
  logic                      s_init_pending_q;
  logic              [  3:0] s_init_target_q;
  logic              [  1:0] s_init_chip_q;

  logic              [  3:0] s_chip_present_q;
  logic              [  3:0] s_chip_ready_q;
  logic              [  3:0] s_chip_qpi_q;
  logic              [  3:0] s_chip_wrap32_q;
  logic              [  3:0] s_chip_err_q;
  logic              [ 47:0] s_chip_id_q            [4];
  logic              [  3:0] s_last_err_bits_q;
  psram_error_e              s_last_err_q;
  logic              [  1:0] s_last_err_chip_q;
  logic              [ 31:0] s_last_err_addr_q;

  logic                      s_mem_write_q;
  logic              [  1:0] s_mem_chip_q;
  logic              [ 22:0] s_mem_addr_q;
  logic              [  2:0] s_mem_len_q;
  logic              [ 31:0] s_mem_wdata_q;
  logic                      s_mem_rsp_err_q;
  logic              [ 31:0] s_mem_rsp_rdata_q;
  logic              [  3:0] s_read_cache_valid_q;
  logic              [  1:0] s_read_cache_chip_q    [4];
  logic              [ 17:0] s_read_cache_base_q    [4];
  logic              [255:0] s_read_cache_data_q    [4];
  logic              [  1:0] s_read_cache_replace_q;
  logic              [  3:0] s_read_cache_hit;
  logic              [  1:0] s_read_cache_hit_index;

  logic                      s_indirect_pending_q;
  logic              [  3:0] s_indirect_cmd_bits_q;
  psram_cmd_e                s_indirect_cmd_q;
  logic              [  1:0] s_indirect_chip_q;
  logic              [ 22:0] s_indirect_addr_q;
  logic              [  3:0] s_indirect_len_q;
  logic              [ 63:0] s_indirect_wdata_q;
  logic              [ 63:0] s_indirect_rdata_q;

  assign s_state_q        = psram_core_state_e'(s_state_bits_q);
  assign s_init_phase_q   = psram_init_phase_e'(s_init_phase_bits_q);
  assign s_last_err_q     = psram_error_e'(s_last_err_bits_q);
  assign s_indirect_cmd_q = psram_cmd_e'(s_indirect_cmd_bits_q);

  psram_core_state_e         s_state_d;
  psram_init_phase_e         s_init_phase_d;
  logic              [ 31:0] s_powerup_count_d;
  logic                      s_powerup_done_d;
  logic                      s_auto_init_started_d;
  logic                      s_init_pending_d;
  logic              [  3:0] s_init_target_d;
  logic              [  1:0] s_init_chip_d;
  logic              [  3:0] s_chip_present_d;
  logic              [  3:0] s_chip_ready_d;
  logic              [  3:0] s_chip_qpi_d;
  logic              [  3:0] s_chip_wrap32_d;
  logic              [  3:0] s_chip_err_d;
  logic              [ 47:0] s_chip_id_d            [4];
  psram_error_e              s_last_err_d;
  logic              [  1:0] s_last_err_chip_d;
  logic              [ 31:0] s_last_err_addr_d;
  logic                      s_mem_write_d;
  logic              [  1:0] s_mem_chip_d;
  logic              [ 22:0] s_mem_addr_d;
  logic              [  2:0] s_mem_len_d;
  logic              [ 31:0] s_mem_wdata_d;
  logic                      s_mem_rsp_err_d;
  logic              [ 31:0] s_mem_rsp_rdata_d;
  logic              [  3:0] s_read_cache_valid_d;
  logic              [  1:0] s_read_cache_chip_d    [4];
  logic              [ 17:0] s_read_cache_base_d    [4];
  logic              [255:0] s_read_cache_data_d    [4];
  logic              [  1:0] s_read_cache_replace_d;
  logic                      s_indirect_pending_d;
  psram_cmd_e                s_indirect_cmd_d;
  logic              [  1:0] s_indirect_chip_d;
  logic              [ 22:0] s_indirect_addr_d;
  logic              [  3:0] s_indirect_len_d;
  logic              [ 63:0] s_indirect_wdata_d;
  logic              [ 63:0] s_indirect_rdata_d;
  logic s_init_done_event_d, s_init_done_event_q;
  logic s_indirect_done_event_d, s_indirect_done_event_q;
  logic s_err_event_d, s_err_event_q;
  logic s_timeout_event_d, s_timeout_event_q;
  logic [2:0] s_perf_read_byte_event_d, s_perf_read_byte_event_q;
  logic [2:0] s_perf_write_byte_event_d, s_perf_write_byte_event_q;
  logic s_perf_cmd_event_d, s_perf_cmd_event_q;
  logic s_perf_err_event_d, s_perf_err_event_q;

  function automatic logic indirect_is_legal(input psram_cmd_e command, input logic chip_qpi,
                                             input logic chip_enabled, input logic chip_present,
                                             input logic [3:0] length);
    logic data_command;
    begin
      data_command = psram_command_is_read(command) || psram_command_is_write(command);
      indirect_is_legal =
          chip_enabled && (length >= 4'd1) && (length <= 4'd8) &&
          (command <= PsramCmdReadId) &&
          (!data_command || chip_present) &&
          !(((command == PsramCmdRead) || (command == PsramCmdFastRead) ||
             (command == PsramCmdReadId) || (command == PsramCmdEnterQpi)) &&
            chip_qpi) &&
          !((command == PsramCmdExitQpi) && !chip_qpi);
    end
  endfunction

  assign init_busy_o = (s_state_q == CoreInitNext) || (s_state_q == CoreInitIssue) ||
                       (s_state_q == CoreInitWait);
  assign indirect_busy_o = s_indirect_pending_q ||
                           (s_state_q == CoreIndirectIssue) ||
                           (s_state_q == CoreIndirectWait);
  assign quiesced_o = init_busy_o || indirect_busy_o;
  assign global_ready_o = controller_enable_i && memory_enable_i && (|s_chip_ready_q);
  assign chip_present_o = s_chip_present_q;
  assign chip_ready_o = s_chip_ready_q;
  assign chip_qpi_o = s_chip_qpi_q;
  assign chip_wrap32_o = s_chip_wrap32_q;
  assign chip_error_o = s_chip_err_q;
  assign chip0_id_o = s_chip_id_q[0];
  assign chip1_id_o = s_chip_id_q[1];
  assign chip2_id_o = s_chip_id_q[2];
  assign chip3_id_o = s_chip_id_q[3];
  assign last_error_o = s_last_err_q;
  assign last_error_chip_o = s_last_err_chip_q;
  assign last_error_addr_o = s_last_err_addr_q;
  assign indirect_rdata_o = s_indirect_rdata_q;

  assign mem_req_ready_o = (s_state_q == CoreIdle) &&
                           (!s_indirect_pending_q || axi_busy_i) &&
                           !init_start_i && !recover_start_i;
  assign mem_rsp_valid_o = s_state_q == CoreMemResponse;
  assign mem_rsp_error_o = s_mem_rsp_err_q;
  assign mem_rsp_rdata_o = s_mem_rsp_rdata_q;

  always_comb begin
    for (int cache_index = 0; cache_index < 4; cache_index++) begin
      s_read_cache_hit[cache_index] =
          s_read_cache_valid_q[cache_index] &&
          (s_read_cache_chip_q[cache_index] == mem_req_chip_i) &&
          (s_read_cache_base_q[cache_index] == mem_req_addr_i[22:5]);
    end
    unique casez (s_read_cache_hit)
      4'b???1: s_read_cache_hit_index = 2'd0;
      4'b??10: s_read_cache_hit_index = 2'd1;
      4'b?100: s_read_cache_hit_index = 2'd2;
      default: s_read_cache_hit_index = 2'd3;
    endcase
  end

  always_comb begin
    phy_req_valid_o   = 1'b0;
    phy_req_command_o = PsramCmdRead;
    phy_req_chip_o    = '0;
    phy_req_qpi_o     = 1'b0;
    phy_req_addr_o    = '0;
    phy_req_length_o  = 6'd1;
    phy_req_wdata_o   = '0;
    unique case (s_state_q)
      CoreInitIssue: begin
        phy_req_valid_o = 1'b1;
        phy_req_chip_o  = s_init_chip_q;
        unique case (s_init_phase_q)
          InitQpiResetEnable: begin
            phy_req_command_o = PsramCmdResetEnable;
            phy_req_qpi_o     = 1'b1;
          end
          InitQpiReset: begin
            phy_req_command_o = PsramCmdReset;
            phy_req_qpi_o     = 1'b1;
          end
          InitSpiResetEnable: phy_req_command_o = PsramCmdResetEnable;
          InitSpiReset:       phy_req_command_o = PsramCmdReset;
          InitReadId: begin
            phy_req_command_o = PsramCmdReadId;
            phy_req_length_o  = 6'd6;
          end
          InitEnterQpi:       phy_req_command_o = PsramCmdEnterQpi;
          default: begin
            phy_req_command_o = PsramCmdToggleWrap;
            phy_req_qpi_o     = 1'b1;
          end
        endcase
      end
      CoreMemIssue: begin
        phy_req_valid_o   = 1'b1;
        phy_req_command_o = s_mem_write_q ? PsramCmdQuadWrite : PsramCmdQuadRead;
        phy_req_chip_o    = s_mem_chip_q;
        phy_req_qpi_o     = 1'b1;
        phy_req_addr_o    = s_mem_write_q ? s_mem_addr_q : {s_mem_addr_q[22:5], 5'd0};
        phy_req_length_o  = s_mem_write_q ? {3'd0, s_mem_len_q} : 6'd32;
        phy_req_wdata_o   = {32'd0, s_mem_wdata_q};
      end
      CoreIndirectIssue: begin
        phy_req_valid_o   = 1'b1;
        phy_req_command_o = s_indirect_cmd_q;
        phy_req_chip_o    = s_indirect_chip_q;
        phy_req_qpi_o     = s_chip_qpi_q[s_indirect_chip_q];
        phy_req_addr_o    = s_indirect_addr_q;
        phy_req_length_o  = {2'd0, s_indirect_len_q};
        phy_req_wdata_o   = s_indirect_wdata_q;
      end
      default: begin
      end
    endcase
  end

  always_comb begin
    s_state_d                 = s_state_q;
    s_init_phase_d            = s_init_phase_q;
    s_powerup_count_d         = s_powerup_count_q;
    s_powerup_done_d          = s_powerup_done_q;
    s_auto_init_started_d     = s_auto_init_started_q;
    s_init_pending_d          = s_init_pending_q;
    s_init_target_d           = s_init_target_q;
    s_init_chip_d             = s_init_chip_q;
    s_chip_present_d          = s_chip_present_q;
    s_chip_ready_d            = s_chip_ready_q;
    s_chip_qpi_d              = s_chip_qpi_q;
    s_chip_wrap32_d           = s_chip_wrap32_q;
    s_chip_err_d              = s_chip_err_q;
    s_last_err_d              = s_last_err_q;
    s_last_err_chip_d         = s_last_err_chip_q;
    s_last_err_addr_d         = s_last_err_addr_q;
    s_mem_write_d             = s_mem_write_q;
    s_mem_chip_d              = s_mem_chip_q;
    s_mem_addr_d              = s_mem_addr_q;
    s_mem_len_d               = s_mem_len_q;
    s_mem_wdata_d             = s_mem_wdata_q;
    s_mem_rsp_err_d           = s_mem_rsp_err_q;
    s_mem_rsp_rdata_d         = s_mem_rsp_rdata_q;
    s_read_cache_valid_d      = s_read_cache_valid_q;
    s_read_cache_replace_d    = s_read_cache_replace_q;
    s_indirect_pending_d      = s_indirect_pending_q;
    s_indirect_cmd_d          = s_indirect_cmd_q;
    s_indirect_chip_d         = s_indirect_chip_q;
    s_indirect_addr_d         = s_indirect_addr_q;
    s_indirect_len_d          = s_indirect_len_q;
    s_indirect_wdata_d        = s_indirect_wdata_q;
    s_indirect_rdata_d        = s_indirect_rdata_q;
    s_init_done_event_d       = 1'b0;
    s_indirect_done_event_d   = 1'b0;
    s_err_event_d             = 1'b0;
    s_timeout_event_d         = 1'b0;
    s_perf_read_byte_event_d  = '0;
    s_perf_write_byte_event_d = '0;
    s_perf_cmd_event_d        = 1'b0;
    s_perf_err_event_d        = 1'b0;
    for (int chip_index = 0; chip_index < 4; chip_index++) begin
      s_chip_id_d[chip_index] = s_chip_id_q[chip_index];
    end
    for (int cache_index = 0; cache_index < 4; cache_index++) begin
      s_read_cache_chip_d[cache_index] = s_read_cache_chip_q[cache_index];
      s_read_cache_base_d[cache_index] = s_read_cache_base_q[cache_index];
      s_read_cache_data_d[cache_index] = s_read_cache_data_q[cache_index];
    end
    s_init_done_event_d       = 1'b0;
    s_indirect_done_event_d   = 1'b0;
    s_err_event_d             = 1'b0;
    s_timeout_event_d         = 1'b0;
    s_perf_read_byte_event_d  = '0;
    s_perf_write_byte_event_d = '0;
    s_perf_cmd_event_d        = 1'b0;
    s_perf_err_event_d        = 1'b0;
    s_chip_err_d              = s_chip_err_q & ~chip_error_clear_i;

    if (!s_powerup_done_q) begin
      if (s_powerup_count_q >= powerup_cycles_i) begin
        s_powerup_done_d = 1'b1;
      end else begin
        s_powerup_count_d = s_powerup_count_q + 1'b1;
      end
    end

    if (indirect_start_i && !s_indirect_pending_q && !indirect_busy_o) begin
      s_indirect_pending_d = 1'b1;
      s_indirect_cmd_d     = indirect_command_i;
      s_indirect_chip_d    = indirect_chip_i;
      s_indirect_addr_d    = indirect_addr_i;
      s_indirect_len_d     = indirect_length_i;
      s_indirect_wdata_d   = indirect_wdata_i;
    end

    if (init_start_i) begin
      s_init_pending_d = 1'b1;
    end
    if (init_start_i || recover_start_i || abort_i || indirect_start_i) begin
      s_read_cache_valid_d = '0;
    end
    if (abort_i && (s_state_q == CoreIdle)) begin
      s_init_pending_d = 1'b0;
    end

    if ((s_state_q == CoreInitIssue) || (s_state_q == CoreMemIssue) ||
          (s_state_q == CoreIndirectIssue)) begin
      if (phy_req_valid_o && phy_req_ready_i) begin
        s_perf_cmd_event_d = 1'b1;
      end
    end

    if (abort_i && (s_state_q != CoreIdle)) begin
      s_last_err_d       = PsramErrorAborted;
      s_err_event_d      = 1'b1;
      s_perf_err_event_d = 1'b1;
      if ((s_state_q == CoreMemIssue) || (s_state_q == CoreMemWait)) begin
        s_mem_rsp_err_d = 1'b1;
        s_state_d       = CoreMemResponse;
      end else begin
        if ((s_state_q == CoreIndirectIssue) || (s_state_q == CoreIndirectWait)) begin
          s_indirect_pending_d    = 1'b0;
          s_indirect_done_event_d = 1'b1;
        end
        s_state_d = CoreIdle;
      end
    end else begin
      unique case (s_state_q)
        CoreIdle: begin
          if (!abort_i &&
                ((s_init_pending_q && s_powerup_done_q) || recover_start_i ||
                 (controller_enable_i && auto_init_i && s_powerup_done_q &&
                  !s_auto_init_started_q))) begin
            s_init_target_d  = recover_start_i ? (4'b0001 << recover_chip_i) : chip_enable_i;
            s_init_chip_d    = '0;
            s_init_phase_d   = InitQpiResetEnable;
            s_init_pending_d = 1'b0;
            if (!recover_start_i) begin
              s_chip_present_d = '0;
              s_chip_ready_d   = '0;
              s_chip_qpi_d     = '0;
              s_chip_wrap32_d  = '0;
              s_chip_err_d     = '0;
            end else begin
              s_chip_present_d[recover_chip_i] = 1'b0;
              s_chip_ready_d[recover_chip_i]   = 1'b0;
              s_chip_qpi_d[recover_chip_i]     = 1'b0;
              s_chip_wrap32_d[recover_chip_i]  = 1'b0;
              s_chip_err_d[recover_chip_i]     = 1'b0;
            end
            s_auto_init_started_d = s_auto_init_started_q || (!init_start_i && !recover_start_i);
            s_state_d             = CoreInitNext;
          end else if (s_indirect_pending_q && !axi_busy_i) begin
            if (!controller_enable_i || !indirect_is_legal(
                    s_indirect_cmd_q,
                    s_chip_qpi_q[s_indirect_chip_q],
                    chip_enable_i[s_indirect_chip_q],
                    s_chip_present_q[s_indirect_chip_q],
                    s_indirect_len_q
                )) begin
              s_last_err_d            = PsramErrorIllegal;
              s_last_err_chip_d       = s_indirect_chip_q;
              s_last_err_addr_d       = {9'd0, s_indirect_addr_q};
              s_indirect_pending_d    = 1'b0;
              s_indirect_done_event_d = 1'b1;
              s_err_event_d           = 1'b1;
              s_perf_err_event_d      = 1'b1;
            end else begin
              s_state_d = CoreIndirectIssue;
            end
          end else if (mem_req_valid_i && mem_req_ready_o) begin
            s_mem_write_d     = mem_req_write_i;
            s_mem_chip_d      = mem_req_chip_i;
            s_mem_addr_d      = mem_req_addr_i;
            s_mem_len_d       = mem_req_len_i;
            s_mem_wdata_d     = mem_req_wdata_i;
            s_mem_rsp_err_d   = 1'b0;
            s_mem_rsp_rdata_d = '0;
            if (!controller_enable_i || !memory_enable_i || !s_chip_ready_q[mem_req_chip_i]) begin
              s_mem_rsp_err_d              = 1'b1;
              s_last_err_d                 = PsramErrorUnavailable;
              s_last_err_chip_d            = mem_req_chip_i;
              s_last_err_addr_d            = {7'd0, mem_req_chip_i, mem_req_addr_i};
              s_chip_err_d[mem_req_chip_i] = 1'b1;
              s_err_event_d                = 1'b1;
              s_perf_err_event_d           = 1'b1;
              s_state_d                    = CoreMemResponse;
            end else if (!mem_req_write_i && (|s_read_cache_hit)) begin
              s_mem_rsp_rdata_d = 32'(s_read_cache_data_q[s_read_cache_hit_index] >>
                                         (mem_req_addr_i[4:0] * 8));
              s_perf_read_byte_event_d = mem_req_len_i;
              s_state_d = CoreMemResponse;
            end else begin
              if (mem_req_write_i) begin
                for (int cache_index = 0; cache_index < 4; cache_index++) begin
                  if (s_read_cache_valid_q[cache_index] &&
                        (s_read_cache_chip_q[cache_index] == mem_req_chip_i) &&
                        (s_read_cache_base_q[cache_index] == mem_req_addr_i[22:5])) begin
                    s_read_cache_valid_d[cache_index] = 1'b0;
                  end
                end
              end
              s_state_d = CoreMemIssue;
            end
          end
        end

        CoreInitNext: begin
          if (s_init_target_q[s_init_chip_q]) begin
            s_init_phase_d = InitQpiResetEnable;
            s_state_d      = CoreInitIssue;
          end else if (s_init_chip_q == 2'd3) begin
            s_init_done_event_d = 1'b1;
            s_state_d           = CoreIdle;
          end else begin
            s_init_chip_d = s_init_chip_q + 1'b1;
          end
        end

        CoreInitIssue: begin
          if (phy_req_valid_o && phy_req_ready_i) begin
            s_state_d = CoreInitWait;
          end
        end

        CoreInitWait: begin
          if (phy_done_i) begin
            if (phy_error_i) begin
              s_chip_err_d[s_init_chip_q]   = 1'b1;
              s_chip_ready_d[s_init_chip_q] = 1'b0;
              s_last_err_d                  = PsramErrorTimeout;
              s_last_err_chip_d             = s_init_chip_q;
              s_last_err_addr_d             = {7'd0, s_init_chip_q, 23'd0};
              s_err_event_d                 = 1'b1;
              s_timeout_event_d             = 1'b1;
              s_perf_err_event_d            = 1'b1;
              if (s_init_chip_q == 2'd3) begin
                s_init_done_event_d = 1'b1;
                s_state_d           = CoreIdle;
              end else begin
                s_init_chip_d = s_init_chip_q + 1'b1;
                s_state_d     = CoreInitNext;
              end
            end else if (s_init_phase_q == InitReadId) begin
              s_chip_id_d[s_init_chip_q] = phy_rdata_i[47:0];
              if ((phy_rdata_i[15:8] !== PSRAM_KGD_PASS) ||
                    (phy_rdata_i[23:16] !== PSRAM_DENSITY_64MBIT)) begin
                s_chip_err_d[s_init_chip_q]   = 1'b1;
                s_chip_ready_d[s_init_chip_q] = 1'b0;
                s_last_err_d                  = PsramErrorId;
                s_last_err_chip_d             = s_init_chip_q;
                s_last_err_addr_d             = {7'd0, s_init_chip_q, 23'd0};
                s_err_event_d                 = 1'b1;
                s_perf_err_event_d            = 1'b1;
                if (s_init_chip_q == 2'd3) begin
                  s_init_done_event_d = 1'b1;
                  s_state_d           = CoreIdle;
                end else begin
                  s_init_chip_d = s_init_chip_q + 1'b1;
                  s_state_d     = CoreInitNext;
                end
              end else begin
                s_chip_present_d[s_init_chip_q] = 1'b1;
                s_init_phase_d                  = InitEnterQpi;
                s_state_d                       = CoreInitIssue;
              end
            end else if (s_init_phase_q == InitEnterQpi) begin
              s_chip_qpi_d[s_init_chip_q] = 1'b1;
              if (wrap32_i) begin
                s_init_phase_d = InitToggleWrap;
                s_state_d      = CoreInitIssue;
              end else begin
                s_chip_ready_d[s_init_chip_q] = 1'b1;
                if (s_init_chip_q == 2'd3) begin
                  s_init_done_event_d = 1'b1;
                  s_state_d           = CoreIdle;
                end else begin
                  s_init_chip_d = s_init_chip_q + 1'b1;
                  s_state_d     = CoreInitNext;
                end
              end
            end else if (s_init_phase_q == InitToggleWrap) begin
              s_chip_wrap32_d[s_init_chip_q] = 1'b1;
              s_chip_ready_d[s_init_chip_q]  = 1'b1;
              if (s_init_chip_q == 2'd3) begin
                s_init_done_event_d = 1'b1;
                s_state_d           = CoreIdle;
              end else begin
                s_init_chip_d = s_init_chip_q + 1'b1;
                s_state_d     = CoreInitNext;
              end
            end else begin
              s_init_phase_d = psram_init_phase_e'(s_init_phase_q + 1'b1);
              s_state_d      = CoreInitIssue;
            end
          end
        end

        CoreMemIssue: begin
          if (phy_req_valid_o && phy_req_ready_i) begin
            s_state_d = CoreMemWait;
          end
        end

        CoreMemWait: begin
          if (phy_done_i) begin
            s_mem_rsp_err_d = phy_error_i;
            s_mem_rsp_rdata_d = s_mem_write_q ? 32'd0 : 32'(phy_rdata_i >> (s_mem_addr_q[4:0] * 8));
            if (phy_error_i) begin
              s_chip_err_d[s_mem_chip_q]   = 1'b1;
              s_chip_ready_d[s_mem_chip_q] = 1'b0;
              s_last_err_d                 = PsramErrorTimeout;
              s_last_err_chip_d            = s_mem_chip_q;
              s_last_err_addr_d            = {7'd0, s_mem_chip_q, s_mem_addr_q};
              s_err_event_d                = 1'b1;
              s_timeout_event_d            = 1'b1;
              s_perf_err_event_d           = 1'b1;
            end else if (s_mem_write_q) begin
              s_perf_write_byte_event_d = s_mem_len_q;
            end else begin
              s_read_cache_valid_d[s_read_cache_replace_q] = 1'b1;
              s_read_cache_chip_d[s_read_cache_replace_q]  = s_mem_chip_q;
              s_read_cache_base_d[s_read_cache_replace_q]  = s_mem_addr_q[22:5];
              s_read_cache_data_d[s_read_cache_replace_q]  = phy_rdata_i;
              s_read_cache_replace_d                       = s_read_cache_replace_q + 1'b1;
              s_perf_read_byte_event_d                     = s_mem_len_q;
            end
            s_state_d = CoreMemResponse;
          end
        end

        CoreMemResponse: begin
          if (mem_rsp_valid_o && mem_rsp_ready_i) begin
            s_state_d = CoreIdle;
          end
        end

        CoreIndirectIssue: begin
          if (phy_req_valid_o && phy_req_ready_i) begin
            s_state_d = CoreIndirectWait;
          end
        end

        CoreIndirectWait: begin
          if (phy_done_i) begin
            s_indirect_pending_d    = 1'b0;
            s_indirect_rdata_d      = phy_rdata_i[63:0];
            s_indirect_done_event_d = 1'b1;
            if (phy_error_i) begin
              s_chip_err_d[s_indirect_chip_q]   = 1'b1;
              s_chip_ready_d[s_indirect_chip_q] = 1'b0;
              s_last_err_d                      = PsramErrorTimeout;
              s_last_err_chip_d                 = s_indirect_chip_q;
              s_last_err_addr_d                 = {7'd0, s_indirect_chip_q, s_indirect_addr_q};
              s_err_event_d                     = 1'b1;
              s_timeout_event_d                 = 1'b1;
              s_perf_err_event_d                = 1'b1;
            end else begin
              unique case (s_indirect_cmd_q)
                PsramCmdEnterQpi: begin
                  s_chip_qpi_d[s_indirect_chip_q]   = 1'b1;
                  s_chip_ready_d[s_indirect_chip_q] = 1'b1;
                end
                PsramCmdExitQpi: begin
                  s_chip_qpi_d[s_indirect_chip_q]   = 1'b0;
                  s_chip_ready_d[s_indirect_chip_q] = 1'b0;
                end
                PsramCmdReset: begin
                  s_chip_qpi_d[s_indirect_chip_q]    = 1'b0;
                  s_chip_wrap32_d[s_indirect_chip_q] = 1'b0;
                  s_chip_ready_d[s_indirect_chip_q]  = 1'b0;
                end
                PsramCmdToggleWrap: begin
                  s_chip_wrap32_d[s_indirect_chip_q] = ~s_chip_wrap32_q[s_indirect_chip_q];
                end
                PsramCmdReadId: begin
                  s_chip_id_d[s_indirect_chip_q] = phy_rdata_i[47:0];
                end
                default: begin
                end
              endcase
            end
            s_state_d = CoreIdle;
          end
        end

        default: s_state_d = CoreIdle;
      endcase
    end
  end
  dffrc #(
      .DATA_WIDTH($bits(psram_core_state_e)),
      .RESET_VAL (CoreIdle)
  ) u_state_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffrc #(
      .DATA_WIDTH($bits(psram_init_phase_e)),
      .RESET_VAL (InitQpiResetEnable)
  ) u_init_phase_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_phase_d),
      .dat_o  (s_init_phase_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_powerup_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_powerup_count_d),
      .dat_o  (s_powerup_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_powerup_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_powerup_done_d),
      .dat_o  (s_powerup_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_auto_init_started_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_auto_init_started_d),
      .dat_o  (s_auto_init_started_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_init_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_pending_d),
      .dat_o  (s_init_pending_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_init_target_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_target_d),
      .dat_o  (s_init_target_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_init_chip_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_chip_d),
      .dat_o  (s_init_chip_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_chip_present_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chip_present_d),
      .dat_o  (s_chip_present_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_chip_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chip_ready_d),
      .dat_o  (s_chip_ready_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_chip_qpi_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chip_qpi_d),
      .dat_o  (s_chip_qpi_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_chip_wrap32_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chip_wrap32_d),
      .dat_o  (s_chip_wrap32_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_chip_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chip_err_d),
      .dat_o  (s_chip_err_q)
  );
  dffrc #(
      .DATA_WIDTH($bits(psram_error_e)),
      .RESET_VAL (PsramErrorNone)
  ) u_last_err_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_err_d),
      .dat_o  (s_last_err_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_last_err_chip_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_err_chip_d),
      .dat_o  (s_last_err_chip_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_last_err_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_err_addr_d),
      .dat_o  (s_last_err_addr_q)
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
      .DATA_WIDTH(2)
  ) u_mem_chip_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_chip_d),
      .dat_o  (s_mem_chip_q)
  );
  dffr #(
      .DATA_WIDTH(23)
  ) u_mem_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_addr_d),
      .dat_o  (s_mem_addr_q)
  );
  dffrc #(
      .DATA_WIDTH(3),
      .RESET_VAL (3'd1)
  ) u_mem_len_dffrc (
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
      .DATA_WIDTH(1)
  ) u_mem_rsp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mem_rsp_err_d),
      .dat_o  (s_mem_rsp_err_q)
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
      .DATA_WIDTH(4)
  ) u_read_cache_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_cache_valid_d),
      .dat_o  (s_read_cache_valid_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_read_cache_replace_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_cache_replace_d),
      .dat_o  (s_read_cache_replace_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_indirect_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_pending_d),
      .dat_o  (s_indirect_pending_q)
  );
  dffrc #(
      .DATA_WIDTH($bits(psram_cmd_e)),
      .RESET_VAL (PsramCmdRead)
  ) u_indirect_cmd_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_cmd_d),
      .dat_o  (s_indirect_cmd_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_indirect_chip_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_chip_d),
      .dat_o  (s_indirect_chip_q)
  );
  dffr #(
      .DATA_WIDTH(23)
  ) u_indirect_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_addr_d),
      .dat_o  (s_indirect_addr_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (4'd1)
  ) u_indirect_len_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_len_d),
      .dat_o  (s_indirect_len_q)
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
  dffr #(
      .DATA_WIDTH(1)
  ) u_init_done_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_done_event_d),
      .dat_o  (s_init_done_event_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_indirect_done_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_indirect_done_event_d),
      .dat_o  (s_indirect_done_event_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_err_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_event_d),
      .dat_o  (s_err_event_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_timeout_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_event_d),
      .dat_o  (s_timeout_event_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_perf_read_byte_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_read_byte_event_d),
      .dat_o  (s_perf_read_byte_event_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_perf_write_byte_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_write_byte_event_d),
      .dat_o  (s_perf_write_byte_event_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_cmd_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_cmd_event_d),
      .dat_o  (s_perf_cmd_event_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_err_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_err_event_d),
      .dat_o  (s_perf_err_event_q)
  );
  for (genvar chip_index = 0; chip_index < 4; chip_index++) begin : gen_chip_id
    dffr #(
        .DATA_WIDTH(48)
    ) u_chip_id_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_chip_id_d[chip_index]),
        .dat_o  (s_chip_id_q[chip_index])
    );
  end
  for (genvar cache_index = 0; cache_index < 4; cache_index++) begin : gen_read_cache
    dffr #(
        .DATA_WIDTH(2)
    ) u_read_cache_chip_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_read_cache_chip_d[cache_index]),
        .dat_o  (s_read_cache_chip_q[cache_index])
    );
    dffr #(
        .DATA_WIDTH(18)
    ) u_read_cache_base_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_read_cache_base_d[cache_index]),
        .dat_o  (s_read_cache_base_q[cache_index])
    );
    dffr #(
        .DATA_WIDTH(256)
    ) u_read_cache_data_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_read_cache_data_d[cache_index]),
        .dat_o  (s_read_cache_data_q[cache_index])
    );
  end


  assign init_done_event_o       = s_init_done_event_q;
  assign indirect_done_event_o   = s_indirect_done_event_q;
  assign error_event_o           = s_err_event_q;
  assign timeout_event_o         = s_timeout_event_q;
  assign perf_read_byte_event_o  = s_perf_read_byte_event_q;
  assign perf_write_byte_event_o = s_perf_write_byte_event_q;
  assign perf_command_event_o    = s_perf_cmd_event_q;
  assign perf_error_event_o      = s_perf_err_event_q;

  logic unused_phy_busy;
  assign unused_phy_busy = phy_busy_i;

endmodule
