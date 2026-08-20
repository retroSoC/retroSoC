`timescale 1ns / 1ps

module crypto_primitive_tb;
  import crypto_pkg::*;

  logic         clk_i = 1'b0;
  logic         rst_n_i = 1'b0;
  logic         zeroize_i = 1'b0;

  logic         aes_key_commit;
  logic [  1:0] aes_key_size;
  logic [255:0] aes_key;
  logic         aes_key_valid;
  logic         aes_start;
  logic         aes_decrypt;
  logic [127:0] aes_block_in;
  logic         aes_busy;
  logic         aes_done;
  logic [127:0] aes_block_out;

  logic         sha_start;
  logic [255:0] sha_state_in;
  logic [511:0] sha_block_in;
  logic         sha_busy;
  logic         sha_done;
  logic [255:0] sha_state_out;

  always #5 clk_i = ~clk_i;

  crypto_aes_core u_crypto_aes_core (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .zeroize_i   (zeroize_i),
      .key_commit_i(aes_key_commit),
      .key_size_i  (aes_key_size),
      .key_i       (aes_key),
      .key_valid_o (aes_key_valid),
      .start_i     (aes_start),
      .decrypt_i   (aes_decrypt),
      .block_i     (aes_block_in),
      .busy_o      (aes_busy),
      .done_o      (aes_done),
      .block_o     (aes_block_out)
  );

  crypto_sha2_core u_crypto_sha2_core (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .zeroize_i(zeroize_i),
      .start_i  (sha_start),
      .state_i  (sha_state_in),
      .block_i  (sha_block_in),
      .busy_o   (sha_busy),
      .done_o   (sha_done),
      .state_o  (sha_state_out)
  );

  task automatic aes_load_key(input logic [1:0] size, input logic [255:0] key);
    begin
      @(negedge clk_i);
      aes_key_size   = size;
      aes_key        = key;
      aes_key_commit = 1'b1;
      @(negedge clk_i);
      aes_key_commit = 1'b0;
      wait (aes_key_valid);
    end
  endtask

  task automatic aes_crypt(input logic decrypt, input logic [127:0] block,
                           input logic [127:0] expected);
    begin
      @(negedge clk_i);
      aes_decrypt  = decrypt;
      aes_block_in = block;
      aes_start    = 1'b1;
      @(negedge clk_i);
      aes_start = 1'b0;
      wait (aes_done);
      if (aes_block_out != expected) begin
        $fatal(1, "AES result mismatch: got %h expected %h", aes_block_out, expected);
      end
    end
  endtask

  initial begin
    aes_key_commit = 1'b0;
    aes_key_size   = AES_KEY_128;
    aes_key        = '0;
    aes_start      = 1'b0;
    aes_decrypt    = 1'b0;
    aes_block_in   = '0;
    sha_start      = 1'b0;
    sha_state_in   = '0;
    sha_block_in   = '0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    aes_load_key(AES_KEY_128,
                 256'h000102030405060708090a0b0c0d0e0f_00000000000000000000000000000000);
    aes_crypt(1'b0, 128'h00112233445566778899aabbccddeeff, 128'h69c4e0d86a7b0430d8cdb78070b4c55a);
    aes_crypt(1'b1, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, 128'h00112233445566778899aabbccddeeff);

    aes_load_key(AES_KEY_192,
                 256'h000102030405060708090a0b0c0d0e0f1011121314151617_0000000000000000);
    aes_crypt(1'b0, 128'h00112233445566778899aabbccddeeff, 128'hdda97ca4864cdfe06eaf70a0ec0d7191);

    aes_load_key(AES_KEY_256,
                 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);
    aes_crypt(1'b0, 128'h00112233445566778899aabbccddeeff, 128'h8ea2b7ca516745bfeafc49904b496089);

    @(negedge clk_i);
    sha_state_in = 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    sha_block_in = {
      32'h61626380,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000000,
      32'h00000018
    };
    sha_start = 1'b1;
    @(negedge clk_i);
    sha_start = 1'b0;
    wait (sha_done);
    if (sha_state_out != 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9c_b410ff61f20015ad) begin
      $fatal(1, "SHA-256 result mismatch: %h", sha_state_out);
    end

    $display("Crypto AES and SHA primitive tests passed");
    $finish;
  end
endmodule
