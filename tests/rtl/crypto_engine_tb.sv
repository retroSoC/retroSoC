`timescale 1ns / 1ps

module crypto_engine_tb;
  import crypto_pkg::*;

  logic         clk_i = 1'b0;
  logic         rst_n_i = 1'b0;
  logic         zeroize_i = 1'b0;

  logic         aes_abort;
  logic         aes_key_commit;
  logic [  1:0] aes_key_size;
  logic [255:0] aes_key;
  logic         aes_key_valid;
  logic         aes_key_busy;
  logic         aes_start;
  logic [  1:0] aes_mode;
  logic         aes_decrypt;
  logic [ 31:0] aes_length;
  logic [127:0] aes_iv;
  logic         aes_input_valid;
  logic         aes_input_ready;
  logic [ 31:0] aes_input_data;
  logic [  3:0] aes_input_keep;
  logic         aes_input_last;
  logic         aes_output_valid;
  logic         aes_output_ready;
  logic [ 31:0] aes_output_data;
  logic [  3:0] aes_output_keep;
  logic         aes_output_last;
  logic         aes_busy;
  logic         aes_done;
  logic         aes_error;
  logic [ 31:0] aes_bytes_in;
  logic [ 31:0] aes_bytes_out;
  logic [ 31:0] aes_cycles;
  logic [127:0] aes_chain;

  logic         sha_abort;
  logic         sha_start;
  logic         sha256;
  logic [ 63:0] sha_length;
  logic         sha_input_valid;
  logic         sha_input_ready;
  logic [ 31:0] sha_input_data;
  logic [  3:0] sha_input_keep;
  logic         sha_input_last;
  logic         sha_busy;
  logic         sha_done;
  logic         sha_error;
  logic         sha_digest_valid;
  logic [255:0] sha_digest;
  logic [ 63:0] sha_bytes_in;
  logic [ 31:0] sha_cycles;

  always #5 clk_i = ~clk_i;

  crypto_aes_engine u_crypto_aes_engine (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .zeroize_i     (zeroize_i),
      .abort_i       (aes_abort),
      .key_commit_i  (aes_key_commit),
      .key_size_i    (aes_key_size),
      .key_i         (aes_key),
      .key_valid_o   (aes_key_valid),
      .key_busy_o    (aes_key_busy),
      .start_i       (aes_start),
      .mode_i        (aes_mode),
      .decrypt_i     (aes_decrypt),
      .length_i      (aes_length),
      .iv_i          (aes_iv),
      .input_valid_i (aes_input_valid),
      .input_ready_o (aes_input_ready),
      .input_data_i  (aes_input_data),
      .input_keep_i  (aes_input_keep),
      .input_last_i  (aes_input_last),
      .output_valid_o(aes_output_valid),
      .output_ready_i(aes_output_ready),
      .output_data_o (aes_output_data),
      .output_keep_o (aes_output_keep),
      .output_last_o (aes_output_last),
      .busy_o        (aes_busy),
      .done_o        (aes_done),
      .error_o       (aes_error),
      .bytes_in_o    (aes_bytes_in),
      .bytes_out_o   (aes_bytes_out),
      .cycles_o      (aes_cycles),
      .chain_o       (aes_chain)
  );

  crypto_sha2_engine u_crypto_sha2_engine (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .zeroize_i     (zeroize_i),
      .abort_i       (sha_abort),
      .start_i       (sha_start),
      .sha256_i      (sha256),
      .length_i      (sha_length),
      .input_valid_i (sha_input_valid),
      .input_ready_o (sha_input_ready),
      .input_data_i  (sha_input_data),
      .input_keep_i  (sha_input_keep),
      .input_last_i  (sha_input_last),
      .busy_o        (sha_busy),
      .done_o        (sha_done),
      .error_o       (sha_error),
      .digest_valid_o(sha_digest_valid),
      .digest_o      (sha_digest),
      .bytes_in_o    (sha_bytes_in),
      .cycles_o      (sha_cycles)
  );

  task automatic aes_load_key(input logic [255:0] key);
    begin
      @(negedge clk_i);
      aes_key_size   = AES_KEY_128;
      aes_key        = key;
      aes_key_commit = 1'b1;
      @(negedge clk_i);
      aes_key_commit = 1'b0;
      wait (aes_key_valid);
    end
  endtask

  task automatic aes_begin(input logic [1:0] mode, input logic [31:0] length,
                           input logic [127:0] iv);
    begin
      @(negedge clk_i);
      aes_mode    = mode;
      aes_length  = length;
      aes_iv      = iv;
      aes_decrypt = 1'b0;
      aes_start   = 1'b1;
      @(negedge clk_i);
      aes_start = 1'b0;
      wait (aes_busy);
    end
  endtask

  task automatic aes_send(input logic [31:0] data, input logic [3:0] keep, input logic last);
    begin
      @(negedge clk_i);
      aes_input_data  = data;
      aes_input_keep  = keep;
      aes_input_last  = last;
      aes_input_valid = 1'b1;
      while (!aes_input_ready) begin
        @(negedge clk_i);
      end
      @(negedge clk_i);
      aes_input_valid = 1'b0;
    end
  endtask

  task automatic aes_expect(input logic [31:0] data, input logic [3:0] keep, input logic last);
    begin
      aes_output_ready = 1'b1;
      while (!aes_output_valid) begin
        @(negedge clk_i);
      end
      if ((aes_output_data != data) || (aes_output_keep != keep) || (aes_output_last != last)) begin
        $fatal(1, "AES stream mismatch: got %h/%h/%b expected %h/%h/%b", aes_output_data,
               aes_output_keep, aes_output_last, data, keep, last);
      end
      @(negedge clk_i);
      aes_output_ready = 1'b0;
    end
  endtask

  task automatic sha_begin(input logic use_sha256, input logic [63:0] length);
    begin
      @(negedge clk_i);
      sha256     = use_sha256;
      sha_length = length;
      sha_start  = 1'b1;
      @(negedge clk_i);
      sha_start = 1'b0;
      wait (sha_busy);
    end
  endtask

  task automatic sha_send(input logic [31:0] data, input logic [3:0] keep, input logic last);
    begin
      @(negedge clk_i);
      sha_input_data  = data;
      sha_input_keep  = keep;
      sha_input_last  = last;
      sha_input_valid = 1'b1;
      while (!sha_input_ready) begin
        @(negedge clk_i);
      end
      @(negedge clk_i);
      sha_input_valid = 1'b0;
    end
  endtask

  initial begin
    aes_abort        = 1'b0;
    aes_key_commit   = 1'b0;
    aes_key_size     = AES_KEY_128;
    aes_key          = '0;
    aes_start        = 1'b0;
    aes_mode         = AES_MODE_ECB;
    aes_decrypt      = 1'b0;
    aes_length       = '0;
    aes_iv           = '0;
    aes_input_valid  = 1'b0;
    aes_input_data   = '0;
    aes_input_keep   = '0;
    aes_input_last   = 1'b0;
    aes_output_ready = 1'b0;
    sha_abort        = 1'b0;
    sha_start        = 1'b0;
    sha256           = 1'b1;
    sha_length       = '0;
    sha_input_valid  = 1'b0;
    sha_input_data   = '0;
    sha_input_keep   = '0;
    sha_input_last   = 1'b0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    aes_load_key(256'h000102030405060708090a0b0c0d0e0f_00000000000000000000000000000000);
    aes_begin(AES_MODE_ECB, 32'd16, '0);
    aes_send(32'h33221100, 4'hf, 1'b0);
    aes_send(32'h77665544, 4'hf, 1'b0);
    aes_send(32'hbbaa9988, 4'hf, 1'b0);
    aes_send(32'hffeeddcc, 4'hf, 1'b1);
    aes_expect(32'hd8e0c469, 4'hf, 1'b0);
    aes_expect(32'h30047b6a, 4'hf, 1'b0);
    aes_expect(32'h80b7cdd8, 4'hf, 1'b0);
    aes_expect(32'h5ac5b470, 4'hf, 1'b1);
    wait (aes_done);
    if (aes_error || (aes_bytes_in != 32'd16) || (aes_bytes_out != 32'd16)) begin
      $fatal(1, "AES ECB status mismatch");
    end

    aes_load_key(256'h2b7e151628aed2a6abf7158809cf4f3c_00000000000000000000000000000000);
    aes_begin(AES_MODE_CTR, 32'd20, 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff);
    aes_send(32'he2bec16b, 4'hf, 1'b0);
    aes_send(32'h969f402e, 4'hf, 1'b0);
    aes_send(32'h117e3de9, 4'hf, 1'b0);
    aes_send(32'h2a179373, 4'hf, 1'b0);
    aes_send(32'h578a2dae, 4'hf, 1'b1);
    aes_expect(32'h91614d87, 4'hf, 1'b0);
    aes_expect(32'h26e320b6, 4'hf, 1'b0);
    aes_expect(32'h6468ef1b, 4'hf, 1'b0);
    aes_expect(32'hceb60d99, 4'hf, 1'b0);
    aes_expect(32'h6bf60698, 4'hf, 1'b1);
    wait (aes_done);
    if (aes_error || (aes_chain != 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdff01)) begin
      $fatal(1, "AES CTR status mismatch: error=%b chain=%h", aes_error, aes_chain);
    end

    sha_begin(1'b1, 64'd3);
    sha_send(32'h00636261, 4'h7, 1'b1);
    wait (sha_done);
    if (sha_error || !sha_digest_valid ||
        (sha_digest != 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9c_b410ff61f20015ad)) begin
      $fatal(1, "SHA-256 stream result mismatch: %h", sha_digest);
    end

    sha_begin(1'b0, 64'd0);
    wait (sha_done);
    if (sha_error || !sha_digest_valid ||
        (sha_digest != 256'hd14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f_00000000)) begin
      $fatal(1, "SHA-224 empty result mismatch: %h", sha_digest);
    end

    $display("Crypto streaming engine tests passed");
    $finish;
  end
endmodule
