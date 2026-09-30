// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
// Prove AES stream retention across abort and fatal faults with arbitrary
// synchronous SRAM data and arbitrary external backpressure.
module crypto_stream_formal (
    input logic        clk_i,
    reset_i,
    abort_i,
    fault_i,
    start_i,
    commit_i,
    input logic        input_valid_i,
    input_last_i,
    output_ready_i,
    input logic [31:0] input_data_i,
    constant_data_i,
    work_data_i,
    input logic [ 3:0] input_keep_i
);
  import crypto_mem_pkg::*;
  logic rst_n = 0, past_valid = 0;
  logic busy, key_busy, key_valid, ready, valid, last;
  logic [31:0] data;
  logic [ 3:0] keep;
  crypto_mem_req_t constant_req, work_req;
  crypto_mem_resp_t constant_resp = '0, work_resp = '0;
  crypto_aes_sram_engine u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n),
      .zeroize_i        (reset_i),
      .fault_i          (fault_i),
      .abort_i          (abort_i),
      .key_commit_i     (commit_i),
      .key_dirty_i      (1'b0),
      .key_size_i       (2'd0),
      .key_valid_o      (key_valid),
      .key_busy_o       (key_busy),
      .start_i          (start_i),
      .mode_i           (2'd0),
      .decrypt_i        (1'b0),
      .length_i         (32'd16),
      .input_valid_i    (input_valid_i),
      .input_ready_o    (ready),
      .input_data_i     (input_data_i),
      .input_keep_i     (input_keep_i),
      .input_last_i     (input_last_i),
      .output_valid_o   (valid),
      .output_ready_i   (output_ready_i),
      .output_data_o    (data),
      .output_keep_o    (keep),
      .output_last_o    (last),
      .busy_o           (busy),
      .done_o           (),
      .error_o          (),
      .bytes_in_o       (),
      .bytes_out_o      (),
      .cycles_o         (),
      .fifo_busy_o      (),
      .fifo_error_o     (),
      .scrub_error_o    (),
      .scrub_error_row_o(),
      .constant_req_o   (constant_req),
      .constant_resp_i  (constant_resp),
      .work_req_o       (work_req),
      .work_resp_i      (work_resp)
  );
  always @(posedge clk_i) begin
    rst_n               <= 1;
    past_valid          <= 1;
    constant_resp.valid <= constant_req.valid;
    constant_resp.write <= constant_req.write;
    constant_resp.row   <= constant_req.row;
    constant_resp.data  <= constant_data_i;
    constant_resp.tag   <= constant_req.tag;
    constant_resp.epoch <= constant_req.epoch;
    constant_resp.token <= constant_req.token;
    work_resp.valid     <= work_req.valid;
    work_resp.write     <= work_req.write;
    work_resp.row       <= work_req.row;
    work_resp.data      <= work_data_i;
    work_resp.tag       <= work_req.tag;
    work_resp.epoch     <= work_req.epoch;
    work_resp.token     <= work_req.token;
    // Model an admitted fresh operation, not a FIFO flush issued over a held
    // output or after the APB wrapper has revoked READY on a fatal fault.
    assume (!start_i || (!busy && key_valid && !valid && !fault_i));
    assume (!commit_i || (!busy && !start_i && !fault_i));
    if (rst_n) begin
      // Common FIFO conservation closes induction: a non-full queue cannot
      // have identical read/write pointers and overwrite its held head.
      assert (u_dut.u_output_fifo.u_payload.r_count <= 4'd8);
      assert ((u_dut.u_output_fifo.u_payload.r_write_ptr -
               u_dut.u_output_fifo.u_payload.r_read_ptr) ==
              u_dut.u_output_fifo.u_payload.r_count[2:0]);
    end
    // A hard/global reset is a coordinated stream boundary. No such exception
    // is allowed for abort or a local erasure fault.
    if (past_valid && rst_n && !$past(reset_i) && $past(valid && !output_ready_i)) begin
      assert (valid);
      assert ({data, keep, last} == $past({data, keep, last}));
    end
    if (rst_n && fault_i) begin
      assert (!ready && !work_req.valid && !constant_req.valid);
      assert (!u_dut.s_regs_d.done);
      assert (u_dut.u_core.s_regs_d == 0);
    end
    if (rst_n && reset_i) assert (u_dut.s_regs_d == 0);
    if (rst_n && abort_i && !fault_i && !reset_i && u_dut.s_regs_q.state < 5'd13) begin
      assert (u_dut.s_regs_d.state == (valid && !output_ready_i ? 5'd13 : 5'd14));
      assert (!u_dut.s_regs_d.done && !work_req.valid);
    end
    cover (rst_n && fault_i && valid && !output_ready_i);
  end
endmodule
