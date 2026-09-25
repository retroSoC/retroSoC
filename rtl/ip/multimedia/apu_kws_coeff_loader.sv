// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_kws_coeff_loader (
    // verilog_format: off -- preserve the private-DMA and coefficient-store columns
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
    output logic        store_active_o,
    output logic        store_req_o,
    output logic        store_write_o,
    output logic [13:0] store_addr_o,
    output logic [31:0] store_data_o,
    input  logic        store_ready_i,
    input  logic        store_valid_i,
    input  logic [31:0] store_data_i,
    input  logic        store_fault_i,
    output logic        busy_o,
    output logic        valid_o,
    output logic        lock_o,
    output logic [31:0] actual_crc_o,
    output logic [63:0] coefficient_id_o,
    output logic [31:0] status_o,
    output logic [ 5:0] error_code_o,
    output logic [ 3:0] error_stage_o,
    output logic [ 1:0] error_resp_o,
    output logic [31:0] error_address_o,
    output logic [31:0] error_detail_o,
    output logic        done_o,
    output logic        abort_done_o
    // verilog_format: on
);
  localparam logic [31:0] ImageBytes = 32'd61504;
  localparam logic [31:0] PayloadBytes = 32'd61440;
  localparam logic [31:0] PayloadCrc = 32'h25e7_c27d;
  localparam logic [31:0] CoefficientIdLow = 32'h8a0b_038d;
  localparam logic [31:0] CoefficientIdHigh = 32'h806c_780d;

  typedef enum logic [3:0] {
    Idle,
    RequestHeader,
    ReceiveHeader,
    WaitHeader,
    CheckHeader,
    RequestPayload,
    ReceivePayload,
    WaitPayload,
    ReadbackRequest,
    Validate,
    Complete,
    CancelWait
  } loader_state_e;

  loader_state_e s_state_q;
  logic [15:0][31:0] s_header_q;
  logic [31:0] s_addr_q, s_size_q, s_expected_crc_q, s_acl_base_q, s_acl_limit_q;
  logic [31:0] s_received_q;
  logic [31:0] s_crc_q, s_readback_crc_q;
  logic [13:0] s_readback_word_q;
  logic [13:0] s_readback_received_q;
  logic s_transfer_err_q, s_padding_err_q, s_store_pending_q;
  logic [31:0] s_padding_addr_q;
  logic s_valid_q, s_lock_q, s_done_q, s_abort_done_q, s_abort_pending_q;
  logic [31:0] s_actual_crc_q, s_stat_q;
  logic [63:0] s_coefficient_id_q;
  logic [ 5:0] s_err_code_q;
  logic [ 3:0] s_err_stage_q;
  logic [ 1:0] s_err_resp_q;
  logic [31:0] s_err_addr_q, s_err_detail_q;
  logic [32:0] s_last_addr, s_snapshot_last_addr;
  logic s_admit_ok, s_snapshot_range_ok, s_data_accept;
  logic [31:0] s_crc_after_word, s_readback_crc_after_word;
  logic s_header_size_err, s_header_err;
  logic [31:0] s_header_err_addr;

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

  function automatic logic [31:0] crc32_word(input logic [31:0] crc_i, input logic [31:0] data_i);
    logic [31:0] s_crc;
    begin
      s_crc = crc_i;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        s_crc = crc32_byte(s_crc, data_i[(byte_index*8)+:8]);
      end
      return s_crc;
    end
  endfunction

  function automatic logic payload_word_is_padding(input logic [13:0] word_i);
    logic [3:0] s_bank;
    logic [9:0] s_row;
    begin
      s_bank = word_i[13:10];
      s_row  = word_i[9:0];
      unique case (s_bank)
        4'd0: payload_word_is_padding = s_row >= 10'd1006;
        4'd1: payload_word_is_padding = s_row >= 10'd769;
        4'd2: payload_word_is_padding = s_row >= 10'd768;
        4'd14: payload_word_is_padding = s_row >= 10'd637;
        default: payload_word_is_padding = 1'b0;
      endcase
    end
  endfunction

  assign s_last_addr = {1'b0, address_i} + {1'b0, size_i} - 1'b1;
  assign s_admit_ok = (size_i == ImageBytes) && (address_i[5:0] == 6'd0) &&
      (address_i >= acl_base_i) && !s_last_addr[32] && (s_last_addr[31:0] <= acl_limit_i) &&
      quiesce_i && !s_lock_q;
  assign s_snapshot_last_addr = {1'b0, s_addr_q} + {1'b0, s_size_q} - 1'b1;
  assign s_snapshot_range_ok = (s_size_q == ImageBytes) && (s_addr_q[5:0] == 6'd0) &&
      (s_addr_q >= s_acl_base_q) && !s_snapshot_last_addr[32] &&
      (s_snapshot_last_addr[31:0] <= s_acl_limit_q);
  assign s_data_accept = dma_valid_i && dma_ready_o;
  assign s_crc_after_word = crc32_word(s_crc_q, dma_data_i);
  assign s_readback_crc_after_word = crc32_word(s_readback_crc_q, store_data_i);

  always_comb begin
    s_header_size_err = 1'b0;
    s_header_err = 1'b0;
    s_header_err_addr = s_addr_q;
    if (s_header_q[2] != ImageBytes) begin
      s_header_size_err = 1'b1;
      s_header_err_addr = s_addr_q + 32'h08;
    end else if (s_header_q[4] != PayloadBytes) begin
      s_header_size_err = 1'b1;
      s_header_err_addr = s_addr_q + 32'h10;
    end else if (s_header_q[0] != 32'h4355_5041) begin
      s_header_err = 1'b1;
    end else if (s_header_q[1] != 32'h0001_0000) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h04;
    end else if (s_header_q[3] != 32'd64) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h0c;
    end else if (s_header_q[5] != 32'd1) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h14;
    end else if (s_header_q[6] != 32'd1) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h18;
    end else if (s_header_q[7] != 32'd15) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h1c;
    end else if (s_header_q[8] != 32'd10) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h20;
    end else if (s_header_q[9] != PayloadCrc) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h24;
    end else if (s_header_q[10] != CoefficientIdLow) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h28;
    end else if (s_header_q[11] != CoefficientIdHigh) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h2c;
    end else if (s_header_q[12] != 32'hb903_4b22) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h30;
    end else if (s_header_q[13] != 32'd11629080) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h34;
    end else if (s_header_q[14] != 32'd0) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h38;
    end else if (s_header_q[15] != 32'd0) begin
      s_header_err      = 1'b1;
      s_header_err_addr = s_addr_q + 32'h3c;
    end
  end

  assign dma_request_valid_o = (s_state_q inside {RequestHeader, RequestPayload}) &&
      s_snapshot_range_ok;
  assign dma_request_address_o = (s_state_q == RequestPayload) ? s_addr_q + 32'd64 : s_addr_q;
  assign dma_request_bytes_o = (s_state_q == RequestPayload) ? PayloadBytes : 32'd64;
  assign dma_ready_o = ((s_state_q == ReceiveHeader) || (s_state_q == ReceivePayload)) &&
      ((s_state_q == ReceiveHeader) || store_ready_i);

  assign store_active_o = s_state_q inside {ReceivePayload, WaitPayload, ReadbackRequest, Validate};
  assign store_req_o = ((s_state_q == ReceivePayload) && s_data_accept) ||
      ((s_state_q == ReadbackRequest) && (s_readback_word_q < 14'd15360));
  assign store_write_o = s_state_q == ReceivePayload;
  assign store_addr_o = (s_state_q == ReceivePayload) ?
      14'((s_received_q - 32'd64) >> 2) : s_readback_word_q;
  assign store_data_o = dma_data_i;

  assign busy_o = s_state_q != Idle;
  assign valid_o = s_valid_q;
  assign lock_o = s_lock_q;
  assign actual_crc_o = s_actual_crc_q;
  assign coefficient_id_o = s_coefficient_id_q;
  assign status_o = {20'd0, s_stat_q[11:8], 5'd0, s_lock_q, s_valid_q, busy_o};
  assign error_code_o = s_err_code_q;
  assign error_stage_o = s_err_stage_q;
  assign error_resp_o = s_err_resp_q;
  assign error_address_o = s_err_addr_q;
  assign error_detail_o = s_err_detail_q;
  assign done_o = s_done_q;
  assign abort_done_o = s_abort_done_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q             <= Idle;
      s_header_q            <= '0;
      s_addr_q              <= 32'd0;
      s_size_q              <= 32'd0;
      s_expected_crc_q      <= 32'd0;
      s_acl_base_q          <= 32'd0;
      s_acl_limit_q         <= 32'd0;
      s_received_q          <= 32'd0;
      s_crc_q               <= 32'hffff_ffff;
      s_readback_crc_q      <= 32'hffff_ffff;
      s_readback_word_q     <= 14'd0;
      s_readback_received_q <= 14'd0;
      s_transfer_err_q      <= 1'b0;
      s_padding_err_q       <= 1'b0;
      s_store_pending_q     <= 1'b0;
      s_padding_addr_q      <= 32'd0;
      s_valid_q             <= 1'b0;
      s_lock_q              <= 1'b0;
      s_done_q              <= 1'b0;
      s_abort_done_q        <= 1'b0;
      s_abort_pending_q     <= 1'b0;
      s_actual_crc_q        <= 32'd0;
      s_stat_q              <= 32'd0;
      s_coefficient_id_q    <= 64'd0;
      s_err_code_q          <= 6'd0;
      s_err_stage_q         <= 4'd0;
      s_err_resp_q          <= 2'd0;
      s_err_addr_q          <= 32'd0;
      s_err_detail_q        <= 32'd0;
    end else begin
      s_done_q       <= 1'b0;
      s_abort_done_q <= 1'b0;
      if (store_valid_i) s_store_pending_q <= 1'b0;

      if ((soft_reset_i || resource_reset_i) && (s_state_q == Idle)) begin
        if (!s_lock_q) begin
          s_stat_q           <= 32'd0;
          s_actual_crc_q     <= 32'd0;
          s_coefficient_id_q <= 64'd0;
        end
      end

      unique case (s_state_q)
        Idle: begin
          if (start_i && s_admit_ok) begin
            s_state_q             <= RequestHeader;
            s_header_q            <= '0;
            s_addr_q              <= address_i;
            s_size_q              <= size_i;
            s_expected_crc_q      <= expected_crc_i;
            s_acl_base_q          <= acl_base_i;
            s_acl_limit_q         <= acl_limit_i;
            s_received_q          <= 32'd0;
            s_crc_q               <= 32'hffff_ffff;
            s_readback_crc_q      <= 32'hffff_ffff;
            s_readback_word_q     <= 14'd0;
            s_readback_received_q <= 14'd0;
            s_transfer_err_q      <= 1'b0;
            s_padding_err_q       <= 1'b0;
            s_store_pending_q     <= 1'b0;
            s_stat_q              <= 32'd0;
            s_actual_crc_q        <= 32'd0;
            s_coefficient_id_q    <= 64'd0;
            s_err_code_q          <= 6'd0;
            s_err_stage_q         <= 4'd0;
            s_err_resp_q          <= 2'd0;
            s_err_addr_q          <= 32'd0;
            s_err_detail_q        <= 32'd0;
          end
        end
        RequestHeader: begin
          if (abort_i || resource_reset_request_i || resource_reset_i || soft_reset_i) begin
            s_abort_done_q <= abort_i && !resource_reset_request_i && !resource_reset_i;
            s_state_q      <= Idle;
          end else if (dma_request_ready_i) begin
            s_received_q <= 32'd0;
            s_state_q    <= ReceiveHeader;
          end
        end
        ReceiveHeader: begin
          if (abort_i || resource_reset_request_i || resource_reset_i || soft_reset_i) begin
            s_abort_pending_q <= abort_i && !resource_reset_request_i && !resource_reset_i;
            s_state_q         <= CancelWait;
          end else begin
            if (s_data_accept) begin
              if ((dma_keep_i != 4'hf) || (s_received_q >= 32'd64) ||
                  (dma_last_i != (s_received_q == 32'd60))) begin
                s_transfer_err_q <= 1'b1;
              end else begin
                s_header_q[s_received_q[5:2]] <= dma_data_i;
              end
              s_received_q <= s_received_q + 32'd4;
            end
            if (dma_error_i) begin
              s_err_code_q  <= dma_error_code_i;
              s_err_stage_q <= dma_error_stage_i;
              s_err_resp_q  <= dma_error_resp_i;
              s_err_addr_q  <= dma_error_address_i;
              s_state_q     <= Complete;
            end else if (dma_done_i) begin
              s_state_q <= WaitHeader;
            end
          end
        end
        WaitHeader: begin
          if (s_transfer_err_q || (s_received_q != 32'd64)) begin
            s_err_code_q  <= `APB4_APU__ERROR_CODE_AXI_READ;
            s_err_stage_q <= `APB4_APU__ERROR_STAGE_DMA_READ;
            s_err_addr_q  <= s_addr_q + s_received_q;
            s_state_q     <= Complete;
          end else begin
            s_state_q <= CheckHeader;
          end
        end
        CheckHeader: begin
          if (s_header_size_err) begin
            s_stat_q[8]    <= 1'b1;
            s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
            s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
            s_err_addr_q   <= s_header_err_addr;
            s_err_detail_q <= 32'h0900_0001;
            s_state_q      <= Complete;
          end else if (s_header_err) begin
            s_stat_q[9]    <= 1'b1;
            s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
            s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
            s_err_addr_q   <= s_header_err_addr;
            s_err_detail_q <= 32'h0900_0002;
            s_state_q      <= Complete;
          end else begin
            s_received_q     <= 32'd64;
            s_crc_q          <= 32'hffff_ffff;
            s_transfer_err_q <= 1'b0;
            s_state_q        <= RequestPayload;
          end
        end
        RequestPayload: begin
          if (abort_i || resource_reset_request_i || resource_reset_i || soft_reset_i) begin
            s_abort_done_q <= abort_i && !resource_reset_request_i && !resource_reset_i;
            s_state_q      <= Idle;
          end else if (dma_request_ready_i) begin
            s_state_q <= ReceivePayload;
          end
        end
        ReceivePayload: begin
          if (abort_i || resource_reset_request_i || resource_reset_i || soft_reset_i) begin
            s_abort_pending_q <= abort_i && !resource_reset_request_i && !resource_reset_i;
            s_state_q         <= CancelWait;
          end else begin
            if (s_data_accept) begin
              if ((dma_keep_i != 4'hf) || (s_received_q >= ImageBytes) ||
                  (dma_last_i != (s_received_q == (ImageBytes - 32'd4)))) begin
                s_transfer_err_q <= 1'b1;
              end else begin
                s_crc_q           <= s_crc_after_word;
                s_store_pending_q <= 1'b1;
                if (payload_word_is_padding(
                        14'((s_received_q - 32'd64) >> 2)
                    ) && (dma_data_i != 32'd0) && !s_padding_err_q) begin
                  s_padding_err_q  <= 1'b1;
                  s_padding_addr_q <= s_addr_q + s_received_q;
                end
              end
              s_received_q <= s_received_q + 32'd4;
            end
            if (dma_error_i) begin
              s_err_code_q  <= dma_error_code_i;
              s_err_stage_q <= dma_error_stage_i;
              s_err_resp_q  <= dma_error_resp_i;
              s_err_addr_q  <= dma_error_address_i;
              s_state_q     <= Complete;
            end else if (dma_done_i) begin
              s_state_q <= WaitPayload;
            end
          end
        end
        WaitPayload: begin
          if (!s_store_pending_q) begin
            if (s_transfer_err_q || (s_received_q != ImageBytes) || store_fault_i) begin
              s_err_code_q  <= `APB4_APU__ERROR_CODE_AXI_READ;
              s_err_stage_q <= `APB4_APU__ERROR_STAGE_DMA_READ;
              s_err_addr_q  <= s_addr_q + s_received_q;
              s_state_q     <= Complete;
            end else if (s_padding_err_q) begin
              s_stat_q[11]   <= 1'b1;
              s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_MODEL;
              s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
              s_err_addr_q   <= s_padding_addr_q;
              s_err_detail_q <= 32'h0900_0004;
              s_state_q      <= Complete;
            end else if ((~s_crc_q != PayloadCrc) || (s_header_q[9] != ~s_crc_q) ||
                         (s_expected_crc_q != ~s_crc_q)) begin
              s_stat_q[10]   <= 1'b1;
              s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_CRC;
              s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
              s_err_addr_q   <= s_addr_q + 32'h24;
              s_err_detail_q <= 32'h0900_0003;
              s_state_q      <= Complete;
            end else begin
              s_readback_crc_q      <= 32'hffff_ffff;
              s_readback_word_q     <= 14'd0;
              s_readback_received_q <= 14'd0;
              s_state_q             <= ReadbackRequest;
            end
          end
        end
        ReadbackRequest: begin
          if (abort_i || resource_reset_request_i || resource_reset_i || soft_reset_i) begin
            s_abort_done_q <= abort_i && !resource_reset_request_i && !resource_reset_i;
            s_state_q      <= Idle;
          end else begin
            if (store_req_o && store_ready_i) begin
              s_readback_word_q <= s_readback_word_q + 1'b1;
            end
            if (store_valid_i) begin
              if (store_fault_i) begin
                s_stat_q[10]   <= 1'b1;
                s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_CRC;
                s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
                s_err_addr_q   <= s_addr_q + 32'h24;
                s_err_detail_q <= 32'h0900_0005;
                s_state_q      <= Complete;
              end else begin
                s_readback_crc_q <= s_readback_crc_after_word;
                if (s_readback_received_q == 14'd15359) begin
                  s_actual_crc_q <= ~s_readback_crc_after_word;
                  s_state_q      <= Validate;
                end else begin
                  s_readback_received_q <= s_readback_received_q + 1'b1;
                end
              end
            end
          end
        end
        Validate: begin
          if (s_actual_crc_q != PayloadCrc) begin
            s_stat_q[10]   <= 1'b1;
            s_err_code_q   <= `APB4_APU__ERROR_CODE_KWS_CRC;
            s_err_stage_q  <= `APB4_APU__ERROR_STAGE_LOADER;
            s_err_addr_q   <= s_addr_q + 32'h24;
            s_err_detail_q <= 32'h0900_0005;
          end else begin
            s_valid_q          <= 1'b1;
            s_lock_q           <= 1'b1;
            s_coefficient_id_q <= {CoefficientIdHigh, CoefficientIdLow};
          end
          s_state_q <= Complete;
        end
        Complete: begin
          s_done_q  <= 1'b1;
          s_state_q <= Idle;
        end
        CancelWait: begin
          if (dma_error_i || dma_done_i) begin
            s_abort_done_q    <= s_abort_pending_q;
            s_abort_pending_q <= 1'b0;
            s_state_q         <= Idle;
          end
        end
        default: s_state_q <= Idle;
      endcase
    end
  end
endmodule
