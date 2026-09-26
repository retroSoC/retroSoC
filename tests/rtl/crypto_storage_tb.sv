// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
module crypto_storage_tb;
  import crypto_mem_pkg::*;
  logic clk = 0, rst_n = 0, mont_start = 0, mont_clear = 0;
  always #5 clk = ~clk;
  crypto_mem_req_t  [5:0] req;
  crypto_mem_req_t        mont_req;
  crypto_mem_resp_t [5:0] resp;
  logic mont_busy, mont_done, mont_owner = 0;
  logic  [  31:0] n0_prime;
  logic  [2047:0] vectors     [0:5];
  string          vector_path;
  crypto_sram_store u_storage (
      .clk_i  (clk),
      .rst_n_i(rst_n),
      .req_i  (req),
      .resp_o (resp)
  );
  crypto_montgomery_sram u_mont (
      .clk_i     (clk),
      .rst_n_i   (rst_n),
      .clear_i   (mont_clear),
      .start_i   (mont_start),
      .n0_prime_i(n0_prime),
      .busy_o    (mont_busy),
      .done_o    (mont_done),
      .req_o     (mont_req),
      .resp_i    (resp[5])
  );
  crypto_mem_req_t [5:0] test_req = '0;
  always_comb begin
    req = test_req;
    if (mont_owner) req[5] = mont_req;
  end
  task automatic write_word(input int bank, input logic [9:0] row, input logic [31:0] data,
                            input logic [3:0] mask);
    @(negedge clk);
    test_req[bank]      = mem_write(row, data);
    test_req[bank].mask = mask;
    test_req[bank].tag  = 2'd2;
    @(negedge clk);
    if(!resp[bank].valid || !resp[bank].write || resp[bank].row!=row || resp[bank].tag!=2'd2 || resp[bank].data!=0)
      $fatal(1, "write retirement/masking bank %0d", bank);
    test_req[bank] = '0;
  endtask
  task automatic read_word(input int bank, input logic [9:0] row, input logic [31:0] expected);
    @(negedge clk);
    test_req[bank]     = mem_read(row);
    test_req[bank].tag = 2'd3;
    @(negedge clk);
    if(!resp[bank].valid || resp[bank].write || resp[bank].row!=row || resp[bank].tag!=2'd3 || resp[bank].data!==expected)
      $fatal(
          1,
          "read retirement bank %0d row %0d got %h expected %h",
          bank,
          row,
          resp[bank].data,
          expected
      );
    test_req[bank] = '0;
  endtask
  initial begin
    logic [2047:0] operand;
    int            cycles;
    if (!$value$plusargs("rsa=%s", vector_path)) $fatal(1, "missing RSA vector");
    $readmemh(vector_path, vectors);
    repeat (3) @(negedge clk);
    rst_n = 1;
    // First/last rows of all banks and each byte mask; no direct SRAM preload.
    for (int bank = 0; bank < 6; bank++) begin
      write_word(bank, 0, 32'h12345678, 4'hf);
      write_word(bank, 1023, 32'h87654321, 4'hf);
      write_word(bank, 0, 32'haabbccdd, 4'h5);
      read_word(bank, 0, 32'h12bb56dd);
      read_word(bank, 1023, 32'h87654321);
      write_word(bank, 1023, 32'hdeadbeef, 4'ha);
      read_word(bank, 1023, 32'hde65be21);
    end
    // Requests on different banks retire concurrently; sequential same-bank
    // read/write does not consume the macro's write-cycle DOUT.
    @(negedge clk);
    for (int bank = 0; bank < 6; bank++) test_req[bank] = mem_read(0);
    @(negedge clk);
    for (int bank = 0; bank < 6; bank++) begin
      if (!resp[bank].valid || resp[bank].data !== 32'h12bb56dd) $fatal(1, "parallel bank read");
      test_req[bank] = mem_write(0, 32'(bank));
    end
    @(negedge clk);
    for (int bank = 0; bank < 6; bank++) begin
      if (!resp[bank].valid || !resp[bank].write || resp[bank].data != 0)
        $fatal(1, "write DOUT consumed");
      test_req[bank] = mem_read(0);
    end
    @(negedge clk);
    for (int bank = 0; bank < 6; bank++)
    if (resp[bank].data !== 32'(bank)) $fatal(1, "same-bank ordering");
    rst_n = 0;
    #1;
    for (int bank = 0; bank < 6; bank++)
    if (resp[bank].valid) $fatal(1, "reset retained response epoch");
    test_req = '0;
    @(negedge clk);
    rst_n    = 1;
    operand  = vectors[0] - 2048'd1;
    n0_prime = vectors[4][31:0];
    for (int index = 0; index < 64; index++) begin
      write_word(5, 10'(index), operand[index*32+:32], 4'hf);
      write_word(5, 10'(64 + index), operand[index*32+:32], 4'hf);
      write_word(5, 10'(128 + index), vectors[0][index*32+:32], 4'hf);
    end
    @(negedge clk);
    mont_owner = 1;
    mont_start = 1;
    @(negedge clk);
    mont_start = 0;
    cycles     = 0;
    while (!mont_done && cycles < 131072) begin
      @(negedge clk);
      cycles++;
    end
    if (!mont_done) $fatal(1, "Montgomery cycle bound");
    @(negedge clk);
    mont_owner = 0;
    for (int index = 0; index < 64; index++)
    read_word(5, 10'(321 + index), vectors[5][index*32+:32]);
    $display("CRYPTO_V2_STORAGE_PASS montgomery_cycles=%0d", cycles);
    $finish;
  end
  initial begin
    #2000000;
    $fatal(1, "storage watchdog");
  end
endmodule
