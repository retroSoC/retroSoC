// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_primitives_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i, f_past_valid;
  wire [2:0] scenario_o, phase_o;
  wire request_valid_o, request_ready_o, request_accept_o;
  wire [3:0] request_class_o;
  wire kernel_busy_o, kernel_outstanding_o;
  wire [31:0] kernel_latency_o;
  wire result_valid_o, result_kernel_o, result_error_o;
  wire [ 5:0] result_error_code_o;
  wire [ 3:0] result_error_stage_o;
  wire [ 7:0] result_error_reason_o;
  wire [31:0] result_cycles_o;
  wire done_o, last_error_o;
  wire [ 5:0] last_error_code_o;
  wire [ 3:0] last_error_stage_o;
  wire [ 7:0] last_error_reason_o;
  wire [31:0] last_data_o;
  wire [6:0] input_count_o, output_count_o;
  wire memory_request_o;

  apu_primitives_formal_design u_design (.*);

  always @(posedge clk_i) begin
    assume (scenario_o <= 3'd6);
    if (rst_n_i) begin
      assert (input_count_o <= 7'd64);
      assert (output_count_o <= 7'd64);
      if (kernel_busy_o && request_valid_o && (request_class_o != 4'd5)) begin
        assert (!request_ready_o);
      end
      if (request_accept_o && (request_class_o != 4'd5)) begin
        assert (!kernel_busy_o);
      end
      if (result_valid_o && result_kernel_o && !result_error_o) begin
        assert (kernel_outstanding_o);
        assert (kernel_latency_o <= result_cycles_o);
      end
      if (done_o && (scenario_o == 3'd0)) begin
        assert (last_error_o);
        assert ({last_error_code_o, last_error_stage_o, last_error_reason_o} ==
                {6'd11, 4'd11, 8'd5});
      end
      if (done_o && (scenario_o == 3'd1)) begin
        assert (!last_error_o);
        assert (last_data_o == 32'hdead_beef);
      end
      if (done_o && (scenario_o == 3'd2)) begin
        assert (!last_error_o);
        assert (last_data_o == 32'h1357_9bdf);
      end
      if (done_o && (scenario_o == 3'd3)) begin
        assert (!last_error_o);
        assert (last_data_o == 32'h2468_ace0);
      end
      if (done_o && (scenario_o == 3'd4)) begin
        assert (last_error_o);
        assert ({last_error_code_o, last_error_stage_o, last_error_reason_o} ==
                {6'd11, 4'd11, 8'd5});
      end
      if (done_o && (scenario_o == 3'd5)) begin
        assert (!last_error_o);
        assert (output_count_o == 7'd1);
      end
      if ((scenario_o == 3'd6) && (phase_o == 3'd1)) begin
        assert (!memory_request_o);
      end
      if (done_o && (scenario_o == 3'd6)) begin
        assert (last_error_o);
        assert ({last_error_code_o, last_error_stage_o, last_error_reason_o} ==
                {6'd11, 4'd11, 8'd5});
        assert (last_data_o == 32'd0);
      end
    end

    cover (rst_n_i && done_o);
    cover (rst_n_i && ((scenario_o != 3'd2) ||
           (kernel_outstanding_o && request_valid_o && !request_ready_o &&
            (request_class_o == 4'd4))));
  end

  logic s_unused;
  assign s_unused = f_past_valid ^ phase_o[0];
endmodule
