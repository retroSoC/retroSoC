// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "crypto_define.svh"

module crypto_mem_ctrl (
    input  logic                                    clk_i,
    input  logic                                    rst_n_i,
    input  logic                                    begin_i,
    input  logic                                    commit_i,
    input  logic                                    cancel_i,
    input  logic                                    table_write_i,
    input  logic                             [31:0] table_data_i,
    input  logic                                    zeroize_i,
    input  logic                                    error_clear_i,
    input  logic                                    engines_busy_i,
    input  logic                                    fifo_busy_i,
    input  logic                                    fifo_error_i,
    input  logic                                    local_error_i,
    input  logic                             [ 2:0] local_error_bank_i,
    input  logic                             [ 9:0] local_error_row_i,
    output logic                                    command_error_o,
    output logic                                    data_error_o,
    output logic                                    clear_o,
    output logic                             [ 6:0] status_o,
    output logic                             [11:0] words_o,
    output logic                             [31:0] crc_o,
    output logic                             [31:0] error_o,
    output logic                             [31:0] cycles_o,
    output logic                                    ready_event_o,
    output logic                                    zeroized_event_o,
    output logic                                    error_event_o,
    output crypto_mem_pkg::crypto_mem_req_t  [ 5:0] req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t [ 5:0] resp_i
);
  import crypto_mem_pkg::*;
  localparam logic [31:0] TableCrc = `APB4_CRYPTO__TABLE_CRC_VALUE;
  typedef enum logic [2:0] {
    MemBoot,
    MemScrub,
    MemIdle,
    MemLoad,
    MemVerify,
    MemDrain,
    MemFault
  } mem_state_e;
  typedef struct packed {
    mem_state_e  state;
    logic        locked;
    logic        explicit_clear;
    logic [11:0] words;
    logic [10:0] row;
    logic [31:0] input_crc;
    logic [31:0] verify_crc;
    logic [31:0] crc;
    logic [31:0] error;
    logic [31:0] cycles;
    logic [13:0] watchdog;
    logic        ready_event;
    logic        zeroized_event;
    logic        error_event;
  } mem_registers_t;
  mem_registers_t s_regs_d, s_regs_q;
  crypto_mem_req_t [3:0] s_scrub_req;
  logic s_scrub_done, s_scrub_busy, s_scrub_err;
  logic [2:0] s_scrub_err_bank;
  logic [9:0] s_scrub_err_row;
  logic s_scrub_start, s_padding_err, s_read_bank;
  logic             [ 7:0] s_err_code;
  logic             [ 2:0] s_err_bank;
  logic             [ 9:0] s_err_row;
  logic             [31:0] s_read_crc;
  crypto_mem_resp_t        s_read_resp;

  dffr #(
      .DATA_WIDTH($bits(mem_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  assign s_scrub_start = (s_regs_q.state == MemBoot) ||
                        (zeroize_i && (s_regs_q.state != MemScrub) &&
                         (s_regs_q.state != MemFault));
  crypto_scrubber #(
      .NumBanks(4)
  ) u_scrub (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (s_scrub_start),
      .cancel_i    (s_regs_q.state == MemFault),
      .first_row_i (10'd0),
      .busy_o      (s_scrub_busy),
      .done_o      (s_scrub_done),
      .error_o     (s_scrub_err),
      .error_bank_o(s_scrub_err_bank),
      .error_row_o (s_scrub_err_row),
      .req_o       (s_scrub_req),
      .resp_i      (resp_i[5:2])
  );
  assign clear_o = s_scrub_start;
  assign status_o = {
    s_regs_q.state == MemFault,
    s_regs_q.locked,
    (s_regs_q.state == MemVerify) || (s_regs_q.state == MemDrain),
    s_regs_q.state == MemLoad,
    (s_regs_q.state == MemBoot) || (s_regs_q.state == MemScrub),
    s_regs_q.locked && (s_regs_q.state != MemFault),
    s_regs_q.locked && (s_regs_q.state == MemIdle)
  };
  assign words_o = s_regs_q.words;
  assign crc_o = s_regs_q.crc;
  assign error_o = s_regs_q.error;
  assign cycles_o = s_regs_q.cycles;
  assign ready_event_o = s_regs_q.ready_event;
  assign zeroized_event_o = s_regs_q.zeroized_event;
  assign error_event_o = s_regs_q.error_event;
  assign s_padding_err = constant_padding_error(s_regs_q.words[10:0], table_data_i);
  assign data_error_o = (s_regs_q.state != MemLoad) || (s_regs_q.words == 12'd2048) ||
                        s_padding_err;
  assign command_error_o =
      (begin_i && ((s_regs_q.state != MemIdle) || s_regs_q.locked || engines_busy_i)) ||
      (commit_i && ((s_regs_q.state != MemLoad) || (s_regs_q.words != 12'd2048) ||
                    (s_regs_q.input_crc != ~TableCrc))) ||
      (cancel_i && (s_regs_q.locked || (s_regs_q.state == MemBoot) ||
                    (s_regs_q.state == MemScrub) || (s_regs_q.state == MemFault)));
  // At most one constant bank has a response in a cycle. Readback is one
  // word/clock, with an explicit final drain before locking the image.
  assign s_read_resp = resp_i[1].valid ? resp_i[1] : resp_i[0];
  // Isolate the constant selector from the mutable-bank response bus so that
  // scrub routing cannot retrigger the readback request combinational block.
  assign s_read_bank = resp_i[1].valid;
  assign s_read_crc = crc_word(s_regs_q.verify_crc, s_read_resp.data);
  always_comb begin
    s_regs_d                = s_regs_q;
    s_regs_d.ready_event    = 1'b0;
    s_regs_d.zeroized_event = 1'b0;
    s_regs_d.error_event    = 1'b0;
    req_o                   = '0;
    s_err_code              = '0;
    s_err_bank              = '0;
    s_err_row               = '0;
    if ((s_regs_q.state == MemBoot) || (s_regs_q.state == MemScrub)) req_o[5:2] = s_scrub_req;
    if (error_clear_i && ((s_regs_q.state == MemIdle) || (s_regs_q.state == MemFault)))
      s_regs_d.error = '0;
    if ((s_regs_q.state == MemScrub) || (s_regs_q.state == MemVerify) ||
        (s_regs_q.state == MemDrain)) begin
      s_regs_d.cycles   = s_regs_q.cycles + 1'b1;
      s_regs_d.watchdog = s_regs_q.watchdog + 1'b1;
    end
    unique case (s_regs_q.state)
      MemBoot: begin
        s_regs_d.state    = MemScrub;
        s_regs_d.watchdog = '0;
      end
      MemScrub: begin
        // An explicit request can join the reset scrub without restarting its
        // row counter, but it still needs a completion event for its caller.
        if (zeroize_i) s_regs_d.explicit_clear = 1'b1;
        if (s_scrub_done && !fifo_busy_i) begin
          if (s_scrub_err || fifo_error_i) begin
            s_err_code = 8'd5;
            s_err_bank = s_scrub_err ? (s_scrub_err_bank + 3'd2) : 3'd0;
            s_err_row  = s_scrub_err ? s_scrub_err_row : 10'd0;
          end else begin
            s_regs_d.state          = MemIdle;
            s_regs_d.zeroized_event = s_regs_q.explicit_clear || zeroize_i;
          end
        end
        if (s_regs_q.watchdog >= 14'd2055) s_err_code = 8'd6;
      end
      MemIdle: begin
        if (begin_i && !command_error_o) begin
          s_regs_d.state     = MemLoad;
          s_regs_d.words     = '0;
          s_regs_d.crc       = '0;
          s_regs_d.input_crc = '1;
          s_regs_d.error     = '0;
          s_regs_d.cycles    = '0;
        end
      end
      MemLoad: begin
        if (table_write_i) begin
          if (s_regs_q.words == 12'd2048) s_err_code = 8'd1;
          else if (s_padding_err) begin
            s_err_code = 8'd2;
            s_err_bank = {2'd0, s_regs_q.words[10]};
            s_err_row  = s_regs_q.words[9:0];
          end else begin
            req_o[s_regs_q.words[10]] = mem_write(s_regs_q.words[9:0], table_data_i);
            s_regs_d.words            = s_regs_q.words + 1'b1;
            s_regs_d.input_crc        = crc_word(s_regs_q.input_crc, table_data_i);
          end
        end
        if (commit_i) begin
          if (s_regs_q.words != 12'd2048) s_err_code = 8'd1;
          else if (s_regs_q.input_crc != ~TableCrc) s_err_code = 8'd3;
          else begin
            s_regs_d.row        = '0;
            s_regs_d.verify_crc = '1;
            s_regs_d.watchdog   = '0;
            s_regs_d.state      = MemVerify;
          end
        end
      end
      MemVerify: begin
        req_o[s_regs_q.row[10]] = mem_read(s_regs_q.row[9:0]);
        if (s_regs_q.row == 11'd2047) s_regs_d.state = MemDrain;
        else s_regs_d.row = s_regs_q.row + 1'b1;
        if (s_read_resp.valid && !s_read_resp.write) s_regs_d.verify_crc = s_read_crc;
        if (s_regs_q.watchdog >= 14'd8191) s_err_code = 8'd6;
      end
      MemDrain: begin
        if (s_read_resp.valid && !s_read_resp.write) begin
          s_regs_d.crc = ~s_read_crc;
          if (s_read_crc != ~TableCrc) s_err_code = 8'd4;
          else begin
            s_regs_d.locked      = 1'b1;
            s_regs_d.ready_event = 1'b1;
            s_regs_d.state       = MemIdle;
          end
        end
        if (s_regs_q.watchdog >= 14'd8191) s_err_code = 8'd6;
      end
      MemFault: req_o = '0;
      default:  s_err_code = 8'd6;
    endcase
    if (((s_regs_q.state == MemVerify) || (s_regs_q.state == MemDrain)) &&
        s_read_resp.valid && !s_read_resp.write && !cancel_i &&
        constant_padding_error(
            {s_read_bank, s_read_resp.row}, s_read_resp.data
        )) begin
      s_err_code = 8'd2;
      s_err_bank = {2'd0, s_read_bank};
      s_err_row  = s_read_resp.row;
    end
    if (cancel_i && !command_error_o) begin
      s_regs_d.locked      = 1'b0;
      s_regs_d.ready_event = 1'b0;
      s_regs_d.state       = MemIdle;
      s_regs_d.words       = '0;
      s_regs_d.crc         = '0;
      s_regs_d.input_crc   = '0;
      s_regs_d.verify_crc  = '0;
      req_o[1:0]           = '0;
    end
    if (local_error_i && (s_regs_q.state != MemFault)) begin
      s_err_code = 8'd5;
      s_err_bank = local_error_bank_i;
      s_err_row  = local_error_row_i;
    end
    if (s_err_code != 8'd0) begin
      if (!s_regs_d.error[31]) s_regs_d.error = {1'b1, 10'd0, s_err_row, s_err_bank, s_err_code};
      s_regs_d.error_event    = 1'b1;
      s_regs_d.ready_event    = 1'b0;
      s_regs_d.zeroized_event = 1'b0;
      if (s_err_code >= 8'd5) begin
        s_regs_d.state = MemFault;
      end else s_regs_d.state = MemIdle;
      req_o = '0;
    end
    if (s_scrub_start) begin
      // Zeroize wins a same-cycle verification completion. Only an image
      // already locked before command acceptance survives this transition.
      s_regs_d.locked         = s_regs_q.locked;
      s_regs_d.state          = MemScrub;
      s_regs_d.explicit_clear = zeroize_i;
      s_regs_d.watchdog       = '0;
      s_regs_d.cycles         = '0;
      s_regs_d.ready_event    = 1'b0;
      if (!s_regs_q.locked) begin
        s_regs_d.words      = '0;
        s_regs_d.crc        = '0;
        s_regs_d.input_crc  = '0;
        s_regs_d.verify_crc = '0;
      end
      req_o = '0;
    end
    // A fatal maintenance failure dominates every software command, including
    // a zeroize accepted on the same edge. Only reset can leave MemFault.
    if (s_err_code >= 8'd5) begin
      s_regs_d.state          = MemFault;
      s_regs_d.locked         = s_regs_q.locked;
      s_regs_d.ready_event    = 1'b0;
      s_regs_d.zeroized_event = 1'b0;
      req_o                   = '0;
    end
  end
endmodule
