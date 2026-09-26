// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_aes_sram_engine (
    input  logic                                    clk_i,
    rst_n_i,
    zeroize_i,
    fault_i,
    abort_i,
    input  logic                                    key_commit_i,
    key_dirty_i,
    input  logic                             [ 1:0] key_size_i,
    output logic                                    key_valid_o,
    key_busy_o,
    input  logic                                    start_i,
    input  logic                             [ 1:0] mode_i,
    input  logic                                    decrypt_i,
    input  logic                             [31:0] length_i,
    input  logic                                    input_valid_i,
    output logic                                    input_ready_o,
    input  logic                             [31:0] input_data_i,
    input  logic                             [ 3:0] input_keep_i,
    input  logic                                    input_last_i,
    output logic                                    output_valid_o,
    input  logic                                    output_ready_i,
    output logic                             [31:0] output_data_o,
    output logic                             [ 3:0] output_keep_o,
    output logic                                    output_last_o,
    output logic                                    busy_o,
    done_o,
    error_o,
    output logic                             [31:0] bytes_in_o,
    bytes_out_o,
    cycles_o,
    output logic                                    fifo_busy_o,
    fifo_error_o,
    scrub_error_o,
    output logic                             [ 9:0] scrub_error_row_o,
    output crypto_mem_pkg::crypto_mem_req_t         constant_req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t        constant_resp_i,
    output crypto_mem_pkg::crypto_mem_req_t         work_req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t        work_resp_i
);
  import crypto_pkg::*;
  import crypto_mem_pkg::*;
  typedef enum logic [4:0] {
    EngineIdle,
    EngineKey,
    EngineIvRead,
    EngineIvWait,
    EngineIvWrite,
    EngineInput,
    EnginePad,
    EngineStart,
    EngineCore,
    EngineOutputRead,
    EngineOutputWait,
    EngineOutputPush,
    EngineLast,
    EngineDrain,
    EngineClear,
    EngineScrub,
    EngineFaultDrain,
    EngineFault
  } engine_state_e;
  typedef struct packed {
    engine_state_e state;
    logic [1:0]    mode;
    logic          decrypt;
    logic [31:0]   length,        bytes_in,   bytes_out, cycles;
    logic [31:0]   word;
    logic [4:0]    block_bytes;
    logic [1:0]    lane,          word_index;
    logic [4:0]    input_index;
    logic          last_block,    done,       error;
    logic [11:0]   scrub_cycles;
    logic          scrub_timeout;
  } engine_registers_t;
  engine_registers_t s_regs_d, s_regs_q;
  crypto_mem_req_t        s_core_req;
  crypto_mem_req_t  [0:0] s_scrub_req;
  crypto_mem_resp_t [0:0] s_scrub_resp;
  logic s_core_busy, s_core_done, s_core_start;
  logic [36:0] s_input_data, s_output_data, s_output_payload;
  logic s_input_empty, s_input_full, s_output_empty, s_output_full;
  logic s_input_pop, s_input_push, s_output_pop, s_output_push;
  logic [1:0] s_fifo_busy, s_fifo_err;
  logic s_fifo_clear, s_scrub_busy, s_scrub_done, s_scrub_err;
  logic [2:0] s_input_bytes, s_head_bytes;
  logic [32:0] s_next_bytes;
  logic [31:0] s_assembled_word;
  logic [ 2:0] s_output_bytes;

  function automatic logic [2:0] count_keep(input logic [3:0] keep);
    unique case (keep)
      4'h1:    return 3'd1;
      4'h3:    return 3'd2;
      4'h7:    return 3'd3;
      4'hf:    return 3'd4;
      default: return 3'd0;
    endcase
  endfunction
  dffr #(
      .DATA_WIDTH($bits(engine_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  crypto_aes_sram_core u_core (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .zeroize_i      (zeroize_i || fault_i),
      .abort_i        (abort_i || s_regs_q.state == EngineClear),
      .key_dirty_i    (key_dirty_i),
      .key_commit_i   (key_commit_i && !busy_o),
      .key_size_i     (key_size_i),
      .start_i        (s_core_start),
      .mode_i         (s_regs_q.mode),
      .decrypt_i      (s_regs_q.decrypt),
      .key_valid_o    (key_valid_o),
      .busy_o         (s_core_busy),
      .done_o         (s_core_done),
      .constant_req_o (constant_req_o),
      .constant_resp_i(constant_resp_i),
      .work_req_o     (s_core_req),
      .work_resp_i    (work_resp_i)
  );
  assign s_fifo_clear = zeroize_i || (s_regs_q.state == EngineClear);
  crypto_clearable_fifo #(
      .Depth(8)
  ) u_input_fifo (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .clear_i      (s_fifo_clear || fault_i),
      .flush_i      (start_i),
      .push_i       (s_input_push),
      .data_i       ({input_last_i, input_keep_i, input_data_i}),
      .pop_i        (s_input_pop),
      .data_o       (s_input_data),
      .empty_o      (s_input_empty),
      .full_o       (s_input_full),
      .count_o      (),
      .clear_busy_o (s_fifo_busy[0]),
      .clear_done_o (),
      .clear_error_o(s_fifo_err[0])
  );
  crypto_clearable_fifo #(
      .Depth(8)
  ) u_output_fifo (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .clear_i      (s_fifo_clear || s_regs_q.state == EngineFault),
      .flush_i      (start_i),
      .push_i       (s_output_push),
      .data_i       (s_output_payload),
      .pop_i        (s_output_pop),
      .data_o       (s_output_data),
      .empty_o      (s_output_empty),
      .full_o       (s_output_full),
      .count_o      (),
      .clear_busy_o (s_fifo_busy[1]),
      .clear_done_o (),
      .clear_error_o(s_fifo_err[1])
  );
  assign s_scrub_resp[0] = work_resp_i;
  crypto_scrubber #(
      .NumBanks(1)
  ) u_scrub (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (s_regs_q.state == EngineClear),
      .cancel_i    (zeroize_i || fault_i),
      .first_row_i (10'd76),
      .busy_o      (s_scrub_busy),
      .done_o      (s_scrub_done),
      .error_o     (s_scrub_err),
      .error_bank_o(),
      .error_row_o (scrub_error_row_o),
      .req_o       (s_scrub_req),
      .resp_i      (s_scrub_resp)
  );
  assign fifo_busy_o = |s_fifo_busy;
  assign fifo_error_o = |s_fifo_err;
  assign scrub_error_o = s_scrub_err || s_regs_q.scrub_timeout;
  assign busy_o = (s_regs_q.state != EngineIdle) && (s_regs_q.state != EngineFault);
  assign key_busy_o = s_regs_q.state == EngineKey;
  assign done_o = s_regs_q.done;
  assign error_o = s_regs_q.error;
  assign bytes_in_o = s_regs_q.bytes_in;
  assign bytes_out_o = s_regs_q.bytes_out;
  assign cycles_o = s_regs_q.cycles;
  assign s_input_bytes = count_keep(input_keep_i);
  assign s_head_bytes = count_keep(s_input_data[35:32]);
  assign s_next_bytes = {1'b0, s_regs_q.bytes_in} + 33'(s_input_bytes);
  assign input_ready_o = busy_o && !key_busy_o && (s_regs_q.state < EngineDrain) && !s_input_full &&
      (s_regs_q.bytes_in < s_regs_q.length) && !abort_i && !fault_i;
  assign s_input_push = input_valid_i && input_ready_o;
  assign output_valid_o = !s_output_empty &&
      ((s_regs_q.state < EngineClear) || (s_regs_q.state == EngineFaultDrain));
  assign output_data_o = s_output_data[31:0];
  assign output_keep_o = s_output_data[35:32];
  assign output_last_o = s_output_data[36];
  assign s_output_pop = output_valid_o && output_ready_i;
  assign s_core_start = s_regs_q.state == EngineStart;
  assign s_output_bytes = (s_regs_q.block_bytes - {1'b0, s_regs_q.word_index, 2'b00}) >= 5'd4 ?
      3'd4 : 3'(s_regs_q.block_bytes - {1'b0, s_regs_q.word_index, 2'b00});
  assign s_output_payload = {
    s_regs_q.last_block && (({1'b0, s_regs_q.word_index, 2'b00} + 5'd4) >= s_regs_q.block_bytes),
    4'((5'd1 << s_output_bytes) - 1'b1),
    byte_reverse(s_regs_q.word)
  };
  always_comb begin
    s_regs_d                                            = s_regs_q;
    s_regs_d.done                                       = 1'b0;
    work_req_o                                          = s_core_req;
    s_input_pop                                         = 1'b0;
    s_output_push                                       = 1'b0;
    s_assembled_word                                    = s_regs_q.word;
    s_assembled_word[31-s_regs_q.input_index[1:0]*8-:8] = s_input_data[s_regs_q.lane*8+:8];
    if (busy_o) s_regs_d.cycles = s_regs_q.cycles + 1'b1;
    if (s_input_push) s_regs_d.bytes_in = s_next_bytes[31:0];
    if (s_output_pop && (s_regs_q.state != EngineDrain)) begin
      s_regs_d.bytes_out = s_regs_q.bytes_out + 32'(count_keep(output_keep_o));
      if (output_last_o) begin
        s_regs_d.done  = 1'b1;
        s_regs_d.state = EngineIdle;
      end
    end
    unique case (s_regs_q.state)
      EngineIdle: begin
        if (key_commit_i) begin
          s_regs_d.state  = EngineKey;
          s_regs_d.cycles = '0;
        end else if (start_i) begin
          s_regs_d = '0;
          if (!key_valid_o || (length_i == 0) || (mode_i == 2'd3) ||
              ((mode_i != AES_MODE_CTR) && (length_i[3:0] != 4'd0))) begin
            s_regs_d.error = 1'b1;
            s_regs_d.done  = 1'b1;
          end else begin
            s_regs_d.state   = EngineIvRead;
            s_regs_d.mode    = mode_i;
            s_regs_d.decrypt = decrypt_i;
            s_regs_d.length  = length_i;
          end
        end
      end
      EngineKey:   if (s_core_done) s_regs_d.state = EngineIdle;
      EngineIvRead: begin
        work_req_o     = mem_read(10'd80 + 10'(s_regs_q.word_index));
        s_regs_d.state = EngineIvWait;
      end
      EngineIvWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = byte_reverse(work_resp_i.data);
        s_regs_d.state = EngineIvWrite;
      end
      EngineIvWrite: begin
        work_req_o          = mem_write(10'd84 + 10'(s_regs_q.word_index), s_regs_q.word);
        s_regs_d.word       = '0;
        s_regs_d.word_index = s_regs_q.word_index + 1'b1;
        s_regs_d.state      = s_regs_q.word_index == 2'd3 ? EngineInput : EngineIvRead;
      end
      EngineInput:
      if (!s_input_empty) begin
        s_regs_d.word        = s_assembled_word;
        s_regs_d.input_index = s_regs_q.input_index + 1'b1;
        if ((s_regs_q.input_index[1:0] == 2'd3) ||
            (s_input_data[36] && (3'(s_regs_q.lane) == (s_head_bytes - 1'b1)))) begin
          work_req_o    = mem_write(10'd88 + 10'(s_regs_q.input_index[3:2]), s_assembled_word);
          s_regs_d.word = '0;
        end
        if (3'(s_regs_q.lane) == (s_head_bytes - 1'b1)) begin
          s_input_pop   = 1'b1;
          s_regs_d.lane = '0;
          if (s_input_data[36]) begin
            s_regs_d.last_block  = 1'b1;
            s_regs_d.block_bytes = s_regs_q.input_index + 1'b1;
            s_regs_d.word_index  = s_regs_q.input_index[3:2] + 1'b1;
            s_regs_d.state       = s_regs_q.input_index[3:2] == 2'd3 ? EngineStart : EnginePad;
          end
        end else s_regs_d.lane = s_regs_q.lane + 1'b1;
        if (s_regs_q.input_index == 5'd15) begin
          s_regs_d.block_bytes = 5'd16;
          s_regs_d.state       = EngineStart;
        end
      end
      EnginePad: begin
        work_req_o          = mem_write(10'd88 + 10'(s_regs_q.word_index), 32'd0);
        s_regs_d.word_index = s_regs_q.word_index + 1'b1;
        if (s_regs_q.word_index == 2'd3) s_regs_d.state = EngineStart;
      end
      EngineStart: s_regs_d.state = EngineCore;
      EngineCore:
      if (s_core_done) begin
        s_regs_d.word_index = '0;
        s_regs_d.state      = EngineOutputRead;
      end
      EngineOutputRead: begin
        work_req_o     = mem_read(10'd92 + 10'(s_regs_q.word_index));
        s_regs_d.state = EngineOutputWait;
      end
      EngineOutputWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = work_resp_i.data;
        s_regs_d.state = EngineOutputPush;
      end
      EngineOutputPush:
      if (!s_output_full) begin
        s_output_push = 1'b1;
        if (({1'b0, s_regs_q.word_index, 2'b00} + 5'd4) >= s_regs_q.block_bytes) begin
          s_regs_d.word        = '0;
          s_regs_d.input_index = '0;
          s_regs_d.state       = s_regs_q.last_block ? EngineLast : EngineInput;
        end else begin
          s_regs_d.word_index = s_regs_q.word_index + 1'b1;
          s_regs_d.state      = EngineOutputRead;
        end
      end
      EngineLast: begin
      end
      EngineDrain: if (s_output_pop || !output_valid_o) s_regs_d.state = EngineClear;
      EngineClear: begin
        s_regs_d.word         = '0;
        s_regs_d.input_index  = '0;
        s_regs_d.lane         = '0;
        s_regs_d.bytes_in     = '0;
        s_regs_d.bytes_out    = '0;
        s_regs_d.scrub_cycles = '0;
        s_regs_d.state        = EngineScrub;
      end
      EngineScrub: begin
        work_req_o            = s_scrub_req[0];
        s_regs_d.scrub_cycles = s_regs_q.scrub_cycles + 1'b1;
        if (s_scrub_done && !fifo_busy_o) s_regs_d.state = EngineIdle;
        if (s_regs_q.scrub_cycles >= 12'd2055) s_regs_d.scrub_timeout = 1'b1;
      end
      EngineFaultDrain, EngineFault: begin
        // Fatal handling below owns these states until coordinated reset.
      end
      default:     s_regs_d.state = EngineClear;
    endcase
    if ((abort_i ||
         (s_input_push && ((s_input_bytes == 0) || (s_next_bytes > {1'b0, s_regs_q.length}) ||
                           (input_last_i != (s_next_bytes == {1'b0, s_regs_q.length}))))) &&
        (s_regs_q.state < EngineDrain)) begin
      s_regs_d.state = output_valid_o && !output_ready_i ? EngineDrain : EngineClear;
      s_regs_d.error = !abort_i;
      s_regs_d.done  = 1'b0;
      work_req_o     = '0;
      s_input_pop    = 1'b0;
      s_output_push  = 1'b0;
    end
    if (fault_i) begin
      // Revoke scalar/key state immediately. Keep only the already-presented
      // FIFO head until its handshake; a fatal fault cannot retract AXIS valid.
      s_regs_d       = '0;
      s_regs_d.state = output_valid_o && !output_ready_i ? EngineFaultDrain : EngineFault;
      work_req_o     = '0;
      s_input_pop    = 1'b0;
      s_output_push  = 1'b0;
    end
    if (zeroize_i) begin
      s_regs_d      = '0;
      work_req_o    = '0;
      s_input_pop   = 1'b0;
      s_output_push = 1'b0;
    end
  end
endmodule
