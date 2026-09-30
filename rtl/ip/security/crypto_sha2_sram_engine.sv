// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_sha2_sram_engine (
    input  logic                                    clk_i,
    rst_n_i,
    zeroize_i,
    abort_i,
    start_i,
    sha256_i,
    input  logic                             [63:0] length_i,
    input  logic                                    input_valid_i,
    output logic                                    input_ready_o,
    input  logic                             [31:0] input_data_i,
    input  logic                             [ 3:0] input_keep_i,
    input  logic                                    input_last_i,
    output logic                                    busy_o,
    done_o,
    error_o,
    digest_valid_o,
    output logic                             [63:0] bytes_in_o,
    output logic                             [31:0] cycles_o,
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
    ShaIdle,
    ShaIvRead,
    ShaIvWait,
    ShaIvWrite,
    ShaFill,
    ShaInitialRead,
    ShaInitialWait,
    ShaInitialWrite,
    ShaWordRead,
    ShaWordWait,
    ShaWordWrite,
    ShaRound,
    ShaFinalRead,
    ShaFinalWait,
    ShaFinalWrite,
    ShaDigestWrite,
    ShaClear,
    ShaScrub
  } sha_state_e;
  typedef struct packed {
    sha_state_e   state;
    logic         sha256,        done,          error,         digest_valid;
    logic         padding,       two_blocks,    final_block;
    logic [63:0]  length,        bytes_in,      consumed;
    logic [31:0]  cycles,        word,          constant_word;
    logic [255:0] active;
    logic [5:0]   byte_index,    round;
    logic [2:0]   index;
    logic [1:0]   lane,          schedule_step;
    logic [11:0]  scrub_cycles;
    logic         scrub_timeout;
  } sha_registers_t;
  sha_registers_t s_regs_d, s_regs_q;
  logic [36:0] s_fifo_data;
  logic s_fifo_empty, s_fifo_full, s_fifo_push, s_fifo_pop;
  logic [2:0] s_input_bytes, s_head_bytes;
  logic [64:0] s_next_bytes;
  logic [63:0] s_bit_length;
  logic [ 7:0] s_byte;
  logic [31:0] s_fill_word, s_t1, s_t2;
  logic [3:0] s_schedule_row;
  logic s_fill_valid, s_scrub_done, s_scrub_busy, s_scrub_err;
  crypto_mem_req_t  [0:0] s_scrub_req;
  crypto_mem_resp_t [0:0] s_scrub_resp;
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
      .DATA_WIDTH($bits(sha_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  crypto_clearable_fifo #(
      .Depth(16)
  ) u_input_fifo (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .clear_i      (zeroize_i || s_regs_q.state == ShaClear),
      .flush_i      (start_i),
      .push_i       (s_fifo_push),
      .data_i       ({input_last_i, input_keep_i, input_data_i}),
      .pop_i        (s_fifo_pop),
      .data_o       (s_fifo_data),
      .empty_o      (s_fifo_empty),
      .full_o       (s_fifo_full),
      .count_o      (),
      .clear_busy_o (fifo_busy_o),
      .clear_done_o (),
      .clear_error_o(fifo_error_o)
  );
  assign s_scrub_resp[0] = work_resp_i;
  crypto_scrubber #(
      .NumBanks(1)
  ) u_scrub (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (s_regs_q.state == ShaClear),
      .cancel_i    (zeroize_i),
      .first_row_i (10'd0),
      .busy_o      (s_scrub_busy),
      .done_o      (s_scrub_done),
      .error_o     (s_scrub_err),
      .error_bank_o(),
      .error_row_o (scrub_error_row_o),
      .req_o       (s_scrub_req),
      .resp_i      (s_scrub_resp)
  );
  assign busy_o = s_regs_q.state != ShaIdle;
  assign done_o = s_regs_q.done;
  assign error_o = s_regs_q.error;
  assign digest_valid_o = s_regs_q.digest_valid;
  assign bytes_in_o = s_regs_q.bytes_in;
  assign cycles_o = s_regs_q.cycles;
  assign scrub_error_o = s_scrub_err || s_regs_q.scrub_timeout;
  assign s_input_bytes = count_keep(input_keep_i);
  assign s_head_bytes = count_keep(s_fifo_data[35:32]);
  assign s_next_bytes = {1'b0, s_regs_q.bytes_in} + 65'(s_input_bytes);
  assign input_ready_o = busy_o && (s_regs_q.state < ShaClear) && !s_fifo_full &&
      (s_regs_q.bytes_in < s_regs_q.length) && !abort_i;
  assign s_fifo_push = input_valid_i && input_ready_o;
  assign s_bit_length = s_regs_q.length << 3;
  assign s_t1 = s_regs_q.active[31:0] + sha2_sum1(
      s_regs_q.active[127:96]
  ) + ((s_regs_q.active[127:96] & s_regs_q.active[95:64]) ^ (
       ~s_regs_q.active[127:96] & s_regs_q.active[63:32])) + s_regs_q.constant_word + s_regs_q.word;
  assign s_t2 = sha2_sum0(
      s_regs_q.active[255:224]
  ) + ((s_regs_q.active[255:224] & s_regs_q.active[223:192]) ^
       (s_regs_q.active[255:224] & s_regs_q.active[191:160]) ^
       (s_regs_q.active[223:192] & s_regs_q.active[191:160]));
  always_comb begin
    s_regs_d       = s_regs_q;
    s_regs_d.done  = 1'b0;
    work_req_o     = '0;
    constant_req_o = '0;
    s_fifo_pop     = 1'b0;
    s_byte         = '0;
    s_fill_valid   = 1'b0;
    s_fill_word    = s_regs_q.word;
    s_schedule_row = s_regs_q.round[3:0];
    unique case (s_regs_q.schedule_step)
      2'd0:    s_schedule_row = s_regs_q.round[3:0] - 4'd2;
      2'd1:    s_schedule_row = s_regs_q.round[3:0] - 4'd7;
      2'd2:    s_schedule_row = s_regs_q.round[3:0] - 4'd15;
      default: s_schedule_row = s_regs_q.round[3:0];
    endcase
    if (busy_o) s_regs_d.cycles = s_regs_q.cycles + 1'b1;
    if (s_fifo_push) s_regs_d.bytes_in = s_next_bytes[63:0];
    unique case (s_regs_q.state)
      ShaIdle:
      if (start_i) begin
        s_regs_d        = '0;
        s_regs_d.sha256 = sha256_i;
        s_regs_d.length = length_i;
        s_regs_d.state  = ShaIvRead;
      end
      ShaIvRead: begin
        constant_req_o = mem_read((s_regs_q.sha256 ? 10'd72 : 10'd64) + 10'(s_regs_q.index));
        s_regs_d.state = ShaIvWait;
      end
      ShaIvWait:
      if (constant_resp_i.valid) begin
        s_regs_d.word  = constant_resp_i.data;
        s_regs_d.state = ShaIvWrite;
      end
      ShaIvWrite: begin
        work_req_o     = mem_write(10'd32 + 10'(s_regs_q.index), s_regs_q.word);
        s_regs_d.index = s_regs_q.index + 1'b1;
        s_regs_d.word  = '0;
        s_regs_d.state = s_regs_q.index == 3'd7 ? ShaFill : ShaIvRead;
      end
      ShaFill: begin
        if (s_regs_q.consumed < s_regs_q.length) begin
          s_fill_valid = !s_fifo_empty;
          s_byte       = s_fifo_data[s_regs_q.lane*8+:8];
          if (s_fill_valid) begin
            s_regs_d.consumed = s_regs_q.consumed + 1'b1;
            if (3'(s_regs_q.lane) == (s_head_bytes - 1'b1)) begin
              s_fifo_pop    = 1'b1;
              s_regs_d.lane = '0;
            end else s_regs_d.lane = s_regs_q.lane + 1'b1;
          end
        end else begin
          s_fill_valid = 1'b1;
          if (!s_regs_q.padding) begin
            s_byte              = 8'h80;
            s_regs_d.padding    = 1'b1;
            s_regs_d.two_blocks = s_regs_q.byte_index >= 6'd56;
          end else if (!s_regs_q.two_blocks && (s_regs_q.byte_index >= 6'd56))
            s_byte = s_bit_length[63-s_regs_q.byte_index[2:0]*8-:8];
        end
        if (s_fill_valid) begin
          s_fill_word[31-s_regs_q.byte_index[1:0]*8-:8] = s_byte;
          s_regs_d.word                                 = s_fill_word;
          s_regs_d.byte_index                           = s_regs_q.byte_index + 1'b1;
          if (s_regs_q.byte_index[1:0] == 2'd3) begin
            work_req_o    = mem_write(10'd16 + 10'(s_regs_q.byte_index[5:2]), s_fill_word);
            s_regs_d.word = '0;
          end
          if (s_regs_q.byte_index == 6'd63) begin
            s_regs_d.final_block = s_regs_q.padding && !s_regs_q.two_blocks;
            s_regs_d.index       = '0;
            s_regs_d.state       = ShaInitialRead;
          end
        end
      end
      ShaInitialRead: begin
        work_req_o     = mem_read(10'd32 + 10'(s_regs_q.index));
        s_regs_d.state = ShaInitialWait;
      end
      ShaInitialWait:
      if (work_resp_i.valid) begin
        s_regs_d.active[255-s_regs_q.index*32-:32] = work_resp_i.data;
        s_regs_d.word                              = work_resp_i.data;
        s_regs_d.state                             = ShaInitialWrite;
      end
      ShaInitialWrite: begin
        work_req_o             = mem_write(10'd40 + 10'(s_regs_q.index), s_regs_q.word);
        s_regs_d.index         = s_regs_q.index + 1'b1;
        s_regs_d.round         = '0;
        s_regs_d.schedule_step = '0;
        s_regs_d.state         = s_regs_q.index == 3'd7 ? ShaWordRead : ShaInitialRead;
      end
      ShaWordRead: begin
        if (s_regs_q.schedule_step == 2'd0) constant_req_o = mem_read({4'd0, s_regs_q.round});
        work_req_o = mem_read(
            s_regs_q.round < 6'd16 ? 10'd16 + 10'(s_regs_q.round) : {6'd0, s_schedule_row});
        s_regs_d.state = ShaWordWait;
      end
      ShaWordWait:
      if (work_resp_i.valid) begin
        if (constant_resp_i.valid) s_regs_d.constant_word = constant_resp_i.data;
        if (s_regs_q.round < 6'd16) begin
          s_regs_d.word  = work_resp_i.data;
          s_regs_d.state = ShaWordWrite;
        end else begin
          unique case (s_regs_q.schedule_step)
            2'd0:    s_regs_d.word = sha2_sigma1(work_resp_i.data);
            2'd1:    s_regs_d.word = s_regs_q.word + work_resp_i.data;
            2'd2:    s_regs_d.word = s_regs_q.word + sha2_sigma0(work_resp_i.data);
            default: s_regs_d.word = s_regs_q.word + work_resp_i.data;
          endcase
          s_regs_d.schedule_step = s_regs_q.schedule_step + 1'b1;
          s_regs_d.state         = s_regs_q.schedule_step == 2'd3 ? ShaWordWrite : ShaWordRead;
        end
      end
      ShaWordWrite: begin
        work_req_o     = mem_write({6'd0, s_regs_q.round[3:0]}, s_regs_q.word);
        s_regs_d.state = ShaRound;
      end
      ShaRound: begin
        s_regs_d.active = {
          s_t1 + s_t2,
          s_regs_q.active[255:160],
          s_regs_q.active[159:128] + s_t1,
          s_regs_q.active[127:32]
        };
        s_regs_d.round = s_regs_q.round + 1'b1;
        s_regs_d.index = '0;
        s_regs_d.schedule_step = '0;
        s_regs_d.state = s_regs_q.round == 6'd63 ? ShaFinalRead : ShaWordRead;
      end
      ShaFinalRead: begin
        work_req_o     = mem_read(10'd40 + 10'(s_regs_q.index));
        s_regs_d.state = ShaFinalWait;
      end
      ShaFinalWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = work_resp_i.data + s_regs_q.active[255-s_regs_q.index*32-:32];
        s_regs_d.state = ShaFinalWrite;
      end
      ShaFinalWrite: begin
        work_req_o     = mem_write(10'd32 + 10'(s_regs_q.index), s_regs_q.word);
        s_regs_d.state = ShaDigestWrite;
      end
      ShaDigestWrite: begin
        if (s_regs_q.final_block)
          work_req_o = mem_write(
            10'd48 + 10'(s_regs_q.index),
            (!s_regs_q.sha256 && s_regs_q.index == 3'd7) ? 32'd0 : s_regs_q.word
          );
        s_regs_d.index = s_regs_q.index + 1'b1;
        if (s_regs_q.index == 3'd7) begin
          s_regs_d.active     = '0;
          s_regs_d.word       = '0;
          s_regs_d.two_blocks = 1'b0;
          if (s_regs_q.final_block) begin
            s_regs_d.digest_valid = 1'b1;
            s_regs_d.done         = 1'b1;
            s_regs_d.state        = ShaIdle;
          end else s_regs_d.state = ShaFill;
        end else s_regs_d.state = ShaFinalRead;
      end
      ShaClear: begin
        s_regs_d.active        = '0;
        s_regs_d.word          = '0;
        s_regs_d.constant_word = '0;
        s_regs_d.digest_valid  = 1'b0;
        s_regs_d.bytes_in      = '0;
        s_regs_d.consumed      = '0;
        s_regs_d.scrub_cycles  = '0;
        s_regs_d.state         = ShaScrub;
      end
      ShaScrub: begin
        work_req_o            = s_scrub_req[0];
        s_regs_d.scrub_cycles = s_regs_q.scrub_cycles + 1'b1;
        if (s_scrub_done && !fifo_busy_o) s_regs_d.state = ShaIdle;
        if (s_regs_q.scrub_cycles >= 12'd2055) s_regs_d.scrub_timeout = 1'b1;
      end
      default: s_regs_d.state = ShaClear;
    endcase
    if ((abort_i ||
         (s_fifo_push && ((s_input_bytes == 0) || (s_next_bytes > {1'b0, s_regs_q.length}) ||
                          (input_last_i != (s_next_bytes == {1'b0, s_regs_q.length}))))) &&
        (s_regs_q.state < ShaClear)) begin
      s_regs_d.state        = ShaClear;
      s_regs_d.error        = !abort_i;
      s_regs_d.done         = 1'b0;
      s_regs_d.digest_valid = 1'b0;
      work_req_o            = '0;
      constant_req_o        = '0;
      s_fifo_pop            = 1'b0;
    end
    if (zeroize_i) begin
      s_regs_d       = '0;
      work_req_o     = '0;
      constant_req_o = '0;
      s_fifo_pop     = 1'b0;
    end
  end
endmodule
