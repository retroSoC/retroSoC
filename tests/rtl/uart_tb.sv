`timescale 1ns / 1ps

`include "apb4_uart_define.svh"

module uart_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic dma_tx_stall;
  logic dma_rx_stall;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  uart_if uart ();

  always #5 clk_i = ~clk_i;

  apb4_uart u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(dma_tx_stall),
      .dma_rx_stall_o(dma_rx_stall),
      .apb4          (apb4),
      .uart          (uart)
  );

  task automatic apb4_write(input logic [31:0] address, input logic [31:0] data,
                            input logic [3:0] strobe, input logic expected_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = strobe;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr !== expected_error) begin
        $fatal(1, "write %h error=%b expected=%b", address, apb4.pslverr, expected_error);
      end
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic apb4_read(input logic [31:0] address, input logic expected_error,
                           output logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr !== expected_error) begin
        $fatal(1, "read %h error=%b expected=%b", address, apb4.pslverr, expected_error);
      end
      data         = apb4.prdata;
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic write_ok(input logic [31:0] address, input logic [31:0] data);
    begin
      apb4_write(address, data, 4'hF, 1'b0);
    end
  endtask

  task automatic configure_uart_flow(input logic [4:0] line_control, input logic [1:0] flow_control,
                                     input logic [6:0] rts_assert_level,
                                     input logic [6:0] rts_deassert_level,
                                     input logic [3:0] control);
    begin
      write_ok(`APB4_UART_CTRL, 0);
      repeat (4) @(posedge clk_i);
      write_ok(`APB4_UART_FIFO_CTRL, 3);
      write_ok(`APB4_UART_BAUD_INT, 16);
      write_ok(`APB4_UART_BAUD_FRAC, 0);
      write_ok(`APB4_UART_LINE_CTRL, line_control);
      write_ok(`APB4_UART_RTS_WATERMARK, {9'd0, rts_deassert_level, 9'd0, rts_assert_level});
      write_ok(`APB4_UART_FLOW_CTRL, flow_control);
      write_ok(`APB4_UART_CTRL, control);
    end
  endtask

  task automatic configure_uart(input logic [4:0] line_control, input logic [3:0] control);
    begin
      configure_uart_flow(line_control, 2'd0, 7'd32, 7'd48, control);
    end
  endtask

  task automatic send_external_8n1(input logic [7:0] data, input logic bad_stop);
    integer bit_index;
    begin
      uart.rx_i = 1'b0;
      repeat (16) @(posedge clk_i);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        uart.rx_i = data[bit_index];
        repeat (16) @(posedge clk_i);
      end
      uart.rx_i = !bad_stop;
      repeat (16) @(posedge clk_i);
      uart.rx_i = 1'b1;
      repeat (24) @(posedge clk_i);
    end
  endtask

  initial begin
    logic   [31:0] value;
    integer        index;

    apb4.psel    = 1'b0;
    apb4.paddr   = '0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    uart.rx_i    = 1'b1;
    uart.cts_n_i = 1'b1;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (4) @(posedge clk_i);

    if (uart.rts_n_o !== 1'b1) $fatal(1, "UART RTS_n was not released after reset");
    apb4_read(`APB4_UART_IP_VERSION, 1'b0, value);
    if (value != 32'h0003_0000) $fatal(1, "UART IP version mismatch");
    apb4_read(`APB4_UART_CAPABILITY, 1'b0, value);
    if (value != 32'h03FF_4040) $fatal(1, "UART capability mismatch");
    apb4_read(32'h0000_0002, 1'b1, value);
    apb4_read(`APB4_UART_RXDATA, 1'b1, value);

    apb4_write(`APB4_UART_RTS_WATERMARK, 32'h0002_0002, 4'hF, 1'b1);
    apb4_read(`APB4_UART_ERROR_STATUS, 1'b0, value);
    if (!value[`UART_ERROR_CONFIG]) $fatal(1, "UART invalid RTS watermark was not reported");
    write_ok(`APB4_UART_ERROR_STATUS, 7'h7F);

    configure_uart_flow(5'd3, 2'b01, 7'd32, 7'd48, 4'b0111);
    write_ok(`APB4_UART_TXDATA, 8'hA5);
    repeat (220) @(posedge clk_i);
    apb4_read(`APB4_UART_RXDATA, 1'b0, value);
    if (value[11:0] != 12'h0A5) $fatal(1, "UART 8N1 loopback mismatch: %h", value);

    configure_uart(5'd3, 4'b0001);
    write_ok(`APB4_UART_TXDATA, 8'h5A);
    repeat (24) @(posedge clk_i);
    apb4_read(`APB4_UART_STATUS, 1'b0, value);
    if (!value[`UART_STATUS_TX_BUSY]) $fatal(1, "UART TX did not start before disable");
    write_ok(`APB4_UART_CTRL, 0);
    repeat (180) @(posedge clk_i);
    apb4_read(`APB4_UART_STATUS, 1'b0, value);
    if (value[`UART_STATUS_TX_BUSY] || !value[`UART_STATUS_TX_EMPTY]) begin
      $fatal(1, "UART TX did not finish its active frame after disable: %h", value);
    end

    write_ok(`APB4_UART_INTR_ENABLE, 7'h7F);
    write_ok(`APB4_UART_INTR_TEST, 7'h20);
    apb4_read(`APB4_UART_INTR_STATUS, 1'b0, value);
    if (!value[`UART_INTR_BREAK] || !uart.irq_o) $fatal(1, "UART interrupt test failed");
    write_ok(`APB4_UART_INTR_STATE, 7'h7F);

    configure_uart_flow(5'd3, 2'b01, 7'd32, 7'd48, 4'b0001);
    write_ok(`APB4_UART_INTR_ENABLE, 7'h40);
    write_ok(`APB4_UART_TXDATA, 8'hC3);
    write_ok(`APB4_UART_TXDATA, 8'h5C);
    repeat (32) @(posedge clk_i);
    apb4_read(`APB4_UART_STATUS, 1'b0, value);
    if (!value[`UART_STATUS_TX_FLOW_BLOCKED] || value[`UART_STATUS_TX_BUSY] ||
        value[`UART_STATUS_CTS_ASSERTED]) begin
      $fatal(1, "UART CTS did not block a new frame: %h", value);
    end
    apb4_read(`APB4_UART_FIFO_LEVEL, 1'b0, value);
    if (value[6:0] != 7'd2) $fatal(1, "UART CTS-blocked FIFO count mismatch: %h", value);

    uart.cts_n_i = 1'b0;
    repeat (32) @(posedge clk_i);
    apb4_read(`APB4_UART_STATUS, 1'b0, value);
    if (!value[`UART_STATUS_CTS_ASSERTED] || !value[`UART_STATUS_TX_BUSY]) begin
      $fatal(1, "UART did not start after CTS assertion: %h", value);
    end
    uart.cts_n_i = 1'b1;
    repeat (200) @(posedge clk_i);
    apb4_read(`APB4_UART_STATUS, 1'b0, value);
    if (!value[`UART_STATUS_TX_FLOW_BLOCKED] || value[`UART_STATUS_TX_BUSY]) begin
      $fatal(1, "UART CTS did not stop at the frame boundary: %h", value);
    end
    apb4_read(`APB4_UART_FIFO_LEVEL, 1'b0, value);
    if (value[6:0] != 7'd1) $fatal(1, "UART frame-boundary FIFO count mismatch: %h", value);
    apb4_read(`APB4_UART_INTR_STATUS, 1'b0, value);
    if (!value[`UART_INTR_CTS_CHANGE] || !uart.irq_o) begin
      $fatal(1, "UART CTS change interrupt failed: %h", value);
    end
    write_ok(`APB4_UART_INTR_STATE, 7'h7F);
    uart.cts_n_i = 1'b0;
    repeat (220) @(posedge clk_i);
    apb4_read(`APB4_UART_FIFO_LEVEL, 1'b0, value);
    if (value[6:0] != 7'd0) $fatal(1, "UART did not resume after CTS assertion: %h", value);

    configure_uart(5'd3, 4'b0010);
    fork
      send_external_8n1(8'h3C, 1'b1);
    join
    apb4_read(`APB4_UART_RXDATA, 1'b0, value);
    if ((value[7:0] != 8'h3C) || !value[`UART_RXDATA_FRAME_ERROR]) begin
      $fatal(1, "UART frame error was not retained: %h", value);
    end

    configure_uart_flow(5'd3, 2'b10, 7'd1, 7'd2, 4'b0010);
    repeat (4) @(posedge clk_i);
    if (uart.rts_n_o !== 1'b0) $fatal(1, "UART RTS_n was not asserted for an empty RX FIFO");
    send_external_8n1(8'h12, 1'b0);
    if (uart.rts_n_o !== 1'b0) $fatal(1, "UART RTS_n asserted state did not hold below watermark");
    send_external_8n1(8'h34, 1'b0);
    if (uart.rts_n_o !== 1'b1) $fatal(1, "UART RTS_n was not released at high watermark");
    apb4_read(`APB4_UART_RXDATA, 1'b0, value);
    repeat (2) @(posedge clk_i);
    if ((value[7:0] != 8'h12) || (uart.rts_n_o !== 1'b0)) begin
      $fatal(1, "UART RTS hysteresis did not reassert below low watermark: %h", value);
    end
    apb4_read(`APB4_UART_RXDATA, 1'b0, value);
    if (value[7:0] != 8'h34) $fatal(1, "UART RTS test RX ordering mismatch: %h", value);

    write_ok(`APB4_UART_CTRL, 0);
    repeat (4) @(posedge clk_i);
    write_ok(`APB4_UART_FIFO_CTRL, 3);
    for (index = 0; index < 64; index = index + 1) begin
      write_ok(`APB4_UART_TXDATA, index);
    end
    apb4_write(`APB4_UART_TXDATA, 32'h55, 4'hF, 1'b1);
    apb4_read(`APB4_UART_FIFO_LEVEL, 1'b0, value);
    if (value[6:0] != 7'd64) $fatal(1, "UART TX FIFO depth mismatch: %h", value);

    write_ok(`APB4_UART_FIFO_CTRL, 3);
    write_ok(`APB4_UART_DMA_CTRL, 3);
    if (!dma_tx_stall || !dma_rx_stall) $fatal(1, "Disabled UART asserted a DMA request");

    $display("UART register, FIFO, loopback, flow-control, interrupt, and DMA test passed");
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk_i);
    $fatal(1, "UART test timeout");
  end

endmodule
