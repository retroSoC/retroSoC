// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "crypto_define.svh"

module apb4_crypto (
    // verilog_format: off -- APB, DMA stream, and interrupt ports are grouped.
    input  logic               clk_i,
    input  logic               rst_n_i,
    output logic               dma_input_proc_o,
    output logic               dma_output_proc_o,
    output logic               irq_o,
    apb4_if.slave              apb4,
    axi4_stream_if.sink        crypto_in_axis,
    axi4_stream_if.source      crypto_out_axis
    // verilog_format: on
);
  import crypto_pkg::*;

  localparam int RsaBits = 2048;
  localparam int RsaWords = RsaBits / 32;
  localparam logic [31:0] IpId = 32'h4352_5950;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [31:0] Capability0 = 32'h00ff_ffff;
  localparam logic [31:0] Capability1 = 32'h0800_2020;

  logic               s_access;
  logic               s_write;
  logic               s_read;
  logic [       11:0] s_offset;
  logic               s_known_offset;
  logic               s_read_only_offset;
  logic               s_secret_offset;
  logic               s_access_err;
  logic [       31:0] s_read_data;

  logic [        8:0] s_aes_cfg_q;
  logic [       31:0] s_aes_len_q;
  logic [       31:0] s_aes_key_q             [         0:7];
  logic [       31:0] s_aes_iv_q              [         0:3];
  logic [      255:0] s_aes_key;
  logic [      127:0] s_aes_iv;
  logic               s_aes_start;
  logic               s_aes_abort;
  logic               s_aes_zeroize;
  logic               s_aes_key_commit;
  logic               s_aes_key_valid;
  logic               s_aes_key_busy;
  logic               s_aes_input_valid;
  logic               s_aes_input_ready;
  logic [       31:0] s_aes_input_data;
  logic [        3:0] s_aes_input_keep;
  logic               s_aes_input_last;
  logic               s_aes_output_valid;
  logic               s_aes_output_ready;
  logic [       31:0] s_aes_output_data;
  logic [        3:0] s_aes_output_keep;
  logic               s_aes_output_last;
  logic               s_aes_busy;
  logic               s_aes_done;
  logic               s_aes_operation_err;
  logic [       31:0] s_aes_bytes_in;
  logic [       31:0] s_aes_bytes_out;
  logic [       31:0] s_aes_cycles;
  logic [      127:0] s_aes_chain;

  logic [        8:0] s_sha_cfg_q;
  logic [       63:0] s_sha_len_q;
  logic               s_sha_start;
  logic               s_sha_abort;
  logic               s_sha_zeroize;
  logic               s_sha_input_valid;
  logic               s_sha_input_ready;
  logic [       31:0] s_sha_input_data;
  logic [        3:0] s_sha_input_keep;
  logic               s_sha_input_last;
  logic               s_sha_busy;
  logic               s_sha_done;
  logic               s_sha_operation_err;
  logic               s_sha_digest_valid;
  logic [      255:0] s_sha_digest;
  logic [       63:0] s_sha_bytes_in;
  logic [       31:0] s_sha_cycles;

  logic [       11:0] s_rsa_exponent_bits_q;
  logic [       31:0] s_rsa_modulus_q         [0:RsaWords-1];
  logic [       31:0] s_rsa_exponent_q        [0:RsaWords-1];
  logic [       31:0] s_rsa_base_q            [0:RsaWords-1];
  logic [RsaBits-1:0] s_rsa_modulus;
  logic [RsaBits-1:0] s_rsa_exponent;
  logic [RsaBits-1:0] s_rsa_base;
  logic [RsaBits-1:0] s_rsa_result;
  logic               s_rsa_prepare;
  logic               s_rsa_start;
  logic               s_rsa_private;
  logic               s_rsa_abort;
  logic               s_rsa_zeroize;
  logic               s_rsa_busy;
  logic               s_rsa_done;
  logic               s_rsa_operation_err;
  logic               s_rsa_prepared;
  logic               s_rsa_result_valid;
  logic               s_rsa_operand_dirty_q;
  logic               s_rsa_prepare_pending_q;
  logic [       31:0] s_rsa_cycles;
  logic [       31:0] s_rsa_progress;

  logic [        4:0] s_irq_state_q;
  logic [        4:0] s_irq_en_q;
  logic [        3:0] s_err_stat_q;
  logic [        4:0] s_irq_evt;
  logic [        4:0] s_irq_clear;
  logic [        4:0] s_irq_test;
  logic [        3:0] s_err_evt;
  logic [        3:0] s_err_clear;
  logic               s_zeroize;
  logic               s_aes_dma_active;
  logic               s_sha_dma_active;

  function automatic logic [31:0] merge_bytes(
      input logic [31:0] current_i, input logic [31:0] write_i, input logic [3:0] strobe_i);
    logic [31:0] result;

    result = current_i;
    for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
      if (strobe_i[byte_index]) begin
        result[(byte_index*8)+:8] = write_i[(byte_index*8)+:8];
      end
    end
    merge_bytes = result;
  endfunction

  function automatic logic [31:0] reverse_word_bytes(input logic [31:0] value_i);
    reverse_word_bytes = {value_i[7:0], value_i[15:8], value_i[23:16], value_i[31:24]};
  endfunction

  function automatic logic valid_keep(input logic [3:0] keep_i);
    valid_keep = (keep_i == 4'b0001) || (keep_i == 4'b0011) ||
                 (keep_i == 4'b0111) || (keep_i == 4'b1111);
  endfunction

  always_comb begin
    for (int unsigned word_index = 0; word_index < 8; word_index++) begin
      s_aes_key[255-word_index*32-:32] = reverse_word_bytes(s_aes_key_q[word_index]);
    end
    for (int unsigned word_index = 0; word_index < 4; word_index++) begin
      s_aes_iv[127-word_index*32-:32] = reverse_word_bytes(s_aes_iv_q[word_index]);
    end
    for (int unsigned word_index = 0; word_index < RsaWords; word_index++) begin
      s_rsa_modulus[word_index*32+:32]  = s_rsa_modulus_q[word_index];
      s_rsa_exponent[word_index*32+:32] = s_rsa_exponent_q[word_index];
      s_rsa_base[word_index*32+:32]     = s_rsa_base_q[word_index];
    end
  end

  assign s_access         = apb4.psel && apb4.penable;
  assign s_write          = s_access && apb4.pwrite;
  assign s_read           = s_access && !apb4.pwrite;
  assign s_offset         = apb4.paddr[11:0];
  assign s_aes_dma_active = s_aes_busy && s_aes_cfg_q[`APB4_CRYPTO__AES_CFG_DMA];
  assign s_sha_dma_active = s_sha_busy && s_sha_cfg_q[`APB4_CRYPTO__SHA_CFG_DMA];

  always_comb begin
    s_known_offset = (s_offset == `APB4_CRYPTO__IP_ID) ||
                     (s_offset == `APB4_CRYPTO__IP_VERSION) ||
                     (s_offset == `APB4_CRYPTO__CAPABILITY0) ||
                     (s_offset == `APB4_CRYPTO__CAPABILITY1) ||
                     (s_offset == `APB4_CRYPTO__COMMAND) ||
                     (s_offset == `APB4_CRYPTO__STATUS) ||
                     (s_offset == `APB4_CRYPTO__IRQ_STATE) ||
                     (s_offset == `APB4_CRYPTO__IRQ_ENABLE) ||
                     (s_offset == `APB4_CRYPTO__IRQ_TEST) ||
                     (s_offset == `APB4_CRYPTO__ERROR_STATUS) ||
                     ((s_offset >= `APB4_CRYPTO__AES_CTRL) &&
                      (s_offset <= `APB4_CRYPTO__AES_KEY_STATUS)) ||
                     ((s_offset >= `APB4_CRYPTO__AES_KEY_BASE) &&
                      (s_offset < (`APB4_CRYPTO__AES_KEY_BASE + 12'h020))) ||
                     ((s_offset >= `APB4_CRYPTO__AES_IV_BASE) &&
                      (s_offset < (`APB4_CRYPTO__AES_IV_BASE + 12'h010))) ||
                     ((s_offset >= `APB4_CRYPTO__AES_CHAIN_BASE) &&
                      (s_offset < (`APB4_CRYPTO__AES_CHAIN_BASE + 12'h010))) ||
                     ((s_offset >= `APB4_CRYPTO__SHA_CTRL) &&
                      (s_offset <= `APB4_CRYPTO__SHA_CYCLES)) ||
                     ((s_offset >= `APB4_CRYPTO__SHA_DIGEST_BASE) &&
                      (s_offset < (`APB4_CRYPTO__SHA_DIGEST_BASE + 12'h020))) ||
                     ((s_offset >= `APB4_CRYPTO__RSA_CTRL) &&
                      (s_offset <= `APB4_CRYPTO__RSA_PROGRESS)) ||
                     ((s_offset >= `APB4_CRYPTO__RSA_MODULUS_BASE) &&
                      (s_offset < (`APB4_CRYPTO__RSA_MODULUS_BASE + 12'h100))) ||
                     ((s_offset >= `APB4_CRYPTO__RSA_EXPONENT_BASE) &&
                      (s_offset < (`APB4_CRYPTO__RSA_EXPONENT_BASE + 12'h100))) ||
                     ((s_offset >= `APB4_CRYPTO__RSA_BASE_BASE) &&
                      (s_offset < (`APB4_CRYPTO__RSA_BASE_BASE + 12'h100))) ||
                     ((s_offset >= `APB4_CRYPTO__RSA_RESULT_BASE) &&
                      (s_offset < (`APB4_CRYPTO__RSA_RESULT_BASE + 12'h100)));

    s_read_only_offset = (s_offset == `APB4_CRYPTO__IP_ID) ||
                         (s_offset == `APB4_CRYPTO__IP_VERSION) ||
                         (s_offset == `APB4_CRYPTO__CAPABILITY0) ||
                         (s_offset == `APB4_CRYPTO__CAPABILITY1) ||
                         (s_offset == `APB4_CRYPTO__STATUS) ||
                         (s_offset == `APB4_CRYPTO__AES_STATUS) ||
                         (s_offset == `APB4_CRYPTO__AES_DATA_OUT) ||
                         (s_offset == `APB4_CRYPTO__AES_DATA_STATUS) ||
                         (s_offset == `APB4_CRYPTO__AES_BYTES_IN) ||
                         (s_offset == `APB4_CRYPTO__AES_BYTES_OUT) ||
                         (s_offset == `APB4_CRYPTO__AES_CYCLES) ||
                         (s_offset == `APB4_CRYPTO__AES_KEY_STATUS) ||
                         ((s_offset >= `APB4_CRYPTO__AES_CHAIN_BASE) &&
                          (s_offset < (`APB4_CRYPTO__AES_CHAIN_BASE + 12'h010))) ||
                         (s_offset == `APB4_CRYPTO__SHA_STATUS) ||
                         (s_offset == `APB4_CRYPTO__SHA_DATA_STATUS) ||
                         (s_offset == `APB4_CRYPTO__SHA_BYTES_IN_LO) ||
                         (s_offset == `APB4_CRYPTO__SHA_BYTES_IN_HI) ||
                         (s_offset == `APB4_CRYPTO__SHA_CYCLES) ||
                         ((s_offset >= `APB4_CRYPTO__SHA_DIGEST_BASE) &&
                          (s_offset < (`APB4_CRYPTO__SHA_DIGEST_BASE + 12'h020))) ||
                         (s_offset == `APB4_CRYPTO__RSA_STATUS) ||
                         (s_offset == `APB4_CRYPTO__RSA_CYCLES) ||
                         (s_offset == `APB4_CRYPTO__RSA_PROGRESS) ||
                         ((s_offset >= `APB4_CRYPTO__RSA_RESULT_BASE) &&
                          (s_offset < (`APB4_CRYPTO__RSA_RESULT_BASE + 12'h100)));
    s_secret_offset = ((s_offset >= `APB4_CRYPTO__AES_KEY_BASE) &&
                       (s_offset < (`APB4_CRYPTO__AES_KEY_BASE + 12'h020))) ||
                      ((s_offset >= `APB4_CRYPTO__RSA_EXPONENT_BASE) &&
                       (s_offset < (`APB4_CRYPTO__RSA_EXPONENT_BASE + 12'h100)));
  end

  always_comb begin
    s_access_err = s_access && (!s_known_offset || (s_offset[1:0] != 2'b00));
    if (s_write && ((s_offset == `APB4_CRYPTO__COMMAND) ||
                    (s_offset == `APB4_CRYPTO__IRQ_STATE) ||
                    (s_offset == `APB4_CRYPTO__IRQ_TEST) ||
                    (s_offset == `APB4_CRYPTO__ERROR_STATUS) ||
                    (s_offset == `APB4_CRYPTO__AES_CTRL) ||
                    (s_offset == `APB4_CRYPTO__AES_KEY_CTRL) ||
                    (s_offset == `APB4_CRYPTO__SHA_CTRL) ||
                    (s_offset == `APB4_CRYPTO__RSA_CTRL)) && !apb4.pstrb[0]) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_read_only_offset) begin
      s_access_err = 1'b1;
    end
    if (s_read && s_secret_offset) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_aes_busy || s_aes_key_busy) &&
        ((s_offset == `APB4_CRYPTO__AES_CFG) ||
         (s_offset == `APB4_CRYPTO__AES_LENGTH) ||
         (s_offset == `APB4_CRYPTO__AES_KEY_CTRL) ||
         ((s_offset >= `APB4_CRYPTO__AES_KEY_BASE) &&
          (s_offset < (`APB4_CRYPTO__AES_KEY_BASE + 12'h020))) ||
         ((s_offset >= `APB4_CRYPTO__AES_IV_BASE) &&
          (s_offset < (`APB4_CRYPTO__AES_IV_BASE + 12'h010))))) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_sha_busy &&
        ((s_offset == `APB4_CRYPTO__SHA_CFG) ||
         (s_offset == `APB4_CRYPTO__SHA_LENGTH_LO) ||
         (s_offset == `APB4_CRYPTO__SHA_LENGTH_HI))) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_rsa_busy &&
        ((s_offset == `APB4_CRYPTO__RSA_CFG) ||
         ((s_offset >= `APB4_CRYPTO__RSA_MODULUS_BASE) &&
          (s_offset < (`APB4_CRYPTO__RSA_BASE_BASE + 12'h100))))) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_CRYPTO__AES_DATA_IN) &&
        (s_aes_cfg_q[`APB4_CRYPTO__AES_CFG_DMA] || !s_aes_input_ready || !valid_keep(
            apb4.pstrb
        ))) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_CRYPTO__SHA_DATA_IN) &&
        (s_sha_cfg_q[`APB4_CRYPTO__SHA_CFG_DMA] || !s_sha_input_ready || !valid_keep(
            apb4.pstrb
        ))) begin
      s_access_err = 1'b1;
    end
    if (s_read && (s_offset == `APB4_CRYPTO__AES_DATA_OUT) &&
        (s_aes_cfg_q[`APB4_CRYPTO__AES_CFG_DMA] || !s_aes_output_valid)) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_CRYPTO__AES_CTRL) &&
        apb4.pwdata[`APB4_CRYPTO__AES_CTRL_START] &&
        (s_aes_busy || !s_aes_key_valid ||
         ((s_aes_cfg_q[1:0] != AES_MODE_CTR) && (s_aes_len_q[3:0] != 4'd0)) ||
         (s_aes_len_q == 32'd0) ||
         (s_aes_cfg_q[1:0] == 2'd3) ||
         (s_aes_cfg_q[`APB4_CRYPTO__AES_CFG_DMA] && s_sha_dma_active))) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_CRYPTO__AES_KEY_CTRL) &&
        apb4.pwdata[`APB4_CRYPTO__AES_KEY_CTRL_COMMIT] && (s_aes_cfg_q[5:4] == 2'd3)) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_CRYPTO__SHA_CTRL) &&
        apb4.pwdata[`APB4_CRYPTO__SHA_CTRL_START] &&
        (s_sha_busy || (s_sha_cfg_q[`APB4_CRYPTO__SHA_CFG_DMA] && s_aes_dma_active))) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_CRYPTO__RSA_CTRL) &&
        ((apb4.pwdata[2:0] == 3'b000) ||
         ((apb4.pwdata[2:0] & (apb4.pwdata[2:0] - 1'b1)) != 3'b000) || s_rsa_busy ||
         (apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PUBLIC] &&
          ((s_rsa_exponent_bits_q == 12'd0) || (s_rsa_exponent_bits_q > 12'd2048))) ||
         ((apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PUBLIC] ||
           apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PRIVATE]) &&
          (s_rsa_operand_dirty_q || !s_rsa_prepared)))) begin
      s_access_err = 1'b1;
    end
  end

  assign apb4.pready  = s_access;
  assign apb4.pslverr = s_access_err;
  assign apb4.prdata  = s_read_data;

  always_comb begin
    s_read_data = 32'd0;
    unique case (s_offset)
      `APB4_CRYPTO__IP_ID: s_read_data = IpId;
      `APB4_CRYPTO__IP_VERSION: s_read_data = IpVersion;
      `APB4_CRYPTO__CAPABILITY0: s_read_data = Capability0;
      `APB4_CRYPTO__CAPABILITY1: s_read_data = Capability1;
      `APB4_CRYPTO__STATUS:
      s_read_data = {
        22'd0,
        s_rsa_prepared && !s_rsa_operand_dirty_q,
        s_aes_key_valid,
        5'd0,
        s_rsa_busy,
        s_sha_busy,
        s_aes_busy || s_aes_key_busy
      };
      `APB4_CRYPTO__IRQ_STATE: s_read_data = {27'd0, s_irq_state_q};
      `APB4_CRYPTO__IRQ_ENABLE: s_read_data = {27'd0, s_irq_en_q};
      `APB4_CRYPTO__ERROR_STATUS: s_read_data = {28'd0, s_err_stat_q};
      `APB4_CRYPTO__AES_CFG: s_read_data = {23'd0, s_aes_cfg_q};
      `APB4_CRYPTO__AES_STATUS:
      s_read_data = {
        28'd0,
        s_aes_key_valid,
        s_aes_operation_err,
        s_irq_state_q[`APB4_CRYPTO__IRQ_AES_DONE],
        s_aes_busy || s_aes_key_busy
      };
      `APB4_CRYPTO__AES_LENGTH: s_read_data = s_aes_len_q;
      `APB4_CRYPTO__AES_DATA_OUT: s_read_data = s_aes_output_data;
      `APB4_CRYPTO__AES_DATA_STATUS:
      s_read_data = {29'd0, s_aes_output_last, s_aes_output_valid, s_aes_input_ready};
      `APB4_CRYPTO__AES_BYTES_IN: s_read_data = s_aes_bytes_in;
      `APB4_CRYPTO__AES_BYTES_OUT: s_read_data = s_aes_bytes_out;
      `APB4_CRYPTO__AES_CYCLES: s_read_data = s_aes_cycles;
      `APB4_CRYPTO__AES_KEY_STATUS: s_read_data = {30'd0, s_aes_key_busy, s_aes_key_valid};
      `APB4_CRYPTO__SHA_CFG: s_read_data = {23'd0, s_sha_cfg_q};
      `APB4_CRYPTO__SHA_STATUS:
      s_read_data = {
        28'd0,
        s_sha_digest_valid,
        s_sha_operation_err,
        s_irq_state_q[`APB4_CRYPTO__IRQ_SHA_DONE],
        s_sha_busy
      };
      `APB4_CRYPTO__SHA_LENGTH_LO: s_read_data = s_sha_len_q[31:0];
      `APB4_CRYPTO__SHA_LENGTH_HI: s_read_data = s_sha_len_q[63:32];
      `APB4_CRYPTO__SHA_DATA_STATUS: s_read_data = {30'd0, s_sha_digest_valid, s_sha_input_ready};
      `APB4_CRYPTO__SHA_BYTES_IN_LO: s_read_data = s_sha_bytes_in[31:0];
      `APB4_CRYPTO__SHA_BYTES_IN_HI: s_read_data = s_sha_bytes_in[63:32];
      `APB4_CRYPTO__SHA_CYCLES: s_read_data = s_sha_cycles;
      `APB4_CRYPTO__RSA_CFG: s_read_data = {20'd0, s_rsa_exponent_bits_q};
      `APB4_CRYPTO__RSA_STATUS:
      s_read_data = {
        27'd0,
        s_rsa_result_valid,
        s_rsa_prepared && !s_rsa_operand_dirty_q,
        s_rsa_operation_err,
        s_irq_state_q[`APB4_CRYPTO__IRQ_RSA_DONE],
        s_rsa_busy
      };
      `APB4_CRYPTO__RSA_CYCLES: s_read_data = s_rsa_cycles;
      `APB4_CRYPTO__RSA_PROGRESS: s_read_data = s_rsa_progress;
      default: begin
        if ((s_offset >= `APB4_CRYPTO__AES_IV_BASE) &&
            (s_offset < (`APB4_CRYPTO__AES_IV_BASE + 12'h010))) begin
          s_read_data = s_aes_iv_q[2'((s_offset-`APB4_CRYPTO__AES_IV_BASE)>>2)];
        end else if ((s_offset >= `APB4_CRYPTO__AES_CHAIN_BASE) &&
                     (s_offset < (`APB4_CRYPTO__AES_CHAIN_BASE + 12'h010))) begin
          s_read_data = reverse_word_bytes(
              s_aes_chain[127-((s_offset-`APB4_CRYPTO__AES_CHAIN_BASE)>>2)*32-:32]);
        end else if ((s_offset >= `APB4_CRYPTO__SHA_DIGEST_BASE) &&
                     (s_offset < (`APB4_CRYPTO__SHA_DIGEST_BASE + 12'h020))) begin
          s_read_data = s_sha_digest[255-((s_offset-`APB4_CRYPTO__SHA_DIGEST_BASE)>>2)*32-:32];
        end else if ((s_offset >= `APB4_CRYPTO__RSA_MODULUS_BASE) &&
                     (s_offset < (`APB4_CRYPTO__RSA_MODULUS_BASE + 12'h100))) begin
          s_read_data = s_rsa_modulus_q[6'((s_offset-`APB4_CRYPTO__RSA_MODULUS_BASE)>>2)];
        end else if ((s_offset >= `APB4_CRYPTO__RSA_BASE_BASE) &&
                     (s_offset < (`APB4_CRYPTO__RSA_BASE_BASE + 12'h100))) begin
          s_read_data = s_rsa_base_q[6'((s_offset-`APB4_CRYPTO__RSA_BASE_BASE)>>2)];
        end else if ((s_offset >= `APB4_CRYPTO__RSA_RESULT_BASE) &&
                     (s_offset < (`APB4_CRYPTO__RSA_RESULT_BASE + 12'h100))) begin
          s_read_data = s_rsa_result[((s_offset-`APB4_CRYPTO__RSA_RESULT_BASE)>>2)*32+:32];
        end
      end
    endcase
  end

  assign s_zeroize = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__COMMAND) &&
                     apb4.pwdata[`APB4_CRYPTO__COMMAND_ZEROIZE];
  assign s_aes_zeroize = s_zeroize;
  assign s_sha_zeroize = s_zeroize;
  assign s_rsa_zeroize = s_zeroize;
  assign s_aes_abort = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__COMMAND) &&
                       apb4.pwdata[`APB4_CRYPTO__COMMAND_ABORT_AES];
  assign s_sha_abort = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__COMMAND) &&
                       apb4.pwdata[`APB4_CRYPTO__COMMAND_ABORT_SHA];
  assign s_rsa_abort = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__COMMAND) &&
                       apb4.pwdata[`APB4_CRYPTO__COMMAND_ABORT_RSA];
  assign s_aes_start = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__AES_CTRL) &&
                       apb4.pwdata[`APB4_CRYPTO__AES_CTRL_START];
  assign s_aes_key_commit = s_write && !s_access_err &&
                            (s_offset == `APB4_CRYPTO__AES_KEY_CTRL) &&
                            apb4.pwdata[`APB4_CRYPTO__AES_KEY_CTRL_COMMIT];
  assign s_sha_start = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__SHA_CTRL) &&
                       apb4.pwdata[`APB4_CRYPTO__SHA_CTRL_START];
  assign s_rsa_prepare = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__RSA_CTRL) &&
                         apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PREPARE];
  assign s_rsa_start = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__RSA_CTRL) &&
                       (apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PUBLIC] ||
                        apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PRIVATE]);
  assign s_rsa_private = apb4.pwdata[`APB4_CRYPTO__RSA_CTRL_PRIVATE];

  always_comb begin
    s_aes_input_valid     = 1'b0;
    s_aes_input_data      = 32'd0;
    s_aes_input_keep      = 4'd0;
    s_aes_input_last      = 1'b0;
    s_sha_input_valid     = 1'b0;
    s_sha_input_data      = 32'd0;
    s_sha_input_keep      = 4'd0;
    s_sha_input_last      = 1'b0;
    crypto_in_axis.tready = 1'b0;
    if (s_aes_dma_active) begin
      s_aes_input_valid     = crypto_in_axis.tvalid;
      s_aes_input_data      = crypto_in_axis.tdata;
      s_aes_input_keep      = crypto_in_axis.tkeep;
      s_aes_input_last      = crypto_in_axis.tlast;
      crypto_in_axis.tready = s_aes_input_ready;
    end else if (s_sha_dma_active) begin
      s_sha_input_valid     = crypto_in_axis.tvalid;
      s_sha_input_data      = crypto_in_axis.tdata;
      s_sha_input_keep      = crypto_in_axis.tkeep;
      s_sha_input_last      = crypto_in_axis.tlast;
      crypto_in_axis.tready = s_sha_input_ready;
    end else begin
      s_aes_input_valid = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__AES_DATA_IN);
      s_aes_input_data  = apb4.pwdata;
      s_aes_input_keep  = apb4.pstrb;
      s_aes_input_last  = (s_aes_bytes_in + $countones(apb4.pstrb)) == s_aes_len_q;
      s_sha_input_valid = s_write && !s_access_err && (s_offset == `APB4_CRYPTO__SHA_DATA_IN);
      s_sha_input_data  = apb4.pwdata;
      s_sha_input_keep  = apb4.pstrb;
      s_sha_input_last  = (s_sha_bytes_in + $countones(apb4.pstrb)) == s_sha_len_q;
    end
  end

  assign s_aes_output_ready = s_aes_dma_active ? crypto_out_axis.tready :
                              (s_read && !s_access_err &&
                               (s_offset == `APB4_CRYPTO__AES_DATA_OUT));
  assign crypto_out_axis.tdata = s_aes_output_data;
  assign crypto_out_axis.tkeep = s_aes_output_keep;
  assign crypto_out_axis.tstrb = s_aes_output_keep;
  assign crypto_out_axis.tlast = s_aes_output_last;
  assign crypto_out_axis.tid = '0;
  assign crypto_out_axis.tdest = '0;
  assign crypto_out_axis.tuser = '0;
  assign crypto_out_axis.tvalid = s_aes_dma_active && s_aes_output_valid;
  assign dma_input_proc_o = crypto_in_axis.tready;
  assign dma_output_proc_o = crypto_out_axis.tvalid;

  always_comb begin
    s_irq_clear = 5'd0;
    s_irq_test  = 5'd0;
    s_err_clear = 4'd0;
    if (s_write && !s_access_err && apb4.pstrb[0]) begin
      if (s_offset == `APB4_CRYPTO__IRQ_STATE) begin
        s_irq_clear = apb4.pwdata[4:0];
      end
      if (s_offset == `APB4_CRYPTO__IRQ_TEST) begin
        s_irq_test = apb4.pwdata[4:0];
      end
      if (s_offset == `APB4_CRYPTO__ERROR_STATUS) begin
        s_err_clear = apb4.pwdata[3:0];
      end
    end
    if (s_aes_start) begin
      s_irq_clear[`APB4_CRYPTO__IRQ_AES_DONE] = 1'b1;
    end
    if (s_sha_start) begin
      s_irq_clear[`APB4_CRYPTO__IRQ_SHA_DONE] = 1'b1;
    end
    if (s_rsa_prepare || s_rsa_start) begin
      s_irq_clear[`APB4_CRYPTO__IRQ_RSA_DONE] = 1'b1;
    end
    s_err_evt = {
      s_access_err,
      s_rsa_done && s_rsa_operation_err,
      s_sha_done && s_sha_operation_err,
      s_aes_done && s_aes_operation_err
    };
    s_irq_evt = {s_zeroize, |s_err_evt, s_rsa_done, s_sha_done, s_aes_done};
  end

  assign irq_o = |(s_irq_state_q & s_irq_en_q);

  crypto_aes_engine u_crypto_aes_engine (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .zeroize_i     (s_aes_zeroize),
      .abort_i       (s_aes_abort),
      .key_commit_i  (s_aes_key_commit),
      .key_size_i    (s_aes_cfg_q[5:4]),
      .key_i         (s_aes_key),
      .key_valid_o   (s_aes_key_valid),
      .key_busy_o    (s_aes_key_busy),
      .start_i       (s_aes_start),
      .mode_i        (s_aes_cfg_q[1:0]),
      .decrypt_i     (s_aes_cfg_q[`APB4_CRYPTO__AES_CFG_DECRYPT]),
      .length_i      (s_aes_len_q),
      .iv_i          (s_aes_iv),
      .input_valid_i (s_aes_input_valid),
      .input_ready_o (s_aes_input_ready),
      .input_data_i  (s_aes_input_data),
      .input_keep_i  (s_aes_input_keep),
      .input_last_i  (s_aes_input_last),
      .output_valid_o(s_aes_output_valid),
      .output_ready_i(s_aes_output_ready),
      .output_data_o (s_aes_output_data),
      .output_keep_o (s_aes_output_keep),
      .output_last_o (s_aes_output_last),
      .busy_o        (s_aes_busy),
      .done_o        (s_aes_done),
      .error_o       (s_aes_operation_err),
      .bytes_in_o    (s_aes_bytes_in),
      .bytes_out_o   (s_aes_bytes_out),
      .cycles_o      (s_aes_cycles),
      .chain_o       (s_aes_chain)
  );

  crypto_sha2_engine u_crypto_sha2_engine (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .zeroize_i     (s_sha_zeroize),
      .abort_i       (s_sha_abort),
      .start_i       (s_sha_start),
      .sha256_i      (s_sha_cfg_q[`APB4_CRYPTO__SHA_CFG_SHA256]),
      .length_i      (s_sha_len_q),
      .input_valid_i (s_sha_input_valid),
      .input_ready_o (s_sha_input_ready),
      .input_data_i  (s_sha_input_data),
      .input_keep_i  (s_sha_input_keep),
      .input_last_i  (s_sha_input_last),
      .busy_o        (s_sha_busy),
      .done_o        (s_sha_done),
      .error_o       (s_sha_operation_err),
      .digest_valid_o(s_sha_digest_valid),
      .digest_o      (s_sha_digest),
      .bytes_in_o    (s_sha_bytes_in),
      .cycles_o      (s_sha_cycles)
  );

  crypto_rsa_core #(
      .Bits(RsaBits)
  ) u_crypto_rsa_core (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .zeroize_i      (s_rsa_zeroize),
      .abort_i        (s_rsa_abort),
      .prepare_i      (s_rsa_prepare),
      .start_i        (s_rsa_start),
      .private_i      (s_rsa_private),
      .exponent_bits_i(s_rsa_exponent_bits_q),
      .modulus_i      (s_rsa_modulus),
      .exponent_i     (s_rsa_exponent),
      .base_i         (s_rsa_base),
      .busy_o         (s_rsa_busy),
      .done_o         (s_rsa_done),
      .error_o        (s_rsa_operation_err),
      .prepared_o     (s_rsa_prepared),
      .result_valid_o (s_rsa_result_valid),
      .result_o       (s_rsa_result),
      .cycles_o       (s_rsa_cycles),
      .progress_o     (s_rsa_progress)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_aes_cfg_q             <= '0;
      s_aes_len_q             <= '0;
      s_sha_cfg_q             <= 9'd1;
      s_sha_len_q             <= '0;
      s_rsa_exponent_bits_q   <= 12'd17;
      s_rsa_operand_dirty_q   <= 1'b1;
      s_rsa_prepare_pending_q <= 1'b0;
      s_irq_state_q           <= '0;
      s_irq_en_q              <= '0;
      s_err_stat_q            <= '0;
      for (int unsigned word_index = 0; word_index < 8; word_index++) begin
        s_aes_key_q[word_index] <= '0;
      end
      for (int unsigned word_index = 0; word_index < 4; word_index++) begin
        s_aes_iv_q[word_index] <= '0;
      end
      for (int unsigned word_index = 0; word_index < RsaWords; word_index++) begin
        s_rsa_modulus_q[word_index]  <= '0;
        s_rsa_exponent_q[word_index] <= '0;
        s_rsa_base_q[word_index]     <= '0;
      end
    end else begin
      s_irq_state_q <= (s_irq_state_q & ~s_irq_clear) | s_irq_test | s_irq_evt;
      s_err_stat_q  <= (s_err_stat_q & ~s_err_clear) | s_err_evt;

      if (s_rsa_prepare) begin
        s_rsa_prepare_pending_q <= 1'b1;
      end
      if (s_rsa_done && s_rsa_prepare_pending_q) begin
        s_rsa_prepare_pending_q <= 1'b0;
        if (!s_rsa_operation_err) begin
          s_rsa_operand_dirty_q <= 1'b0;
        end
      end
      if (s_zeroize) begin
        s_aes_cfg_q             <= '0;
        s_aes_len_q             <= '0;
        s_sha_cfg_q             <= 9'd1;
        s_sha_len_q             <= '0;
        s_rsa_exponent_bits_q   <= 12'd17;
        s_rsa_operand_dirty_q   <= 1'b1;
        s_rsa_prepare_pending_q <= 1'b0;
        for (int unsigned word_index = 0; word_index < 8; word_index++) begin
          s_aes_key_q[word_index] <= '0;
        end
        for (int unsigned word_index = 0; word_index < 4; word_index++) begin
          s_aes_iv_q[word_index] <= '0;
        end
        for (int unsigned word_index = 0; word_index < RsaWords; word_index++) begin
          s_rsa_modulus_q[word_index]  <= '0;
          s_rsa_exponent_q[word_index] <= '0;
          s_rsa_base_q[word_index]     <= '0;
        end
      end else if (s_write && !s_access_err) begin
        unique case (s_offset)
          `APB4_CRYPTO__AES_CFG:
          s_aes_cfg_q <= 9'(merge_bytes({23'd0, s_aes_cfg_q}, apb4.pwdata, apb4.pstrb));
          `APB4_CRYPTO__AES_LENGTH:
          s_aes_len_q <= merge_bytes(s_aes_len_q, apb4.pwdata, apb4.pstrb);
          `APB4_CRYPTO__SHA_CFG:
          s_sha_cfg_q <= 9'(merge_bytes({23'd0, s_sha_cfg_q}, apb4.pwdata, apb4.pstrb));
          `APB4_CRYPTO__SHA_LENGTH_LO:
          s_sha_len_q[31:0] <= merge_bytes(s_sha_len_q[31:0], apb4.pwdata, apb4.pstrb);
          `APB4_CRYPTO__SHA_LENGTH_HI:
          s_sha_len_q[63:32] <= merge_bytes(s_sha_len_q[63:32], apb4.pwdata, apb4.pstrb);
          `APB4_CRYPTO__RSA_CFG:
          s_rsa_exponent_bits_q <= 12'(merge_bytes(
              {20'd0, s_rsa_exponent_bits_q}, apb4.pwdata, apb4.pstrb
          ));
          `APB4_CRYPTO__IRQ_ENABLE:
          s_irq_en_q <= 5'(merge_bytes({27'd0, s_irq_en_q}, apb4.pwdata, apb4.pstrb));
          default: begin
            if ((s_offset >= `APB4_CRYPTO__AES_KEY_BASE) &&
                (s_offset < (`APB4_CRYPTO__AES_KEY_BASE + 12'h020))) begin
              s_aes_key_q[3'((s_offset-`APB4_CRYPTO__AES_KEY_BASE)>>2)] <=
                  merge_bytes(s_aes_key_q[3'((s_offset-`APB4_CRYPTO__AES_KEY_BASE)>>2)],
                              apb4.pwdata, apb4.pstrb);
            end else if ((s_offset >= `APB4_CRYPTO__AES_IV_BASE) &&
                         (s_offset < (`APB4_CRYPTO__AES_IV_BASE + 12'h010))) begin
              s_aes_iv_q[2'((s_offset-`APB4_CRYPTO__AES_IV_BASE)>>2)] <= merge_bytes(
                  s_aes_iv_q[2'((s_offset-`APB4_CRYPTO__AES_IV_BASE)>>2)], apb4.pwdata, apb4.pstrb);
            end else if ((s_offset >= `APB4_CRYPTO__RSA_MODULUS_BASE) &&
                         (s_offset < (`APB4_CRYPTO__RSA_MODULUS_BASE + 12'h100))) begin
              s_rsa_modulus_q[6'((s_offset-`APB4_CRYPTO__RSA_MODULUS_BASE)>>2)] <= merge_bytes(
                  s_rsa_modulus_q[6'((s_offset-`APB4_CRYPTO__RSA_MODULUS_BASE)>>2)],
                  apb4.pwdata,
                  apb4.pstrb
              );
              s_rsa_operand_dirty_q <= 1'b1;
            end else if ((s_offset >= `APB4_CRYPTO__RSA_EXPONENT_BASE) &&
                         (s_offset < (`APB4_CRYPTO__RSA_EXPONENT_BASE + 12'h100))) begin
              s_rsa_exponent_q[6'((s_offset-`APB4_CRYPTO__RSA_EXPONENT_BASE)>>2)] <= merge_bytes(
                  s_rsa_exponent_q[6'((s_offset-`APB4_CRYPTO__RSA_EXPONENT_BASE)>>2)],
                  apb4.pwdata,
                  apb4.pstrb
              );
            end else if ((s_offset >= `APB4_CRYPTO__RSA_BASE_BASE) &&
                         (s_offset < (`APB4_CRYPTO__RSA_BASE_BASE + 12'h100))) begin
              s_rsa_base_q[6'((s_offset-`APB4_CRYPTO__RSA_BASE_BASE)>>2)] <= merge_bytes(
                  s_rsa_base_q[6'((s_offset-`APB4_CRYPTO__RSA_BASE_BASE)>>2)],
                  apb4.pwdata,
                  apb4.pstrb
              );
            end
          end
        endcase
      end
    end
  end
endmodule
