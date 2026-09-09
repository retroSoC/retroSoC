// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_entropy_engine (
    // verilog_format: off -- preserve command, memory, and reservoir columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  flush_i,
    input  logic                  req_valid_i,
    output logic                  req_ready_o,
    input  logic [ 3:0]           opcode_i,
    input  logic [ 3:0]           dst_i,
    input  logic [ 7:0]           aux_i,
    input  logic [31:0]           immediate_i,
    input  logic [31:0]           source0_i,
    input  logic [31:0]           source1_i,
    input  logic [15:0]           table_offset_i,
    output logic                  memory_req_o,
    output logic [16:0]           memory_addr_o,
    input  logic                  memory_valid_i,
    input  logic [31:0]           memory_data_i,
    input  logic                  memory_error_i,
    output logic                  bit_req_valid_o,
    input  logic                  bit_req_ready_i,
    output logic [ 2:0]           bit_req_op_o,
    output logic [ 5:0]           bit_req_width_o,
    input  logic                  bit_result_valid_i,
    input  logic [31:0]           bit_result_data_i,
    input  logic                  bit_error_i,
    output logic                  result_valid_o,
    output logic [ 3:0]           result_dst_o,
    output logic [ 3:0][31:0]     result_data_o,
    output logic [ 2:0]           result_words_o,
    output logic                  error_o,
    output logic [ 5:0]           error_code_o,
    output logic [ 3:0]           error_stage_o,
    output logic [31:0]           cycles_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    TableRequest,
    TableWait,
    BitRequest,
    BitWait,
    ConsumeRequest,
    ConsumeWait,
    UnaryRequest,
    UnaryWait,
    RiceRequest,
    RiceWait,
    ValueRequest,
    ValueWait,
    SignRequest,
    SignWait
  } state_e;

  state_e s_state_q;
  logic [3:0] s_opcode_q, s_dst_q;
  logic [4:0] s_aux_q;
  logic [31:0] s_immediate_q, s_source0_q;
  logic [15:0] s_table_offset_q;
  logic [31:0] s_entry_index_q, s_entry_count_q, s_entry_issue_q;
  logic [24:0] s_code_q, s_candidate_code_q;
  logic [4:0] s_previous_len_q, s_len_q;
  logic [31:0] s_symbol_q, s_run_q, s_quotient_q, s_magnitude_q;
  logic [5:0] s_value_width_q;
  logic       s_unused;
  logic s_direct_bit_req, s_huff_peek_req, s_huff_consume_req;
  logic s_unary_continue_req, s_rice_continue_req, s_rice_value_req, s_sign_req;
  logic [5:0] s_rice_width;
  logic s_direct_huff_bit_req, s_huff_entry_valid, s_huff_entry_match;
  logic [5:0] s_huff_width_q;
  logic [31:0] s_huff_bits_q, s_huff_prefix;
  logic s_huff_peek_pending_q;

  assign req_ready_o = s_state_q == Idle;
  assign s_rice_width = (s_opcode_q == `APB4_APU__MC_ENTROPY_RICE4) ?
      {2'd0, s_source0_q[3:0]} : {1'b0, s_source0_q[4:0]};
  assign s_direct_huff_bit_req = (s_state_q == Idle) && req_valid_i && req_ready_o &&
      (opcode_i <= `APB4_APU__MC_ENTROPY_HUFF_QUAD) &&
      (source1_i >= 32'd1) && (source1_i <= 32'd4096);
  assign s_direct_bit_req = (s_state_q == Idle) && req_valid_i && req_ready_o &&
      (opcode_i > `APB4_APU__MC_ENTROPY_HUFF_QUAD) &&
      !((opcode_i == `APB4_APU__MC_ENTROPY_SIGN_RESTORE) && (source0_i == 32'd0)) &&
      !((opcode_i inside {`APB4_APU__MC_ENTROPY_RICE4,
                          `APB4_APU__MC_ENTROPY_RICE5}) &&
        (((opcode_i == `APB4_APU__MC_ENTROPY_RICE4) && (source0_i[3:0] == 4'd15)) ||
         ((opcode_i == `APB4_APU__MC_ENTROPY_RICE5) && (source0_i[4:0] == 5'd31))) &&
        ((source1_i[5:0] == 6'd0) || (source1_i[5:0] > 6'd32)));
  assign s_huff_peek_req = (s_state_q == BitWait) && !s_huff_peek_pending_q &&
      bit_result_valid_i && !bit_error_i && (bit_result_data_i[6:0] != 7'd0);
  assign s_huff_consume_req = (s_state_q == TableRequest) && memory_valid_i &&
      !memory_error_i && s_huff_entry_match;
  assign s_unary_continue_req = (s_state_q == UnaryWait) && bit_result_valid_i && !bit_error_i &&
      (bit_result_data_i[0] == s_aux_q[0]) && (s_run_q < s_immediate_q);
  assign s_rice_continue_req = (s_state_q == RiceWait) && bit_result_valid_i && !bit_error_i &&
      !bit_result_data_i[0] && (s_quotient_q < 32'd65535);
  assign s_rice_value_req = (s_state_q == RiceWait) && bit_result_valid_i && !bit_error_i &&
      bit_result_data_i[0] && (s_rice_width != 6'd0);
  assign s_sign_req = (s_state_q == ValueWait) && bit_result_valid_i && !bit_error_i &&
      (s_opcode_q == `APB4_APU__MC_ENTROPY_SIGN_RESTORE);
  assign memory_req_o = (s_state_q == TableRequest) && (s_entry_issue_q < s_entry_count_q);
  assign memory_addr_o = 17'({16'd0, s_table_offset_q} + s_source0_q + (s_entry_issue_q << 2));
  assign bit_req_valid_o = s_direct_huff_bit_req || s_direct_bit_req || s_huff_peek_req ||
      s_huff_consume_req || s_unary_continue_req || s_rice_continue_req ||
      s_rice_value_req || s_sign_req || (s_state_q inside {
    BitRequest, ConsumeRequest, UnaryRequest, RiceRequest, ValueRequest, SignRequest
  });
  assign bit_req_op_o = s_direct_huff_bit_req ? 3'd0 :
      (((s_state_q == BitRequest) || s_huff_peek_req) ? 3'd1 : 3'd2);
  assign bit_req_width_o = s_direct_huff_bit_req ? {1'b0, aux_i[4:0]} :
      (s_direct_bit_req ?
      ((opcode_i == `APB4_APU__MC_ENTROPY_UNARY) ? 6'd1 :
       ((opcode_i inside {`APB4_APU__MC_ENTROPY_RICE4,
                           `APB4_APU__MC_ENTROPY_RICE5}) ?
        ((((opcode_i == `APB4_APU__MC_ENTROPY_RICE4) && (source0_i[3:0] == 4'd15)) ||
          ((opcode_i == `APB4_APU__MC_ENTROPY_RICE5) && (source0_i[4:0] == 5'd31))) ?
         source1_i[5:0] : 6'd1) :
        ((source1_i[4:0] == 5'd0) ? 6'd1 : {1'b0, source1_i[4:0]}))) :
      (s_huff_peek_req ? bit_result_data_i[5:0] :
       (s_huff_consume_req ? {1'b0, memory_data_i[20:16]} :
        (s_rice_value_req ? s_rice_width :
        ((s_state_q inside {UnaryRequest, RiceRequest, SignRequest}) ||
         s_unary_continue_req || s_rice_continue_req || s_sign_req ? 6'd1 :
         ((s_state_q == ValueRequest) ? s_value_width_q : {1'b0, s_len_q}))))));

  always_comb begin
    s_candidate_code_q = s_code_q << (memory_data_i[20:16] - s_previous_len_q);
    s_huff_entry_valid = (memory_data_i[31:21] == 11'd0) &&
        (memory_data_i[20:16] >= s_previous_len_q) &&
        (memory_data_i[20:16] != 5'd0) && (memory_data_i[20:16] <= s_aux_q) &&
        (s_candidate_code_q < (25'd1 << memory_data_i[20:16]));
    s_huff_prefix = 32'd0;
    if ({1'b0, memory_data_i[20:16]} <= s_huff_width_q) begin
      s_huff_prefix = s_huff_bits_q >> (s_huff_width_q - memory_data_i[20:16]);
    end
    s_huff_entry_match = s_huff_entry_valid &&
        ({1'b0, memory_data_i[20:16]} <= s_huff_width_q) &&
        (s_huff_prefix == {7'd0, s_candidate_code_q});
  end
  always_comb begin
    if (s_opcode_q <= `APB4_APU__MC_ENTROPY_HUFF_QUAD) begin
      cycles_o = 32'd26 + s_entry_count_q;
    end else if (s_opcode_q == `APB4_APU__MC_ENTROPY_UNARY) begin
      cycles_o = 32'd2 + s_run_q;
    end else if (s_opcode_q inside {`APB4_APU__MC_ENTROPY_RICE4, `APB4_APU__MC_ENTROPY_RICE5}) begin
      if (((s_opcode_q == `APB4_APU__MC_ENTROPY_RICE4) &&
           (s_source0_q[3:0] == 4'd15)) ||
          ((s_opcode_q == `APB4_APU__MC_ENTROPY_RICE5) &&
           (s_source0_q[4:0] == 5'd31))) begin
        cycles_o = 32'd4 + {26'd0, s_value_width_q};
      end else begin
        cycles_o = 32'd4 + s_quotient_q + {26'd0, s_value_width_q};
      end
    end else begin
      cycles_o = 32'd3 + {26'd0, s_value_width_q};
    end
  end
  assign s_unused = ^aux_i[7:5] && 1'b0;

  function automatic logic [31:0] rice_signed(
      input logic [31:0] quotient_i, input logic [31:0] remainder_i, input logic [5:0] width_i);
    logic [31:0] s_unsigned;
    begin
      s_unsigned = (quotient_i << width_i) | remainder_i;
      return (s_unsigned >> 1) ^ (32'd0 - s_unsigned[0]);
    end
  endfunction

  `define RETROSOC_APU__ENTROPY_ERROR(CODE)               \
    begin                                                  \
      s_state_q       <= Idle;                             \
      error_o         <= 1'b1;                             \
      error_code_o    <= CODE;                             \
      error_stage_o   <= `APB4_APU__ERROR_STAGE_ENTROPY;  \
      result_valid_o  <= 1'b1;                             \
      result_words_o  <= 3'd0;                             \
    end

  `define RETROSOC_APU__ENTROPY_LOCAL_ERROR                 \
    begin                                                    \
      s_state_q       <= Idle;                               \
      error_o         <= 1'b1;                               \
      error_code_o    <= `APB4_APU__ERROR_CODE_SEQUENCER;   \
      error_stage_o   <= `APB4_APU__ERROR_STAGE_LIFECYCLE;  \
      result_valid_o  <= 1'b1;                               \
      result_words_o  <= 3'd0;                               \
    end

  `define RETROSOC_APU__ENTROPY_FINISH_ONE(VALUE)  \
    begin                                           \
      s_state_q        <= Idle;                     \
      result_valid_o   <= 1'b1;                     \
      result_words_o   <= 3'd1;                     \
      result_dst_o     <= s_dst_q;                  \
      result_data_o[0] <= VALUE;                    \
    end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q             <= Idle;
      s_opcode_q            <= 4'd0;
      s_dst_q               <= 4'd0;
      s_aux_q               <= 5'd0;
      s_immediate_q         <= 32'd0;
      s_source0_q           <= 32'd0;
      s_table_offset_q      <= 16'd0;
      s_entry_index_q       <= 32'd0;
      s_entry_count_q       <= 32'd0;
      s_entry_issue_q       <= 32'd0;
      s_code_q              <= 25'd0;
      s_previous_len_q      <= 5'd0;
      s_len_q               <= 5'd0;
      s_symbol_q            <= 32'd0;
      s_run_q               <= 32'd0;
      s_quotient_q          <= 32'd0;
      s_magnitude_q         <= 32'd0;
      s_value_width_q       <= 6'd0;
      s_huff_width_q        <= 6'd0;
      s_huff_bits_q         <= 32'd0;
      s_huff_peek_pending_q <= 1'b0;
      result_valid_o        <= 1'b0;
      result_dst_o          <= 4'd0;
      result_data_o         <= '0;
      result_words_o        <= 3'd0;
      error_o               <= 1'b0;
      error_code_o          <= 6'd0;
      error_stage_o         <= 4'd0;
    end else if (flush_i) begin
      s_state_q      <= Idle;
      result_valid_o <= 1'b0;
      error_o        <= 1'b0;
    end else begin
      result_valid_o <= 1'b0;
      error_o        <= 1'b0;
      unique case (s_state_q)
        Idle: begin
          if (req_valid_i) begin
            s_opcode_q            <= opcode_i;
            s_dst_q               <= dst_i;
            s_aux_q               <= aux_i[4:0];
            s_immediate_q         <= immediate_i;
            s_source0_q           <= source0_i;
            s_table_offset_q      <= table_offset_i;
            s_entry_index_q       <= 32'd0;
            s_entry_count_q       <= source1_i;
            s_entry_issue_q       <= 32'd0;
            s_code_q              <= 25'd0;
            s_previous_len_q      <= 5'd0;
            s_run_q               <= 32'd0;
            s_quotient_q          <= 32'd0;
            s_huff_peek_pending_q <= 1'b0;
            if (opcode_i <= `APB4_APU__MC_ENTROPY_HUFF_QUAD) begin
              if ((source1_i == 32'd0) || (source1_i > 32'd4096)) begin
                `RETROSOC_APU__ENTROPY_ERROR(6'd7)
              end else begin
                s_state_q <= s_direct_huff_bit_req ? BitWait : BitRequest;
              end
            end else if (opcode_i == `APB4_APU__MC_ENTROPY_UNARY) begin
              s_state_q <= s_direct_bit_req ? UnaryWait : UnaryRequest;
            end else if (opcode_i inside {`APB4_APU__MC_ENTROPY_RICE4,
                                          `APB4_APU__MC_ENTROPY_RICE5}) begin
              if (((opcode_i == `APB4_APU__MC_ENTROPY_RICE4) &&
                   (source0_i[3:0] == 4'd15)) ||
                  ((opcode_i == `APB4_APU__MC_ENTROPY_RICE5) &&
                   (source0_i[4:0] == 5'd31))) begin
                s_value_width_q <= source1_i[5:0];
                if ((source1_i[5:0] == 6'd0) || (source1_i[5:0] > 6'd32)) begin
                  `RETROSOC_APU__ENTROPY_ERROR(6'd7)
                end else begin
                  s_state_q <= s_direct_bit_req ? ValueWait : ValueRequest;
                end
              end else begin
                s_state_q <= s_direct_bit_req ? RiceWait : RiceRequest;
              end
            end else begin
              s_magnitude_q <= source0_i;
              if (source0_i == 32'd0) begin
                `RETROSOC_APU__ENTROPY_FINISH_ONE(32'd0)
              end else begin
                s_value_width_q <= {1'b0, source1_i[4:0]};
                if (source1_i[4:0] == 5'd0) begin
                  s_state_q <= s_direct_bit_req ? SignWait : SignRequest;
                end else begin
                  s_state_q <= s_direct_bit_req ? ValueWait : ValueRequest;
                end
              end
            end
          end
        end
        TableRequest: begin
          if (memory_req_o) s_entry_issue_q <= s_entry_issue_q + 1'b1;
          if (memory_error_i) begin
            `RETROSOC_APU__ENTROPY_LOCAL_ERROR
          end else if (memory_valid_i) begin
            if (!s_huff_entry_valid) begin
              `RETROSOC_APU__ENTROPY_ERROR(6'd7);
            end else if ({1'b0, memory_data_i[20:16]} > s_huff_width_q) begin
              `RETROSOC_APU__ENTROPY_ERROR(6'd5);
            end else if (s_huff_entry_match) begin
              s_len_q    <= memory_data_i[20:16];
              s_symbol_q <= {16'd0, memory_data_i[15:0]};
              s_state_q  <= s_huff_consume_req ? ConsumeWait : ConsumeRequest;
            end else if (s_entry_index_q + 1'b1 >= s_entry_count_q) begin
              `RETROSOC_APU__ENTROPY_ERROR(6'd7);
            end else begin
              s_code_q         <= s_candidate_code_q + 1'b1;
              s_previous_len_q <= memory_data_i[20:16];
              s_entry_index_q  <= s_entry_index_q + 1'b1;
            end
          end
        end
        TableWait: s_state_q <= TableRequest;
        BitRequest: begin
          if (bit_req_ready_i) s_state_q <= BitWait;
        end
        BitWait: begin
          if (bit_error_i) begin
            `RETROSOC_APU__ENTROPY_ERROR(6'd5);
          end else if (bit_result_valid_i) begin
            if (!s_huff_peek_pending_q) begin
              if (bit_result_data_i[6:0] == 7'd0) begin
                `RETROSOC_APU__ENTROPY_ERROR(6'd5);
              end else begin
                s_huff_width_q        <= bit_result_data_i[5:0];
                s_huff_peek_pending_q <= 1'b1;
              end
            end else begin
              s_huff_bits_q         <= bit_result_data_i;
              s_entry_index_q       <= 32'd0;
              s_entry_issue_q       <= 32'd0;
              s_code_q              <= 25'd0;
              s_previous_len_q      <= 5'd0;
              s_huff_peek_pending_q <= 1'b0;
              s_state_q             <= TableRequest;
            end
          end
        end
        ConsumeRequest: begin
          if (bit_req_ready_i) s_state_q <= ConsumeWait;
        end
        ConsumeWait: begin
          if (bit_error_i) begin
            `RETROSOC_APU__ENTROPY_ERROR(6'd5);
          end else if (bit_result_valid_i) begin
            s_state_q      <= Idle;
            result_valid_o <= 1'b1;
            result_dst_o   <= s_dst_q;
            if (s_opcode_q == `APB4_APU__MC_ENTROPY_HUFF_SYMBOL) begin
              result_words_o   <= 3'd1;
              result_data_o[0] <= s_symbol_q;
            end else if (s_opcode_q == `APB4_APU__MC_ENTROPY_HUFF_PAIR) begin
              result_words_o   <= 3'd2;
              result_data_o[0] <= {28'd0, s_symbol_q[7:4]};
              result_data_o[1] <= {28'd0, s_symbol_q[3:0]};
            end else begin
              result_words_o <= 3'd4;
              for (int index = 0; index < 4; index++) begin
                result_data_o[index] <= {31'd0, s_symbol_q[3-index]};
              end
            end
          end
        end
        UnaryRequest, RiceRequest, ValueRequest, SignRequest: begin
          if (bit_req_ready_i) begin
            unique case (s_state_q)
              UnaryRequest: s_state_q <= UnaryWait;
              RiceRequest:  s_state_q <= RiceWait;
              ValueRequest: s_state_q <= ValueWait;
              default:      s_state_q <= SignWait;
            endcase
          end
        end
        UnaryWait: begin
          if (bit_error_i) begin
            `RETROSOC_APU__ENTROPY_ERROR(6'd5)
          end else if (bit_result_valid_i) begin
            if (bit_result_data_i[0] != s_aux_q[0]) begin
              `RETROSOC_APU__ENTROPY_FINISH_ONE(s_run_q)
            end else if (s_run_q >= s_immediate_q) begin
              `RETROSOC_APU__ENTROPY_ERROR(6'd7)
            end else begin
              s_run_q   <= s_run_q + 1'b1;
              s_state_q <= s_unary_continue_req ? UnaryWait : UnaryRequest;
            end
          end
        end
        RiceWait: begin
          if (bit_error_i) begin
            `RETROSOC_APU__ENTROPY_ERROR(6'd5)
          end else if (bit_result_valid_i) begin
            if (bit_result_data_i[0]) begin
              s_value_width_q <= (s_opcode_q == `APB4_APU__MC_ENTROPY_RICE4) ?
                  {2'd0, s_source0_q[3:0]} : {1'd0, s_source0_q[4:0]};
              if (((s_opcode_q == `APB4_APU__MC_ENTROPY_RICE4) &&
                   (s_source0_q[3:0] == 4'd0)) ||
                  ((s_opcode_q == `APB4_APU__MC_ENTROPY_RICE5) &&
                   (s_source0_q[4:0] == 5'd0))) begin
                `RETROSOC_APU__ENTROPY_FINISH_ONE((s_quotient_q >> 1) ^ (32'd0 - s_quotient_q[0]));
              end else begin
                s_state_q <= s_rice_value_req ? ValueWait : ValueRequest;
              end
            end else if (s_quotient_q == 32'd65535) begin
              `RETROSOC_APU__ENTROPY_ERROR(6'd7);
            end else begin
              s_quotient_q <= s_quotient_q + 1'b1;
              s_state_q    <= s_rice_continue_req ? RiceWait : RiceRequest;
            end
          end
        end
        ValueWait: begin
          if (bit_error_i) begin
            `RETROSOC_APU__ENTROPY_ERROR(6'd5)
          end else if (bit_result_valid_i) begin
            if (s_opcode_q inside {`APB4_APU__MC_ENTROPY_RICE4, `APB4_APU__MC_ENTROPY_RICE5}) begin
              if (((s_opcode_q == `APB4_APU__MC_ENTROPY_RICE4) &&
                   (s_source0_q[3:0] == 4'd15)) ||
                  ((s_opcode_q == `APB4_APU__MC_ENTROPY_RICE5) &&
                   (s_source0_q[4:0] == 5'd31))) begin
                `RETROSOC_APU__ENTROPY_FINISH_ONE($unsigned(
                                                  $signed(
                                                      bit_result_data_i << (6'd32 - s_value_width_q)
                                                  ) >>> (6'd32 - s_value_width_q)
                                                  ));
              end else begin
                `RETROSOC_APU__ENTROPY_FINISH_ONE(
                    rice_signed(s_quotient_q, bit_result_data_i, s_value_width_q));
              end
            end else begin
              s_magnitude_q <= s_magnitude_q + bit_result_data_i;
              s_state_q     <= s_sign_req ? SignWait : SignRequest;
            end
          end
        end
        SignWait: begin
          if (bit_error_i) begin
            `RETROSOC_APU__ENTROPY_ERROR(6'd5)
          end else if (bit_result_valid_i) begin
            `RETROSOC_APU__ENTROPY_FINISH_ONE(
                bit_result_data_i[0] ? (32'd0 - s_magnitude_q) : s_magnitude_q);
          end
        end
        default:   s_state_q <= Idle;
      endcase
    end
  end

  `undef RETROSOC_APU__ENTROPY_ERROR
  `undef RETROSOC_APU__ENTROPY_LOCAL_ERROR
  `undef RETROSOC_APU__ENTROPY_FINISH_ONE
endmodule
