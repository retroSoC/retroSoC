// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_rsa_sram_core (
    input  logic                                    clk_i,
    rst_n_i,
    zeroize_i,
    abort_i,
    modulus_dirty_i,
    input  logic                                    prepare_i,
    start_i,
    private_i,
    input  logic                             [11:0] exponent_bits_i,
    output logic                                    busy_o,
    done_o,
    error_o,
    prepared_o,
    result_valid_o,
    output logic                             [31:0] cycles_o,
    progress_o,
    output logic                                    scrub_error_o,
    output logic                             [ 2:0] scrub_error_bank_o,
    output logic                             [ 9:0] scrub_error_row_o,
    output crypto_mem_pkg::crypto_mem_req_t         retained_req_o,
    work_req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t        retained_resp_i,
    work_resp_i
);
  import crypto_mem_pkg::*;
  typedef enum logic [5:0] {
    RsaIdle,
    PrepareRead,
    PrepareWait,
    PrepareCopy,
    PrepareSeed,
    PrepareInverse,
    PrepareDoubleRead,
    PrepareDoubleWait,
    PrepareDoubleWrite,
    PrepareHighWrite,
    PrepareSubtractRead,
    PrepareSubtractWait,
    PrepareSubtractWrite,
    PrepareSelectRead,
    PrepareSelectWait,
    PrepareCandidateRead,
    PrepareCandidateWait,
    PrepareSelectWrite,
    BaseRead,
    BaseWait,
    BaseModulusRead,
    BaseModulusWait,
    LaunchMultiply,
    CopyLeftRead,
    CopyLeftWait,
    CopyLeftWrite,
    CopyRightRead,
    CopyRightWait,
    CopyRightWrite,
    CopyModulusRead,
    CopyModulusWait,
    CopyModulusWrite,
    MultiplyStart,
    MultiplyWait,
    ProductRead,
    ProductWait,
    ProductWrite,
    MultiplyReturn,
    CopyRead,
    CopyWait,
    CopyWrite,
    ExponentRead,
    ExponentWait,
    VerifyRead,
    VerifyWait,
    VerifyBaseRead,
    VerifyBaseWait,
    ReleaseRead,
    ReleaseWait,
    ReleaseWrite,
    PrivateClear,
    RsaClear,
    RsaScrub
  } rsa_state_e;
  typedef enum logic [3:0] {
    ConvertBase,
    ConvertOne,
    Table2,
    Table3,
    PrivateSquare1,
    PrivateSquare2,
    PrivateMultiply,
    PublicSquare,
    PublicMultiply,
    ConvertOut,
    VerifyConvert,
    VerifySquare,
    VerifyMultiply,
    VerifyOut
  } rsa_phase_e;
  typedef struct packed {
    rsa_state_e  state;
    rsa_phase_e  phase;
    logic        prepared,       result_valid,  done,        error,          private_operation;
    logic [31:0] cycles;
    logic [31:0] word,           selected_word, modulus_low, inverse,        n0_prime;
    logic [5:0]  index;
    logic [11:0] prepare_round;
    logic [2:0]  inverse_round;
    logic        carry,          high,          borrow,      use_subtracted;
    logic        greater,        less,          mismatch;
    logic [10:0] exponent_index;
    logic [9:0]  window_index;
    logic [1:0]  window_value,   scan_index;
    logic [4:0]  left_slot,      right_slot;
    logic [3:0]  result_slot,    copy_slot;
    logic [2:0]  clear_slot;
    logic [11:0] scrub_cycles;
    logic        scrub_timeout;
  } rsa_registers_t;
  rsa_registers_t s_regs_d, s_regs_q;
  logic [31:0] s_inverse_next;
  logic [32:0] s_difference;
  logic [3:0] s_scan_slot, s_clear_slot;
  logic s_mont_busy, s_mont_done, s_scrub_busy, s_scrub_done, s_scrub_err;
  crypto_mem_req_t        s_mont_req;
  crypto_mem_req_t  [1:0] s_scrub_req;
  crypto_mem_resp_t [1:0] s_scrub_resp;
  logic             [2:0] s_scrub_bank;
  dffr #(
      .DATA_WIDTH($bits(rsa_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  crypto_montgomery_sram u_montgomery (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .clear_i   (zeroize_i || abort_i || s_regs_q.state == RsaClear),
      .start_i   (s_regs_q.state == MultiplyStart),
      .n0_prime_i(s_regs_q.n0_prime),
      .busy_o    (s_mont_busy),
      .done_o    (s_mont_done),
      .req_o     (s_mont_req),
      .resp_i    (work_resp_i)
  );
  assign s_scrub_resp = {work_resp_i, retained_resp_i};
  crypto_scrubber #(
      .NumBanks(2)
  ) u_scrub (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (s_regs_q.state == RsaClear),
      .cancel_i    (zeroize_i),
      .first_row_i (10'd0),
      .busy_o      (s_scrub_busy),
      .done_o      (s_scrub_done),
      .error_o     (s_scrub_err),
      .error_bank_o(s_scrub_bank),
      .error_row_o (scrub_error_row_o),
      .req_o       (s_scrub_req),
      .resp_i      (s_scrub_resp)
  );
  assign busy_o = s_regs_q.state != RsaIdle;
  assign done_o = s_regs_q.done;
  assign error_o = s_regs_q.error;
  assign prepared_o = s_regs_q.prepared;
  assign result_valid_o = s_regs_q.result_valid;
  assign cycles_o = s_regs_q.cycles;
  assign progress_o = {20'd0, s_regs_q.exponent_index, s_regs_q.private_operation};
  assign scrub_error_o = s_scrub_err || s_regs_q.scrub_timeout;
  assign scrub_error_bank_o = s_scrub_bank + 3'd4;
  assign s_inverse_next = s_regs_q.inverse * (32'd2 - s_regs_q.modulus_low * s_regs_q.inverse);
  assign
      s_difference = {1'b0, work_resp_i.data} - {1'b0, retained_resp_i.data} - 33'(s_regs_q.borrow);
  always_comb begin
    unique case (s_regs_q.scan_index)
      2'd0:    s_scan_slot = 4'd5;
      2'd1:    s_scan_slot = 4'd6;
      2'd2:    s_scan_slot = 4'd8;
      default: s_scan_slot = 4'd9;
    endcase
    unique case (s_regs_q.clear_slot)
      3'd0:    s_clear_slot = 4'd1;
      3'd1:    s_clear_slot = 4'd7;
      3'd2:    s_clear_slot = 4'd8;
      3'd3:    s_clear_slot = 4'd9;
      default: s_clear_slot = 4'd11;
    endcase
    s_regs_d       = s_regs_q;
    s_regs_d.done  = 1'b0;
    retained_req_o = '0;
    work_req_o     = s_mont_req;
    if (busy_o) s_regs_d.cycles = s_regs_q.cycles + 1'b1;
    unique case (s_regs_q.state)
      RsaIdle: begin
        if (prepare_i) begin
          s_regs_d       = '0;
          s_regs_d.state = PrepareRead;
        end else if (start_i) begin
          s_regs_d.result_valid = 1'b0;
          s_regs_d.error        = 1'b0;
          s_regs_d.cycles       = '0;
          if (!s_regs_q.prepared ||
              (!private_i && ((exponent_bits_i == 0) || (exponent_bits_i > 12'd2048)))) begin
            s_regs_d.error = 1'b1;
            s_regs_d.done  = 1'b1;
          end else begin
            s_regs_d.private_operation = private_i;
            s_regs_d.exponent_index    = private_i ? 11'd2047 : 11'(exponent_bits_i - 1'b1);
            s_regs_d.window_index      = 10'd1023;
            s_regs_d.index             = 6'd63;
            s_regs_d.greater           = 1'b0;
            s_regs_d.less              = 1'b0;
            s_regs_d.mismatch          = 1'b0;
            s_regs_d.state             = BaseRead;
          end
        end
      end
      PrepareRead: begin
        retained_req_o = mem_read({4'd0, s_regs_q.index});
        s_regs_d.state = PrepareWait;
      end
      PrepareWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word = retained_resp_i.data;
        if (s_regs_q.index == 0) s_regs_d.modulus_low = retained_resp_i.data;
        if (((s_regs_q.index == 0) && !retained_resp_i.data[0]) ||
            ((s_regs_q.index == 6'd63) && !retained_resp_i.data[31]))
          s_regs_d.error = 1'b1;
        s_regs_d.state = PrepareCopy;
      end
      PrepareCopy: begin
        retained_req_o = mem_write({4'd12, s_regs_q.index}, s_regs_q.word);
        s_regs_d.state = PrepareSeed;
      end
      PrepareSeed: begin
        retained_req_o = mem_write({4'd4, s_regs_q.index}, s_regs_q.index == 0 ? 32'd1 : 32'd0);
        if (s_regs_q.index == 6'd63) begin
          if (s_regs_q.error) begin
            s_regs_d.done  = 1'b1;
            s_regs_d.state = RsaIdle;
          end else begin
            s_regs_d.inverse       = 32'd1;
            s_regs_d.inverse_round = '0;
            s_regs_d.state         = PrepareInverse;
          end
        end else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = PrepareRead;
        end
      end
      PrepareInverse: begin
        s_regs_d.inverse = s_inverse_next;
        if (s_regs_q.inverse_round == 3'd4) begin
          s_regs_d.n0_prime      = ~s_inverse_next + 1'b1;
          s_regs_d.index         = '0;
          s_regs_d.carry         = 1'b0;
          s_regs_d.prepare_round = '0;
          s_regs_d.state         = PrepareDoubleRead;
        end else s_regs_d.inverse_round = s_regs_q.inverse_round + 1'b1;
      end
      PrepareDoubleRead: begin
        retained_req_o = mem_read({4'd4, s_regs_q.index});
        s_regs_d.state = PrepareDoubleWait;
      end
      PrepareDoubleWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = {retained_resp_i.data[30:0], s_regs_q.carry};
        s_regs_d.carry = retained_resp_i.data[31];
        s_regs_d.state = PrepareDoubleWrite;
      end
      PrepareDoubleWrite: begin
        work_req_o = mem_write(10'd385 + 10'(s_regs_q.index), s_regs_q.word);
        if (s_regs_q.index == 6'd63) begin
          s_regs_d.high   = s_regs_q.carry;
          s_regs_d.index  = '0;
          s_regs_d.borrow = 1'b0;
          s_regs_d.state  = PrepareHighWrite;
        end else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = PrepareDoubleRead;
        end
      end
      PrepareHighWrite: begin
        work_req_o     = mem_write(10'd449, {31'd0, s_regs_q.high});
        s_regs_d.state = PrepareSubtractRead;
      end
      PrepareSubtractRead: begin
        work_req_o     = mem_read(10'd385 + 10'(s_regs_q.index));
        retained_req_o = mem_read({4'd12, s_regs_q.index});
        s_regs_d.state = PrepareSubtractWait;
      end
      PrepareSubtractWait:
      if (work_resp_i.valid && retained_resp_i.valid) begin
        s_regs_d.word   = s_difference[31:0];
        s_regs_d.borrow = s_difference[32];
        s_regs_d.state  = PrepareSubtractWrite;
      end
      PrepareSubtractWrite: begin
        work_req_o = mem_write(10'd450 + 10'(s_regs_q.index), s_regs_q.word);
        if (s_regs_q.index == 6'd63) begin
          s_regs_d.use_subtracted = s_regs_q.high || !s_regs_q.borrow;
          s_regs_d.index          = '0;
          s_regs_d.state          = PrepareSelectRead;
        end else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = PrepareSubtractRead;
        end
      end
      PrepareSelectRead: begin
        work_req_o     = mem_read(10'd385 + 10'(s_regs_q.index));
        s_regs_d.state = PrepareSelectWait;
      end
      PrepareSelectWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = work_resp_i.data;
        s_regs_d.state = PrepareCandidateRead;
      end
      PrepareCandidateRead: begin
        work_req_o     = mem_read(10'd450 + 10'(s_regs_q.index));
        s_regs_d.state = PrepareCandidateWait;
      end
      PrepareCandidateWait:
      if (work_resp_i.valid) begin
        if (s_regs_q.use_subtracted) s_regs_d.word = work_resp_i.data;
        s_regs_d.state = PrepareSelectWrite;
      end
      PrepareSelectWrite: begin
        retained_req_o = mem_write({4'd4, s_regs_q.index}, s_regs_q.word);
        if (s_regs_q.index == 6'd63) begin
          s_regs_d.index = '0;
          s_regs_d.carry = 1'b0;
          if (s_regs_q.prepare_round == 12'd4095) begin
            s_regs_d.prepared = 1'b1;
            s_regs_d.done     = 1'b1;
            s_regs_d.state    = RsaIdle;
          end else begin
            s_regs_d.prepare_round = s_regs_q.prepare_round + 1'b1;
            s_regs_d.state         = PrepareDoubleRead;
          end
        end else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = PrepareSelectRead;
        end
      end
      BaseRead: begin
        retained_req_o = mem_read({4'd2, s_regs_q.index});
        s_regs_d.state = BaseWait;
      end
      BaseWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = retained_resp_i.data;
        s_regs_d.state = BaseModulusRead;
      end
      BaseModulusRead: begin
        retained_req_o = mem_read({4'd0, s_regs_q.index});
        s_regs_d.state = BaseModulusWait;
      end
      BaseModulusWait:
      if (retained_resp_i.valid) begin
        if (!s_regs_q.greater && !s_regs_q.less) begin
          s_regs_d.greater = s_regs_q.word > retained_resp_i.data;
          s_regs_d.less    = s_regs_q.word < retained_resp_i.data;
        end
        if (s_regs_q.index == 0) begin
          if (!s_regs_d.less) begin
            s_regs_d.error = 1'b1;
            s_regs_d.done  = 1'b1;
            s_regs_d.state = RsaIdle;
          end else begin
            s_regs_d.phase = ConvertBase;
            s_regs_d.state = LaunchMultiply;
          end
        end else begin
          s_regs_d.index = s_regs_q.index - 1'b1;
          s_regs_d.state = BaseRead;
        end
      end
      LaunchMultiply: begin
        s_regs_d.index       = '0;
        s_regs_d.scan_index  = '0;
        s_regs_d.left_slot   = 5'd7;
        s_regs_d.right_slot  = 5'd7;
        s_regs_d.result_slot = 4'd7;
        unique case (s_regs_q.phase)
          ConvertBase: begin
            s_regs_d.left_slot   = 5'd2;
            s_regs_d.right_slot  = 5'd4;
            s_regs_d.result_slot = 4'd6;
          end
          ConvertOne: begin
            s_regs_d.left_slot   = 5'd16;
            s_regs_d.right_slot  = 5'd4;
            s_regs_d.result_slot = 4'd5;
          end
          Table2: begin
            s_regs_d.left_slot   = 5'd6;
            s_regs_d.right_slot  = 5'd6;
            s_regs_d.result_slot = 4'd8;
          end
          Table3: begin
            s_regs_d.left_slot   = 5'd8;
            s_regs_d.right_slot  = 5'd6;
            s_regs_d.result_slot = 4'd9;
          end
          PrivateMultiply: s_regs_d.right_slot = 5'd17;
          PublicMultiply:  s_regs_d.right_slot = 5'd6;
          ConvertOut: begin
            s_regs_d.right_slot  = 5'd16;
            s_regs_d.result_slot = s_regs_q.private_operation ? 4'd10 : 4'd3;
          end
          VerifyConvert: begin
            s_regs_d.left_slot   = 5'd10;
            s_regs_d.right_slot  = 5'd4;
            s_regs_d.result_slot = 4'd11;
          end
          VerifyMultiply:  s_regs_d.right_slot = 5'd11;
          VerifyOut: begin
            s_regs_d.right_slot  = 5'd16;
            s_regs_d.result_slot = 4'd13;
          end
          default: begin
          end
        endcase
        s_regs_d.state = CopyLeftRead;
      end
      CopyLeftRead: begin
        // Slot 16 is the scalar integer one; it is never a hidden wide copy.
        if (s_regs_q.left_slot == 5'd16) begin
          s_regs_d.word  = s_regs_q.index == 0 ? 32'd1 : 32'd0;
          s_regs_d.state = CopyLeftWrite;
        end else begin
          retained_req_o = mem_read({s_regs_q.left_slot[3:0], s_regs_q.index});
          s_regs_d.state = CopyLeftWait;
        end
      end
      CopyLeftWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = retained_resp_i.data;
        s_regs_d.state = CopyLeftWrite;
      end
      CopyLeftWrite: begin
        work_req_o          = mem_write({4'd0, s_regs_q.index}, s_regs_q.word);
        s_regs_d.scan_index = '0;
        s_regs_d.state      = CopyRightRead;
      end
      CopyRightRead: begin
        if (s_regs_q.right_slot == 5'd16) begin
          s_regs_d.word  = s_regs_q.index == 0 ? 32'd1 : 32'd0;
          s_regs_d.state = CopyRightWrite;
        end else begin
          retained_req_o = mem_read({s_regs_q.right_slot == 5'd17 ? s_scan_slot :
                                     s_regs_q.right_slot[3:0], s_regs_q.index});
          s_regs_d.state = CopyRightWait;
        end
      end
      CopyRightWait:
      if (retained_resp_i.valid) begin
        if ((s_regs_q.right_slot != 5'd17) || (s_regs_q.scan_index == s_regs_q.window_value))
          s_regs_d.word = retained_resp_i.data;
        // Scan 0,1,2,3 for every private window and limb, independent of data.
        if ((s_regs_q.right_slot == 5'd17) && (s_regs_q.scan_index != 2'd3)) begin
          s_regs_d.scan_index = s_regs_q.scan_index + 1'b1;
          s_regs_d.state      = CopyRightRead;
        end else s_regs_d.state = CopyRightWrite;
      end
      CopyRightWrite: begin
        work_req_o     = mem_write(10'd64 + 10'(s_regs_q.index), s_regs_q.word);
        s_regs_d.state = CopyModulusRead;
      end
      CopyModulusRead: begin
        retained_req_o = mem_read({4'd0, s_regs_q.index});
        s_regs_d.state = CopyModulusWait;
      end
      CopyModulusWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = retained_resp_i.data;
        s_regs_d.state = CopyModulusWrite;
      end
      CopyModulusWrite: begin
        work_req_o     = mem_write(10'd128 + 10'(s_regs_q.index), s_regs_q.word);
        s_regs_d.index = s_regs_q.index + 1'b1;
        s_regs_d.state = s_regs_q.index == 6'd63 ? MultiplyStart : CopyLeftRead;
      end
      MultiplyStart: s_regs_d.state = MultiplyWait;
      MultiplyWait:
      if (s_mont_done) begin
        s_regs_d.index = '0;
        s_regs_d.state = ProductRead;
      end
      ProductRead: begin
        work_req_o     = mem_read(10'd321 + 10'(s_regs_q.index));
        s_regs_d.state = ProductWait;
      end
      ProductWait:
      if (work_resp_i.valid) begin
        s_regs_d.word  = work_resp_i.data;
        s_regs_d.state = ProductWrite;
      end
      ProductWrite: begin
        retained_req_o = mem_write({s_regs_q.result_slot, s_regs_q.index}, s_regs_q.word);
        s_regs_d.index = s_regs_q.index + 1'b1;
        s_regs_d.state = s_regs_q.index == 6'd63 ? MultiplyReturn : ProductRead;
      end
      MultiplyReturn: begin
        s_regs_d.state = LaunchMultiply;
        unique case (s_regs_q.phase)
          ConvertBase:    s_regs_d.phase = ConvertOne;
          ConvertOne: begin
            s_regs_d.phase     = s_regs_q.private_operation ? Table2 : PublicSquare;
            s_regs_d.copy_slot = 4'd5;
            s_regs_d.state     = CopyRead;
          end
          Table2:         s_regs_d.phase = Table3;
          Table3:         s_regs_d.phase = PrivateSquare1;
          PrivateSquare1: s_regs_d.phase = PrivateSquare2;
          PrivateSquare2: s_regs_d.state = ExponentRead;
          PrivateMultiply: begin
            if (s_regs_q.window_index == 0) s_regs_d.phase = ConvertOut;
            else begin
              s_regs_d.window_index = s_regs_q.window_index - 1'b1;
              s_regs_d.phase        = PrivateSquare1;
            end
          end
          PublicSquare:   s_regs_d.state = ExponentRead;
          PublicMultiply: begin
            if (s_regs_q.exponent_index == 0) s_regs_d.phase = ConvertOut;
            else begin
              s_regs_d.exponent_index = s_regs_q.exponent_index - 1'b1;
              s_regs_d.phase          = PublicSquare;
            end
          end
          ConvertOut: begin
            if (s_regs_q.private_operation) s_regs_d.phase = VerifyConvert;
            else begin
              s_regs_d.result_valid = 1'b1;
              s_regs_d.done         = 1'b1;
              s_regs_d.state        = RsaIdle;
            end
          end
          VerifyConvert: begin
            s_regs_d.phase          = VerifySquare;
            s_regs_d.exponent_index = 11'd16;
            s_regs_d.copy_slot      = 4'd5;
            s_regs_d.state          = CopyRead;
          end
          VerifySquare: begin
            if ((s_regs_q.exponent_index == 11'd16) || (s_regs_q.exponent_index == 0))
              s_regs_d.phase = VerifyMultiply;
            else s_regs_d.exponent_index = s_regs_q.exponent_index - 1'b1;
          end
          VerifyMultiply: begin
            if (s_regs_q.exponent_index == 0) s_regs_d.phase = VerifyOut;
            else begin
              s_regs_d.exponent_index = s_regs_q.exponent_index - 1'b1;
              s_regs_d.phase          = VerifySquare;
            end
          end
          VerifyOut: begin
            s_regs_d.mismatch = 1'b0;
            s_regs_d.state    = VerifyRead;
          end
          default:        s_regs_d.state = RsaClear;
        endcase
      end
      CopyRead: begin
        retained_req_o = mem_read({s_regs_q.copy_slot, s_regs_q.index});
        s_regs_d.state = CopyWait;
      end
      CopyWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = retained_resp_i.data;
        s_regs_d.state = CopyWrite;
      end
      CopyWrite: begin
        retained_req_o = mem_write({4'd7, s_regs_q.index}, s_regs_q.word);
        s_regs_d.index = s_regs_q.index + 1'b1;
        s_regs_d.state = s_regs_q.index == 6'd63 ? LaunchMultiply : CopyRead;
      end
      ExponentRead: begin
        retained_req_o = mem_read(
          {
            4'd1,
            s_regs_q.private_operation ? s_regs_q.window_index[9:4] : s_regs_q.exponent_index[10:5]
          }
        );
        s_regs_d.state = ExponentWait;
      end
      ExponentWait:
      if (retained_resp_i.valid) begin
        s_regs_d.state = LaunchMultiply;
        if (s_regs_q.private_operation) begin
          s_regs_d.window_value = retained_resp_i.data[s_regs_q.window_index[3:0]*2+:2];
          s_regs_d.phase        = PrivateMultiply;
        end else if (retained_resp_i.data[s_regs_q.exponent_index[4:0]])
          s_regs_d.phase = PublicMultiply;
        else if (s_regs_q.exponent_index == 0) s_regs_d.phase = ConvertOut;
        else begin
          s_regs_d.exponent_index = s_regs_q.exponent_index - 1'b1;
          s_regs_d.phase          = PublicSquare;
        end
      end
      VerifyRead: begin
        retained_req_o = mem_read({4'd13, s_regs_q.index});
        s_regs_d.state = VerifyWait;
      end
      VerifyWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = retained_resp_i.data;
        s_regs_d.state = VerifyBaseRead;
      end
      VerifyBaseRead: begin
        retained_req_o = mem_read({4'd2, s_regs_q.index});
        s_regs_d.state = VerifyBaseWait;
      end
      VerifyBaseWait:
      if (retained_resp_i.valid) begin
        s_regs_d.mismatch = s_regs_q.mismatch || (s_regs_q.word != retained_resp_i.data);
        s_regs_d.index    = s_regs_q.index + 1'b1;
        s_regs_d.state    = s_regs_q.index == 6'd63 ? ReleaseRead : VerifyRead;
      end
      ReleaseRead: begin
        retained_req_o = mem_read({4'd10, s_regs_q.index});
        s_regs_d.state = ReleaseWait;
      end
      ReleaseWait:
      if (retained_resp_i.valid) begin
        s_regs_d.word  = s_regs_q.mismatch ? 32'd0 : retained_resp_i.data;
        s_regs_d.state = ReleaseWrite;
      end
      ReleaseWrite: begin
        retained_req_o      = mem_write({4'd3, s_regs_q.index}, s_regs_q.word);
        s_regs_d.index      = s_regs_q.index + 1'b1;
        s_regs_d.clear_slot = '0;
        s_regs_d.state      = s_regs_q.index == 6'd63 ? PrivateClear : ReleaseRead;
      end
      PrivateClear: begin
        retained_req_o = mem_write({s_clear_slot, s_regs_q.index}, 32'd0);
        s_regs_d.index = s_regs_q.index + 1'b1;
        if (s_regs_q.index == 6'd63) begin
          if (s_regs_q.clear_slot == 3'd4) begin
            s_regs_d.result_valid = !s_regs_q.mismatch;
            s_regs_d.error        = s_regs_q.mismatch;
            s_regs_d.done         = 1'b1;
            s_regs_d.word         = '0;
            s_regs_d.window_value = '0;
            s_regs_d.state        = RsaIdle;
          end else s_regs_d.clear_slot = s_regs_q.clear_slot + 1'b1;
        end
      end
      RsaClear: begin
        s_regs_d        = '0;
        s_regs_d.cycles = s_regs_q.cycles + 1'b1;
        s_regs_d.state  = RsaScrub;
      end
      RsaScrub: begin
        retained_req_o        = s_scrub_req[0];
        work_req_o            = s_scrub_req[1];
        s_regs_d.scrub_cycles = s_regs_q.scrub_cycles + 1'b1;
        if (s_scrub_done) s_regs_d.state = RsaIdle;
        if (s_regs_q.scrub_cycles >= 12'd2055) s_regs_d.scrub_timeout = 1'b1;
      end
      default:       s_regs_d.state = RsaClear;
    endcase
    if (modulus_dirty_i) s_regs_d.prepared = 1'b0;
    if (abort_i && (s_regs_q.state < RsaClear)) begin
      s_regs_d.state        = RsaClear;
      s_regs_d.prepared     = 1'b0;
      s_regs_d.result_valid = 1'b0;
      s_regs_d.done         = 1'b0;
      retained_req_o        = '0;
      work_req_o            = '0;
    end
    if (zeroize_i) begin
      s_regs_d       = '0;
      retained_req_o = '0;
      work_req_o     = '0;
    end
  end
`ifndef SYNTHESIS
`ifdef FORMAL
  // Control proof with arbitrary SRAM data; arithmetic is covered by KATs.
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (!result_valid_o || !busy_o);
      // Inductive invariants span the limb-copy and cleanup loops; a short
      // induction window must not start in an impossible release phase.
      if (s_regs_q.state >= VerifyRead && s_regs_q.state <= PrivateClear)
        assert (s_regs_q.phase == VerifyOut);
      if (s_regs_q.state >= LaunchMultiply && s_regs_q.state <= PrivateClear &&
          s_regs_q.phase == VerifyOut)
        assert (s_regs_q.exponent_index == 0);
      if (result_valid_o && s_regs_q.private_operation) begin
        assert (!s_regs_q.mismatch);
        assert (s_regs_q.phase == VerifyOut);
        assert (s_regs_q.exponent_index == 0);
      end
      if (s_regs_q.state == ReleaseWrite && !s_regs_q.mismatch)
        assert (s_regs_q.phase == VerifyOut);
      if (s_regs_q.state == RsaScrub) assert (!result_valid_o && !prepared_o);
      if (zeroize_i || (abort_i && s_regs_q.state < RsaClear))
        assert (!retained_req_o.valid && !work_req_o.valid);
    end
  end
`endif
`endif
endmodule
