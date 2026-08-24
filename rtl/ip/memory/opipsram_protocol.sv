// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module opipsram_protocol (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic        write_i,
    input  logic        indirect_register_i,
    input  logic [31:0] addr_i,
    input  logic [15:0] opi_cmd_i,
    input  logic        opi_width16_i,
    input  logic [31:0] opi_timing_i,
    input  logic [31:0] hyper_timing_i,
    output logic [47:0] hyper_ca_o,
    output logic [1:0]  opi_cmd_count_o,
    output logic [7:0]  opi_cmd_first_o,
    output logic [7:0]  opi_cmd_second_o,
    output logic [2:0]  opi_addr_bytes_o,
    output logic [31:0] opi_addr_shift_o,
    output logic [9:0]  opi_wait_phases_o,
    output logic [9:0]  hyper_wait_phases_o,
    output logic        opi_dqs_read_o,
    output logic        opi_dqs_write_o
    // verilog_format: on
);

  logic [ 9:0] s_opi_wait_ck;
  logic [ 9:0] s_hyper_wait_ck;
  logic [31:0] s_hyper_word_addr;
  logic        unused_opi_timing_reserved;
  logic        unused_hyper_timing_reserved;

  assign opi_cmd_count_o              = opi_width16_i ? 2'd2 : 2'd1;
  assign opi_cmd_first_o              = opi_width16_i ? opi_cmd_i[15:8] : opi_cmd_i[7:0];
  assign opi_cmd_second_o             = opi_cmd_i[7:0];
  assign opi_addr_bytes_o             = (opi_timing_i[1:0] == 2'd1) ? 3'd4 : 3'd3;
  assign opi_addr_shift_o             = (opi_addr_bytes_o == 3'd4) ? addr_i : {addr_i[23:0], 8'd0};
  assign s_opi_wait_ck                = {2'd0, opi_timing_i[9:2]} + {5'd0, opi_timing_i[14:10]};
  assign s_hyper_wait_ck              = {2'd0, hyper_timing_i[7:0]};
  assign opi_wait_phases_o            = s_opi_wait_ck << 1;
  assign hyper_wait_phases_o          = s_hyper_wait_ck << 1;
  assign opi_dqs_read_o               = opi_timing_i[15];
  assign opi_dqs_write_o              = opi_timing_i[16];
  assign s_hyper_word_addr            = {1'b0, addr_i[31:1]};
  assign unused_opi_timing_reserved   = ^opi_timing_i[31:17];
  assign unused_hyper_timing_reserved = ^hyper_timing_i[31:8];

  always_comb begin
    hyper_ca_o        = 48'd0;
    hyper_ca_o[47]    = !write_i;
    hyper_ca_o[46]    = indirect_register_i;
    hyper_ca_o[45]    = 1'b1;
    hyper_ca_o[44:16] = s_hyper_word_addr[31:3];
    hyper_ca_o[15:3]  = 13'd0;
    hyper_ca_o[2:0]   = s_hyper_word_addr[2:0];
  end

endmodule
