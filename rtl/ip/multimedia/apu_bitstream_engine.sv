// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_bitstream_engine (
    // verilog_format: off -- preserve request and FIFO columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        flush_i,
    input  logic        req_valid_i,
    output logic        req_ready_o,
    input  logic [ 2:0] req_op_i,
    input  logic [ 5:0] req_width_i,
    output logic        result_valid_o,
    output logic [31:0] result_data_o,
    output logic [ 6:0] available_bits_o,
    output logic        eof_o,
    output logic        error_o,
    input  logic        fifo_empty_i,
    input  logic [40:0] fifo_data_i,
    output logic        fifo_pop_o
    // verilog_format: on
);
  typedef enum logic [1:0] {
    Idle,
    Refill,
    Check,
    Execute
  } state_e;

  state_e         s_state_q;
  logic   [127:0] s_bits_q;
  logic   [  6:0] s_count_q;
  logic   [  2:0] s_op_q;
  logic   [  5:0] s_width_q;
  logic   [  2:0] s_bit_position_q;
  logic           s_eof_q;
  logic   [  6:0] s_append_bits;
  logic   [127:0] s_append_value;
  logic   [ 31:0] s_peek_value;
  logic   [  5:0] s_effective_width;
  logic   [ 31:0] s_req_peek_value;
  logic   [  5:0] s_req_effective_width;
  logic   [127:0] s_req_buffer;
  logic   [  6:0] s_req_buffer_count;

  function automatic logic [7:0] reverse_byte(input logic [7:0] value_i);
    logic [7:0] s_value;
    begin
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        s_value[bit_index] = value_i[7-bit_index];
      end
      return s_value;
    end
  endfunction

  always_comb begin
    s_append_bits  = 7'(fifo_data_i[34:32] * 8);
    s_append_value = 128'd0;
    for (int byte_index = 0; byte_index < 4; byte_index++) begin
      if (byte_index < fifo_data_i[34:32]) begin
        s_append_value[(byte_index*8)+:8] = reverse_byte(fifo_data_i[(byte_index*8)+:8]);
      end
    end
    s_peek_value       = 32'd0;
    s_req_peek_value   = 32'd0;
    s_req_buffer       = s_bits_q | (s_append_value << s_count_q);
    s_req_buffer_count = s_count_q + s_append_bits;
    for (int bit_index = 0; bit_index < 32; bit_index++) begin
      if (bit_index < s_width_q) begin
        s_peek_value[32'(s_width_q)-1-bit_index] = s_bits_q[bit_index];
      end
      if (bit_index < req_width_i) begin
        s_req_peek_value[32'(req_width_i)-1-bit_index] = s_req_buffer[bit_index];
      end
    end
    s_effective_width = (s_op_q == 3'd4) ? {3'd0, ((3'd0 - s_bit_position_q) & 3'd7)} : s_width_q;
    s_req_effective_width = (req_op_i == 3'd4) ?
        {3'd0, ((3'd0 - s_bit_position_q) & 3'd7)} : req_width_i;
  end

  assign req_ready_o = s_state_q == Idle;
  assign available_bits_o = s_count_q;
  assign eof_o = s_eof_q && fifo_empty_i && (s_count_q == 7'd0);
  assign fifo_pop_o = ((s_state_q == Refill) && !fifo_empty_i) ||
      ((s_state_q == Idle) && req_valid_i && req_ready_o &&
       (req_op_i != 3'd4) && (s_count_q < {1'b0, req_width_i}) && !fifo_empty_i);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q        <= Idle;
      s_bits_q         <= '0;
      s_count_q        <= 7'd0;
      s_op_q           <= 3'd0;
      s_width_q        <= 6'd0;
      s_bit_position_q <= 3'd0;
      s_eof_q          <= 1'b0;
      result_valid_o   <= 1'b0;
      result_data_o    <= 32'd0;
      error_o          <= 1'b0;
    end else if (flush_i) begin
      s_state_q        <= Idle;
      s_bits_q         <= '0;
      s_count_q        <= 7'd0;
      s_bit_position_q <= 3'd0;
      s_eof_q          <= 1'b0;
      result_valid_o   <= 1'b0;
      result_data_o    <= 32'd0;
      error_o          <= 1'b0;
    end else begin
      result_valid_o <= 1'b0;
      error_o        <= 1'b0;
      unique case (s_state_q)
        Idle: begin
          if (req_valid_i) begin
            s_op_q    <= req_op_i;
            s_width_q <= req_width_i;
            if ((req_op_i == 3'd4) || (s_count_q >= {1'b0, req_width_i})) begin
              result_data_o <= (req_op_i == 3'd0) ? {25'd0, s_count_q} : s_req_peek_value;
              if (req_op_i inside {3'd2, 3'd3, 3'd4}) begin
                s_bits_q         <= s_bits_q >> s_req_effective_width;
                s_count_q        <= s_count_q - s_req_effective_width;
                s_bit_position_q <= s_bit_position_q + s_req_effective_width[2:0];
              end
              result_valid_o <= 1'b1;
              s_state_q      <= Idle;
            end else if (!fifo_empty_i) begin
              s_bits_q  <= s_req_buffer;
              s_count_q <= s_req_buffer_count;
              if (fifo_data_i[40]) s_eof_q <= 1'b1;
              if (fifo_data_i[40] && (req_op_i != 3'd0) &&
                  (s_req_buffer_count < {1'b0, req_width_i})) begin
                error_o        <= 1'b1;
                result_valid_o <= 1'b1;
                s_state_q      <= Idle;
              end else if ((req_op_i != 3'd0) && (s_req_buffer_count >= {1'b0, req_width_i})) begin
                result_data_o <= s_req_peek_value;
                if (req_op_i inside {3'd2, 3'd3}) begin
                  s_bits_q         <= s_req_buffer >> req_width_i;
                  s_count_q        <= s_req_buffer_count - req_width_i;
                  s_bit_position_q <= s_bit_position_q + req_width_i[2:0];
                end
                result_valid_o <= 1'b1;
                s_state_q      <= Idle;
              end else begin
                s_state_q <= Check;
              end
            end else begin
              s_state_q <= Refill;
            end
          end
        end
        Refill: begin
          if (!fifo_empty_i) begin
            s_bits_q  <= s_bits_q | (s_append_value << s_count_q);
            s_count_q <= s_count_q + s_append_bits;
            if (fifo_data_i[40]) s_eof_q <= 1'b1;
            s_state_q <= Check;
          end else if (s_eof_q) begin
            if (s_op_q == 3'd0) begin
              s_state_q <= Execute;
            end else begin
              error_o        <= 1'b1;
              result_valid_o <= 1'b1;
              s_state_q      <= Idle;
            end
          end
        end
        Check: begin
          if (s_count_q >= {1'b0, s_width_q}) begin
            result_data_o <= (s_op_q == 3'd0) ? {25'd0, s_count_q} : s_peek_value;
            if (s_op_q inside {3'd2, 3'd3, 3'd4}) begin
              s_bits_q         <= s_bits_q >> s_effective_width;
              s_count_q        <= s_count_q - s_effective_width;
              s_bit_position_q <= s_bit_position_q + s_effective_width[2:0];
            end
            result_valid_o <= 1'b1;
            s_state_q      <= Idle;
          end else if (s_eof_q && fifo_empty_i) begin
            if (s_op_q == 3'd0) begin
              result_data_o  <= {25'd0, s_count_q};
              result_valid_o <= 1'b1;
              s_state_q      <= Idle;
            end else begin
              error_o        <= 1'b1;
              result_valid_o <= 1'b1;
              s_state_q      <= Idle;
            end
          end else begin
            s_state_q <= Refill;
          end
        end
        Execute: begin
          if ((s_op_q != 3'd0) && (s_count_q < {1'b0, s_effective_width})) begin
            s_state_q <= Refill;
          end else begin
            result_data_o <= (s_op_q == 3'd0) ? {25'd0, s_count_q} : s_peek_value;
            if (s_op_q inside {3'd2, 3'd3, 3'd4}) begin
              s_bits_q         <= s_bits_q >> s_effective_width;
              s_count_q        <= s_count_q - s_effective_width;
              s_bit_position_q <= s_bit_position_q + s_effective_width[2:0];
            end
            result_valid_o <= 1'b1;
            s_state_q      <= Idle;
          end
        end
        default: s_state_q <= Idle;
      endcase
    end
  end
endmodule
