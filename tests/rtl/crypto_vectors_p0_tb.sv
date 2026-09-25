// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps

module crypto_vectors_p0_tb;
  import crypto_pkg::*;
  logic  [255:0] expected_sha[0:21];
  string         sha_path;
  initial begin
    #1000000;
    $fatal(1, "Crypto vector watchdog");
  end

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

    if (!$value$plusargs("sha=%s", sha_path)) $fatal(1, "missing SHA oracle vectors");
    $readmemh(sha_path, expected_sha);
    // NIST SP 800-38A F.2.1 first CBC block, with a stalled output.
    aes_load_key(256'h2b7e151628aed2a6abf7158809cf4f3c_00000000000000000000000000000000);
    aes_begin(AES_MODE_CBC, 32'd16, 128'h000102030405060708090a0b0c0d0e0f);
    aes_send(32'he2bec16b, 4'hf, 1'b0);
    aes_send(32'h969f402e, 4'hf, 1'b0);
    aes_send(32'h117e3de9, 4'hf, 1'b0);
    aes_send(32'h2a179373, 4'hf, 1'b1);
    wait (aes_output_valid);
    repeat (7) begin
      @(negedge clk_i);
      if (!aes_output_valid || aes_output_data != 32'hacab4976)
        $fatal(1, "AES output changed while stalled");
    end
    aes_expect(32'hacab4976, 4'hf, 1'b0);
    aes_expect(32'h46b21981, 4'hf, 1'b0);
    aes_expect(32'h9b8ee9ce, 4'hf, 1'b0);
    aes_expect(32'h7d19e912, 4'hf, 1'b1);
    wait (aes_done);
    aes_begin(AES_MODE_CTR, 32'd3, 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff);
    aes_send(32'h00bec16b, 4'h7, 1'b1);
    // Only KEEP-selected bytes are meaningful on a partial output word.
    aes_output_ready = 1'b1;
    wait (aes_output_valid);
    #1;
    if (aes_output_data[23:0] != 24'h614d87 || aes_output_keep != 4'h7 || !aes_output_last)
      $fatal(
          1,
          "AES partial CTR tail data=%h keep=%h last=%b",
          aes_output_data,
          aes_output_keep,
          aes_output_last
      );
    @(posedge clk_i);
    @(negedge clk_i);
    aes_output_ready = 1'b0;
    wait (aes_done);

    for (int mode = 0; mode < 2; mode++) begin
      for (int test_id = 0; test_id < 11; test_id++) begin
        int length;
        case (test_id)
          0:       length = 0;
          1:       length = 1;
          2:       length = 3;
          3:       length = 55;
          4:       length = 56;
          5:       length = 63;
          6:       length = 64;
          7:       length = 65;
          8:       length = 127;
          9:       length = 128;
          default: length = 129;
        endcase
        sha_begin(1'(mode), 64'(length));
        for (int offset = 0; offset < length; offset += 4) begin
          logic [31:0] data;
          logic [ 3:0] keep;
          data = 0;
          keep = 0;
          for (int byte_id = 0; byte_id < 4; byte_id++) begin
            if (offset + byte_id < length) begin
              data[byte_id*8+:8] = 8'(offset + byte_id);
              keep[byte_id]      = 1'b1;
            end
          end
          sha_send(data, keep, offset + 4 >= length);
        end
        wait (sha_done);
        #1;
        if (sha_error || !sha_digest_valid || sha_digest !== expected_sha[mode*11+test_id])
          $fatal(1, "SHA padding mismatch mode=%0d bytes=%0d", mode, length);
        $display("CRYPTO_SHA_CASE mode=%0d bytes=%0d cycles=%0d", mode, length, sha_cycles);
      end
    end
    // Abort a partially supplied SHA job, then invalidate both engines.
    sha_begin(1'b1, 64'd64);
    sha_send(32'h01020304, 4'hf, 1'b0);
    @(negedge clk_i);
    sha_abort = 1'b1;
    @(negedge clk_i);
    sha_abort = 1'b0;
    if (sha_busy || sha_digest_valid) $fatal(1, "SHA abort retained validity");
    zeroize_i = 1'b1;
    @(negedge clk_i);
    zeroize_i = 1'b0;
    if (aes_key_valid || aes_busy || sha_digest_valid) $fatal(1, "V1 zeroize validity");
    $display("CRYPTO_P0_VECTORS_PASS");
    $finish;
  end
endmodule
