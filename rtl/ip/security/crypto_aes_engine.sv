// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_aes_engine #(
    parameter int FifoDepth = 8
) (
    // verilog_format: off -- command, stream, and observation ports are grouped.
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         zeroize_i,
    input  logic         abort_i,
    input  logic         key_commit_i,
    input  logic [  1:0] key_size_i,
    input  logic [255:0] key_i,
    output logic         key_valid_o,
    output logic         key_busy_o,
    input  logic         start_i,
    input  logic [  1:0] mode_i,
    input  logic         decrypt_i,
    input  logic [ 31:0] length_i,
    input  logic [127:0] iv_i,
    input  logic         input_valid_i,
    output logic         input_ready_o,
    input  logic [ 31:0] input_data_i,
    input  logic [  3:0] input_keep_i,
    input  logic         input_last_i,
    output logic         output_valid_o,
    input  logic         output_ready_i,
    output logic [ 31:0] output_data_o,
    output logic [  3:0] output_keep_o,
    output logic         output_last_o,
    output logic         busy_o,
    output logic         done_o,
    output logic         error_o,
    output logic [ 31:0] bytes_in_o,
    output logic [ 31:0] bytes_out_o,
    output logic [ 31:0] cycles_o,
    output logic [127:0] chain_o
    // verilog_format: on
);
  import crypto_pkg::*;

  localparam int FifoCountWidth = $clog2(FifoDepth) + 1;

  logic [              36:0] s_input_fifo_data;
  logic [              36:0] s_output_fifo_data;
  logic [              36:0] s_output_fifo_write_data;
  logic [FifoCountWidth-1:0] s_input_fifo_count;
  logic [FifoCountWidth-1:0] s_output_fifo_count;
  logic                      s_input_fifo_full;
  logic                      s_input_fifo_empty;
  logic                      s_output_fifo_full;
  logic                      s_output_fifo_empty;
  logic                      s_input_fifo_push;
  logic                      s_input_fifo_pop;
  logic                      s_output_fifo_push;
  logic                      s_output_fifo_pop;
  logic                      s_fifo_flush;

  logic [               1:0] s_mode_q;
  logic                      s_decrypt_q;
  logic [              31:0] s_len_q;
  logic [             127:0] s_chain_q;
  logic [             127:0] s_assembly_q;
  logic [               4:0] s_assembly_bytes_q;
  logic [               4:0] s_block_bytes_q;
  logic                      s_block_ready_q;
  logic                      s_block_last_q;
  logic                      s_input_complete_q;
  logic [             127:0] s_active_input_q;
  logic [               4:0] s_active_bytes_q;
  logic                      s_active_last_q;
  logic [             127:0] s_result_block;
  logic [             127:0] s_serialize_block_q;
  logic [               2:0] s_serialize_words_q;
  logic [               2:0] s_serialize_index_q;
  logic [               2:0] s_serialize_last_bytes_q;
  logic                      s_serialize_last_q;
  logic                      s_serialize_q;
  logic [               2:0] s_input_bytes;
  logic                      s_input_keep_valid;
  logic [              31:0] s_next_bytes_in;
  logic [             127:0] s_cnt_next;
  logic [              31:0] s_output_segment;

  logic                      s_core_key_commit;
  logic                      s_core_start;
  logic                      s_core_busy;
  logic                      s_core_done;
  logic                      s_core_decrypt;
  logic [             127:0] s_core_input;
  logic [             127:0] s_core_output;

  function automatic logic [2:0] count_keep(input logic [3:0] keep);
    case (keep)
      4'b0001: count_keep = 3'd1;
      4'b0011: count_keep = 3'd2;
      4'b0111: count_keep = 3'd3;
      4'b1111: count_keep = 3'd4;
      default: count_keep = 3'd0;
    endcase
  endfunction

  function automatic logic [31:0] reverse_word_bytes(input logic [31:0] value);
    reverse_word_bytes = {value[7:0], value[15:8], value[23:16], value[31:24]};
  endfunction

  crypto_aes_core u_crypto_aes_core (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .zeroize_i   (zeroize_i),
      .key_commit_i(s_core_key_commit),
      .key_size_i  (key_size_i),
      .key_i       (key_i),
      .key_valid_o (key_valid_o),
      .start_i     (s_core_start),
      .decrypt_i   (s_core_decrypt),
      .block_i     (s_core_input),
      .busy_o      (s_core_busy),
      .done_o      (s_core_done),
      .block_o     (s_core_output)
  );

  fifo #(
      .DATA_WIDTH  (37),
      .BUFFER_DEPTH(FifoDepth)
  ) u_input_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i (s_input_fifo_push),
      .full_o (s_input_fifo_full),
      .dat_i  ({input_last_i, input_keep_i, input_data_i}),
      .pop_i  (s_input_fifo_pop),
      .empty_o(s_input_fifo_empty),
      .dat_o  (s_input_fifo_data),
      .cnt_o  (s_input_fifo_count)
  );

  fifo #(
      .DATA_WIDTH  (37),
      .BUFFER_DEPTH(FifoDepth)
  ) u_output_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i (s_output_fifo_push),
      .full_o (s_output_fifo_full),
      .dat_i  (s_output_fifo_write_data),
      .pop_i  (s_output_fifo_pop),
      .empty_o(s_output_fifo_empty),
      .dat_o  (s_output_fifo_data),
      .cnt_o  (s_output_fifo_count)
  );

  always_comb begin
    s_input_bytes = count_keep(input_keep_i);
    s_input_keep_valid = s_input_bytes != 3'd0;
    s_next_bytes_in = bytes_in_o + 32'(s_input_bytes);
    input_ready_o = busy_o && !s_input_complete_q && !s_input_fifo_full &&
                    (s_input_fifo_count < FifoCountWidth'(FifoDepth));
    output_valid_o = !s_output_fifo_empty && (s_output_fifo_count != '0);
    s_input_fifo_push = input_valid_i && input_ready_o;
    s_input_fifo_pop   = busy_o && !s_input_fifo_empty && !s_block_ready_q &&
                         (s_assembly_bytes_q <= 5'd12);
    s_output_fifo_pop = output_valid_o && output_ready_i;
    s_fifo_flush = zeroize_i || abort_i || (start_i && !busy_o);

    output_data_o = s_output_fifo_data[31:0];
    output_keep_o = s_output_fifo_data[35:32];
    output_last_o = s_output_fifo_data[36];

    s_core_key_commit = key_commit_i && !busy_o;
    s_core_start = busy_o && s_block_ready_q && !s_core_busy && !s_core_done && !s_serialize_q;
    s_core_decrypt = (s_mode_q == AES_MODE_CTR) ? 1'b0 : s_decrypt_q;
    unique case (s_mode_q)
      AES_MODE_CBC: s_core_input = s_decrypt_q ? s_assembly_q : (s_assembly_q ^ s_chain_q);
      AES_MODE_CTR: s_core_input = s_chain_q;
      default:      s_core_input = s_assembly_q;
    endcase

    unique case (s_mode_q)
      AES_MODE_CBC: s_result_block = s_decrypt_q ? (s_core_output ^ s_chain_q) : s_core_output;
      AES_MODE_CTR: s_result_block = s_active_input_q ^ s_core_output;
      default:      s_result_block = s_core_output;
    endcase

    s_cnt_next                      = s_chain_q + 1'b1;
    s_output_segment                = s_serialize_block_q[127-s_serialize_index_q*32-:32];
    s_output_fifo_write_data[31:0]  = reverse_word_bytes(s_output_segment);
    s_output_fifo_write_data[35:32] = 4'hf;
    if ((s_serialize_index_q == (s_serialize_words_q - 1'b1)) &&
        (s_serialize_last_bytes_q != 3'd4)) begin
      s_output_fifo_write_data[35:32] = 4'((5'd1 << s_serialize_last_bytes_q) - 1'b1);
    end
    s_output_fifo_write_data[36] = s_serialize_last_q &&
                                    (s_serialize_index_q == (s_serialize_words_q - 1'b1));
    s_output_fifo_push = s_serialize_q && !s_output_fifo_full;
  end

  assign chain_o    = s_chain_q;
  assign key_busy_o = s_core_busy && !busy_o;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_mode_q                 <= AES_MODE_ECB;
      s_decrypt_q              <= 1'b0;
      s_len_q                  <= '0;
      s_chain_q                <= '0;
      s_assembly_q             <= '0;
      s_assembly_bytes_q       <= '0;
      s_block_bytes_q          <= '0;
      s_block_ready_q          <= 1'b0;
      s_block_last_q           <= 1'b0;
      s_input_complete_q       <= 1'b0;
      s_active_input_q         <= '0;
      s_active_bytes_q         <= '0;
      s_active_last_q          <= 1'b0;
      s_serialize_block_q      <= '0;
      s_serialize_words_q      <= '0;
      s_serialize_index_q      <= '0;
      s_serialize_last_bytes_q <= '0;
      s_serialize_last_q       <= 1'b0;
      s_serialize_q            <= 1'b0;
      busy_o                   <= 1'b0;
      done_o                   <= 1'b0;
      error_o                  <= 1'b0;
      bytes_in_o               <= '0;
      bytes_out_o              <= '0;
      cycles_o                 <= '0;
    end else begin
      done_o <= 1'b0;
      if (busy_o) begin
        cycles_o <= cycles_o + 1'b1;
      end
      if (zeroize_i || abort_i) begin
        s_chain_q           <= '0;
        s_assembly_q        <= '0;
        s_active_input_q    <= '0;
        s_serialize_block_q <= '0;
        s_block_ready_q     <= 1'b0;
        s_serialize_q       <= 1'b0;
        s_input_complete_q  <= 1'b0;
        busy_o              <= 1'b0;
        error_o             <= 1'b0;
        bytes_in_o          <= '0;
        bytes_out_o         <= '0;
      end else begin
        if (start_i && !busy_o) begin
          error_o <= 1'b0;
          if (!key_valid_o || (length_i == 0) || (mode_i == 2'd3) ||
              ((mode_i != AES_MODE_CTR) && (length_i[3:0] != 4'd0))) begin
            error_o <= 1'b1;
            done_o  <= 1'b1;
          end else begin
            s_mode_q                 <= mode_i;
            s_decrypt_q              <= decrypt_i;
            s_len_q                  <= length_i;
            s_chain_q                <= iv_i;
            s_assembly_q             <= '0;
            s_assembly_bytes_q       <= '0;
            s_block_ready_q          <= 1'b0;
            s_input_complete_q       <= 1'b0;
            s_serialize_q            <= 1'b0;
            s_serialize_index_q      <= '0;
            s_serialize_last_bytes_q <= '0;
            busy_o                   <= 1'b1;
            bytes_in_o               <= '0;
            bytes_out_o              <= '0;
            cycles_o                 <= '0;
          end
        end

        if (s_input_fifo_push) begin
          if (!s_input_keep_valid || (s_next_bytes_in > s_len_q) ||
              (input_last_i != (s_next_bytes_in == s_len_q))) begin
            error_o <= 1'b1;
            busy_o  <= 1'b0;
          end else begin
            bytes_in_o <= s_next_bytes_in;
            if (input_last_i) begin
              s_input_complete_q <= 1'b1;
            end
          end
        end

        if (s_input_fifo_pop) begin
          for (int unsigned lane = 0; lane < 4; lane++) begin
            if (s_input_fifo_data[32+lane]) begin
              s_assembly_q[127-(7'(s_assembly_bytes_q)+7'(lane))*8-:8] <=
                  s_input_fifo_data[lane*8+:8];
            end
          end
          s_assembly_bytes_q <= s_assembly_bytes_q + 5'(count_keep(s_input_fifo_data[35:32]));
          if (((s_assembly_bytes_q + 5'(count_keep(
                  s_input_fifo_data[35:32]
              ))) == 5'd16) || s_input_fifo_data[36]) begin
            s_block_bytes_q <= s_assembly_bytes_q + 5'(count_keep(s_input_fifo_data[35:32]));
            s_block_ready_q <= 1'b1;
            s_block_last_q  <= s_input_fifo_data[36];
          end
        end

        if (s_core_start) begin
          s_active_input_q   <= s_assembly_q;
          s_active_bytes_q   <= s_block_bytes_q;
          s_active_last_q    <= s_block_last_q;
          s_assembly_q       <= '0;
          s_assembly_bytes_q <= '0;
          s_block_ready_q    <= 1'b0;
        end

        if (s_core_done) begin
          s_serialize_block_q <= s_result_block;
          s_serialize_words_q <= 3'((s_active_bytes_q + 5'd3) >> 2);
          s_serialize_index_q <= '0;
          if (s_active_bytes_q[1:0] == 2'd0) begin
            s_serialize_last_bytes_q <= 3'd4;
          end else begin
            s_serialize_last_bytes_q <= {1'b0, s_active_bytes_q[1:0]};
          end
          s_serialize_last_q <= s_active_last_q;
          s_serialize_q      <= 1'b1;
          if (s_mode_q == AES_MODE_CBC) begin
            s_chain_q <= s_decrypt_q ? s_active_input_q : s_core_output;
          end else if (s_mode_q == AES_MODE_CTR) begin
            s_chain_q <= s_cnt_next;
          end
        end

        if (s_output_fifo_push) begin
          if (s_serialize_index_q == (s_serialize_words_q - 1'b1)) begin
            s_serialize_q <= 1'b0;
          end else begin
            s_serialize_index_q <= s_serialize_index_q + 1'b1;
          end
        end

        if (s_output_fifo_pop) begin
          bytes_out_o <= bytes_out_o + 32'(count_keep(s_output_fifo_data[35:32]));
          if (s_output_fifo_data[36]) begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
          end
        end
      end
    end
  end
endmodule
