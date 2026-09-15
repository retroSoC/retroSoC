// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

// APUM 1.0 is fetched before it is published.  valid/lock therefore cannot
// expose a partially DMA-written image to the capture or inference engines.
module apu_kws_model_loader (
    // verilog_format: off -- preserve the private-DMA and KWS-SRAM columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        start_i,
    input  logic        abort_i,
    input  logic        soft_reset_i,
    input  logic        resource_reset_request_i,
    input  logic        resource_reset_i,
    input  logic        quiesce_i,
    input  logic [31:0] address_i,
    input  logic [31:0] size_i,
    input  logic [31:0] expected_crc_i,
    input  logic [31:0] acl_base_i,
    input  logic [31:0] acl_limit_i,
    output logic        dma_request_valid_o,
    input  logic        dma_request_ready_i,
    output logic [31:0] dma_request_address_o,
    output logic [31:0] dma_request_bytes_o,
    input  logic [31:0] dma_data_i,
    input  logic [ 3:0] dma_keep_i,
    input  logic        dma_last_i,
    input  logic        dma_valid_i,
    output logic        dma_ready_o,
    input  logic        dma_done_i,
    input  logic        dma_error_i,
    input  logic [ 5:0] dma_error_code_i,
    input  logic [ 3:0] dma_error_stage_i,
    input  logic [ 1:0] dma_error_resp_i,
    input  logic [31:0] dma_error_address_i,
    output logic        local_request_o,
    output logic [16:0] local_address_o,
    output logic [31:0] local_data_o,
    output logic [ 3:0] local_strb_o,
    input  logic        local_ready_i,
    output logic        busy_o,
    output logic        valid_o,
    output logic        lock_o,
    output logic [31:0] actual_crc_o,
    output logic [31:0] status_o,
    output logic [5:0]  error_code_o,
    output logic [3:0]  error_stage_o,
    output logic [1:0]  error_resp_o,
    output logic [31:0] error_address_o,
    output logic [31:0] error_detail_o,
    output logic        config_publish_o,
    output logic [15:0] config_default_o,
    output logic        done_o,
    output logic        abort_done_o
    // verilog_format: on
);
  `include "apu_kws_apum_profile.svh"

  localparam logic [31:0] ModelBytes = 32'd32768;
  localparam logic [31:0] ModelCrc = 32'hb903_4b22;
  localparam logic [31:0] ModelAddress = 32'hce4f_7000;
  localparam logic [31:0] ModelAddressLo = 32'h6843_eaae;
  localparam logic [31:0] KwsBase = `APB4_APU__LOCAL_KWS_BASE;

  typedef enum logic [3:0] {
    Idle,
    RequestHeader,
    ReceiveHeader,
    WaitHeader,
    CheckHeader,
    RequestPayload,
    ReceivePayload,
    WaitPayload,
    Validate,
    Complete
  } state_e;

  state_e s_state_q;
  logic s_valid_q, s_lock_q, s_done_q, s_abort_done_q, s_abort_pending_q;
  logic [31:0] s_crc_q, s_actual_crc_q, s_stat_q;
  logic [5:0] s_err_code_q;
  logic [3:0] s_err_stage_q;
  logic [1:0] s_err_resp_q;
  logic [31:0] s_err_addr_q, s_err_detail_q;
  logic [31:0]       s_received_q;
  logic [15:0][31:0] s_header_q;
  logic              s_padding_err_q;
  logic              s_profile_err_q;
  logic              s_receive_err_q;
  logic [31:0]       s_profile_err_addr_q;
  logic [ 1:0]       s_profile_word_check;
  logic              s_profile_candidate;
  logic [32:0]       s_last_addr;
  logic [32:0]       s_snapshot_last_addr;
  logic              s_admit_ok;
  logic              s_snapshot_range_ok;
  logic              s_data_accept;
  logic [31:0]       s_crc_after_word;
  logic [31:0]       s_addr_q;
  logic [31:0]       s_size_q;
  logic [31:0]       s_expected_crc_q;
  logic [31:0]       s_acl_base_q;
  logic [31:0]       s_acl_limit_q;

  function automatic logic [31:0] crc32_byte(input logic [31:0] crc_i, input logic [7:0] byte_i);
    logic [31:0] s_crc;
    begin
      s_crc = crc_i ^ {24'd0, byte_i};
      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        s_crc = s_crc[0] ? ((s_crc >> 1) ^ 32'hedb8_8320) : (s_crc >> 1);
      end
      return s_crc;
    end
  endfunction

  function automatic logic [31:0] crc32_word(input logic [31:0] crc_i, input logic [31:0] data_i,
                                             input logic [3:0] keep_i);
    logic [31:0] s_crc;
    begin
      s_crc = crc_i;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (keep_i[byte_index]) begin
          s_crc = crc32_byte(s_crc, data_i[(byte_index*8)+:8]);
        end
      end
      return s_crc;
    end
  endfunction

  function automatic logic padding_is_zero(input logic [31:0] offset_i, input logic [31:0] data_i);
    logic s_in_padding;
    begin
      s_in_padding = ((offset_i >= 32'h0000_04e0) && (offset_i < 32'h0000_0500)) ||
          (offset_i >= 32'h0000_7690);
      return !s_in_padding || (data_i == 32'd0);
    end
  endfunction

  function automatic logic profile_word_candidate(input logic [31:0] offset_i);
    begin
      return (offset_i < 32'h0500) ||
          ((offset_i >= 32'h1000) && (offset_i < 32'h1200)) ||
          ((offset_i >= 32'h1540) && (offset_i < 32'h1740)) ||
          ((offset_i >= 32'h2840) && (offset_i < 32'h2a40)) ||
          ((offset_i >= 32'h2d80) && (offset_i < 32'h2f80)) ||
          ((offset_i >= 32'h4080) && (offset_i < 32'h4280)) ||
          ((offset_i >= 32'h45c0) && (offset_i < 32'h47c0)) ||
          ((offset_i >= 32'h58c0) && (offset_i < 32'h5ac0)) ||
          ((offset_i >= 32'h5e00) && (offset_i < 32'h6000)) ||
          ((offset_i >= 32'h7100) && (offset_i < 32'h7300)) ||
          ((offset_i >= 32'h7630) && (offset_i < 32'h7690));
    end
  endfunction

  assign s_last_addr = {1'b0, address_i} + {1'b0, size_i} - 1'b1;
  assign s_admit_ok = (size_i == ModelBytes) && (address_i[5:0] == 6'd0) &&
      (address_i >= acl_base_i) && !s_last_addr[32] && (s_last_addr[31:0] <= acl_limit_i) &&
      quiesce_i && !s_lock_q;
  assign s_snapshot_last_addr = {1'b0, s_addr_q} + {1'b0, s_size_q} - 1'b1;
  assign s_snapshot_range_ok = (s_size_q == ModelBytes) && (s_addr_q[5:0] == 6'd0) &&
      (s_addr_q >= s_acl_base_q) && !s_snapshot_last_addr[32] &&
      (s_snapshot_last_addr[31:0] <= s_acl_limit_q);
  assign s_data_accept = dma_valid_i && dma_ready_o;
  assign s_crc_after_word = crc32_word(s_crc_q, dma_data_i, dma_keep_i);
  assign s_profile_candidate = profile_word_candidate(s_received_q);
  assign s_profile_word_check = s_profile_candidate ? apu_kws_apum_fixed_word_check(
      s_received_q[14:0], dma_data_i
  ) : 2'b00;

  assign dma_request_valid_o = ((s_state_q == RequestHeader) ||
                                (s_state_q == RequestPayload)) && s_snapshot_range_ok;
  assign dma_request_address_o = (s_state_q == RequestPayload) ? s_addr_q + 32'd64 : s_addr_q;
  assign dma_request_bytes_o = (s_state_q == RequestPayload) ? s_size_q - 32'd64 : 32'd64;
  assign dma_ready_o = ((s_state_q == ReceiveHeader) ||
                        (s_state_q == ReceivePayload)) && local_ready_i;
  assign local_request_o = s_data_accept;
  assign local_address_o = KwsBase[16:0] + s_received_q[16:0];
  assign local_data_o = dma_data_i;
  assign local_strb_o = dma_keep_i;
  assign busy_o = s_state_q != Idle;
  assign valid_o = s_valid_q;
  assign lock_o = s_lock_q;
  assign actual_crc_o = s_actual_crc_q;
  assign status_o = s_stat_q;
  assign error_code_o = s_err_code_q;
  assign error_stage_o = s_err_stage_q;
  assign error_resp_o = s_err_resp_q;
  assign error_address_o = s_err_addr_q;
  assign error_detail_o = s_err_detail_q;
  assign config_publish_o = (s_state_q == Validate) && !abort_i &&
      !resource_reset_request_i && !resource_reset_i && (~s_crc_q == ModelCrc) &&
      (s_header_q[9] == ~s_crc_q) &&
      (s_expected_crc_q == ~s_crc_q) && !s_padding_err_q && !s_profile_err_q;
  assign config_default_o = s_header_q[12][15:0];
  assign done_o = s_done_q;
  assign abort_done_o = s_abort_done_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q            <= Idle;
      s_valid_q            <= 1'b0;
      s_lock_q             <= 1'b0;
      s_done_q             <= 1'b0;
      s_abort_done_q       <= 1'b0;
      s_abort_pending_q    <= 1'b0;
      s_crc_q              <= 32'hffff_ffff;
      s_actual_crc_q       <= 32'd0;
      s_stat_q             <= 32'd0;
      s_err_code_q         <= 6'd0;
      s_err_stage_q        <= 4'd0;
      s_err_resp_q         <= 2'd0;
      s_err_addr_q         <= 32'd0;
      s_err_detail_q       <= 32'd0;
      s_received_q         <= 32'd0;
      s_header_q           <= '0;
      s_padding_err_q      <= 1'b0;
      s_profile_err_q      <= 1'b0;
      s_receive_err_q      <= 1'b0;
      s_profile_err_addr_q <= 32'd0;
      s_addr_q             <= 32'd0;
      s_size_q             <= 32'd0;
      s_expected_crc_q     <= 32'd0;
      s_acl_base_q         <= 32'd0;
      s_acl_limit_q        <= 32'd0;
    end else begin
      s_done_q       <= 1'b0;
      s_abort_done_q <= 1'b0;
      if (soft_reset_i || resource_reset_i) begin
        s_state_q            <= Idle;
        s_done_q             <= 1'b0;
        s_abort_done_q       <= 1'b0;
        s_abort_pending_q    <= 1'b0;
        s_valid_q            <= s_lock_q && s_valid_q;
        s_lock_q             <= s_lock_q && s_valid_q;
        s_crc_q              <= 32'hffff_ffff;
        s_actual_crc_q       <= (s_lock_q && s_valid_q) ? s_actual_crc_q : 32'd0;
        s_stat_q             <= {29'd0, s_lock_q && s_valid_q, s_lock_q && s_valid_q, 1'b0};
        s_err_code_q         <= 6'd0;
        s_err_stage_q        <= 4'd0;
        s_err_resp_q         <= 2'd0;
        s_err_addr_q         <= 32'd0;
        s_err_detail_q       <= 32'd0;
        s_received_q         <= 32'd0;
        s_padding_err_q      <= 1'b0;
        s_profile_err_q      <= 1'b0;
        s_receive_err_q      <= 1'b0;
        s_profile_err_addr_q <= 32'd0;
        s_addr_q             <= 32'd0;
        s_size_q             <= 32'd0;
        s_expected_crc_q     <= 32'd0;
        s_acl_base_q         <= 32'd0;
        s_acl_limit_q        <= 32'd0;
      end else begin
        unique case (s_state_q)
          Idle: begin
            if (start_i && !s_lock_q) begin
              s_abort_pending_q    <= 1'b0;
              s_valid_q            <= 1'b0;
              s_actual_crc_q       <= 32'd0;
              s_crc_q              <= 32'hffff_ffff;
              s_stat_q             <= 32'd1;
              s_err_code_q         <= 6'd0;
              s_err_stage_q        <= 4'd0;
              s_err_resp_q         <= 2'd0;
              s_err_addr_q         <= 32'd0;
              s_err_detail_q       <= 32'd0;
              s_received_q         <= 32'd0;
              s_header_q           <= '0;
              s_padding_err_q      <= 1'b0;
              s_profile_err_q      <= 1'b0;
              s_receive_err_q      <= 1'b0;
              s_profile_err_addr_q <= 32'd0;
              s_addr_q             <= address_i;
              s_size_q             <= size_i;
              s_expected_crc_q     <= expected_crc_i;
              s_acl_base_q         <= acl_base_i;
              s_acl_limit_q        <= acl_limit_i;
              if (size_i != ModelBytes) begin
                s_stat_q       <= 32'h0000_0400;
                s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q   <= 32'(`APB4_APU__KWS_MODEL_SIZE);
                s_err_detail_q <= 32'h0700_0001;
                s_state_q      <= Complete;
              end else if (!s_admit_ok) begin
                s_stat_q       <= 32'h0000_0200;
                s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q   <= address_i;
                s_err_detail_q <= 32'h0700_0003;
                s_state_q      <= Complete;
              end else begin
                s_state_q <= RequestHeader;
              end
            end
          end
          RequestHeader: begin
            if (abort_i || resource_reset_request_i) begin
              s_stat_q          <= 32'd0;
              s_err_code_q      <= 6'd0;
              s_err_stage_q     <= 4'd0;
              s_err_resp_q      <= 2'd0;
              s_err_addr_q      <= 32'd0;
              s_err_detail_q    <= 32'd0;
              s_abort_done_q    <= abort_i && !resource_reset_request_i;
              s_abort_pending_q <= 1'b0;
              s_state_q         <= Idle;
            end else if (!s_snapshot_range_ok) begin
              s_stat_q       <= 32'h0000_0200;
              s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
              s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
              s_err_addr_q   <= s_addr_q;
              s_err_detail_q <= 32'h0700_0003;
              s_state_q      <= Complete;
            end else if (dma_request_ready_i) begin
              s_state_q <= ReceiveHeader;
            end
          end
          ReceiveHeader: begin
            if (dma_done_i) begin
              if (dma_error_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= dma_error_code_i;
                s_err_stage_q     <= dma_error_stage_i;
                s_err_resp_q      <= dma_error_resp_i;
                s_err_addr_q      <= dma_error_address_i;
                s_err_detail_q    <= 32'd0;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Complete;
              end else if (abort_i || s_abort_pending_q || resource_reset_request_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= 6'd0;
                s_err_stage_q     <= 4'd0;
                s_err_resp_q      <= 2'd0;
                s_err_addr_q      <= 32'd0;
                s_err_detail_q    <= 32'd0;
                s_abort_done_q    <= (abort_i || s_abort_pending_q) && !resource_reset_request_i;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Idle;
              end else if (s_data_accept && dma_last_i && (s_received_q == 32'd60) &&
                           (dma_keep_i == 4'hf)) begin
                s_header_q[s_received_q[5:2]] <= dma_data_i;
                s_received_q                  <= s_received_q + 32'd4;
                s_state_q                     <= CheckHeader;
              end else begin
                s_stat_q        <= 32'h0000_0200;
                s_err_code_q    <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                s_err_stage_q   <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q    <= s_addr_q + s_received_q;
                s_err_detail_q  <= 32'h0700_0003;
                s_receive_err_q <= 1'b1;
                s_state_q       <= Complete;
              end
            end else if (abort_i || resource_reset_request_i) begin
              s_abort_pending_q <= abort_i && !resource_reset_request_i;
              s_state_q         <= WaitHeader;
            end else if (s_data_accept) begin
              if ((s_received_q[1:0] != 2'd0) || (dma_keep_i != 4'hf) ||
                  (s_received_q >= 32'd64) ||
                  (!dma_last_i && (s_received_q == 32'd60)) ||
                  (dma_last_i && (s_received_q != 32'd60))) begin
                s_stat_q        <= 32'h0000_0200;
                s_err_code_q    <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                s_err_stage_q   <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q    <= s_addr_q + s_received_q;
                s_err_detail_q  <= 32'h0700_0003;
                s_receive_err_q <= 1'b1;
                s_state_q       <= WaitHeader;
              end else begin
                s_header_q[s_received_q[5:2]] <= dma_data_i;
                s_received_q                  <= s_received_q + 32'd4;
                if (dma_last_i) begin
                  s_state_q <= WaitHeader;
                end
              end
            end
          end
          WaitHeader: begin
            if (abort_i && !resource_reset_request_i) s_abort_pending_q <= 1'b1;
            if (dma_done_i) begin
              if (dma_error_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= dma_error_code_i;
                s_err_stage_q     <= dma_error_stage_i;
                s_err_resp_q      <= dma_error_resp_i;
                s_err_addr_q      <= dma_error_address_i;
                s_err_detail_q    <= 32'd0;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Complete;
              end else if (abort_i || s_abort_pending_q || resource_reset_request_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= 6'd0;
                s_err_stage_q     <= 4'd0;
                s_err_resp_q      <= 2'd0;
                s_err_addr_q      <= 32'd0;
                s_err_detail_q    <= 32'd0;
                s_abort_done_q    <= (abort_i || s_abort_pending_q) && !resource_reset_request_i;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Idle;
              end else if (s_receive_err_q) begin
                s_state_q <= Complete;
              end else begin
                s_state_q <= CheckHeader;
              end
            end
          end
          CheckHeader: begin
            if (abort_i || resource_reset_request_i) begin
              s_stat_q          <= 32'd0;
              s_err_code_q      <= 6'd0;
              s_err_stage_q     <= 4'd0;
              s_err_resp_q      <= 2'd0;
              s_err_addr_q      <= 32'd0;
              s_err_detail_q    <= 32'd0;
              s_abort_done_q    <= abort_i && !resource_reset_request_i;
              s_abort_pending_q <= 1'b0;
              s_state_q         <= Idle;
            end else if ((s_received_q != 32'd64) ||
                (s_header_q[0] != 32'h4d55_5041) || (s_header_q[1] != 32'h0001_0000) ||
                (s_header_q[2] != ModelBytes) || (s_header_q[3] != 32'd1) ||
                (s_header_q[4] != 32'h000a_0031) || (s_header_q[5] != 32'h000c_000c) ||
                (s_header_q[6] != 32'd29072) || (s_header_q[7] != ModelBytes) ||
                (s_header_q[8] != 32'd1) || (s_header_q[10] != ModelAddressLo) ||
                (s_header_q[11] != ModelAddress) || (s_header_q[12] != 32'h0000_0380) ||
                (s_header_q[13] != 32'd13) || (s_header_q[14] != 32'd1) ||
                (s_header_q[15] != 32'd0)) begin
              s_stat_q      <= 32'h0000_0100;
              s_err_code_q  <= `APB4_APU__ERROR_CODE_KWS_MODEL;
              s_err_stage_q <= `APB4_APU__ERROR_STAGE_LOADER;
              if (s_received_q != 32'd64) s_err_addr_q <= s_addr_q + s_received_q;
              else if (s_header_q[0] != 32'h4d55_5041) s_err_addr_q <= s_addr_q;
              else if (s_header_q[1] != 32'h0001_0000) s_err_addr_q <= s_addr_q + 32'h04;
              else if (s_header_q[2] != ModelBytes) s_err_addr_q <= s_addr_q + 32'h08;
              else if (s_header_q[3] != 32'd1) s_err_addr_q <= s_addr_q + 32'h0c;
              else if (s_header_q[4] != 32'h000a_0031) s_err_addr_q <= s_addr_q + 32'h10;
              else if (s_header_q[5] != 32'h000c_000c) s_err_addr_q <= s_addr_q + 32'h14;
              else if (s_header_q[6] != 32'd29072) s_err_addr_q <= s_addr_q + 32'h18;
              else if (s_header_q[7] != ModelBytes) s_err_addr_q <= s_addr_q + 32'h1c;
              else if (s_header_q[8] != 32'd1) s_err_addr_q <= s_addr_q + 32'h20;
              else if (s_header_q[10] != ModelAddressLo) s_err_addr_q <= s_addr_q + 32'h28;
              else if (s_header_q[11] != ModelAddress) s_err_addr_q <= s_addr_q + 32'h2c;
              else if (s_header_q[12] != 32'h0000_0380) s_err_addr_q <= s_addr_q + 32'h30;
              else if (s_header_q[13] != 32'd13) s_err_addr_q <= s_addr_q + 32'h34;
              else if (s_header_q[14] != 32'd1) s_err_addr_q <= s_addr_q + 32'h38;
              else s_err_addr_q <= s_addr_q + 32'h3c;
              s_err_detail_q <= 32'h0700_0002;
              s_state_q      <= Complete;
            end else begin
              s_state_q <= RequestPayload;
            end
          end
          RequestPayload: begin
            if (abort_i || resource_reset_request_i) begin
              s_stat_q          <= 32'd0;
              s_err_code_q      <= 6'd0;
              s_err_stage_q     <= 4'd0;
              s_err_resp_q      <= 2'd0;
              s_err_addr_q      <= 32'd0;
              s_err_detail_q    <= 32'd0;
              s_abort_done_q    <= abort_i && !resource_reset_request_i;
              s_abort_pending_q <= 1'b0;
              s_state_q         <= Idle;
            end else if (!s_snapshot_range_ok) begin
              s_stat_q       <= 32'h0000_0200;
              s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
              s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
              s_err_addr_q   <= s_addr_q + s_received_q;
              s_err_detail_q <= 32'h0700_0003;
              s_state_q      <= Complete;
            end else if (dma_request_ready_i) begin
              s_state_q <= ReceivePayload;
            end
          end
          ReceivePayload: begin
            if (dma_done_i) begin
              if (dma_error_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= dma_error_code_i;
                s_err_stage_q     <= dma_error_stage_i;
                s_err_resp_q      <= dma_error_resp_i;
                s_err_addr_q      <= dma_error_address_i;
                s_err_detail_q    <= 32'd0;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Complete;
              end else if (abort_i || s_abort_pending_q || resource_reset_request_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= 6'd0;
                s_err_stage_q     <= 4'd0;
                s_err_resp_q      <= 2'd0;
                s_err_addr_q      <= 32'd0;
                s_err_detail_q    <= 32'd0;
                s_abort_done_q    <= (abort_i || s_abort_pending_q) && !resource_reset_request_i;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Idle;
              end else if (s_data_accept && dma_last_i &&
                           (s_received_q == (s_size_q - 32'd4)) &&
                           (dma_keep_i == 4'hf)) begin
                if (!padding_is_zero(s_received_q, dma_data_i) && !s_profile_err_q) begin
                  s_padding_err_q      <= 1'b1;
                  s_profile_err_addr_q <= s_addr_q + s_received_q;
                end
                if (s_profile_candidate && !s_profile_err_q && s_profile_word_check[1] &&
                    !s_profile_word_check[0]) begin
                  s_profile_err_q      <= 1'b1;
                  s_profile_err_addr_q <= s_addr_q + s_received_q;
                end
                s_crc_q        <= s_crc_after_word;
                s_actual_crc_q <= ~s_crc_after_word;
                s_received_q   <= s_received_q + 32'd4;
                s_state_q      <= Validate;
              end else begin
                s_stat_q       <= 32'h0000_0200;
                s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q   <= s_addr_q + s_received_q;
                s_err_detail_q <= 32'h0700_0003;
                s_state_q      <= Complete;
              end
            end else if (abort_i || resource_reset_request_i) begin
              s_abort_pending_q <= abort_i && !resource_reset_request_i;
              s_state_q         <= WaitPayload;
            end else if (s_data_accept) begin
              if ((s_received_q[1:0] != 2'd0) || (dma_keep_i != 4'hf) ||
                  (s_received_q < 32'd64) || (s_received_q >= s_size_q) ||
                  (!dma_last_i && (s_received_q == (s_size_q - 32'd4))) ||
                  (dma_last_i && (s_received_q != (s_size_q - 32'd4)))) begin
                s_stat_q        <= 32'h0000_0200;
                s_err_code_q    <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                s_err_stage_q   <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q    <= s_addr_q + s_received_q;
                s_err_detail_q  <= 32'h0700_0003;
                s_receive_err_q <= 1'b1;
                s_state_q       <= WaitPayload;
              end else begin
                if (!padding_is_zero(s_received_q, dma_data_i) && !s_profile_err_q) begin
                  s_padding_err_q      <= 1'b1;
                  s_profile_err_addr_q <= s_addr_q + s_received_q;
                end
                if (s_profile_candidate && !s_profile_err_q) begin
                  if (s_profile_word_check[1] && !s_profile_word_check[0]) begin
                    s_profile_err_q      <= 1'b1;
                    s_profile_err_addr_q <= s_addr_q + s_received_q;
                  end
                end
                s_crc_q      <= s_crc_after_word;
                s_received_q <= s_received_q + 32'd4;
                if (dma_last_i) begin
                  s_state_q <= WaitPayload;
                end
              end
            end
          end
          WaitPayload: begin
            if (abort_i && !resource_reset_request_i) s_abort_pending_q <= 1'b1;
            if (dma_done_i) begin
              if (dma_error_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= dma_error_code_i;
                s_err_stage_q     <= dma_error_stage_i;
                s_err_resp_q      <= dma_error_resp_i;
                s_err_addr_q      <= dma_error_address_i;
                s_err_detail_q    <= 32'd0;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Complete;
              end else if (abort_i || s_abort_pending_q || resource_reset_request_i) begin
                s_stat_q          <= 32'd0;
                s_err_code_q      <= 6'd0;
                s_err_stage_q     <= 4'd0;
                s_err_resp_q      <= 2'd0;
                s_err_addr_q      <= 32'd0;
                s_err_detail_q    <= 32'd0;
                s_abort_done_q    <= (abort_i || s_abort_pending_q) && !resource_reset_request_i;
                s_abort_pending_q <= 1'b0;
                s_state_q         <= Idle;
              end else if (s_receive_err_q || (s_received_q != s_size_q)) begin
                if (!s_receive_err_q) begin
                  s_stat_q       <= 32'h0000_0200;
                  s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
                  s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
                  s_err_addr_q   <= s_addr_q + s_received_q;
                  s_err_detail_q <= 32'h0700_0003;
                end
                s_state_q <= Complete;
              end else begin
                s_actual_crc_q <= ~s_crc_q;
                s_state_q      <= Validate;
              end
            end
          end
          Validate: begin
            if (abort_i || resource_reset_request_i) begin
              s_stat_q          <= 32'd0;
              s_err_code_q      <= 6'd0;
              s_err_stage_q     <= 4'd0;
              s_err_resp_q      <= 2'd0;
              s_err_addr_q      <= 32'd0;
              s_err_detail_q    <= 32'd0;
              s_abort_done_q    <= abort_i && !resource_reset_request_i;
              s_abort_pending_q <= 1'b0;
              s_state_q         <= Idle;
            end else if ((~s_crc_q != ModelCrc) || (s_header_q[9] != ~s_crc_q) ||
                                  (s_expected_crc_q != ~s_crc_q)) begin
              s_stat_q       <= 32'h0000_0800;
              s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_CRC;
              s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
              s_err_addr_q   <= s_addr_q + 32'h24;
              s_err_detail_q <= 32'h0700_0004;
              s_state_q      <= Complete;
            end else if (s_padding_err_q || s_profile_err_q) begin
              s_stat_q       <= 32'h0000_1000;
              s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
              s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
              s_err_addr_q   <= s_profile_err_addr_q;
              s_err_detail_q <= 32'h0700_0005;
              s_state_q      <= Complete;
            end else begin
              s_valid_q <= 1'b1;
              s_lock_q  <= 1'b1;
              s_stat_q  <= 32'h0000_0006;
              s_state_q <= Complete;
            end
          end
          Complete: begin
            s_done_q  <= 1'b1;
            s_state_q <= Idle;
          end
          default: s_state_q <= Idle;
        endcase
      end
    end
  end
endmodule
