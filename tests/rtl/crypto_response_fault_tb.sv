// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
// Response fault model: a client accepts one matching epoch and ignores
// duplicate, delayed-after-abort and missing responses.
`timescale 1ns / 1ps
module crypto_response_fault_tb;
  import crypto_mem_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  crypto_mem_req_t [5:0] req_a = '0, req_b = '0;
  crypto_mem_resp_t [5:0] resp_a, resp_b;
  logic [3:0] current_epoch = 4'd3;
  logic       pending = 1'b0;
  int accepted = 0, ignored = 0;
  logic read_seen = 1'b0;

  crypto_sram_store #(
      .ResponseDelay    (1),
      .DuplicateResponse(1'b1)
  ) u_duplicate (
      .clk_i  (clk),
      .rst_n_i(rst_n),
      .req_i  (req_a),
      .resp_o (resp_a)
  );
  crypto_sram_store #(
      .ResponseDelay   (1),
      .DropResponseMask(6'b000001)
  ) u_drop (
      .clk_i  (clk),
      .rst_n_i(rst_n),
      .req_i  (req_b),
      .resp_o (resp_b)
  );

  always @(posedge clk) begin
    if (rst_n) begin
      if (resp_a[0].valid) begin
        if (!resp_a[0].write && (resp_a[0].epoch == 4'd1)) begin
          if (resp_a[0].data !== 32'hcafebabe)
            $fatal(1, "delayed response data mismatch: %h", resp_a[0].data);
          read_seen <= 1'b1;
        end
        if (pending && (resp_a[0].epoch == current_epoch)) begin
          accepted++;
          pending <= 1'b0;
        end else ignored++;
      end
      if (resp_b[0].valid) $fatal(1, "dropped response became visible");
    end
  end

  task automatic issue(input logic [3:0] epoch);
    @(negedge clk);
    req_a[0]       = mem_read(10'd7);
    req_a[0].tag   = 2'd0;
    req_a[0].epoch = epoch;
    pending        = 1'b1;
    @(negedge clk);
    req_a[0] = '0;
  endtask

  task automatic write_then_read;
    @(negedge clk);
    req_a[0]       = mem_write(10'd7, 32'hcafebabe);
    req_a[0].tag   = 2'd0;
    req_a[0].epoch = 4'd1;
    @(negedge clk);
    req_a[0] = '0;
    repeat (2) @(negedge clk);
    @(negedge clk);
    req_a[0]       = mem_read(10'd7);
    req_a[0].tag   = 2'd0;
    req_a[0].epoch = 4'd1;
    @(negedge clk);
    req_a[0] = '0;
    repeat (2) @(negedge clk);
    if (!read_seen) $fatal(1, "delayed response was not observed");
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    write_then_read();
    accepted = 0;
    ignored  = 0;
    issue(4'd3);
    repeat (3) @(negedge clk);
    if ((accepted != 1) || (ignored != 1))
      $fatal(1, "duplicate response count: accepted=%0d ignored=%0d", accepted, ignored);
    current_epoch = 4'd4;
    issue(4'd3);
    current_epoch = 4'd4;
    pending       = 1'b0;
    repeat (3) @(negedge clk);
    if (accepted != 1) $fatal(1, "late response crossed an epoch boundary");
    @(negedge clk);
    req_b[0]       = mem_read(10'd9);
    req_b[0].tag   = 2'd0;
    req_b[0].epoch = 4'd4;
    @(negedge clk);
    req_b[0] = '0;
    repeat (3) @(negedge clk);
    $display("CRYPTO_V2_RESPONSE_FAULT_PASS accepted=%0d ignored=%0d", accepted, ignored);
    $finish;
  end
  initial begin
    #10000;
    $fatal(1, "response fault watchdog");
  end
endmodule
