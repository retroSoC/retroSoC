// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_scrubber #(
    parameter int NumBanks = 4
) (
    input  logic                                            clk_i,
    input  logic                                            rst_n_i,
    input  logic                                            start_i,
    input  logic                                            cancel_i,
    input  logic                             [         9:0] first_row_i,
    output logic                                            busy_o,
    output logic                                            done_o,
    output logic                                            error_o,
    output logic                             [         2:0] error_bank_o,
    output logic                             [         9:0] error_row_o,
    output crypto_mem_pkg::crypto_mem_req_t  [NumBanks-1:0] req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t [NumBanks-1:0] resp_i
);
  import crypto_mem_pkg::*;
  typedef enum logic [2:0] {
    ScrubIdle,
    ScrubWrite,
    ScrubRead,
    ScrubDrain,
    ScrubDone
  } scrub_state_e;
  typedef struct packed {
    scrub_state_e state;
    logic [9:0]   row;
    logic [9:0]   first_row;
    logic         error;
    logic [2:0]   error_bank;
    logic [9:0]   error_row;
  } scrub_registers_t;
  scrub_registers_t s_regs_d, s_regs_q;
  dffr #(
      .DATA_WIDTH($bits(scrub_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  assign busy_o       = s_regs_q.state != ScrubIdle;
  assign done_o       = s_regs_q.state == ScrubDone;
  assign error_o      = s_regs_q.error;
  assign error_bank_o = s_regs_q.error_bank;
  assign error_row_o  = s_regs_q.error_row;
  always_comb begin
    s_regs_d = s_regs_q;
    req_o    = '0;
    unique case (s_regs_q.state)
      ScrubIdle:
      if (start_i) begin
        s_regs_d           = '0;
        s_regs_d.state     = ScrubWrite;
        s_regs_d.row       = first_row_i;
        s_regs_d.first_row = first_row_i;
      end
      ScrubWrite: begin
        for (int unsigned bank = 0; bank < NumBanks; bank++)
        req_o[bank] = mem_write(s_regs_q.row, 32'd0);
        if (s_regs_q.row == 10'd1023) begin
          s_regs_d.row   = s_regs_q.first_row;
          s_regs_d.state = ScrubRead;
        end else s_regs_d.row = s_regs_q.row + 1'b1;
      end
      ScrubRead: begin
        for (int unsigned bank = 0; bank < NumBanks; bank++) req_o[bank] = mem_read(s_regs_q.row);
        if (s_regs_q.row == 10'd1023) s_regs_d.state = ScrubDrain;
        else s_regs_d.row = s_regs_q.row + 1'b1;
      end
      ScrubDrain: s_regs_d.state = ScrubDone;
      ScrubDone:  s_regs_d.state = ScrubIdle;
      default:    s_regs_d.state = ScrubIdle;
    endcase
    if ((s_regs_q.state == ScrubRead) || (s_regs_q.state == ScrubDrain)) begin
      for (int unsigned bank = 0; bank < NumBanks; bank++) begin
        if (resp_i[bank].valid && !resp_i[bank].write && (resp_i[bank].data != 32'd0) &&
            !s_regs_d.error) begin
          s_regs_d.error      = 1'b1;
          s_regs_d.error_bank = 3'(bank);
          s_regs_d.error_row  = resp_i[bank].row;
        end
      end
    end
    if (cancel_i) begin
      s_regs_d = '0;
      req_o    = '0;
    end
  end
endmodule
