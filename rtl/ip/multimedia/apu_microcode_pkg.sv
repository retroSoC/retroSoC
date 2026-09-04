// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

package apu_microcode_pkg;
  typedef struct packed {
    logic [10:0] entry_pc;
    logic [10:0] first_pc;
    logic [10:0] last_pc;
    logic [15:0] max_loop_count;
    logic [23:0] max_retired;
  } apu_mc_entry_t;

  function automatic logic [31:0] crc32_word(input logic [31:0] crc_i, input logic [31:0] data_i,
                                             input logic [3:0] keep_i);
    logic [31:0] s_crc;
    logic [ 7:0] s_byte;
    begin
      s_crc = crc_i;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (keep_i[byte_index]) begin
          s_byte = data_i[(byte_index*8)+:8];
          s_crc  = s_crc ^ {24'd0, s_byte};
          for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
            s_crc = s_crc[0] ? ((s_crc >> 1) ^ 32'hedb8_8320) : (s_crc >> 1);
          end
        end
      end
      return s_crc;
    end
  endfunction

  function automatic logic [31:0] trap_detail(input logic [7:0] reason_i, input logic [10:0] pc_i,
                                              input logic [63:0] instruction_i);
    logic s_unused;
    begin
      s_unused = ^{instruction_i[55:37], instruction_i[31:0]};
      return {instruction_i[36:32], instruction_i[59:56], instruction_i[63:60], pc_i, reason_i} |
          {32{s_unused && 1'b0}};
    end
  endfunction

  function automatic logic instruction_encoding_valid(input logic [63:0] instruction_i);
    logic [ 3:0] s_class;
    logic [ 3:0] s_opcode;
    logic [ 3:0] s_predicate;
    logic [ 3:0] s_dst;
    logic [ 3:0] s_src0;
    logic [ 3:0] s_src1;
    logic [ 7:0] s_aux;
    logic [31:0] s_immediate;
    logic        s_valid;
    begin
      s_class     = instruction_i[63:60];
      s_opcode    = instruction_i[59:56];
      s_predicate = instruction_i[55:52];
      s_dst       = instruction_i[51:48];
      s_src0      = instruction_i[47:44];
      s_src1      = instruction_i[43:40];
      s_aux       = instruction_i[39:32];
      s_immediate = instruction_i[31:0];
      s_valid     = s_predicate <= `APB4_APU__MC_PRED_TRANSPORT_DONE;
      if (s_class == `APB4_APU__MC_CLASS_CONTROL) begin
        unique case (s_opcode)
          `APB4_APU__MC_CONTROL_NOP, `APB4_APU__MC_CONTROL_END:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux, s_immediate} == 52'd0);
          `APB4_APU__MC_CONTROL_TRAP:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux} == 20'd0);
          `APB4_APU__MC_CONTROL_JUMP_FWD, `APB4_APU__MC_CONTROL_CALL_FWD:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux} == 20'd0) &&
              (s_immediate[31:11] == 21'd0) && (s_immediate[10:0] != 11'd0);
          `APB4_APU__MC_CONTROL_RET:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux, s_immediate} == 52'd0) &&
              (s_predicate == `APB4_APU__MC_PRED_ALWAYS);
          `APB4_APU__MC_CONTROL_LOOP_SETUP:
          s_valid = s_valid && ({s_dst, s_src1, s_immediate} == 40'd0) &&
              (s_aux[7:2] == 6'd0) && (s_predicate == `APB4_APU__MC_PRED_ALWAYS);
          `APB4_APU__MC_CONTROL_LOOP_BACK:
          s_valid = s_valid && ({s_dst, s_src0, s_src1} == 12'd0) &&
              (s_aux[7:2] == 6'd0) && (s_immediate[31:11] == 21'd0) &&
              (s_immediate[10:0] != 11'd0) &&
              (s_predicate == `APB4_APU__MC_PRED_ALWAYS);
          `APB4_APU__MC_CONTROL_WAIT:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_immediate} == 44'd0) &&
              (s_aux <= 8'd5) && (s_predicate == `APB4_APU__MC_PRED_ALWAYS);
          default: s_valid = 1'b0;
        endcase
      end else if (s_class == `APB4_APU__MC_CLASS_SCALAR) begin
        unique case (s_opcode)
          `APB4_APU__MC_SCALAR_MOV: s_valid = s_valid && ({s_src1, s_aux, s_immediate} == 44'd0);
          `APB4_APU__MC_SCALAR_MOVI: s_valid = s_valid && ({s_src0, s_src1, s_aux} == 16'd0);
          `APB4_APU__MC_SCALAR_ADD, `APB4_APU__MC_SCALAR_SUB,
          `APB4_APU__MC_SCALAR_AND, `APB4_APU__MC_SCALAR_OR,
          `APB4_APU__MC_SCALAR_XOR, `APB4_APU__MC_SCALAR_SHL,
          `APB4_APU__MC_SCALAR_SHR, `APB4_APU__MC_SCALAR_SAR:
          s_valid = s_valid && ({s_aux, s_immediate} == 40'd0);
          `APB4_APU__MC_SCALAR_CMP: s_valid = s_valid && ({s_dst, s_aux, s_immediate} == 44'd0);
          `APB4_APU__MC_SCALAR_MIN, `APB4_APU__MC_SCALAR_MAX:
          s_valid = s_valid && (s_aux[7:1] == 7'd0) && (s_immediate == 32'd0);
          `APB4_APU__MC_SCALAR_SAT:
          s_valid = s_valid && (s_src1 == 4'd0) && (s_aux[7:6] == 2'd0) &&
              ((s_aux[4:0] == 5'd0) || (s_aux[4:0] == 5'd8) ||
               (s_aux[4:0] == 5'd16) || (s_aux[4:0] == 5'd24)) &&
              (s_immediate == 32'd0);
          default: s_valid = 1'b0;
        endcase
      end else if (s_class == 4'd2) begin
        unique case (s_opcode)
          4'd0, 4'd1, 4'd2:
          s_valid = s_valid && ({s_src0, s_src1, s_aux} == 16'd0) &&
              (s_immediate[31:6] == 26'd0) && (s_immediate[5:0] != 6'd0);
          4'd3:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux} == 20'd0) &&
              (s_immediate[31:6] == 26'd0) && (s_immediate[5:0] != 6'd0);
          4'd4: s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux, s_immediate} == 52'd0);
          4'd5:
          s_valid = s_valid && (s_aux[7:5] == 3'd0) && (s_aux[4:0] >= 5'd8) &&
              (s_aux[4:0] <= 5'd16) && (s_immediate[31:16] == 16'd0) &&
              (s_immediate[15:0] != 16'd0);
          4'd6, 4'd7: s_valid = s_valid && ({s_aux, s_immediate} == 40'd0);
          default: s_valid = 1'b0;
        endcase
      end else if (s_class == 4'd3) begin
        unique case (s_opcode)
          4'd0, 4'd1, 4'd2:
          s_valid = s_valid && (s_aux[7:5] == 3'd0) && (s_aux[4:0] != 5'd0) &&
              (s_aux[4:0] <= 5'd24) && (s_immediate == 32'd0) &&
              ((s_opcode != 4'd1) || (s_dst <= 4'd14)) &&
              ((s_opcode != 4'd2) || (s_dst <= 4'd12));
          4'd3:
          s_valid = s_valid && ({s_src0, s_src1} == 8'd0) && (s_aux[7:1] == 7'd0) &&
              (s_immediate[31:16] == 16'd0) && (s_immediate[15:0] != 16'd0);
          4'd4, 4'd5, 4'd6: s_valid = s_valid && ({s_aux, s_immediate} == 40'd0);
          default: s_valid = 1'b0;
        endcase
      end else if (s_class == 4'd4) begin
        unique case (s_opcode)
          4'd0: s_valid = s_valid && ({s_src1, s_aux} == 12'd0) && (s_immediate[31:16] == 16'd0);
          4'd1: s_valid = s_valid && ({s_dst, s_aux} == 12'd0) && (s_immediate[31:16] == 16'd0);
          4'd2, 4'd3, 4'd4: s_valid = s_valid && ({s_aux, s_immediate} == 40'd0);
          4'd5:
          s_valid = s_valid && (s_dst <= 4'd14) && ({s_src0, s_src1, s_aux, s_immediate} == 48'd0);
          4'd6: s_valid = s_valid && ({s_dst, s_aux, s_immediate} == 44'd0);
          default: s_valid = 1'b0;
        endcase
      end else if (s_class == 4'd5) begin
        s_valid = s_valid && (s_opcode <= 4'd9) && (s_immediate[31:16] == 16'd0) &&
            (s_immediate[15:0] != 16'd0);
        unique case (s_opcode)
          4'd0: s_valid = s_valid && (s_aux[7:6] != 2'd3);
          4'd1, 4'd7: s_valid = s_valid && (s_aux[7:2] == 6'd0);
          4'd2, 4'd3, 4'd4: s_valid = s_valid && (s_aux == 8'd0);
          4'd5: s_valid = s_valid && (s_aux[7:3] == 5'd0) && (s_aux[2:0] <= 3'd4);
          4'd6:
          s_valid = s_valid && (s_aux[7:6] == 2'd0) && (s_aux[5:0] != 6'd0) &&
              (s_aux[5:0] <= 6'd32);
          4'd8: s_valid = s_valid && (s_aux[7:4] == 4'd0);
          4'd9: s_valid = s_valid && (s_aux[7:3] == 5'd0) && (s_aux[1:0] <= 2'd1);
          default: s_valid = 1'b0;
        endcase
      end else if (s_class == 4'd6) begin
        unique case (s_opcode)
          4'd0, 4'd1, 4'd2: s_valid = s_valid && ({s_aux, s_immediate} == 40'd0);
          4'd3: s_valid = s_valid && ({s_src0, s_src1, s_aux, s_immediate} == 48'd0);
          4'd4: s_valid = s_valid && ({s_dst, s_aux, s_immediate} == 44'd0);
          4'd5:
          s_valid = s_valid && (s_dst == 4'd0) && (s_src0[3:0] == s_src0) &&
              (s_aux[7:4] == 4'd0) && (s_immediate == 32'd0);
          4'd6:
          s_valid = s_valid && ({s_dst, s_src0, s_src1, s_aux} == 20'd0) &&
              (s_immediate[31:11] == 21'd0) && (s_immediate[10:0] != 11'd0) &&
              ((s_immediate[10:0] & ~11'h0c0) == 11'd0);
          default: s_valid = 1'b0;
        endcase
      end else begin
        s_valid = 1'b0;
      end
      return s_valid;
    end
  endfunction
endpackage
