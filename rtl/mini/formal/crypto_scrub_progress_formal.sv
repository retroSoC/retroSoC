// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
module crypto_scrub_progress_formal (
    input logic       clk_i,
    start,
    cancel,
    input logic [9:0] first_row
);
  import crypto_mem_pkg::*;
  logic        rst_n_i = 0;
  logic [11:0] elapsed = 0;
  logic busy, done, error;
  crypto_mem_req_t  [3:0] req;
  crypto_mem_resp_t [3:0] resp = '0;
  crypto_scrubber #(
      .NumBanks(4)
  ) u_dut (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (start),
      .cancel_i    (cancel),
      .first_row_i (first_row),
      .busy_o      (busy),
      .done_o      (done),
      .error_o     (error),
      .error_bank_o(),
      .error_row_o (),
      .req_o       (req),
      .resp_i      (resp)
  );
  always @(posedge clk_i) begin
    rst_n_i <= 1;
    if (cancel || (!busy && start)) elapsed <= 0;
    else if (busy) elapsed <= elapsed + 1'b1;
    for (int bank = 0; bank < 4; bank++) begin
      resp[bank].valid <= req[bank].valid;
      resp[bank].write <= req[bank].write;
      resp[bank].row   <= req[bank].row;
      resp[bank].data  <= 32'd0;
      resp[bank].tag   <= req[bank].tag;
      resp[bank].epoch <= req[bank].epoch;
      resp[bank].token <= req[bank].token;
    end
    if (rst_n_i) begin
      assert (!error);
      if (busy) assert (elapsed <= 12'd2049);
      if (req[0].valid && req[0].write) begin
        assert (u_dut.s_regs_q.row >= u_dut.s_regs_q.first_row);
        assert (elapsed == 12'(u_dut.s_regs_q.row) - 12'(u_dut.s_regs_q.first_row));
      end
      if (req[0].valid && !req[0].write) begin
        assert (u_dut.s_regs_q.row >= u_dut.s_regs_q.first_row);
        assert(elapsed==12'd1024+12'(u_dut.s_regs_q.row)-12'd2*12'(u_dut.s_regs_q.first_row));
      end
      if (busy && !done && !req[0].valid && !cancel)
        assert (elapsed == 12'd2048 - 12'd2 * 12'(u_dut.s_regs_q.first_row));
      if (done) assert (elapsed == 12'd2049 - 12'd2 * 12'(u_dut.s_regs_q.first_row));
      if (busy && elapsed == 12'd2049) assert (done);
    end
  end
endmodule
