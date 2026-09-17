// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
//
// Vector file format (flat 32-bit hex words, eight words per item, generated
// by tests/test_npu_rtl_compute.py from scripts/npu_reference.py):
//   word 0: acc (signed INT32 accumulator input)
//   word 1: multiplier (nonnegative INT32)
//   word 2: shift (sign-extended signed 32, low 8 bits used, range -31..30)
//   word 3: zout (sign-extended signed 32, low 8 bits used, range -128..127)
//   word 4: act_min (sign-extended signed 32, low 8 bits used)
//   word 5: act_max (sign-extended signed 32, low 8 bits used)
//   word 6: expected output byte, sign-extended signed 32 (0 on fault items)
//   word 7: expected fault flag (0 or 1)

`timescale 1ns / 1ps

module npu_requantizer_tb;
  localparam int unsigned MaxVectorCount = 512;
  localparam int unsigned WordsPerItem = 8;

  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               req_valid;
  logic               req_ready;
  logic signed [31:0] req_acc;
  logic        [31:0] req_multiplier;
  logic signed [ 7:0] req_shift;
  logic signed [ 7:0] req_zout;
  logic signed [ 7:0] req_act_min;
  logic signed [ 7:0] req_act_max;
  logic               resp_valid;
  logic               resp_ready;
  logic signed [ 7:0] resp_data;
  logic               resp_fault;

  logic        [31:0] vectors        [0:MaxVectorCount*WordsPerItem-1];
  integer             vector_count;
  string              vector_path;
  integer             recv_count;
  integer             error_count;
  integer             stall_count;

  always #5 clk_i = ~clk_i;

  npu_requantizer u_dut (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .req_valid_i     (req_valid),
      .req_ready_o     (req_ready),
      .req_acc_i       (req_acc),
      .req_multiplier_i(req_multiplier),
      .req_shift_i     (req_shift),
      .req_zout_i      (req_zout),
      .req_act_min_i   (req_act_min),
      .req_act_max_i   (req_act_max),
      .resp_valid_o    (resp_valid),
      .resp_ready_i    (resp_ready),
      .resp_data_o     (resp_data),
      .resp_fault_o    (resp_fault)
  );

  // Deterministic response backpressure: ready is low in three-cycle stall
  // stretches inside an eleven-cycle period.
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      stall_count <= 0;
      resp_ready  <= 1'b0;
    end else begin
      stall_count <= (stall_count == 10) ? 0 : stall_count + 1;
      resp_ready  <= (stall_count < 4) || (stall_count > 6);
    end
  end

  // In-order response checker: one item retires per handshake.
  always @(posedge clk_i) begin
    if (rst_n_i && resp_valid && resp_ready) begin
      if (recv_count >= vector_count) begin
        $fatal(1, "NPU requantizer published more items than sent");
      end
      if ((resp_data !== vectors[recv_count*WordsPerItem+6][7:0]) ||
          (resp_fault !== vectors[recv_count*WordsPerItem+7][0])) begin
        $display(
            "NPU requantizer mismatch item=%0d got data=%08x fault=%0d expected data=%08x fault=%08x",
            recv_count, resp_data, resp_fault, vectors[recv_count*WordsPerItem+6],
            vectors[recv_count*WordsPerItem+7]);
        error_count <= error_count + 1;
      end
      recv_count <= recv_count + 1;
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
    vector_count = 0;
    if (!$value$plusargs("VECTOR_COUNT=%d", vector_count)) begin
      $fatal(1, "NPU requantizer vector count missing");
    end
    if (!$value$plusargs("VECTORS=%s", vector_path)) begin
      $fatal(1, "NPU requantizer vector path missing");
    end
    if ((vector_count < 1) || (vector_count > MaxVectorCount)) begin
      $fatal(1, "NPU requantizer vector count out of range count=%0d", vector_count);
    end
    $readmemh(vector_path, vectors);

    req_valid      = 1'b0;
    req_acc        = 32'd0;
    req_multiplier = 32'd0;
    req_shift      = 8'd0;
    req_zout       = 8'd0;
    req_act_min    = 8'd0;
    req_act_max    = 8'd0;
    recv_count     = 0;
    error_count    = 0;

    hard_reset();

    for (int item = 0; item < vector_count; item++) begin
      // Deterministic request idle gaps, zero to three cycles.
      repeat (item % 4) @(posedge clk_i);
      @(negedge clk_i);
      req_acc        = vectors[item*WordsPerItem+0];
      req_multiplier = vectors[item*WordsPerItem+1];
      req_shift      = vectors[item*WordsPerItem+2][7:0];
      req_zout       = vectors[item*WordsPerItem+3][7:0];
      req_act_min    = vectors[item*WordsPerItem+4][7:0];
      req_act_max    = vectors[item*WordsPerItem+5][7:0];
      req_valid      = 1'b1;
      for (int cycle = 0; cycle < 200; cycle++) begin
        @(posedge clk_i);
        if (req_ready) begin
          @(negedge clk_i);
          req_valid = 1'b0;
          break;
        end
        if (cycle == 199) begin
          $fatal(1, "NPU requantizer request timeout item=%0d", item);
        end
      end
    end

    for (int cycle = 0; cycle < 20000; cycle++) begin
      @(posedge clk_i);
      if (recv_count == vector_count) begin
        break;
      end
      if (cycle == 19999) begin
        $fatal(1, "NPU requantizer response timeout sent=%0d received=%0d", vector_count,
               recv_count);
      end
    end
    repeat (2) @(posedge clk_i);
    if (recv_count != vector_count) begin
      $fatal(1, "NPU requantizer item count mismatch sent=%0d received=%0d", vector_count,
             recv_count);
    end
    if (error_count != 0) begin
      $fatal(1, "NPU requantizer mismatches=%0d", error_count);
    end
    $display("NPU requantizer test passed");
    $finish;
  end
endmodule
