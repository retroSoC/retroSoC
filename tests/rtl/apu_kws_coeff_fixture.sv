// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Verification-only APUC loader for focused engine tests. Product integration
// always uses apu_kws_coeff_loader through the private AXI DMA.
module apu_kws_coeff_fixture (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        frontend_req_valid_i,
    output logic        frontend_req_ready_o,
    input  logic [ 3:0] frontend_kind_i,
    input  logic [13:0] frontend_index_i,
    output logic        frontend_resp_valid_o,
    input  logic        frontend_resp_ready_i,
    output logic [63:0] frontend_resp_data_o,
    output logic        frontend_resp_fault_o,
    input  logic        inference_req_valid_i,
    output logic        inference_req_ready_o,
    input  logic [ 6:0] inference_index_i,
    output logic        inference_resp_valid_o,
    input  logic        inference_resp_ready_i,
    output logic [31:0] inference_resp_data_o,
    output logic        inference_resp_fault_o,
    output logic        initialized_o
);
  logic [31:0] s_apuc_words[0:15375];
  logic s_loader_active, s_loader_req, s_loader_ready, s_loader_valid, s_loader_fault;
  logic [13:0] s_loader_addr;
  logic [31:0] s_loader_data, s_loader_rdata;
  string s_apuc_path;

  apu_kws_coeff_store u_coeff_store (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .abort_i               (1'b0),
      .valid_i               (initialized_o),
      .loader_active_i       (s_loader_active),
      .loader_req_i          (s_loader_req),
      .loader_write_i        (1'b1),
      .loader_addr_i         (s_loader_addr),
      .loader_data_i         (s_loader_data),
      .loader_ready_o        (s_loader_ready),
      .loader_valid_o        (s_loader_valid),
      .loader_data_o         (s_loader_rdata),
      .loader_fault_o        (s_loader_fault),
      .frontend_req_valid_i  (frontend_req_valid_i),
      .frontend_req_ready_o  (frontend_req_ready_o),
      .frontend_kind_i       (frontend_kind_i),
      .frontend_index_i      (frontend_index_i),
      .frontend_resp_valid_o (frontend_resp_valid_o),
      .frontend_resp_ready_i (frontend_resp_ready_i),
      .frontend_resp_data_o  (frontend_resp_data_o),
      .frontend_resp_fault_o (frontend_resp_fault_o),
      .inference_req_valid_i (inference_req_valid_i),
      .inference_req_ready_o (inference_req_ready_o),
      .inference_index_i     (inference_index_i),
      .inference_resp_valid_o(inference_resp_valid_o),
      .inference_resp_ready_i(inference_resp_ready_i),
      .inference_resp_data_o (inference_resp_data_o),
      .inference_resp_fault_o(inference_resp_fault_o),
      .profile_req_valid_i   (1'b0),
      .profile_req_ready_o   (),
      .profile_index_i       (11'd0),
      .profile_resp_valid_o  (),
      .profile_resp_ready_i  (1'b0),
      .profile_resp_data_o   (),
      .profile_resp_fault_o  ()
  );

  initial begin
    initialized_o  = 1'b0;
    s_loader_active = 1'b0;
    s_loader_req    = 1'b0;
    s_loader_addr   = 14'd0;
    s_loader_data   = 32'd0;
    if (!$value$plusargs("APUC_HEX=%s", s_apuc_path)) begin
      $fatal(1, "missing +APUC_HEX=<path>");
    end
    $readmemh(s_apuc_path, s_apuc_words);
    wait (rst_n_i);
    @(negedge clk_i);
    s_loader_active = 1'b1;
    for (int unsigned word_index = 0; word_index < 15360; word_index++) begin
      while (!s_loader_ready) @(negedge clk_i);
      s_loader_addr = 14'(word_index);
      s_loader_data = s_apuc_words[word_index+16];
      s_loader_req  = 1'b1;
      @(negedge clk_i);
      s_loader_req = 1'b0;
      while (!s_loader_valid) @(negedge clk_i);
      if (s_loader_fault) $fatal(1, "APUC fixture store fault at word %0d", word_index);
    end
    s_loader_active = 1'b0;
    initialized_o   = 1'b1;
  end

  logic s_unused_loader_data;
  assign s_unused_loader_data = ^s_loader_rdata;
endmodule
