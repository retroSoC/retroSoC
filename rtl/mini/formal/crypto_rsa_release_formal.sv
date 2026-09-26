// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
// SRAM data is arbitrary. Prove the release/abort policy, not RSA arithmetic.
module crypto_rsa_release_formal (
    input logic        clk_i,
    input logic        clear,
    abort,
    dirty,
    prepare,
    start,
    private_operation,
    input logic [11:0] exponent_bits,
    input logic [31:0] retained_data,
    work_data
);
  import crypto_mem_pkg::*;
  logic rst_n_i = 1'b0;
  crypto_mem_req_t retained_req, work_req;
  crypto_mem_resp_t retained_resp = '0, work_resp = '0;
  logic busy, done, error, prepared, result_valid;
  crypto_rsa_sram_core u_dut (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .zeroize_i         (clear),
      .abort_i           (abort),
      .modulus_dirty_i   (dirty),
      .prepare_i         (prepare),
      .start_i           (start),
      .private_i         (private_operation),
      .exponent_bits_i   (exponent_bits),
      .busy_o            (busy),
      .done_o            (done),
      .error_o           (error),
      .prepared_o        (prepared),
      .result_valid_o    (result_valid),
      .cycles_o          (),
      .progress_o        (),
      .scrub_error_o     (),
      .scrub_error_bank_o(),
      .scrub_error_row_o (),
      .retained_req_o    (retained_req),
      .work_req_o        (work_req),
      .retained_resp_i   (retained_resp),
      .work_resp_i       (work_resp)
  );
  always @(posedge clk_i) begin
    rst_n_i             <= 1'b1;
    retained_resp.valid <= retained_req.valid;
    retained_resp.write <= retained_req.write;
    retained_resp.row   <= retained_req.row;
    retained_resp.data  <= retained_data;
    retained_resp.tag   <= retained_req.tag;
    retained_resp.epoch <= retained_req.epoch;
    retained_resp.token <= retained_req.token;
    work_resp.valid     <= work_req.valid;
    work_resp.write     <= work_req.write;
    work_resp.row       <= work_req.row;
    work_resp.data      <= work_data;
    work_resp.tag       <= work_req.tag;
    work_resp.epoch     <= work_req.epoch;
    work_resp.token     <= work_req.token;
    if (rst_n_i) begin
      assert (!result_valid || !busy);
    end
  end
endmodule
