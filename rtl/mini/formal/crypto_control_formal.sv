// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
// Control proofs assume a running clock and one-cycle, non-failing SRAM
// responses. Constant data is unconstrained; arithmetic is tested separately.
module crypto_control_formal (
    input logic        clk_i,
    reset_i,
    input logic [ 2:0] command,
    input logic        table_write,
    zeroize,
    engines_busy,
    error_clear,
    input logic        local_error,
    input logic [31:0] table_data,
    constant_data
);
  import crypto_mem_pkg::*;
  logic                    rst_n_i = 1'b0;
  logic                    past_valid = 1'b0;
  crypto_mem_req_t  [ 5:0] req;
  crypto_mem_resp_t [ 5:0] resp = '0;
  logic             [ 6:0] status;
  logic             [11:0] words;
  logic [31:0] crc, error, cycles;
  logic ready_event, zeroized_event, error_event;
  crypto_mem_ctrl u_dut (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .begin_i           (command[0]),
      .commit_i          (command[1]),
      .cancel_i          (command[2]),
      .table_write_i     (table_write),
      .table_data_i      (table_data),
      .zeroize_i         (zeroize),
      .error_clear_i     (error_clear),
      .engines_busy_i    (engines_busy),
      .fifo_busy_i       (1'b0),
      .fifo_error_i      (1'b0),
      .local_error_i     (local_error),
      .local_error_bank_i(3'd0),
      .local_error_row_i (10'd0),
      .command_error_o   (),
      .data_error_o      (),
      .clear_o           (),
      .status_o          (status),
      .words_o           (words),
      .crc_o             (crc),
      .error_o           (error),
      .cycles_o          (cycles),
      .ready_event_o     (ready_event),
      .zeroized_event_o  (zeroized_event),
      .error_event_o     (error_event),
      .req_o             (req),
      .resp_i            (resp)
  );
  always @(posedge clk_i) begin
    rst_n_i    <= !reset_i;
    past_valid <= 1'b1;
    assume ((command & (command - 1'b1)) == 0);
    assume (!(table_write && (|command)));
    for (int bank = 0; bank < 6; bank++) begin
      resp[bank].valid <= req[bank].valid;
      resp[bank].write <= req[bank].write;
      resp[bank].row   <= req[bank].row;
      resp[bank].tag   <= req[bank].tag;
      resp[bank].epoch <= req[bank].epoch;
      resp[bank].token <= req[bank].token;
      resp[bank].data  <= bank < 2 ? constant_data : 32'd0;
    end
    if (rst_n_i) begin
      if (past_valid && $past(rst_n_i && (status[6] || local_error))) assert (status[6]);
      assert (words <= 12'd2048);
      assert (!status[0] || (status[5:1] == 5'b10001));
      // Lock retains image identity through scrub/fault as well as READY.
      // This invariant also closes induction across the 2050-cycle scrub.
      assert (!status[5] || crc == 32'h99ca52fe);
      assert (!status[5] || words == 12'd2048);
      assert (!status[5] || !(status[3] || status[4]));
      assert (!status[4] || words == 12'd2048);
      assert (!ready_event || status[0]);
      assert (!zeroized_event || !status[2]);
      assert (!(ready_event && zeroized_event));
      assert (!status[5] || !(req[0].write || req[1].write));
      assert (req[2] == req[3] && req[2] == req[4] && req[2] == req[5]);
      if (req[2].valid) begin
        assert (status[2]);
        assert (!req[2].write || (req[2].data == 0 && req[2].mask == 4'hf));
      end
      // Internal progress has an explicit watchdog; no unbounded poll state.
      if (status[2]) assert (u_dut.s_regs_q.watchdog <= 14'd2056);
      if (status[4]) assert (u_dut.s_regs_q.watchdog <= 14'd8192);
      if (status[6]) assert (!status[0] && !ready_event && !zeroized_event);
    end
    cover (rst_n_i && !status[2]);
    cover (rst_n_i && zeroized_event);
  end
endmodule
