// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
//
// Vector file format (flat 32-bit hex words, 5 + 64 words per item, generated
// by tests/test_npu_rtl_compute.py):
//   word 0: activation bytes lanes 3..0 (lane p occupies byte p)
//   word 1: activation bytes lanes 7..4
//   word 2: weight bytes lanes 3..0
//   word 3: weight bytes lanes 7..4
//   word 4: {8'h00, in_zero[7:0], a_valid[7:0], w_valid[7:0]}
//   words 5..68: expected signed 17-bit products, sign-extended signed 32,
//                in position-major order (index = position*8 + channel)

`timescale 1ns / 1ps

module npu_mac_array_tb;
  localparam int unsigned MaxVectorCount = 256;
  localparam int unsigned WordsPerItem = 5 + 64;

  logic                           clk_i = 1'b0;
  logic                           rst_n_i = 1'b0;
  logic                           req_valid;
  logic                           req_ready;
  logic        [ 7:0][ 7:0]       req_a_bytes;
  logic        [ 7:0][ 7:0]       req_w_bytes;
  logic signed [ 7:0]             req_in_zero;
  logic        [ 7:0]             req_a_valid;
  logic        [ 7:0]             req_w_valid;
  logic                           resp_valid;
  logic                           resp_ready;
  logic        [ 7:0][ 7:0][16:0] resp_products;

  logic        [31:0]             vectors        [0:MaxVectorCount*WordsPerItem-1];
  logic        [63:0][16:0]       products_flat;
  integer                         vector_count;
  string                          vector_path;
  integer                         stall_count;
  integer                         error_count;

  always #5 clk_i = ~clk_i;

  assign products_flat = resp_products;

  npu_mac_array u_dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .req_valid_i    (req_valid),
      .req_ready_o    (req_ready),
      .req_a_bytes_i  (req_a_bytes),
      .req_w_bytes_i  (req_w_bytes),
      .req_in_zero_i  (req_in_zero),
      .req_a_valid_i  (req_a_valid),
      .req_w_valid_i  (req_w_valid),
      .resp_valid_o   (resp_valid),
      .resp_ready_i   (resp_ready),
      .resp_products_o(resp_products)
  );

  // Deterministic response backpressure: ready is low in two-cycle stall
  // stretches inside a seven-cycle period.
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      stall_count <= 0;
      resp_ready  <= 1'b0;
    end else begin
      stall_count <= (stall_count == 6) ? 0 : stall_count + 1;
      resp_ready  <= (stall_count < 2) || (stall_count > 3);
    end
  end

  task automatic hard_reset;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  initial begin
    integer base;
    vector_count = 0;
    if (!$value$plusargs("VECTOR_COUNT=%d", vector_count)) begin
      $fatal(1, "NPU mac array vector count missing");
    end
    if (!$value$plusargs("VECTORS=%s", vector_path)) begin
      $fatal(1, "NPU mac array vector path missing");
    end
    if ((vector_count < 1) || (vector_count > MaxVectorCount)) begin
      $fatal(1, "NPU mac array vector count out of range count=%0d", vector_count);
    end
    $readmemh(vector_path, vectors);

    req_valid   = 1'b0;
    req_a_bytes = '0;
    req_w_bytes = '0;
    req_in_zero = 8'd0;
    req_a_valid = 8'd0;
    req_w_valid = 8'd0;
    error_count = 0;

    hard_reset();

    for (int item = 0; item < vector_count; item++) begin
      base = item * WordsPerItem;
      // Deterministic request idle gaps, zero to two cycles.
      repeat (item % 3) @(posedge clk_i);
      @(negedge clk_i);
      req_a_bytes = {vectors[base+1], vectors[base+0]};
      req_w_bytes = {vectors[base+3], vectors[base+2]};
      req_in_zero = vectors[base+4][23:16];
      req_a_valid = vectors[base+4][15:8];
      req_w_valid = vectors[base+4][7:0];
      req_valid   = 1'b1;
      for (int cycle = 0; cycle < 200; cycle++) begin
        @(posedge clk_i);
        if (req_ready) begin
          @(negedge clk_i);
          req_valid = 1'b0;
          break;
        end
        if (cycle == 199) begin
          $fatal(1, "NPU mac array request timeout item=%0d", item);
        end
      end
      for (int cycle = 0; cycle < 200; cycle++) begin
        @(posedge clk_i);
        if (resp_valid && resp_ready) begin
          for (int index = 0; index < 64; index++) begin
            if (products_flat[index] !== vectors[base+5+index][16:0]) begin
              $display("NPU mac array mismatch item=%0d index=%0d got=%05x expected=%05x", item,
                       index, products_flat[index], vectors[base+5+index][16:0]);
              error_count = error_count + 1;
            end
          end
          break;
        end
        if (cycle == 199) begin
          $fatal(1, "NPU mac array response timeout item=%0d", item);
        end
      end
    end

    repeat (2) @(posedge clk_i);
    if (error_count != 0) begin
      $fatal(1, "NPU mac array mismatches=%0d", error_count);
    end
    $display("NPU mac array test passed");
    $finish;
  end
endmodule
