// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps

module apu_p9_storage_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic loader_active, loader_req, loader_write, loader_ready, loader_valid, loader_fault;
  logic [13:0] loader_addr;
  logic [31:0] loader_data, loader_rdata;
  logic front_req, front_ready, front_valid, front_consume, front_fault;
  logic [ 3:0] front_kind;
  logic [13:0] front_index;
  logic [63:0] front_data;
  logic infer_req, infer_ready, infer_valid, infer_consume, infer_fault;
  logic [ 6:0] infer_index;
  logic [31:0] infer_data;
  logic memo_clear, memo_lookup, memo_insert, memo_ready, memo_done, memo_valid;
  logic [12:0] memo_addr;
  logic [63:0] memo_key, memo_read_key;
  int unsigned clear_cycles;

  always #5 clk_i = ~clk_i;

  apu_kws_coeff_store u_coeff_store (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .abort_i               (1'b0),
      .valid_i               (!loader_active),
      .loader_active_i       (loader_active),
      .loader_req_i          (loader_req),
      .loader_write_i        (loader_write),
      .loader_addr_i         (loader_addr),
      .loader_data_i         (loader_data),
      .loader_ready_o        (loader_ready),
      .loader_valid_o        (loader_valid),
      .loader_data_o         (loader_rdata),
      .loader_fault_o        (loader_fault),
      .frontend_req_valid_i  (front_req),
      .frontend_req_ready_o  (front_ready),
      .frontend_kind_i       (front_kind),
      .frontend_index_i      (front_index),
      .frontend_resp_valid_o (front_valid),
      .frontend_resp_ready_i (front_consume),
      .frontend_resp_data_o  (front_data),
      .frontend_resp_fault_o (front_fault),
      .inference_req_valid_i (infer_req),
      .inference_req_ready_o (infer_ready),
      .inference_index_i     (infer_index),
      .inference_resp_valid_o(infer_valid),
      .inference_resp_ready_i(infer_consume),
      .inference_resp_data_o (infer_data),
      .inference_resp_fault_o(infer_fault),
      .profile_req_valid_i   (1'b0),
      .profile_req_ready_o   (),
      .profile_index_i       (11'd0),
      .profile_resp_valid_o  (),
      .profile_resp_ready_i  (1'b0),
      .profile_resp_data_o   (),
      .profile_resp_fault_o  ()
  );

  apu_proof_memo u_proof_memo (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .abort_i     (1'b0),
      .clear_i     (memo_clear),
      .lookup_i    (memo_lookup),
      .insert_i    (memo_insert),
      .addr_i      (memo_addr),
      .key_i       (memo_key),
      .ready_o     (memo_ready),
      .done_o      (memo_done),
      .read_valid_o(memo_valid),
      .read_key_o  (memo_read_key)
  );

  task automatic write_coefficient(input logic [13:0] address_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      loader_addr = address_i;
      loader_data = data_i;
      loader_req  = 1'b1;
      @(negedge clk_i);
      loader_req = 1'b0;
      wait (loader_valid);
      if (loader_fault) $fatal(1, "coefficient write fault at %0d", address_i);
    end
  endtask

  task automatic memo_command(input logic clear_i, input logic lookup_i, input logic insert_i,
                              input logic [12:0] address_i, input logic [63:0] key_i);
    begin
      wait (memo_ready);
      @(negedge clk_i);
      memo_addr   = address_i;
      memo_key    = key_i;
      memo_clear  = clear_i;
      memo_lookup = lookup_i;
      memo_insert = insert_i;
      @(negedge clk_i);
      memo_clear  = 1'b0;
      memo_lookup = 1'b0;
      memo_insert = 1'b0;
      wait (memo_done);
    end
  endtask

  initial begin
    loader_active = 1'b0;
    loader_req = 1'b0;
    loader_write = 1'b1;
    loader_addr = 14'd0;
    loader_data = 32'd0;
    front_req = 1'b0;
    front_kind = 4'd0;
    front_index = 14'd0;
    front_consume = 1'b0;
    infer_req = 1'b0;
    infer_index = 7'd0;
    infer_consume = 1'b0;
    memo_clear = 1'b0;
    memo_lookup = 1'b0;
    memo_insert = 1'b0;
    memo_addr = 13'd0;
    memo_key = 64'd0;
    repeat (3) @(negedge clk_i);
    rst_n_i = 1'b1;

    loader_active = 1'b1;
    write_coefficient(14'(1024 + 5), 32'h1111_1111);
    write_coefficient(14'(2048 + 5), 32'h2222_2222);
    write_coefficient(14'(14 * 1024 + 512 + 3), 32'h3333_3333);
    loader_active = 1'b0;

    @(negedge clk_i);
    front_kind  = 4'd1;
    front_index = 14'd5;
    front_req   = 1'b1;
    infer_index = 7'd3;
    infer_req   = 1'b1;
    if (!front_ready || !infer_ready) $fatal(1, "parallel coefficient clients were not ready");
    @(negedge clk_i);
    front_req = 1'b0;
    infer_req = 1'b0;
    wait (front_valid && infer_valid);
    if (front_fault || infer_fault || (front_data != 64'h2222_2222_1111_1111) ||
        (infer_data != 32'h3333_3333)) begin
      $fatal(1, "parallel coefficient response mismatch");
    end
    repeat (2) begin
      @(negedge clk_i);
      if (!front_valid || !infer_valid) $fatal(1, "coefficient response was not retained");
    end
    front_consume = 1'b1;
    infer_consume = 1'b1;
    @(negedge clk_i);
    front_consume = 1'b0;
    infer_consume = 1'b0;

    front_kind = 4'd9;
    front_index = 14'd0;
    front_req = 1'b1;
    @(negedge clk_i);
    front_req = 1'b0;
    wait (front_valid);
    if (!front_fault) $fatal(1, "illegal coefficient kind did not fault");
    front_consume = 1'b1;
    @(negedge clk_i);
    front_consume = 1'b0;

    clear_cycles  = 0;
    @(negedge clk_i);
    memo_clear = 1'b1;
    @(negedge clk_i);
    memo_clear = 1'b0;
    while (!memo_done) begin
      clear_cycles++;
      @(negedge clk_i);
    end
    if (clear_cycles > 260) $fatal(1, "memo clear exceeded 260 cycles");
    memo_command(1'b0, 1'b0, 1'b1, 13'd31, 64'h0123_4567_89ab_cdef);
    memo_command(1'b0, 1'b1, 1'b0, 13'd31, 64'h0123_4567_89ab_cdef);
    if (!memo_valid || (memo_read_key != 64'h0123_4567_89ab_cdef)) begin
      $fatal(1, "memo key/bitmap lookup mismatch");
    end
    memo_command(1'b0, 1'b1, 1'b0, 13'd32, 64'd0);
    if (memo_valid) $fatal(1, "adjacent bitmap row was unexpectedly valid");

    $display("APU-P9 coefficient store and proof memo test passed");
    $finish;
  end

  initial begin
    repeat (2000) @(posedge clk_i);
    $fatal(1, "APU-P9 storage test timeout");
  end
endmodule
