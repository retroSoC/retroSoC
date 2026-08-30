// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module hp_lifecycle_controller (
    // verilog_format: off -- preserve the AON lifecycle contract columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        release_req_i,
    input  logic        hp_idle_i,
    input  logic        flush_busy_i,
    input  logic        cache_clean_i,
    input  logic [15:0] timeout_i,
    output logic        hp_release_o,
    output logic        block_new_o,
    output logic        flush_o,
    output logic        cache_request_o,
    output logic        draining_o,
    output logic        forced_fault_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Held,
    Running,
    CacheRequest,
    Quiesce,
    FlushRequest,
    FlushWait
  } state_e;

  state_e s_state_d, s_state_q;
  logic s_hp_release_d, s_hp_release_q;
  logic s_block_new_d, s_block_new_q;
  logic s_flush_d, s_flush_q;
  logic s_forced_fault_d, s_forced_fault_q;
  logic [15:0] s_timeout_cnt_d, s_timeout_cnt_q;
  logic [15:0] s_timeout_limit;

  assign s_timeout_limit = (timeout_i < 16'd2) ? 16'd2 : timeout_i;
  assign hp_release_o = s_hp_release_q;
  assign block_new_o = s_block_new_q;
  assign flush_o = s_flush_q;
  assign cache_request_o = s_state_q == CacheRequest;
  assign draining_o = (s_state_q == CacheRequest) || (s_state_q == Quiesce) ||
                      (s_state_q == FlushRequest) || (s_state_q == FlushWait);
  assign forced_fault_o = s_forced_fault_q;

  always_comb begin
    s_state_d        = s_state_q;
    s_hp_release_d   = s_hp_release_q;
    s_block_new_d    = s_block_new_q;
    s_flush_d        = s_flush_q;
    s_forced_fault_d = s_forced_fault_q;
    s_timeout_cnt_d  = s_timeout_cnt_q;
    unique case (s_state_q)
      Held: begin
        s_hp_release_d  = 1'b0;
        s_block_new_d   = 1'b0;
        s_flush_d       = 1'b0;
        s_timeout_cnt_d = '0;
        if (release_req_i) begin
          s_hp_release_d   = 1'b1;
          s_forced_fault_d = 1'b0;
          s_state_d        = Running;
        end
      end
      Running: begin
        s_hp_release_d  = 1'b1;
        s_block_new_d   = 1'b0;
        s_flush_d       = 1'b0;
        s_timeout_cnt_d = '0;
        if (!release_req_i) begin
          s_state_d = CacheRequest;
        end
      end
      CacheRequest: begin
        s_hp_release_d = 1'b1;
        s_block_new_d  = 1'b0;
        s_flush_d      = 1'b0;
        if (cache_clean_i) begin
          s_block_new_d   = 1'b1;
          s_timeout_cnt_d = '0;
          s_state_d       = Quiesce;
        end else if (s_timeout_cnt_q == s_timeout_limit - 1'b1) begin
          s_forced_fault_d = 1'b1;
          s_block_new_d    = 1'b1;
          s_timeout_cnt_d  = '0;
          s_state_d        = Quiesce;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      Quiesce: begin
        s_block_new_d = 1'b1;
        if (hp_idle_i) begin
          s_flush_d       = 1'b1;
          s_timeout_cnt_d = '0;
          s_state_d       = FlushRequest;
        end else if (s_timeout_cnt_q == s_timeout_limit - 1'b1) begin
          s_forced_fault_d = 1'b1;
          s_flush_d        = 1'b1;
          s_timeout_cnt_d  = '0;
          s_state_d        = FlushRequest;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      FlushRequest: begin
        s_block_new_d = 1'b1;
        s_flush_d     = 1'b1;
        if (flush_busy_i) begin
          s_flush_d       = 1'b0;
          s_timeout_cnt_d = '0;
          s_state_d       = FlushWait;
        end else if (s_timeout_cnt_q == s_timeout_limit - 1'b1) begin
          s_forced_fault_d = 1'b1;
          s_flush_d        = 1'b0;
          s_timeout_cnt_d  = '0;
          s_state_d        = FlushWait;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      FlushWait: begin
        s_block_new_d = 1'b1;
        s_flush_d     = 1'b0;
        if (!flush_busy_i || (s_timeout_cnt_q == s_timeout_limit - 1'b1)) begin
          if (flush_busy_i) s_forced_fault_d = 1'b1;
          s_hp_release_d  = 1'b0;
          s_block_new_d   = 1'b0;
          s_timeout_cnt_d = '0;
          s_state_d       = Held;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      default: s_state_d = Held;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q        <= Held;
      s_hp_release_q   <= 1'b0;
      s_block_new_q    <= 1'b0;
      s_flush_q        <= 1'b0;
      s_forced_fault_q <= 1'b0;
      s_timeout_cnt_q  <= '0;
    end else begin
      s_state_q        <= s_state_d;
      s_hp_release_q   <= s_hp_release_d;
      s_block_new_q    <= s_block_new_d;
      s_flush_q        <= s_flush_d;
      s_forced_fault_q <= s_forced_fault_d;
      s_timeout_cnt_q  <= s_timeout_cnt_d;
    end
  end
endmodule
