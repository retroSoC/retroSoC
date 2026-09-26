// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_aes_sram_core (
    input  logic                                   clk_i,
    rst_n_i,
    zeroize_i,
    abort_i,
    key_dirty_i,
    key_commit_i,
    input  logic                             [1:0] key_size_i,
    input  logic                                   start_i,
    input  logic                             [1:0] mode_i,
    input  logic                                   decrypt_i,
    output logic                                   key_valid_o,
    busy_o,
    done_o,
    output crypto_mem_pkg::crypto_mem_req_t        constant_req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t       constant_resp_i,
    output crypto_mem_pkg::crypto_mem_req_t        work_req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t       work_resp_i
);
  import crypto_pkg::*;
  import crypto_mem_pkg::*;
  typedef enum logic [5:0] {
    AesIdle,
    KeyCopyRead,
    KeyCopyWait,
    KeyCopyWrite,
    KeyPreviousRead,
    KeyPreviousWait,
    KeySubRead,
    KeySubWait,
    KeyRconRead,
    KeyRconWait,
    KeyOldRead,
    KeyOldWait,
    KeyWrite,
    BlockRead,
    BlockWait,
    BlockChainRead,
    BlockChainWait,
    RoundKeyRead,
    RoundKeyWait,
    RoundNext,
    RoundSubRead,
    RoundSubWait,
    RoundTransform,
    OutputRead,
    OutputWait,
    OutputWrite,
    ChainRead,
    ChainWait,
    ChainWrite,
    AesDone
  } aes_state_e;
  typedef struct packed {
    aes_state_e   state;
    logic         key_valid,  expanding;
    logic [3:0]   nk,         nr;
    logic [5:0]   key_word;
    logic [3:0]   key_mod,    rcon,          round, byte_index;
    logic [1:0]   word_index;
    logic [31:0]  word;
    logic [127:0] active;
    logic [1:0]   mode;
    logic         decrypt,    initial_round, carry;
  } aes_registers_t;
  aes_registers_t s_regs_d, s_regs_q;
  logic [31:0] s_active_word;
  logic [32:0] s_cnt_sum;
  dffr #(
      .DATA_WIDTH($bits(aes_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  assign key_valid_o   = s_regs_q.key_valid;
  assign busy_o        = s_regs_q.state != AesIdle;
  assign done_o        = s_regs_q.state == AesDone;
  assign s_active_word = s_regs_q.active[127-s_regs_q.word_index*32-:32];
  assign s_cnt_sum     = {1'b0, work_resp_i.data} + {32'd0, s_regs_q.carry};
  always_comb begin
    s_regs_d       = s_regs_q;
    constant_req_o = '0;
    work_req_o     = '0;
    unique case (s_regs_q.state)
      AesIdle: begin
        if (key_commit_i) begin
          s_regs_d.key_valid = 1'b0;
          s_regs_d.expanding = 1'b1;
          s_regs_d.nk = key_size_i == AES_KEY_128 ? 4'd4 : key_size_i == AES_KEY_192 ? 4'd6 : 4'd8;
          s_regs_d.nr = key_size_i == AES_KEY_128 ? 4'd10 :
              key_size_i == AES_KEY_192 ? 4'd12 : 4'd14;
          s_regs_d.key_word = '0;
          s_regs_d.key_mod = '0;
          s_regs_d.rcon = 4'd1;
          s_regs_d.state = KeyCopyRead;
        end else if (start_i && s_regs_q.key_valid) begin
          s_regs_d.mode          = mode_i;
          s_regs_d.decrypt       = decrypt_i && (mode_i != AES_MODE_CTR);
          s_regs_d.word_index    = '0;
          s_regs_d.round         = (decrypt_i && (mode_i != AES_MODE_CTR)) ? s_regs_q.nr : 4'd0;
          s_regs_d.initial_round = 1'b1;
          s_regs_d.state         = BlockRead;
        end
      end
      KeyCopyRead: begin
        work_req_o     = mem_read({4'd0, s_regs_q.key_word});
        s_regs_d.state = KeyCopyWait;
      end
      KeyCopyWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = byte_reverse(work_resp_i.data);
        s_regs_d.state = KeyCopyWrite;
      end
      KeyCopyWrite: begin
        work_req_o = mem_write(10'd16 + 10'(s_regs_q.key_word), s_regs_q.word);
        s_regs_d.key_word = s_regs_q.key_word + 1'b1;
        s_regs_d.state = s_regs_q.key_word == (6'(s_regs_q.nk) - 1'b1) ? KeyPreviousRead :
            KeyCopyRead;
      end
      KeyPreviousRead: begin
        work_req_o     = mem_read(10'd15 + 10'(s_regs_q.key_word));
        s_regs_d.state = KeyPreviousWait;
      end
      KeyPreviousWait:
      if (work_resp_i.valid) begin
        s_regs_d.word       = work_resp_i.data;
        s_regs_d.byte_index = '0;
        if (s_regs_q.key_mod == 4'd0) begin
          s_regs_d.word  = {work_resp_i.data[23:0], work_resp_i.data[31:24]};
          s_regs_d.state = KeySubRead;
        end else if ((s_regs_q.nk == 4'd8) && (s_regs_q.key_mod == 4'd4))
          s_regs_d.state = KeySubRead;
        else s_regs_d.state = KeyOldRead;
      end
      KeySubRead: begin
        constant_req_o = mem_read({2'd0, s_regs_q.word[31-s_regs_q.byte_index*8-:8]});
        s_regs_d.state = KeySubWait;
      end
      KeySubWait:
      if (constant_resp_i.valid) begin
        s_regs_d.word[31-s_regs_q.byte_index*8-:8] = constant_resp_i.data[7:0];
        if (s_regs_q.byte_index == 4'd3)
          s_regs_d.state = s_regs_q.key_mod == 4'd0 ? KeyRconRead : KeyOldRead;
        else begin
          s_regs_d.byte_index = s_regs_q.byte_index + 1'b1;
          s_regs_d.state      = KeySubRead;
        end
      end
      KeyRconRead: begin
        constant_req_o = mem_read(10'd512 + 10'(s_regs_q.rcon));
        s_regs_d.state = KeyRconWait;
      end
      KeyRconWait:
      if (constant_resp_i.valid) begin
        s_regs_d.word[31:24] = s_regs_q.word[31:24] ^ constant_resp_i.data[7:0];
        s_regs_d.rcon        = s_regs_q.rcon + 1'b1;
        s_regs_d.state       = KeyOldRead;
      end
      KeyOldRead: begin
        work_req_o     = mem_read(10'd16 + 10'(s_regs_q.key_word) - 10'(s_regs_q.nk));
        s_regs_d.state = KeyOldWait;
      end
      KeyOldWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = s_regs_q.word ^ work_resp_i.data;
        s_regs_d.state = KeyWrite;
      end
      KeyWrite: begin
        work_req_o = mem_write(10'd16 + 10'(s_regs_q.key_word), s_regs_q.word);
        s_regs_d.key_word = s_regs_q.key_word + 1'b1;
        s_regs_d.key_mod = s_regs_q.key_mod == (s_regs_q.nk - 1'b1) ? 4'd0 :
            s_regs_q.key_mod + 1'b1;
        if (s_regs_q.key_word == (6'(s_regs_q.nr) * 6'd4 + 6'd3)) begin
          s_regs_d.key_valid = 1'b1;
          s_regs_d.expanding = 1'b0;
          s_regs_d.word      = '0;
          s_regs_d.state     = AesDone;
        end else s_regs_d.state = KeyPreviousRead;
      end
      BlockRead: begin
        work_req_o =
            mem_read((s_regs_q.mode == AES_MODE_CTR ? 10'd84 : 10'd88) + 10'(s_regs_q.word_index));
        s_regs_d.state = BlockWait;
      end
      BlockWait:
      if (work_resp_i.valid) begin
        s_regs_d.active[127-s_regs_q.word_index*32-:32] = work_resp_i.data;
        if ((s_regs_q.mode == AES_MODE_CBC) && !s_regs_q.decrypt) s_regs_d.state = BlockChainRead;
        else begin
          s_regs_d.word_index = s_regs_q.word_index + 1'b1;
          s_regs_d.state      = s_regs_q.word_index == 2'd3 ? RoundKeyRead : BlockRead;
        end
      end
      BlockChainRead: begin
        work_req_o     = mem_read(10'd84 + 10'(s_regs_q.word_index));
        s_regs_d.state = BlockChainWait;
      end
      BlockChainWait:
      if (work_resp_i.valid) begin
        s_regs_d.active[127-s_regs_q.word_index*32-:32] = s_active_word ^ work_resp_i.data;
        s_regs_d.word_index = s_regs_q.word_index + 1'b1;
        s_regs_d.state = s_regs_q.word_index == 2'd3 ? RoundKeyRead : BlockRead;
      end
      RoundKeyRead: begin
        work_req_o     = mem_read(10'd16 + 10'(s_regs_q.round) * 10'd4 + 10'(s_regs_q.word_index));
        s_regs_d.state = RoundKeyWait;
      end
      RoundKeyWait:
      if (work_resp_i.valid) begin
        s_regs_d.active[127-s_regs_q.word_index*32-:32] = s_active_word ^ work_resp_i.data;
        s_regs_d.word_index = s_regs_q.word_index + 1'b1;
        s_regs_d.state = s_regs_q.word_index == 2'd3 ? RoundNext : RoundKeyRead;
      end
      RoundNext: begin
        if (!s_regs_q.initial_round &&
            (s_regs_q.decrypt ? s_regs_q.round == 4'd0 : s_regs_q.round == s_regs_q.nr))
          s_regs_d.state = OutputRead;
        else begin
          if (s_regs_q.decrypt) begin
            s_regs_d.active = aes_inverse_shift_rows(s_regs_q.initial_round ? s_regs_q.active :
                                                     aes_inverse_mix_columns(s_regs_q.active));
            s_regs_d.round = s_regs_q.round - 1'b1;
          end else s_regs_d.round = s_regs_q.round + 1'b1;
          s_regs_d.initial_round = 1'b0;
          s_regs_d.byte_index    = '0;
          s_regs_d.state         = RoundSubRead;
        end
      end
      RoundSubRead: begin
        constant_req_o =
            mem_read({1'b0, s_regs_q.decrypt, s_regs_q.active[127-s_regs_q.byte_index*8-:8]});
        s_regs_d.state = RoundSubWait;
      end
      RoundSubWait:
      if (constant_resp_i.valid) begin
        s_regs_d.active[127-s_regs_q.byte_index*8-:8] = constant_resp_i.data[7:0];
        s_regs_d.byte_index = s_regs_q.byte_index + 1'b1;
        s_regs_d.state = s_regs_q.byte_index == 4'd15 ? RoundTransform : RoundSubRead;
      end
      RoundTransform: begin
        if (!s_regs_q.decrypt) begin
          s_regs_d.active = aes_shift_rows(s_regs_q.active);
          if (s_regs_q.round != s_regs_q.nr) s_regs_d.active = aes_mix_columns(s_regs_d.active);
        end
        s_regs_d.state = RoundKeyRead;
      end
      OutputRead: begin
        s_regs_d.word = s_active_word;
        if ((s_regs_q.mode == AES_MODE_CTR) ||
            ((s_regs_q.mode == AES_MODE_CBC) && s_regs_q.decrypt)) begin
          work_req_o = mem_read((s_regs_q.mode == AES_MODE_CTR ? 10'd88 : 10'd84) +
                                10'(s_regs_q.word_index));
          s_regs_d.state = OutputWait;
        end else s_regs_d.state = OutputWrite;
      end
      OutputWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = s_active_word ^ work_resp_i.data;
        s_regs_d.state = OutputWrite;
      end
      OutputWrite: begin
        work_req_o = mem_write(10'd92 + 10'(s_regs_q.word_index), s_regs_q.word);
        if (s_regs_q.word_index == 2'd3) begin
          s_regs_d.word_index = s_regs_q.mode == AES_MODE_CTR ? 2'd3 : 2'd0;
          s_regs_d.carry      = 1'b1;
          s_regs_d.state      = s_regs_q.mode == AES_MODE_ECB ? AesDone : ChainRead;
        end else begin
          s_regs_d.word_index = s_regs_q.word_index + 1'b1;
          s_regs_d.state      = OutputRead;
        end
      end
      ChainRead: begin
        work_req_o = mem_read((s_regs_q.mode == AES_MODE_CTR ? 10'd84 :
                               s_regs_q.decrypt ? 10'd88 : 10'd92) + 10'(s_regs_q.word_index));
        s_regs_d.state = ChainWait;
      end
      ChainWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = s_regs_q.mode == AES_MODE_CTR ? s_cnt_sum[31:0] : work_resp_i.data;
        s_regs_d.carry = s_cnt_sum[32];
        s_regs_d.state = ChainWrite;
      end
      ChainWrite: begin
        work_req_o = mem_write(10'd84 + 10'(s_regs_q.word_index), s_regs_q.word);
        if (s_regs_q.mode == AES_MODE_CTR) begin
          s_regs_d.word_index = s_regs_q.word_index - 1'b1;
          s_regs_d.state      = s_regs_q.word_index == 2'd0 ? AesDone : ChainRead;
        end else begin
          s_regs_d.word_index = s_regs_q.word_index + 1'b1;
          s_regs_d.state      = s_regs_q.word_index == 2'd3 ? AesDone : ChainRead;
        end
      end
      AesDone: begin
        s_regs_d.active = '0;
        s_regs_d.word   = '0;
        s_regs_d.state  = AesIdle;
      end
      default: s_regs_d.state = AesIdle;
    endcase
    if (key_dirty_i) s_regs_d.key_valid = 1'b0;
    if (abort_i) begin
      s_regs_d           = '0;
      s_regs_d.key_valid = s_regs_q.key_valid && !s_regs_q.expanding;
      s_regs_d.nk        = s_regs_q.nk;
      s_regs_d.nr        = s_regs_q.nr;
      work_req_o         = '0;
      constant_req_o     = '0;
    end
    if (zeroize_i) begin
      s_regs_d       = '0;
      work_req_o     = '0;
      constant_req_o = '0;
    end
  end
endmodule
