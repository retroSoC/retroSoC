// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "crypto_define.svh"
module apb4_crypto #(
    parameter int         ResponseDelay     = 0,
    parameter logic [5:0] DropResponseMask  = 6'd0,
    parameter bit         DuplicateResponse = 1'b0
) (
    input  logic                 clk_i,
    rst_n_i,
    output logic                 dma_input_proc_o,
    dma_output_proc_o,
    irq_o,
           apb4_if.slave         apb4,
           axi4_stream_if.sink   crypto_in_axis,
           axi4_stream_if.source crypto_out_axis
);
  import crypto_mem_pkg::*;
  typedef enum logic [1:0] {
    ApbIdle,
    ApbAccess,
    ApbReadWait
  } apb_state_e;
  typedef struct packed {
    apb_state_e  state;
    logic [11:0] offset;
    logic        write;
    logic [31:0] data;
    logic [3:0]  mask;
    logic [8:0]  aes_cfg,        sha_cfg;
    logic [31:0] aes_length;
    logic [63:0] sha_length;
    logic [11:0] exponent_bits;
    logic [5:0]  irq_state,      irq_enable;
    logic [4:0]  errors;
    logic [2:0]  previous_error;
  } apb_registers_t;
  localparam apb_registers_t ResetValue = {
    ApbIdle, 12'd0, 1'b0, 32'd0, 4'd0, 9'd0, 9'd1, 32'd0, 64'd0, 12'd17, 6'd0, 6'd0, 5'd0, 3'd0
  };
  apb_registers_t s_regs_d, s_regs_q;
  logic [11:0] s_offset;
  logic [31:0] s_wdata;
  logic [ 3:0] s_strb;
  assign s_offset = s_regs_q.offset;
  assign s_wdata  = s_regs_q.data;
  assign s_strb   = s_regs_q.mask;
  crypto_mem_req_t [5:0] s_engine_req, s_maintenance_req, s_store_req;
  crypto_mem_resp_t [5:0] s_store_resp, s_engine_resp, s_maintenance_resp;
  logic [ 6:0] s_mem_stat;
  logic [11:0] s_table_words;
  logic [31:0] s_table_crc, s_mem_err, s_mem_cycles;
  logic s_mem_begin, s_mem_commit, s_mem_cancel, s_table_write;
  logic s_mem_cmd_err, s_mem_data_err, s_mem_clear, s_zeroize, s_engine_clear;
  logic s_memory_ready_evt, s_zeroized_evt, s_memory_err_evt;
  logic [2:0] s_busy, s_done, s_operation_err, s_abort, s_start, s_command;
  logic [11:0] s_epoch_d, s_epoch_q;
  logic [5:0] s_engine_pending_d, s_engine_pending_q;
  logic [23:0] s_token_d, s_token_q, s_pending_token_d, s_pending_token_q;
  logic [2:0]      s_scrub_err;
  logic [2:0][9:0] s_scrub_err_row;
  logic [2:0]      s_rsa_scrub_bank;
  logic [1:0] s_fifo_busy, s_fifo_err;
  logic s_aes_key_valid, s_aes_key_busy, s_key_commit, s_key_dirty;
  logic s_sha_digest_valid, s_rsa_prepared, s_rsa_result_valid, s_modulus_dirty;
  logic s_aes_input_ready, s_sha_input_ready, s_aes_output_valid, s_aes_output_ready;
  logic s_aes_input_valid, s_sha_input_valid, s_aes_input_last, s_sha_input_last;
  logic [ 9:0] s_local_err_row;
  logic [ 2:0] s_local_err_bank;
  logic [31:0] s_aes_output_data;
  logic [ 3:0] s_aes_output_keep;
  logic        s_aes_output_last;
  logic [31:0]
      s_aes_bytes_in, s_aes_bytes_out, s_aes_cycles, s_sha_cycles, s_rsa_cycles, s_rsa_progress;
  logic [63:0] s_sha_bytes_in;
  logic s_aes_dma_active, s_sha_dma_active, s_maintenance_busy;
  logic s_req, s_req_accept, s_write_accept, s_read_accept, s_access_err, s_decode_err;
  logic s_read_only, s_write_only, s_known, s_control, s_engine_control;
  logic s_bank_access, s_bank_zero, s_bank_reverse, s_bank_secret, s_bank_busy;
  logic [2:0] s_bank;
  logic [9:0] s_row;
  logic [31:0] s_read_data, s_merged;
  logic [5:0] s_irq_evt;
  logic [4:0] s_err_evt;
  logic [2:0] s_pio_bytes;

  function automatic logic [31:0] merge_bytes(input logic [31:0] previous, input logic [31:0] value,
                                              input logic [3:0] mask);
    logic [31:0] result;
    result = previous;
    for (int unsigned lane = 0; lane < 4; lane++)
    if (mask[lane]) result[lane*8+:8] = value[lane*8+:8];
    return result;
  endfunction
  function automatic logic [2:0] count_keep(input logic [3:0] keep);
    unique case (keep)
      4'h1:    return 3'd1;
      4'h3:    return 3'd2;
      4'h7:    return 3'd3;
      4'hf:    return 3'd4;
      default: return 3'd0;
    endcase
  endfunction

  dffrc #(
      .DATA_WIDTH($bits(apb_registers_t)),
      .RESET_VAL (ResetValue)
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_epoch (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_epoch_d),
      .dat_o  (s_epoch_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_engine_pending (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_engine_pending_d),
      .dat_o  (s_engine_pending_q)
  );
  dffr #(
      .DATA_WIDTH(24)
  ) u_token (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_token_d),
      .dat_o  (s_token_q)
  );
  dffr #(
      .DATA_WIDTH(24)
  ) u_pending_token (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pending_token_d),
      .dat_o  (s_pending_token_q)
  );
  assign s_maintenance_busy = |s_mem_stat[4:2];
  assign s_engine_clear = s_mem_clear || s_mem_stat[6];
  assign s_aes_dma_active = s_busy[0] && !s_aes_key_busy && s_regs_q.aes_cfg[8];
  assign s_sha_dma_active = s_busy[1] && s_regs_q.sha_cfg[8];
  assign s_req = apb4.psel && apb4.penable && (s_regs_q.state != ApbIdle);
  assign s_req_accept = s_req && apb4.pready;
  assign s_write_accept = s_req_accept && s_regs_q.write && !s_access_err;
  assign s_read_accept = s_req_accept && !s_regs_q.write && !s_access_err;
  assign s_pio_bytes = count_keep(s_strb);
  assign s_zeroize = s_write_accept && s_offset == `APB4_CRYPTO__COMMAND && s_wdata[0];
  // COMMAND has no wait states. Decode its abort pulse independently of the
  // data-port readiness checks: an abort itself suppresses input readiness.
  assign s_abort = (s_req && s_regs_q.write && s_strb[0] && s_offset == `APB4_CRYPTO__COMMAND &&
                    !s_wdata[0] && !(|s_wdata[31:4])) ? s_wdata[3:1] : 3'd0;
  assign s_start[0] = s_write_accept && s_offset == `APB4_CRYPTO__AES_CTRL && s_wdata[0];
  assign s_start[1] = s_write_accept && s_offset == `APB4_CRYPTO__SHA_CTRL && s_wdata[0];
  assign s_start[2] = s_write_accept && s_offset == `APB4_CRYPTO__RSA_CTRL && (|s_wdata[2:1]);
  assign s_command = {s_write_accept && s_offset == `APB4_CRYPTO__RSA_CTRL, s_start[1:0]};
  assign s_key_commit = s_write_accept && s_offset == `APB4_CRYPTO__AES_KEY_CTRL && s_wdata[0];
  assign s_key_dirty = s_write_accept && s_bank_access && s_bank == 3'd2 && s_row < 10'd8;
  assign s_modulus_dirty = s_write_accept && s_bank_access && s_bank == 3'd4 && s_row < 10'd64;

  // Loader attempts reach the controller on the completing access even when
  // CRC/count/padding reject the attempt. Malformed APB writes never reach it.
  assign s_mem_begin = s_req && !s_decode_err && s_regs_q.write &&
      s_offset == `APB4_CRYPTO__MEM_CONTROL && s_wdata[0];
  assign s_mem_commit = s_req && !s_decode_err && s_regs_q.write &&
      s_offset == `APB4_CRYPTO__MEM_CONTROL && s_wdata[1];
  assign s_mem_cancel = s_req && !s_decode_err && s_regs_q.write &&
      s_offset == `APB4_CRYPTO__MEM_CONTROL && s_wdata[2];
  assign s_table_write = s_req && !s_decode_err && s_regs_q.write &&
      s_offset == `APB4_CRYPTO__TABLE_DATA;
  assign s_aes_input_valid = s_aes_dma_active ? crypto_in_axis.tvalid :
      s_write_accept && s_offset == `APB4_CRYPTO__AES_DATA_IN;
  assign s_aes_input_last = s_aes_dma_active ?
      crypto_in_axis.tlast : (s_aes_bytes_in + 32'(s_pio_bytes)) == s_regs_q.aes_length;
  assign s_sha_input_valid = s_sha_dma_active ? crypto_in_axis.tvalid :
      s_write_accept && s_offset == `APB4_CRYPTO__SHA_DATA_IN;
  assign s_sha_input_last = s_sha_dma_active ?
      crypto_in_axis.tlast : (s_sha_bytes_in + 64'(s_pio_bytes)) == s_regs_q.sha_length;
  assign s_local_err_row = s_scrub_err[0] ? s_scrub_err_row[0] :
      s_scrub_err[1] ? s_scrub_err_row[1] : s_scrub_err[2] ? s_scrub_err_row[2] : 10'd0;
  // FIFO-only failures have no physical SRAM bank/row address.
  assign s_local_err_bank = s_scrub_err[0] ? 3'd2 : s_scrub_err[1] ? 3'd3 :
      s_scrub_err[2] ? s_rsa_scrub_bank : 3'd0;
  crypto_mem_ctrl u_memory_ctrl (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .begin_i           (s_mem_begin),
      .commit_i          (s_mem_commit),
      .cancel_i          (s_mem_cancel),
      .table_write_i     (s_table_write),
      .table_data_i      (s_wdata),
      .zeroize_i         (s_zeroize),
      .error_clear_i     (s_write_accept && s_offset == `APB4_CRYPTO__ERROR_STATUS && s_wdata[4]),
      .engines_busy_i    (|s_busy),
      .fifo_busy_i       (|s_fifo_busy),
      .fifo_error_i      (|s_fifo_err),
      .local_error_i     ((|s_scrub_err) || ((|s_fifo_err) && !s_maintenance_busy)),
      .local_error_bank_i(s_local_err_bank),
      .local_error_row_i (s_local_err_row),
      .command_error_o   (s_mem_cmd_err),
      .data_error_o      (s_mem_data_err),
      .clear_o           (s_mem_clear),
      .status_o          (s_mem_stat),
      .words_o           (s_table_words),
      .crc_o             (s_table_crc),
      .error_o           (s_mem_err),
      .cycles_o          (s_mem_cycles),
      .ready_event_o     (s_memory_ready_evt),
      .zeroized_event_o  (s_zeroized_evt),
      .error_event_o     (s_memory_err_evt),
      .req_o             (s_maintenance_req),
      .resp_i            (s_maintenance_resp)
  );
  crypto_sram_store #(
      .ResponseDelay    (ResponseDelay),
      .DropResponseMask (DropResponseMask),
      .DuplicateResponse(DuplicateResponse)
  ) u_storage (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .req_i  (s_store_req),
      .resp_o (s_store_resp)
  );
  always_comb begin
    s_store_req        = '0;
    s_engine_resp      = '0;
    s_maintenance_resp = '0;
    for (int unsigned bank = 0; bank < 6; bank++) begin
      if (s_mem_stat[0]) begin
        s_store_req[bank] = s_engine_req[bank];
        if (bank < 2) s_store_req[bank].epoch = s_epoch_q[3:0];
        else if (bank < 4) s_store_req[bank].epoch = s_epoch_q[7:4];
        else s_store_req[bank].epoch = s_epoch_q[11:8];
        if (s_engine_pending_q[bank]) s_store_req[bank].token = s_pending_token_q[bank*4+:4];
        else s_store_req[bank].token = s_token_q[bank*4+:4];
      end
      if (s_maintenance_req[bank].valid) begin
        s_store_req[bank]     = s_maintenance_req[bank];
        s_store_req[bank].tag = 2'd1;
      end
      if (s_store_resp[bank].valid && (s_store_resp[bank].tag == 2'd0) &&
          s_engine_pending_q[bank] &&
          ((bank < 2 && s_store_resp[bank].epoch == s_epoch_q[3:0]) ||
           (bank >= 2 && bank < 4 && s_store_resp[bank].epoch == s_epoch_q[7:4]) ||
           (bank >= 4 && s_store_resp[bank].epoch == s_epoch_q[11:8])) &&
          s_store_resp[bank].token == s_pending_token_q[bank*4+:4])
        s_engine_resp[bank] = s_store_resp[bank];
      if (s_store_resp[bank].tag == 2'd1) s_maintenance_resp[bank] = s_store_resp[bank];
    end
    if (s_req && (s_regs_q.state == ApbAccess) && s_bank_access && !s_bank_zero &&
        !s_access_err) begin
      s_store_req[s_bank]       = mem_read(s_row);
      s_store_req[s_bank].tag   = 2'd2;
      s_store_req[s_bank].write = s_regs_q.write;
      s_store_req[s_bank].data  = s_wdata;
      s_store_req[s_bank].mask  = s_strb;
    end
  end

  crypto_aes_sram_engine u_aes (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .zeroize_i        (s_mem_clear),
      .fault_i          (s_mem_stat[6]),
      .abort_i          (s_abort[0]),
      .key_commit_i     (s_key_commit),
      .key_dirty_i      (s_key_dirty),
      .key_size_i       (s_regs_q.aes_cfg[5:4]),
      .key_valid_o      (s_aes_key_valid),
      .key_busy_o       (s_aes_key_busy),
      .start_i          (s_start[0]),
      .mode_i           (s_regs_q.aes_cfg[1:0]),
      .decrypt_i        (s_regs_q.aes_cfg[2]),
      .length_i         (s_regs_q.aes_length),
      .input_valid_i    (s_aes_input_valid),
      .input_ready_o    (s_aes_input_ready),
      .input_data_i     (s_aes_dma_active ? crypto_in_axis.tdata : s_wdata),
      .input_keep_i     (s_aes_dma_active ? crypto_in_axis.tkeep : s_strb),
      .input_last_i     (s_aes_input_last),
      .output_valid_o   (s_aes_output_valid),
      .output_ready_i   (s_aes_output_ready),
      .output_data_o    (s_aes_output_data),
      .output_keep_o    (s_aes_output_keep),
      .output_last_o    (s_aes_output_last),
      .busy_o           (s_busy[0]),
      .done_o           (s_done[0]),
      .error_o          (s_operation_err[0]),
      .bytes_in_o       (s_aes_bytes_in),
      .bytes_out_o      (s_aes_bytes_out),
      .cycles_o         (s_aes_cycles),
      .fifo_busy_o      (s_fifo_busy[0]),
      .fifo_error_o     (s_fifo_err[0]),
      .scrub_error_o    (s_scrub_err[0]),
      .scrub_error_row_o(s_scrub_err_row[0]),
      .constant_req_o   (s_engine_req[0]),
      .constant_resp_i  (s_engine_resp[0]),
      .work_req_o       (s_engine_req[2]),
      .work_resp_i      (s_engine_resp[2])
  );
  crypto_sha2_sram_engine u_sha (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .zeroize_i        (s_engine_clear),
      .abort_i          (s_abort[1]),
      .start_i          (s_start[1]),
      .sha256_i         (s_regs_q.sha_cfg[0]),
      .length_i         (s_regs_q.sha_length),
      .input_valid_i    (s_sha_input_valid),
      .input_ready_o    (s_sha_input_ready),
      .input_data_i     (s_sha_dma_active ? crypto_in_axis.tdata : s_wdata),
      .input_keep_i     (s_sha_dma_active ? crypto_in_axis.tkeep : s_strb),
      .input_last_i     (s_sha_input_last),
      .busy_o           (s_busy[1]),
      .done_o           (s_done[1]),
      .error_o          (s_operation_err[1]),
      .digest_valid_o   (s_sha_digest_valid),
      .bytes_in_o       (s_sha_bytes_in),
      .cycles_o         (s_sha_cycles),
      .fifo_busy_o      (s_fifo_busy[1]),
      .fifo_error_o     (s_fifo_err[1]),
      .scrub_error_o    (s_scrub_err[1]),
      .scrub_error_row_o(s_scrub_err_row[1]),
      .constant_req_o   (s_engine_req[1]),
      .constant_resp_i  (s_engine_resp[1]),
      .work_req_o       (s_engine_req[3]),
      .work_resp_i      (s_engine_resp[3])
  );
  crypto_rsa_sram_core u_rsa (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .zeroize_i         (s_engine_clear),
      .abort_i           (s_abort[2]),
      .modulus_dirty_i   (s_modulus_dirty),
      .prepare_i         (s_write_accept && s_offset == `APB4_CRYPTO__RSA_CTRL && s_wdata[0]),
      .start_i           (s_start[2]),
      .private_i         (s_wdata[2]),
      .exponent_bits_i   (s_regs_q.exponent_bits),
      .busy_o            (s_busy[2]),
      .done_o            (s_done[2]),
      .error_o           (s_operation_err[2]),
      .prepared_o        (s_rsa_prepared),
      .result_valid_o    (s_rsa_result_valid),
      .cycles_o          (s_rsa_cycles),
      .progress_o        (s_rsa_progress),
      .scrub_error_o     (s_scrub_err[2]),
      .scrub_error_bank_o(s_rsa_scrub_bank),
      .scrub_error_row_o (s_scrub_err_row[2]),
      .retained_req_o    (s_engine_req[4]),
      .retained_resp_i   (s_engine_resp[4]),
      .work_req_o        (s_engine_req[5]),
      .work_resp_i       (s_engine_resp[5])
  );
  assign crypto_in_axis.tready = s_aes_dma_active ? s_aes_input_ready :
      s_sha_dma_active ? s_sha_input_ready : 1'b0;
  assign crypto_out_axis.tvalid = s_aes_dma_active && s_aes_output_valid;
  assign crypto_out_axis.tdata = s_aes_output_data;
  assign crypto_out_axis.tkeep = s_aes_output_keep;
  assign crypto_out_axis.tlast = s_aes_output_last;
  assign crypto_out_axis.tstrb = s_aes_output_keep;
  assign crypto_out_axis.tid = '0;
  assign crypto_out_axis.tdest = '0;
  assign crypto_out_axis.tuser = '0;
  assign s_aes_output_ready = s_aes_dma_active ? crypto_out_axis.tready :
      s_read_accept && s_offset == `APB4_CRYPTO__AES_DATA_OUT;
  assign dma_input_proc_o = crypto_in_axis.tready;
  assign dma_output_proc_o = crypto_out_axis.tvalid;
  assign irq_o = |(s_regs_q.irq_state & s_regs_q.irq_enable);

  always_comb begin
    s_known          = 1'b1;
    s_read_only      = 1'b1;
    s_write_only     = 1'b0;
    s_control        = 1'b0;
    s_engine_control = 1'b0;
    s_bank_access    = 1'b0;
    s_bank_zero      = 1'b0;
    s_bank_secret    = 1'b0;
    s_bank_reverse   = 1'b0;
    s_bank_busy      = 1'b0;
    s_bank           = '0;
    s_row            = '0;
    s_read_data      = '0;
    unique case (s_offset)
      `APB4_CRYPTO__IP_ID: s_read_data = `APB4_CRYPTO__IP_ID_VALUE;
      `APB4_CRYPTO__IP_VERSION: s_read_data = `APB4_CRYPTO__IP_VERSION_VALUE;
`ifdef HAVE_SRAM_MACRO
      `APB4_CRYPTO__CAPABILITY0: s_read_data = 32'h03ffffff;
`else
      `APB4_CRYPTO__CAPABILITY0: s_read_data = 32'h01ffffff;
`endif
      `APB4_CRYPTO__CAPABILITY1: s_read_data = 32'h08002020;
      `APB4_CRYPTO__STATUS:
      s_read_data = {
        22'd0, s_rsa_prepared, s_aes_key_valid, 3'd0, s_mem_stat[0], s_maintenance_busy, s_busy
      };
      `APB4_CRYPTO__MEM_STATUS: s_read_data = {25'd0, s_mem_stat};
      `APB4_CRYPTO__TABLE_ID: s_read_data = `APB4_CRYPTO__TABLE_ID_VALUE;
      `APB4_CRYPTO__TABLE_WORDS: s_read_data = {20'd0, s_table_words};
      `APB4_CRYPTO__TABLE_CRC: s_read_data = s_table_crc;
      `APB4_CRYPTO__MEM_ERROR: s_read_data = s_mem_err;
      `APB4_CRYPTO__MEM_CYCLES: s_read_data = s_mem_cycles;
      `APB4_CRYPTO__IRQ_STATE: begin
        s_read_data = {26'd0, s_regs_q.irq_state};
        s_read_only = 1'b0;
        s_control   = 1'b1;
      end
      `APB4_CRYPTO__IRQ_ENABLE: begin
        s_read_data = {26'd0, s_regs_q.irq_enable};
        s_read_only = 1'b0;
      end
      `APB4_CRYPTO__ERROR_STATUS: begin
        s_read_data = {27'd0, s_regs_q.errors};
        s_read_only = 1'b0;
        s_control   = 1'b1;
      end
      `APB4_CRYPTO__COMMAND, `APB4_CRYPTO__IRQ_TEST: begin
        s_read_only = 1'b0;
        s_control   = 1'b1;
      end
      `APB4_CRYPTO__MEM_CONTROL, `APB4_CRYPTO__TABLE_DATA: begin
        s_read_only  = 1'b0;
        s_write_only = 1'b1;
        s_control    = 1'b1;
      end
      `APB4_CRYPTO__AES_CTRL, `APB4_CRYPTO__AES_KEY_CTRL, `APB4_CRYPTO__SHA_CTRL,
          `APB4_CRYPTO__RSA_CTRL: begin
        s_read_only      = 1'b0;
        s_control        = 1'b1;
        s_engine_control = 1'b1;
      end
      `APB4_CRYPTO__AES_CFG: begin
        s_read_data      = {23'd0, s_regs_q.aes_cfg};
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
        s_bank_busy      = s_busy[0];
      end
      `APB4_CRYPTO__AES_LENGTH: begin
        s_read_data      = s_regs_q.aes_length;
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
        s_bank_busy      = s_busy[0];
      end
      `APB4_CRYPTO__AES_STATUS:
      s_read_data = {28'd0, s_aes_key_valid, s_operation_err[0], s_regs_q.irq_state[0], s_busy[0]};
      `APB4_CRYPTO__AES_DATA_IN: begin
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
      end
      `APB4_CRYPTO__AES_DATA_OUT: begin
        s_read_data      = s_aes_output_data;
        s_engine_control = 1'b1;
      end
      `APB4_CRYPTO__AES_DATA_STATUS:
      s_read_data = {29'd0, s_aes_output_last, s_aes_output_valid, s_aes_input_ready};
      `APB4_CRYPTO__AES_BYTES_IN: s_read_data = s_aes_bytes_in;
      `APB4_CRYPTO__AES_BYTES_OUT: s_read_data = s_aes_bytes_out;
      `APB4_CRYPTO__AES_CYCLES: s_read_data = s_aes_cycles;
      `APB4_CRYPTO__AES_KEY_STATUS: s_read_data = {30'd0, s_aes_key_busy, s_aes_key_valid};
      `APB4_CRYPTO__SHA_CFG: begin
        s_read_data      = {23'd0, s_regs_q.sha_cfg};
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
        s_bank_busy      = s_busy[1];
      end
      `APB4_CRYPTO__SHA_LENGTH_LO: begin
        s_read_data      = s_regs_q.sha_length[31:0];
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
        s_bank_busy      = s_busy[1];
      end
      `APB4_CRYPTO__SHA_LENGTH_HI: begin
        s_read_data      = s_regs_q.sha_length[63:32];
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
        s_bank_busy      = s_busy[1];
      end
      `APB4_CRYPTO__SHA_STATUS:
      s_read_data = {
        28'd0, s_sha_digest_valid, s_operation_err[1], s_regs_q.irq_state[1], s_busy[1]
      };
      `APB4_CRYPTO__SHA_DATA_IN: begin
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
      end
      `APB4_CRYPTO__SHA_DATA_STATUS: s_read_data = {30'd0, s_sha_digest_valid, s_sha_input_ready};
      `APB4_CRYPTO__SHA_BYTES_IN_LO: s_read_data = s_sha_bytes_in[31:0];
      `APB4_CRYPTO__SHA_BYTES_IN_HI: s_read_data = s_sha_bytes_in[63:32];
      `APB4_CRYPTO__SHA_CYCLES: s_read_data = s_sha_cycles;
      `APB4_CRYPTO__RSA_CFG: begin
        s_read_data      = {20'd0, s_regs_q.exponent_bits};
        s_read_only      = 1'b0;
        s_engine_control = 1'b1;
        s_bank_busy      = s_busy[2];
      end
      `APB4_CRYPTO__RSA_STATUS:
      s_read_data = {
        27'd0,
        s_rsa_result_valid,
        s_rsa_prepared,
        s_operation_err[2],
        s_regs_q.irq_state[2],
        s_busy[2]
      };
      `APB4_CRYPTO__RSA_CYCLES: s_read_data = s_rsa_cycles;
      `APB4_CRYPTO__RSA_PROGRESS: s_read_data = s_rsa_progress;
      default: begin
        s_bank_access    = 1'b1;
        s_engine_control = 1'b1;
        if ((s_offset >= 12'h140) && (s_offset < 12'h160)) begin
          s_bank        = 3'd2;
          s_row         = {7'd0, s_offset[4:2]};
          s_bank_secret = 1'b1;
          s_read_only   = 1'b0;
        end else if ((s_offset >= 12'h160) && (s_offset < 12'h170)) begin
          s_bank      = 3'd2;
          s_row       = 10'd80 + 10'(s_offset[3:2]);
          s_read_only = 1'b0;
        end else if ((s_offset >= 12'h170) && (s_offset < 12'h180)) begin
          s_bank         = 3'd2;
          s_row          = 10'd84 + 10'(s_offset[3:2]);
          s_bank_reverse = 1'b1;
        end else if ((s_offset >= 12'h240) && (s_offset < 12'h260)) begin
          s_bank      = 3'd3;
          s_row       = 10'd48 + 10'(s_offset[4:2]);
          s_bank_zero = !s_sha_digest_valid;
        end else if ((s_offset >= 12'h400) && (s_offset < 12'h500)) begin
          s_bank      = 3'd4;
          s_row       = {4'd0, s_offset[7:2]};
          s_read_only = 1'b0;
        end else if ((s_offset >= 12'h600) && (s_offset < 12'h700)) begin
          s_bank        = 3'd4;
          s_row         = {4'd1, s_offset[7:2]};
          s_read_only   = 1'b0;
          s_bank_secret = 1'b1;
        end else if ((s_offset >= 12'h800) && (s_offset < 12'h900)) begin
          s_bank      = 3'd4;
          s_row       = {4'd2, s_offset[7:2]};
          s_read_only = 1'b0;
        end else if ((s_offset >= 12'ha00) && (s_offset < 12'hb00)) begin
          s_bank      = 3'd4;
          s_row       = {4'd3, s_offset[7:2]};
          s_bank_zero = !s_rsa_result_valid;
        end else begin
          s_known       = 1'b0;
          s_bank_access = 1'b0;
        end
        s_bank_busy = s_bank == 3'd2 ? s_busy[0] : s_bank == 3'd3 ? s_busy[1] : s_busy[2];
        if (!s_bank_zero && s_store_resp[s_bank].valid && s_store_resp[s_bank].tag == 2'd2)
          s_read_data = s_bank_reverse ? byte_reverse(
            s_store_resp[s_bank].data
          ) : s_store_resp[s_bank].data;
      end
    endcase
    s_decode_err = !s_known || (s_offset[1:0] != 0) ||
        (s_regs_q.write && s_read_only) || (!s_regs_q.write && (s_write_only || s_bank_secret)) ||
        (s_regs_q.write && s_control && !s_strb[0]) || (s_engine_control && !s_mem_stat[0]) ||
        (s_bank_busy && (s_bank_access || s_regs_q.write));
    if (s_regs_q.write) begin
      unique case (s_offset)
        `APB4_CRYPTO__MEM_CONTROL:
        if ((s_strb != 4'hf) || (|s_wdata[31:3]) || ((s_wdata[2:0] & (s_wdata[2:0] - 1'b1)) != 0))
          s_decode_err = 1'b1;
        `APB4_CRYPTO__TABLE_DATA: if (s_strb != 4'hf) s_decode_err = 1'b1;
        `APB4_CRYPTO__COMMAND:
        if ((|s_wdata[31:4]) || (s_wdata[0] && (s_aes_dma_active || s_sha_dma_active ||
                                                crypto_out_axis.tvalid || s_mem_stat[6])))
          s_decode_err = 1'b1;
        `APB4_CRYPTO__AES_KEY_CTRL:
        if (s_busy[0] || s_regs_q.aes_cfg[5:4] == 2'd3) s_decode_err = 1'b1;
        `APB4_CRYPTO__AES_CTRL:
        if (s_wdata[0] &&
            (s_busy[0] || !s_aes_key_valid || s_regs_q.aes_length == 0 || s_regs_q.aes_cfg[1:0] ==
             2'd3 || (s_regs_q.aes_cfg[1:0] != 2'd2 && s_regs_q.aes_length[3:0] != 0) ||
             (s_regs_q.aes_cfg[8] && s_sha_dma_active)))
          s_decode_err = 1'b1;
        `APB4_CRYPTO__SHA_CTRL:
        if (s_wdata[0] && (s_busy[1] || (s_regs_q.sha_cfg[8] && s_aes_dma_active)))
          s_decode_err = 1'b1;
        `APB4_CRYPTO__RSA_CTRL:
        if (s_busy[2] || s_wdata[2:0] == 0 || ((s_wdata[2:0] & (s_wdata[2:0] - 1'b1)) != 0) ||
            ((|s_wdata[2:1]) && !s_rsa_prepared) ||
            (s_wdata[1] && (s_regs_q.exponent_bits == 0 || s_regs_q.exponent_bits > 12'd2048)))
          s_decode_err = 1'b1;
        `APB4_CRYPTO__AES_DATA_IN:
        if (s_regs_q.aes_cfg[8] || !s_aes_input_ready || s_pio_bytes == 0) s_decode_err = 1'b1;
        `APB4_CRYPTO__SHA_DATA_IN:
        if (s_regs_q.sha_cfg[8] || !s_sha_input_ready || s_pio_bytes == 0) s_decode_err = 1'b1;
        default: begin
        end
      endcase
    end
    if (!s_regs_q.write && s_offset == `APB4_CRYPTO__AES_DATA_OUT &&
        (s_regs_q.aes_cfg[8] || !s_aes_output_valid))
      s_decode_err = 1'b1;
  end
  assign s_access_err = s_decode_err ||
      (s_req && s_regs_q.write && s_offset == `APB4_CRYPTO__MEM_CONTROL && s_mem_cmd_err) ||
      (s_req && s_regs_q.write && s_offset == `APB4_CRYPTO__TABLE_DATA && s_mem_data_err);
  assign apb4.pready = s_req && (s_access_err || !s_bank_access || s_bank_zero || s_regs_q.write ||
                                 (s_regs_q.state == ApbReadWait && s_store_resp[s_bank].valid &&
                                  s_store_resp[s_bank].tag == 2'd2));
  assign apb4.pslverr = s_req && s_access_err;
  assign apb4.prdata = s_access_err ? 32'd0 : s_read_data;
  assign s_err_evt = {
    s_memory_err_evt, s_req_accept && s_access_err, s_operation_err & ~s_regs_q.previous_error
  };
  assign s_irq_evt = {
    s_memory_ready_evt,
    s_zeroized_evt && !s_zeroize,
    |s_err_evt,
    s_engine_clear ? 3'd0 : (s_done & ~s_command)
  };
  always_comb begin
    s_regs_d                = s_regs_q;
    s_epoch_d               = s_epoch_q;
    s_engine_pending_d      = s_engine_pending_q;
    s_token_d               = s_token_q;
    s_pending_token_d       = s_pending_token_q;
    s_merged                = '0;
    s_regs_d.previous_error = s_operation_err;
    if (s_regs_q.state == ApbIdle && apb4.psel && !apb4.penable) begin
      s_regs_d.state  = ApbAccess;
      s_regs_d.offset = apb4.paddr[11:0];
      s_regs_d.write  = apb4.pwrite;
      s_regs_d.data   = apb4.pwdata;
      s_regs_d.mask   = apb4.pstrb;
    end
    if (s_req) begin
      if (s_req_accept) s_regs_d.state = ApbIdle;
      else if (s_regs_q.state == ApbAccess) s_regs_d.state = ApbReadWait;
    end
    if (s_write_accept) begin
      unique case (s_offset)
        `APB4_CRYPTO__AES_CFG:
        s_regs_d.aes_cfg = 9'(merge_bytes({23'd0, s_regs_q.aes_cfg}, s_wdata, s_strb));
        `APB4_CRYPTO__AES_LENGTH:
        s_regs_d.aes_length = merge_bytes(s_regs_q.aes_length, s_wdata, s_strb);
        `APB4_CRYPTO__SHA_CFG:
        s_regs_d.sha_cfg = 9'(merge_bytes({23'd0, s_regs_q.sha_cfg}, s_wdata, s_strb));
        `APB4_CRYPTO__SHA_LENGTH_LO:
        s_regs_d.sha_length[31:0] = merge_bytes(s_regs_q.sha_length[31:0], s_wdata, s_strb);
        `APB4_CRYPTO__SHA_LENGTH_HI:
        s_regs_d.sha_length[63:32] = merge_bytes(s_regs_q.sha_length[63:32], s_wdata, s_strb);
        `APB4_CRYPTO__RSA_CFG:
        s_regs_d.exponent_bits = 12'(merge_bytes({20'd0, s_regs_q.exponent_bits}, s_wdata, s_strb));
        `APB4_CRYPTO__IRQ_ENABLE:
        s_regs_d.irq_enable = 6'(merge_bytes({26'd0, s_regs_q.irq_enable}, s_wdata, s_strb));
        `APB4_CRYPTO__IRQ_STATE: s_regs_d.irq_state = s_regs_q.irq_state & ~s_wdata[5:0];
        `APB4_CRYPTO__IRQ_TEST: s_regs_d.irq_state = s_regs_q.irq_state | s_wdata[5:0];
        `APB4_CRYPTO__ERROR_STATUS: begin
          s_regs_d.errors[3:0] = s_regs_q.errors[3:0] & ~s_wdata[3:0];
          if (!s_maintenance_busy) s_regs_d.errors[4] = s_regs_q.errors[4] && !s_wdata[4];
        end
        default: begin
        end
      endcase
    end
    if (s_mem_begin && !s_mem_cmd_err) s_regs_d.errors[4] = 1'b0;
    if (s_zeroize) begin
      s_regs_d.aes_cfg       = '0;
      s_regs_d.aes_length    = '0;
      s_regs_d.sha_cfg       = 9'd1;
      s_regs_d.sha_length    = '0;
      s_regs_d.exponent_bits = 12'd17;
      s_regs_d.irq_state[4]  = 1'b0;
    end
    // A new operation supersedes the previous completion, including a pulse
    // retiring on this edge. Independent fresh events still win over W1C.
    s_regs_d.irq_state[2:0] = s_regs_d.irq_state[2:0] & ~s_command;
    s_regs_d.irq_state      = s_regs_d.irq_state | s_irq_evt;
    s_regs_d.errors         = s_regs_d.errors | s_err_evt;
    for (int unsigned bank = 0; bank < 6; bank++) begin
      if (s_mem_stat[0] && s_engine_req[bank].valid && !s_engine_pending_q[bank]) begin
        if (!s_engine_req[bank].write) begin
          s_engine_pending_d[bank]     = 1'b1;
          s_pending_token_d[bank*4+:4] = s_token_q[bank*4+:4];
        end
        s_token_d[bank*4+:4] = s_token_q[bank*4+:4] + 1'b1;
      end
      if (s_store_resp[bank].valid && (s_store_resp[bank].tag == 2'd0) &&
          s_engine_pending_q[bank] &&
          ((bank < 2 && s_store_resp[bank].epoch == s_epoch_q[3:0]) ||
           (bank >= 2 && bank < 4 && s_store_resp[bank].epoch == s_epoch_q[7:4]) ||
           (bank >= 4 && s_store_resp[bank].epoch == s_epoch_q[11:8])) &&
          s_store_resp[bank].token == s_pending_token_q[bank*4+:4])
        s_engine_pending_d[bank] = 1'b0;
    end
    if (s_abort[0] || s_mem_clear) s_engine_pending_d[0] = 1'b0;
    if (s_abort[1] || s_mem_clear) s_engine_pending_d[1] = 1'b0;
    if (s_abort[2] || s_mem_clear) begin
      s_engine_pending_d[4] = 1'b0;
      s_engine_pending_d[5] = 1'b0;
    end
    if (s_abort[0] || s_mem_clear) s_pending_token_d[3:0] = '0;
    if (s_abort[1] || s_mem_clear) s_pending_token_d[7:4] = '0;
    if (s_abort[2] || s_mem_clear) begin
      s_pending_token_d[19:16] = '0;
      s_pending_token_d[23:20] = '0;
    end
    if (s_start[0] || s_abort[0] || s_mem_clear) s_epoch_d[3:0] = s_epoch_q[3:0] + 1'b1;
    if (s_start[1] || s_abort[1] || s_mem_clear) s_epoch_d[7:4] = s_epoch_q[7:4] + 1'b1;
    if (s_start[2] || s_abort[2] || s_mem_clear) s_epoch_d[11:8] = s_epoch_q[11:8] + 1'b1;
  end
endmodule
