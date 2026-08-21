// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_sha2_engine #(
    parameter int FifoDepth = 16
) (
    // verilog_format: off -- command, stream, and digest ports are grouped.
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         zeroize_i,
    input  logic         abort_i,
    input  logic         start_i,
    input  logic         sha256_i,
    input  logic [ 63:0] length_i,
    input  logic         input_valid_i,
    output logic         input_ready_o,
    input  logic [ 31:0] input_data_i,
    input  logic [  3:0] input_keep_i,
    input  logic         input_last_i,
    output logic         busy_o,
    output logic         done_o,
    output logic         error_o,
    output logic         digest_valid_o,
    output logic [255:0] digest_o,
    output logic [ 63:0] bytes_in_o,
    output logic [ 31:0] cycles_o
    // verilog_format: on
);
  import crypto_pkg::*;

  localparam int FifoCountWidth = $clog2(FifoDepth) + 1;
  localparam logic [1:0] FollowNone = 2'd0;
  localparam logic [1:0] FollowEmptyPad = 2'd1;
  localparam logic [1:0] FollowSecondPad = 2'd2;

  logic [              36:0] s_input_fifo_data;
  logic [FifoCountWidth-1:0] s_input_fifo_count;
  logic                      s_input_fifo_full;
  logic                      s_input_fifo_empty;
  logic                      s_input_fifo_push;
  logic                      s_input_fifo_pop;
  logic                      s_fifo_flush;

  logic                      s_sha256_q;
  logic [              63:0] s_len_q;
  logic [             255:0] s_hash_state_q;
  logic [             511:0] s_block_q;
  logic [               6:0] s_block_bytes_q;
  logic                      s_block_ready_q;
  logic                      s_block_final_q;
  logic [               1:0] s_block_follow_q;
  logic [               1:0] s_active_follow_q;
  logic                      s_active_final_q;
  logic                      s_finalize_pending_q;
  logic [               2:0] s_input_bytes;
  logic                      s_input_keep_valid;
  logic [              63:0] s_next_bytes_in;
  logic [              63:0] s_bit_len;
  logic [             511:0] s_padded_block;
  logic                      s_padding_needs_second;

  logic                      s_core_start;
  logic                      s_core_busy;
  logic                      s_core_done;
  logic [             255:0] s_core_state;

  function automatic logic [2:0] count_keep(input logic [3:0] keep);
    case (keep)
      4'b0001: count_keep = 3'd1;
      4'b0011: count_keep = 3'd2;
      4'b0111: count_keep = 3'd3;
      4'b1111: count_keep = 3'd4;
      default: count_keep = 3'd0;
    endcase
  endfunction

  crypto_sha2_core u_crypto_sha2_core (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .zeroize_i(zeroize_i),
      .start_i  (s_core_start),
      .state_i  (s_hash_state_q),
      .block_i  (s_block_q),
      .busy_o   (s_core_busy),
      .done_o   (s_core_done),
      .state_o  (s_core_state)
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

  always_comb begin
    s_input_bytes = count_keep(input_keep_i);
    s_input_keep_valid = s_input_bytes != 3'd0;
    s_next_bytes_in = bytes_in_o + 64'(s_input_bytes);
    s_bit_len = s_len_q << 3;
    input_ready_o = busy_o && (bytes_in_o < s_len_q) && !s_input_fifo_full &&
                    (s_input_fifo_count < FifoCountWidth'(FifoDepth));
    s_input_fifo_push = input_valid_i && input_ready_o;
    s_input_fifo_pop   = busy_o && !s_input_fifo_empty && !s_block_ready_q &&
                         !s_finalize_pending_q && (s_block_bytes_q <= 7'd60);
    s_fifo_flush = zeroize_i || abort_i || (start_i && !busy_o);
    s_core_start = busy_o && s_block_ready_q && !s_core_busy && !s_core_done;

    s_padded_block = s_block_q;
    s_padding_needs_second = 1'b0;
    if (s_finalize_pending_q) begin
      for (int unsigned index = 0; index < 64; index++) begin
        if (index >= s_block_bytes_q) begin
          s_padded_block[511-index*8-:8] = 8'h00;
        end
      end
      if (s_block_bytes_q < 7'd64) begin
        s_padded_block[511-s_block_bytes_q*8-:8] = 8'h80;
      end
      s_padding_needs_second = s_block_bytes_q > 7'd55;
      if (!s_padding_needs_second) begin
        for (int unsigned index = 0; index < 8; index++) begin
          s_padded_block[63-index*8-:8] = s_bit_len[63-index*8-:8];
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_sha256_q           <= SHA2_256;
      s_len_q              <= '0;
      s_hash_state_q       <= '0;
      s_block_q            <= '0;
      s_block_bytes_q      <= '0;
      s_block_ready_q      <= 1'b0;
      s_block_final_q      <= 1'b0;
      s_block_follow_q     <= FollowNone;
      s_active_follow_q    <= FollowNone;
      s_active_final_q     <= 1'b0;
      s_finalize_pending_q <= 1'b0;
      busy_o               <= 1'b0;
      done_o               <= 1'b0;
      error_o              <= 1'b0;
      digest_valid_o       <= 1'b0;
      digest_o             <= '0;
      bytes_in_o           <= '0;
      cycles_o             <= '0;
    end else begin
      done_o <= 1'b0;
      if (busy_o) begin
        cycles_o <= cycles_o + 1'b1;
      end
      if (zeroize_i || abort_i) begin
        s_hash_state_q       <= '0;
        s_block_q            <= '0;
        s_block_bytes_q      <= '0;
        s_block_ready_q      <= 1'b0;
        s_finalize_pending_q <= 1'b0;
        busy_o               <= 1'b0;
        error_o              <= 1'b0;
        digest_valid_o       <= 1'b0;
        digest_o             <= '0;
        bytes_in_o           <= '0;
      end else begin
        if (start_i && !busy_o) begin
          s_sha256_q <= (sha256_i == SHA2_256) ? SHA2_256 : SHA2_224;
          s_len_q    <= length_i;
          if (sha256_i) begin
            s_hash_state_q <= 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
          end else begin
            s_hash_state_q <= 256'hc1059ed8367cd5073070dd17f70e5939ffc00b316858151164f98fa7befa4fa4;
          end
          s_block_q            <= '0;
          s_block_bytes_q      <= '0;
          s_block_ready_q      <= 1'b0;
          s_block_follow_q     <= FollowNone;
          s_finalize_pending_q <= length_i == 64'd0;
          busy_o               <= 1'b1;
          error_o              <= 1'b0;
          digest_valid_o       <= 1'b0;
          bytes_in_o           <= '0;
          cycles_o             <= '0;
        end

        if (s_input_fifo_push) begin
          if (!s_input_keep_valid || (s_next_bytes_in > s_len_q) ||
              (input_last_i != (s_next_bytes_in == s_len_q))) begin
            error_o <= 1'b1;
            busy_o  <= 1'b0;
          end else begin
            bytes_in_o <= s_next_bytes_in;
          end
        end

        if (s_input_fifo_pop) begin
          for (int unsigned lane = 0; lane < 4; lane++) begin
            if (s_input_fifo_data[32+lane]) begin
              s_block_q[511-(9'(s_block_bytes_q)+9'(lane))*8-:8] <= s_input_fifo_data[lane*8+:8];
            end
          end
          s_block_bytes_q <= s_block_bytes_q + 7'(count_keep(s_input_fifo_data[35:32]));
          if ((s_block_bytes_q + 7'(count_keep(s_input_fifo_data[35:32]))) == 7'd64) begin
            s_block_ready_q  <= 1'b1;
            s_block_final_q  <= 1'b0;
            s_block_follow_q <= s_input_fifo_data[36] ? FollowEmptyPad : FollowNone;
          end else if (s_input_fifo_data[36]) begin
            s_finalize_pending_q <= 1'b1;
          end
        end

        if (s_finalize_pending_q && !s_block_ready_q) begin
          s_block_q            <= s_padded_block;
          s_block_ready_q      <= 1'b1;
          s_block_final_q      <= !s_padding_needs_second;
          s_block_follow_q     <= s_padding_needs_second ? FollowSecondPad : FollowNone;
          s_finalize_pending_q <= 1'b0;
        end

        if (s_core_start) begin
          s_active_follow_q <= s_block_follow_q;
          s_active_final_q  <= s_block_final_q;
          s_block_q         <= '0;
          s_block_bytes_q   <= '0;
          s_block_ready_q   <= 1'b0;
          s_block_follow_q  <= FollowNone;
          s_block_final_q   <= 1'b0;
        end

        if (s_core_done) begin
          s_hash_state_q <= s_core_state;
          if (s_active_follow_q == FollowEmptyPad) begin
            s_block_q       <= {8'h80, 440'd0, s_bit_len};
            s_block_ready_q <= 1'b1;
            s_block_final_q <= 1'b1;
          end else if (s_active_follow_q == FollowSecondPad) begin
            s_block_q       <= {448'd0, s_bit_len};
            s_block_ready_q <= 1'b1;
            s_block_final_q <= 1'b1;
          end else if (s_active_final_q) begin
            digest_o       <= s_sha256_q ? s_core_state : {s_core_state[255:32], 32'd0};
            digest_valid_o <= 1'b1;
            busy_o         <= 1'b0;
            done_o         <= 1'b1;
          end
        end
      end
    end
  end
endmodule
