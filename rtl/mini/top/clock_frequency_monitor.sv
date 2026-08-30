// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module clock_frequency_monitor #(
    parameter int unsigned CounterWidth = 16,
    parameter int unsigned WindowCycles = 256
) (
    // verilog_format: off -- preserve the monitored/reference domain columns
    input  logic                    ref_clk_i,
    input  logic                    ref_rst_n_i,
    input  logic                    monitored_clk_i,
    input  logic                    monitored_rst_n_i,
    input  logic                    clear_fault_i,
    output logic                    alive_o,
    output logic                    fault_o,
    output logic [CounterWidth-1:0] edge_delta_o
    // verilog_format: on
);
  localparam int unsigned WindowWidth = $clog2(WindowCycles);

  logic [CounterWidth-1:0] s_monitored_count_q;
  logic [CounterWidth-1:0] s_monitored_gray;
  logic [CounterWidth-1:0] s_monitored_gray_ref;
  logic [CounterWidth-1:0] s_monitored_count_ref;
  logic [CounterWidth-1:0] s_last_count_q;
  logic [ WindowWidth-1:0] s_window_count_q;
  logic                    s_window_valid_q;

  function automatic logic [CounterWidth-1:0] gray_to_bin(input logic [CounterWidth-1:0] value_i);
    logic [CounterWidth-1:0] result;
    result[CounterWidth-1] = value_i[CounterWidth-1];
    for (int bit_index = CounterWidth - 2; bit_index >= 0; bit_index--) begin
      result[bit_index] = result[bit_index+1] ^ value_i[bit_index];
    end
    return result;
  endfunction

  assign s_monitored_gray      = s_monitored_count_q ^ (s_monitored_count_q >> 1);
  assign s_monitored_count_ref = gray_to_bin(s_monitored_gray_ref);

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(CounterWidth)
  ) u_count_sync (
      .clk_i  (ref_clk_i),
      .rst_n_i(ref_rst_n_i),
      .dat_i  (s_monitored_gray),
      .dat_o  (s_monitored_gray_ref)
  );

  always_ff @(posedge monitored_clk_i or negedge monitored_rst_n_i) begin
    if (!monitored_rst_n_i) begin
      s_monitored_count_q <= '0;
    end else begin
      s_monitored_count_q <= s_monitored_count_q + 1'b1;
    end
  end

  always_ff @(posedge ref_clk_i or negedge ref_rst_n_i) begin
    if (!ref_rst_n_i) begin
      s_last_count_q   <= '0;
      s_window_count_q <= '0;
      s_window_valid_q <= 1'b0;
      edge_delta_o     <= '0;
      alive_o          <= 1'b0;
      fault_o          <= 1'b0;
    end else begin
      if (clear_fault_i) fault_o <= 1'b0;
      if (s_window_count_q == WindowWidth'(WindowCycles - 1)) begin
        edge_delta_o <= s_monitored_count_ref - s_last_count_q;
        alive_o      <= s_monitored_count_ref != s_last_count_q;
        if (!clear_fault_i && s_window_valid_q && (s_monitored_count_ref == s_last_count_q)) begin
          fault_o <= 1'b1;
        end
        s_last_count_q   <= s_monitored_count_ref;
        s_window_count_q <= '0;
        s_window_valid_q <= 1'b1;
      end else begin
        s_window_count_q <= s_window_count_q + 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((CounterWidth < 4) || (WindowCycles < 4) ||
        ((WindowCycles & (WindowCycles - 1)) != 0)) begin
      $fatal(1, "clock_frequency_monitor: invalid counter or window geometry");
    end
  end
`endif
endmodule
