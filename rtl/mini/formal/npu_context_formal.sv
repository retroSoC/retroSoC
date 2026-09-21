// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module npu_context_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        clear,
    output logic        start_valid,
    output logic        start_ready,
    output logic        start_context,
    output logic        row_valid,
    output logic        row_ready,
    output logic        row_context,
    output logic        drain_valid,
    output logic        drain_context,
    output logic        drain_data_valid,
    output logic        drain_data_ready,
    output logic [31:0] drain_data,
    output logic        drain_last,
    output logic        busy,
    output logic        fault_sticky,
    output logic [ 5:0] fault_sum,
    output logic [ 5:0] cycle
);
  (* anyconst *)logic [                      3:0]                                  f_stall_mask;
  (* anyconst *)logic                                                              f_clear_enable;
  (* anyconst *)logic [                      4:0]                                  f_clear_cycle;

  logic [npu_pkg::ChannelLanes-1:0][                     31:0]       s_bias;
  logic [npu_pkg::SpatialLanes-1:0][npu_pkg::ChannelLanes-1:0][16:0] s_products;

  assign rst_n_i          = cycle >= 6'd2;
  assign clear            = rst_n_i && f_clear_enable && (cycle == {1'b0, f_clear_cycle});
  assign start_valid      = rst_n_i && ((cycle == 6'd6) || (cycle == 6'd7));
  assign row_valid        = rst_n_i && ((cycle == 6'd9) || (cycle == 6'd10));
  assign row_context      = cycle == 6'd10;
  assign drain_valid      = rst_n_i && ((cycle == 6'd12) || (cycle == 6'd13));
  assign drain_context    = cycle == 6'd13;
  assign drain_data_ready = !f_stall_mask[cycle[1:0]];
  assign s_bias           = '0;
  assign s_products       = 'd1;

  npu_accumulator u_dut (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .clear_i           (clear),
      .start_valid_i     (start_valid),
      .start_ready_o     (start_ready),
      .start_bias_i      (s_bias),
      .start_context_o   (start_context),
      .row_valid_i       (row_valid),
      .row_ready_o       (row_ready),
      .row_context_i     (row_context),
      .row_products_i    (s_products),
      .drain_valid_i     (drain_valid),
      .drain_context_i   (drain_context),
      .drain_data_valid_o(drain_data_valid),
      .drain_data_ready_i(drain_data_ready),
      .drain_data_o      (drain_data),
      .drain_last_o      (drain_last),
      .busy_o            (busy),
      .fault_sticky_o    (fault_sticky),
      .fault_sum_o       (fault_sum)
  );

  always_ff @(posedge clk_i) begin
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      cycle <= cycle + 1'b1;
    end else if (cycle != 6'h3f) begin
      cycle <= cycle + 1'b1;
    end
  end

  initial begin
    cycle        = '0;
    f_past_valid = 1'b0;
  end
endmodule
