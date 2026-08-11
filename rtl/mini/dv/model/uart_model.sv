// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`timescale 1ns / 1ps

module uart_model #(
    parameter int BAUD_RATE    = 115200,
    parameter bit LOOPBACK     = 1'b0,
    parameter bit FLOW_CONTROL = 1'b0
) (
    // verilog_format: off
    input  logic uart_tx_i,
    input  logic uart_rts_n_i,
    output logic uart_rx_o,
    output logic uart_cts_n_o
    // verilog_format: on
);

  localparam time BIT_PERIOD_NS = 1_000_000_000 / BAUD_RATE;

  logic [7:0] s_data;

  initial begin
    uart_rx_o    = 1'b1;
    uart_cts_n_o = FLOW_CONTROL ? 1'b0 : 1'bz;
  end

  always @(negedge uart_tx_i) begin
    receive(s_data);
    $write("%c", s_data);
    if (LOOPBACK) begin
      send(s_data);
    end
  end

  task automatic receive(output logic [7:0] value);
    begin
      value = '0;
      #(BIT_PERIOD_NS + (BIT_PERIOD_NS / 2));
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        value[bit_index] = uart_tx_i;
        #(BIT_PERIOD_NS);
      end
    end
  endtask

  task automatic send(input logic [7:0] value);
    begin
      if (FLOW_CONTROL) begin
        wait (uart_rts_n_i === 1'b0);
      end
      uart_rx_o = 1'b0;
      #(BIT_PERIOD_NS);
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        uart_rx_o = value[bit_index];
        #(BIT_PERIOD_NS);
      end
      uart_rx_o = 1'b1;
      #(BIT_PERIOD_NS);
    end
  endtask

  task automatic set_cts(input logic asserted);
    begin
      if (FLOW_CONTROL) begin
        uart_cts_n_o = ~asserted;
      end
    end
  endtask

endmodule
