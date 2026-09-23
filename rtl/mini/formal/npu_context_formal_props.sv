// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module npu_context_formal;
  (* anyseq *) (* gclk *)reg          clk_i;
  wire         rst_n_i;
  wire         f_past_valid;
  wire         clear;
  wire         start_valid;
  wire         start_ready;
  wire         start_context;
  wire         row_valid;
  wire         row_ready;
  wire         row_context;
  wire         drain_valid;
  wire         drain_context;
  wire         drain_data_valid;
  wire         drain_data_ready;
  wire  [31:0] drain_data;
  wire         drain_last;
  wire         busy;
  wire         fault_sticky;
  wire  [ 5:0] fault_sum;
  wire  [ 5:0] cycle;

  logic [ 1:0] s_context_owned_q;
  logic [ 6:0] s_drain_beats_q;
  logic [ 1:0] s_drain_completions_q;

  npu_context_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (!rst_n_i || clear) begin
      s_context_owned_q     <= '0;
      s_drain_beats_q       <= '0;
      s_drain_completions_q <= '0;
    end else begin
      if (start_valid && start_ready) begin
        assert (!s_context_owned_q[start_context]);
        s_context_owned_q[start_context] <= 1'b1;
      end
      if (row_valid) begin
        assert (row_ready == s_context_owned_q[row_context]);
      end
      if (drain_data_valid && drain_data_ready) begin
        if (drain_last) begin
          assert (s_drain_beats_q == 7'd63);
          s_drain_beats_q       <= '0;
          s_drain_completions_q <= s_drain_completions_q + 1'b1;
          if (s_drain_completions_q == 2'd0) begin
            s_context_owned_q[0] <= 1'b0;
          end else begin
            s_context_owned_q[1] <= 1'b0;
          end
        end else begin
          assert (s_drain_beats_q < 7'd63);
          s_drain_beats_q <= s_drain_beats_q + 1'b1;
        end
      end
      assert (s_drain_completions_q <= 2'd2);
      assert (!fault_sticky);
      assert (fault_sum == 6'd0);
    end

    if (f_past_valid && $past(rst_n_i) && !$past(clear)) begin
      if ($past(drain_data_valid && !drain_data_ready)) begin
        assert (drain_data_valid);
        assert (drain_data == $past(drain_data));
        assert (drain_last == $past(drain_last));
      end
    end

    if (f_past_valid && $past(clear)) begin
      assert (!busy);
      assert (!drain_data_valid);
    end

    cover (rst_n_i && (s_drain_completions_q == 2'd2));
    cover (rst_n_i && drain_data_valid && !drain_data_ready);
    cover (rst_n_i && clear && busy);
  end
endmodule
