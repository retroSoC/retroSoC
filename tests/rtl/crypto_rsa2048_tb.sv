// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps

module crypto_rsa2048_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        zeroize_i = 1'b0;
  logic        abort_i = 1'b0;
  logic        prepare_i = 1'b0;
  logic        start_i = 1'b0;
  logic        private_i = 1'b0;
  logic [11:0] exponent_bits_i = 12'd17;
  logic [2047:0] modulus_i, exponent_i, base_i;
  logic busy_o, done_o, error_o, prepared_o, result_valid_o;
  logic [2047:0] result_o;
  logic [31:0] cycles_o, progress_o;
  logic mont_start = 1'b0;
  logic mont_busy, mont_done;
  logic  [2047:0] mont_result;
  logic  [2047:0] vectors        [0:5];
  logic  [  31:0] private_cycles;
  string          vector_path;

  always #5 clk_i = ~clk_i;

  crypto_rsa_core #(
      .Bits(2048)
  ) u_rsa (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .zeroize_i      (zeroize_i),
      .abort_i        (abort_i),
      .prepare_i      (prepare_i),
      .start_i        (start_i),
      .private_i      (private_i),
      .exponent_bits_i(exponent_bits_i),
      .modulus_i      (modulus_i),
      .exponent_i     (exponent_i),
      .base_i         (base_i),
      .busy_o         (busy_o),
      .done_o         (done_o),
      .error_o        (error_o),
      .prepared_o     (prepared_o),
      .result_valid_o (result_valid_o),
      .result_o       (result_o),
      .cycles_o       (cycles_o),
      .progress_o     (progress_o)
  );
  crypto_montgomery #(
      .Bits(2048)
  ) u_mont (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .zeroize_i (zeroize_i),
      .start_i   (mont_start),
      .left_i    (modulus_i - 2048'd1),
      .right_i   (modulus_i - 2048'd1),
      .modulus_i (modulus_i),
      .n0_prime_i(vectors[4][31:0]),
      .busy_o    (mont_busy),
      .done_o    (mont_done),
      .result_o  (mont_result)
  );

  task automatic run_operation(input logic private_mode, input logic expect_error);
    @(negedge clk_i);
    private_i = private_mode;
    start_i   = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (done_o);
    #1;
    if (error_o != expect_error || result_valid_o == expect_error)
      $fatal(1, "RSA-2048 completion/verification mismatch");
  endtask

  initial begin
    #2000000000;
    $fatal(1, "RSA-2048 test watchdog");
  end

  initial begin
    if (!$value$plusargs("vectors=%s", vector_path)) $fatal(1, "missing RSA vectors");
    $readmemh(vector_path, vectors);
    modulus_i  = vectors[0];
    exponent_i = 2048'd65537;
    base_i     = vectors[2];
    repeat (3) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    prepare_i = 1'b1;
    @(negedge clk_i);
    prepare_i = 1'b0;
    wait (done_o);
    #1;
    if (!prepared_o || error_o) $fatal(1, "RSA-2048 prepare");
    $display("CRYPTO_CYCLES operation=rsa2048_prepare cycles=%0d", cycles_o);

    @(negedge clk_i);
    mont_start = 1'b1;
    @(negedge clk_i);
    mont_start = 1'b0;
    wait (mont_done);
    #1;
    if (mont_result !== vectors[5]) $fatal(1, "RSA-2048 Montgomery carry vector");

    run_operation(1'b0, 1'b0);
    if (result_o !== vectors[3]) $fatal(1, "RSA-2048 public numerical mismatch");
    $display("CRYPTO_CYCLES operation=rsa2048_public cycles=%0d", cycles_o);
    exponent_i      = vectors[1];
    exponent_bits_i = 12'd2048;
    base_i          = vectors[3];
    run_operation(1'b1, 1'b0);
    if (result_o !== vectors[2]) $fatal(1, "RSA-2048 private numerical mismatch");
    private_cycles = cycles_o;
    $display("CRYPTO_CYCLES operation=rsa2048_private cycles=%0d", cycles_o);

    exponent_i = vectors[1] ^ 2048'd2;
    run_operation(1'b1, 1'b1);
    if (cycles_o != private_cycles) $fatal(1, "private exponent changed schedule");
    if (result_o != 2048'd0) $fatal(1, "failed private verification released data");
    $display("CRYPTO_CYCLES operation=rsa2048_bad_private cycles=%0d", cycles_o);

    @(negedge clk_i);
    zeroize_i = 1'b1;
    @(negedge clk_i);
    zeroize_i = 1'b0;
    if (prepared_o || result_valid_o || busy_o || result_o != 0)
      $fatal(1, "RSA-2048 zeroize state");
    $display("CRYPTO_P0_RSA2048_PASS");
    $finish;
  end
endmodule
