// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

package crypto_mem_pkg;
  // Fixed-latency, single-port transactions. A request retires on the next
  // cycle; clients must consume that response even when canceling their work.
  // Tags distinguish engine, APB and maintenance responses at the arbiter;
  // epoch/token together identify the live engine transaction.
  typedef struct packed {
    logic        valid;
    logic        write;
    logic [9:0]  row;
    logic [31:0] data;
    logic [3:0]  mask;
    logic [1:0]  tag;
    logic [3:0]  epoch;
    logic [3:0]  token;
  } crypto_mem_req_t;
  typedef struct packed {
    logic        valid;
    logic        write;
    logic [9:0]  row;
    logic [31:0] data;
    logic [1:0]  tag;
    logic [3:0]  epoch;
    logic [3:0]  token;
  } crypto_mem_resp_t;

  function automatic crypto_mem_req_t mem_read(input logic [9:0] row);
    crypto_mem_req_t result;
    result       = '0;
    result.valid = 1'b1;
    result.row   = row;
    return result;
  endfunction

  function automatic crypto_mem_req_t mem_write(input logic [9:0] row, input logic [31:0] data);
    crypto_mem_req_t result;
    result       = mem_read(row);
    result.write = 1'b1;
    result.mask  = 4'hf;
    result.data  = data;
    return result;
  endfunction

  function automatic logic [31:0] crc_word(input logic [31:0] crc, input logic [31:0] data);
    logic [31:0] value;
    value = crc ^ data;
    for (int unsigned bit_index = 0; bit_index < 32; bit_index++) begin
      value = (value >> 1) ^ (value[0] ? 32'hedb88320 : 32'd0);
    end
    return value;
  endfunction

  function automatic logic constant_padding_error(input logic [10:0] row, input logic [31:0] data);
    if (row < 11'd528) return |data[31:8];
    if ((row < 11'd1024) || (row >= 11'd1104)) return |data;
    return 1'b0;
  endfunction

  function automatic logic [31:0] byte_reverse(input logic [31:0] value);
    return {value[7:0], value[15:8], value[23:16], value[31:24]};
  endfunction
endpackage
