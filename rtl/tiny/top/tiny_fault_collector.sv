// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Terminal transaction pulses contribute independently to the count. One
// deterministic winner supplies metadata; SYSCTRL owns validity and W1C.
module tiny_fault_collector (
    input  logic [ 1:0]       local_valid_i,
    input  logic [ 1:0][31:0] local_addr_i,
    input  logic [ 1:0]       local_write_i,
    input  logic [ 5:0]       external_valid_i,
    input  logic [ 5:0][31:0] external_addr_i,
    input  logic [ 5:0][ 1:0] external_resp_i,
    input  logic [ 5:0]       external_instruction_i,
    output logic [ 3:0]       count_o,
    output logic [31:0]       addr_o,
    output logic [ 1:0]       master_o,
    output logic              write_o,
    output logic [ 1:0]       resp_o
);
  logic [7:0] s_valid, s_write, s_instruction;
  logic [7:0][31:0] s_addr;
  logic [7:0][1:0] s_master, s_resp;
  logic [7:0][3:0] s_rank;
  logic [3:0]      s_best_rank;
  assign s_valid            = {external_valid_i, local_valid_i};
  assign s_addr             = {external_addr_i, local_addr_i};
  assign s_write[1:0]       = local_write_i;
  assign s_master[1:0]      = '0;
  assign s_resp[1:0]        = {2'b10, 2'b10};
  assign s_instruction[1:0] = 2'b01;
  for (genvar slot = 0; slot < 6; slot++) begin : gen_external
    assign s_write[slot+2]       = 1'(slot % 2);
    assign s_master[slot+2]      = 2'(slot / 2);
    assign s_resp[slot+2]        = external_resp_i[slot];
    assign s_instruction[slot+2] = (slot < 2) && external_instruction_i[slot];
  end
  for (genvar slot = 0; slot < 8; slot++) begin : gen_rank
    assign s_rank[slot] = {s_master[slot], !s_instruction[slot], s_write[slot]};
  end
  always_comb begin
    count_o     = '0;
    addr_o      = '0;
    master_o    = '0;
    write_o     = 1'b0;
    resp_o      = '0;
    s_best_rank = 4'hf;
    for (int slot = 0; slot < 8; slot++) begin
      if (s_valid[slot]) begin
        count_o = count_o + 4'd1;
        if (s_rank[slot] < s_best_rank) begin
          s_best_rank = s_rank[slot];
          addr_o      = s_addr[slot];
          master_o    = s_master[slot];
          write_o     = s_write[slot];
          resp_o      = s_resp[slot];
        end
      end
    end
  end
endmodule
