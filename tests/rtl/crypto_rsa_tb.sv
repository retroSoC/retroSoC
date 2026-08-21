`timescale 1ns / 1ps

module crypto_rsa_tb;
  localparam int Bits = 64;

  logic            clk_i = 1'b0;
  logic            rst_n_i = 1'b0;
  logic            zeroize_i = 1'b0;
  logic            abort_i = 1'b0;
  logic            prepare_i = 1'b0;
  logic            start_i = 1'b0;
  logic            private_i = 1'b0;
  logic [    11:0] exponent_bits_i = '0;
  logic [Bits-1:0] modulus_i = '0;
  logic [Bits-1:0] exponent_i = '0;
  logic [Bits-1:0] base_i = '0;
  logic            busy_o;
  logic            done_o;
  logic            error_o;
  logic            prepared_o;
  logic            result_valid_o;
  logic [Bits-1:0] result_o;
  logic [    31:0] cycles_o;
  logic [    31:0] progress_o;
  logic            mont_start = 1'b0;
  logic [Bits-1:0] mont_left = '0;
  logic [Bits-1:0] mont_right = '0;
  logic            mont_busy;
  logic            mont_done;
  logic [Bits-1:0] mont_result;

  always #5 clk_i = ~clk_i;

  crypto_rsa_core #(
      .Bits(Bits)
  ) u_crypto_rsa_core (
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
      .Bits(Bits)
  ) u_direct_montgomery (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .zeroize_i (zeroize_i),
      .start_i   (mont_start),
      .left_i    (mont_left),
      .right_i   (mont_right),
      .modulus_i (modulus_i),
      .n0_prime_i(32'h03030303),
      .busy_o    (mont_busy),
      .done_o    (mont_done),
      .result_o  (mont_result)
  );

  task automatic pulse_prepare;
    begin
      @(negedge clk_i);
      prepare_i = 1'b1;
      @(negedge clk_i);
      prepare_i = 1'b0;
      wait (done_o);
      if (!prepared_o || error_o) begin
        $fatal(1, "RSA modulus preparation failed");
      end
    end
  endtask

  task automatic pulse_start(input logic is_private);
    begin
      @(negedge clk_i);
      private_i = is_private;
      start_i   = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      wait (done_o);
      if (!result_valid_o || error_o) begin
        $fatal(1, "RSA modular exponentiation failed");
      end
    end
  endtask

  initial begin
    repeat (3) @(posedge clk_i);
    rst_n_i   = 1'b1;

    modulus_i = 64'hffffffea00000055;
    pulse_prepare();
    if (u_crypto_rsa_core.s_r2_q != 64'h00001afbffff7b85) begin
      $fatal(1, "RSA R2 mismatch: %h", u_crypto_rsa_core.s_r2_q);
    end
    if (u_crypto_rsa_core.s_n0_prime_q != 32'h03030303) begin
      $fatal(1, "RSA n0 prime mismatch: %h", u_crypto_rsa_core.s_n0_prime_q);
    end

    @(negedge clk_i);
    mont_left  = 64'h0123456789abcdef;
    mont_right = 64'h00001afbffff7b85;
    mont_start = 1'b1;
    @(negedge clk_i);
    mont_start = 1'b0;
    wait (mont_done);
    if (mont_result != 64'h9abcdefafa4fa4f2) begin
      $fatal(1, "direct Montgomery result mismatch: %h", mont_result);
    end

    @(negedge clk_i);
    mont_left  = 64'h9abcdefafa4fa4f2;
    mont_right = 64'h9abcdefafa4fa4f2;
    mont_start = 1'b1;
    @(negedge clk_i);
    mont_start = 1'b0;
    wait (mont_done);
    if (mont_result != 64'hba9c5877ea4e6ea3) begin
      $fatal(1, "direct Montgomery square mismatch: %h", mont_result);
    end

    base_i          = 64'h0123456789abcdef;
    exponent_i      = 64'h0000000000010001;
    exponent_bits_i = 12'd17;
    pulse_start(1'b0);
    if (result_o != 64'h61c4c4e9f38bdddb) begin
      $fatal(1, "RSA public result mismatch: %h", result_o);
    end

    base_i          = 64'h61c4c4e9f38bdddb;
    exponent_i      = 64'h81817e725d5da2d9;
    exponent_bits_i = 12'd64;
    pulse_start(1'b1);
    if (result_o != 64'h0123456789abcdef) begin
      $fatal(1, "RSA private result mismatch: %h", result_o);
    end

    @(negedge clk_i);
    zeroize_i = 1'b1;
    @(negedge clk_i);
    zeroize_i = 1'b0;
    if (prepared_o || result_valid_o) begin
      $fatal(1, "RSA zeroize retained prepared or result state");
    end

    $display("Crypto RSA Montgomery tests passed");
    $finish;
  end
endmodule
