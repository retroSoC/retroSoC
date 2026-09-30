// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

package crypto_pkg;
  localparam logic [1:0] AES_KEY_128 = 2'd0;
  localparam logic [1:0] AES_KEY_192 = 2'd1;
  localparam logic [1:0] AES_KEY_256 = 2'd2;

  localparam logic [1:0] AES_MODE_ECB = 2'd0;
  localparam logic [1:0] AES_MODE_CBC = 2'd1;
  localparam logic [1:0] AES_MODE_CTR = 2'd2;

  localparam logic SHA2_224 = 1'b0;
  localparam logic SHA2_256 = 1'b1;

  function automatic logic [7:0] aes_xtime(input logic [7:0] value);
    aes_xtime = {value[6:0], 1'b0} ^ (8'h1b & {8{value[7]}});
  endfunction

  function automatic logic [7:0] aes_multiply(input logic [7:0] left, input logic [3:0] right);
    logic [7:0] value;
    logic [7:0] product;
    begin
      value   = left;
      product = '0;
      for (int unsigned bit_index = 0; bit_index < 4; bit_index++) begin
        if (right[bit_index]) begin
          product ^= value;
        end
        value = aes_xtime(value);
      end
      aes_multiply = product;
    end
  endfunction

  function automatic logic [127:0] aes_shift_rows(input logic [127:0] state);
    logic        [127:0] result;
    int unsigned         source_index;
    begin
      for (int unsigned column = 0; column < 4; column++) begin
        for (int unsigned row = 0; row < 4; row++) begin
          source_index                    = 4 * ((column + row) % 4) + row;
          result[127-(4*column+row)*8-:8] = state[127-source_index*8-:8];
        end
      end
      aes_shift_rows = result;
    end
  endfunction

  function automatic logic [127:0] aes_inverse_shift_rows(input logic [127:0] state);
    logic        [127:0] result;
    int unsigned         source_index;
    begin
      for (int unsigned column = 0; column < 4; column++) begin
        for (int unsigned row = 0; row < 4; row++) begin
          source_index                    = 4 * ((column + 4 - row) % 4) + row;
          result[127-(4*column+row)*8-:8] = state[127-source_index*8-:8];
        end
      end
      aes_inverse_shift_rows = result;
    end
  endfunction

  function automatic logic [127:0] aes_mix_columns(input logic [127:0] state);
    logic [127:0] result;
    logic [  7:0] a0;
    logic [  7:0] a1;
    logic [  7:0] a2;
    logic [  7:0] a3;
    begin
      for (int unsigned column = 0; column < 4; column++) begin
        a0                            = state[127-(4*column)*8-:8];
        a1                            = state[127-(4*column+1)*8-:8];
        a2                            = state[127-(4*column+2)*8-:8];
        a3                            = state[127-(4*column+3)*8-:8];
        result[127-(4*column)*8-:8]   = aes_multiply(a0, 4'h2) ^ aes_multiply(a1, 4'h3) ^ a2 ^ a3;
        result[127-(4*column+1)*8-:8] = a0 ^ aes_multiply(a1, 4'h2) ^ aes_multiply(a2, 4'h3) ^ a3;
        result[127-(4*column+2)*8-:8] = a0 ^ a1 ^ aes_multiply(a2, 4'h2) ^ aes_multiply(a3, 4'h3);
        result[127-(4*column+3)*8-:8] = aes_multiply(a0, 4'h3) ^ a1 ^ a2 ^ aes_multiply(a3, 4'h2);
      end
      aes_mix_columns = result;
    end
  endfunction

  function automatic logic [127:0] aes_inverse_mix_columns(input logic [127:0] state);
    logic [127:0] result;
    logic [  7:0] a0;
    logic [  7:0] a1;
    logic [  7:0] a2;
    logic [  7:0] a3;
    begin
      for (int unsigned column = 0; column < 4; column++) begin
        a0 = state[127-(4*column)*8-:8];
        a1 = state[127-(4*column+1)*8-:8];
        a2 = state[127-(4*column+2)*8-:8];
        a3 = state[127-(4*column+3)*8-:8];
        result[127-(4*column)*8-:8] = aes_multiply(a0, 4'he) ^ aes_multiply(a1, 4'hb) ^
            aes_multiply(a2, 4'hd) ^ aes_multiply(a3, 4'h9);
        result[127-(4*column+1)*8-:8] = aes_multiply(a0, 4'h9) ^ aes_multiply(a1, 4'he) ^
            aes_multiply(a2, 4'hb) ^ aes_multiply(a3, 4'hd);
        result[127-(4*column+2)*8-:8] = aes_multiply(a0, 4'hd) ^ aes_multiply(a1, 4'h9) ^
            aes_multiply(a2, 4'he) ^ aes_multiply(a3, 4'hb);
        result[127-(4*column+3)*8-:8] = aes_multiply(a0, 4'hb) ^ aes_multiply(a1, 4'hd) ^
            aes_multiply(a2, 4'h9) ^ aes_multiply(a3, 4'he);
      end
      aes_inverse_mix_columns = result;
    end
  endfunction

  function automatic logic [31:0] rotate_right(input logic [31:0] value, input int unsigned amount);
    rotate_right = (value >> amount) | (value << (32 - amount));
  endfunction

  function automatic logic [31:0] sha2_sigma0(input logic [31:0] value);
    sha2_sigma0 = rotate_right(value, 7) ^ rotate_right(value, 18) ^ (value >> 3);
  endfunction

  function automatic logic [31:0] sha2_sigma1(input logic [31:0] value);
    sha2_sigma1 = rotate_right(value, 17) ^ rotate_right(value, 19) ^ (value >> 10);
  endfunction

  function automatic logic [31:0] sha2_sum0(input logic [31:0] value);
    sha2_sum0 = rotate_right(value, 2) ^ rotate_right(value, 13) ^ rotate_right(value, 22);
  endfunction

  function automatic logic [31:0] sha2_sum1(input logic [31:0] value);
    sha2_sum1 = rotate_right(value, 6) ^ rotate_right(value, 11) ^ rotate_right(value, 25);
  endfunction
endpackage
