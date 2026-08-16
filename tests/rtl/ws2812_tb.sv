`timescale 1ns / 1ps

`include "ws2812_define.svh"

module ws2812_tb;
  localparam int FIFO_DEPTH = 4;
  localparam int BIT_CYCLES = 4;
  localparam int T0H_CYCLES = 1;
  localparam int T1H_CYCLES = 3;
  localparam int RESET_CYCLES = 5;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  ws2812_if ws2812 ();

  logic          monitor_enable = 1'b0;
  logic   [23:0] expected_pixels                  [0:7];
  integer        expected_pixel_count = 0;
  integer        observed_pixel = 0;
  integer        observed_bit = 0;
  integer        observed_cycle = 0;
  integer        expected_bit_cycles = BIT_CYCLES;
  integer        expected_t0h_cycles = T0H_CYCLES;
  integer        expected_t1h_cycles = T1H_CYCLES;
  integer        reset_low_cycles = 0;
  integer        test_stage = 0;

  always #5 clk_i = ~clk_i;

  initial begin
    repeat (10000) @(posedge clk_i);
    $fatal(1, "WS2812 test timeout at stage %0d state=%0d valid=%b ready=%b", test_stage,
           u_dut.u_ws2812_core.s_state_q, apb4.psel, apb4.pready);
  end

  apb4_ws2812 #(
      .TxFifoDepth(FIFO_DEPTH)
  ) u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .apb4   (apb4),
      .ws2812 (ws2812)
  );

  task automatic apb4_write(input logic [31:0] address, input logic [31:0] data,
                            input logic [3:0] strobe, input logic expected_error,
                            output integer wait_cycles);
    begin
      wait_cycles = 0;
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = strobe;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) begin
        @(negedge clk_i);
        wait_cycles = wait_cycles + 1;
      end
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
    integer ignored_wait;
    begin
      apb4_write(address, data, 4'hF, 1'b0, ignored_wait);
    end
  endtask

  task automatic wait_until_idle;
    logic [31:0] status;
    begin
      status = 32'h1;
      while (status[`WS2812_STATUS_BUSY]) begin
        apb4_read(`APB4_WS2812_STATUS, 1'b0, status);
      end
    end
  endtask

  task automatic configure_timing;
    begin
      write_ok(`APB4_WS2812_BIT_CYCLES, BIT_CYCLES);
      write_ok(`APB4_WS2812_T0H_CYCLES, T0H_CYCLES);
      write_ok(`APB4_WS2812_T1H_CYCLES, T1H_CYCLES);
      write_ok(`APB4_WS2812_RESET_CYCLES, RESET_CYCLES);
      write_ok(`APB4_WS2812_FIFO_WATERMARK, 3);
      write_ok(`APB4_WS2812_INTR_ENABLE, 4'hF);
    end
  endtask

  always @(posedge clk_i) begin
    #1;
    if (!rst_n_i && ws2812.dat_o !== 1'b0) begin
      $fatal(1, "WS2812 output is not low during reset");
    end
    if (monitor_enable && u_dut.s_busy && !u_dut.s_reset_active) begin
      integer high_cycles;
      logic   expected_data;
      high_cycles = expected_pixels[observed_pixel][23-observed_bit] ? expected_t1h_cycles :
                                                                         expected_t0h_cycles;
      expected_data = observed_cycle < high_cycles;
      if (ws2812.dat_o !== expected_data) begin
        $fatal(1, "waveform mismatch pixel=%0d bit=%0d cycle=%0d", observed_pixel, observed_bit,
               observed_cycle);
      end
      observed_cycle = observed_cycle + 1;
      if (observed_cycle == expected_bit_cycles) begin
        observed_cycle = 0;
        observed_bit   = observed_bit + 1;
        if (observed_bit == 24) begin
          observed_bit   = 0;
          observed_pixel = observed_pixel + 1;
        end
      end
    end
    if (monitor_enable && u_dut.s_reset_active) begin
      if (ws2812.dat_o !== 1'b0) begin
        $fatal(1, "WS2812 output is high during latch/reset");
      end
      reset_low_cycles = reset_low_cycles + 1;
    end
  end

  task automatic begin_monitor(input integer pixel_count);
    begin
      observed_pixel       = 0;
      observed_bit         = 0;
      observed_cycle       = 0;
      reset_low_cycles     = 0;
      expected_pixel_count = pixel_count;
      monitor_enable       = 1'b1;
    end
  endtask

  task automatic end_monitor(input logic expect_complete_frame);
    begin
      monitor_enable = 1'b0;
      if (expect_complete_frame && observed_pixel != expected_pixel_count) begin
        $fatal(1, "observed %0d pixels, expected %0d", observed_pixel, expected_pixel_count);
      end
      if (reset_low_cycles < RESET_CYCLES) begin
        $fatal(1, "latch/reset low interval was only %0d cycles", reset_low_cycles);
      end
    end
  endtask

  initial begin
    logic   [31:0] value;
    integer        wait_cycles;

    apb4.psel   = 1'b0;
    apb4.paddr  = '0;
    apb4.pwdata = '0;
    apb4.pstrb  = '0;
    repeat (3) @(posedge clk_i);
    rst_n_i    = 1'b1;

    test_stage = 1;
    apb4_read(`APB4_WS2812_IP_INFO, 1'b0, value);
    if (value !== 32'h1804_0100) begin
      $fatal(1, "unexpected IP_INFO %h", value);
    end
    apb4_read(`APB4_WS2812_STATUS, 1'b0, value);
    if (value[`WS2812_STATUS_CONFIG_VALID] || !value[`WS2812_STATUS_FIFO_EMPTY]) begin
      $fatal(1, "unexpected reset status %h", value);
    end
    apb4_read(`APB4_WS2812_CTRL, 1'b1, value);
    apb4_write(8'h02, 32'd1, 4'hF, 1'b1, wait_cycles);
    apb4_read(32'h00000100, 1'b1, value);
    apb4_write(`APB4_WS2812_TXDATA, 24'h112233, 4'h7, 1'b1, wait_cycles);
    write_ok(`APB4_WS2812_TXDATA, 24'h112233);
    write_ok(`APB4_WS2812_FRAME_WORDS, 1);
    apb4_write(`APB4_WS2812_CTRL, 32'h1, 4'hF, 1'b1, wait_cycles);
    apb4_read(`APB4_WS2812_ERROR_STATUS, 1'b0, value);
    if (!value[`WS2812_ERROR_CONFIG]) begin
      $fatal(1, "invalid timing did not set CONFIG error");
    end
    write_ok(`APB4_WS2812_ERROR_STATUS, 32'h7);
    write_ok(`APB4_WS2812_CTRL, 32'h4);

    configure_timing();
    apb4_read(`APB4_WS2812_STATUS, 1'b0, value);
    if (!value[`WS2812_STATUS_CONFIG_VALID]) begin
      $fatal(1, "legal timing was not accepted");
    end

    test_stage = 2;
    for (integer index = 0; index < FIFO_DEPTH; index = index + 1) begin
      write_ok(`APB4_WS2812_TXDATA, index);
    end
    apb4_write(`APB4_WS2812_TXDATA, 32'h55, 4'hF, 1'b1, wait_cycles);
    write_ok(`APB4_WS2812_CTRL, 32'h4);
    write_ok(`APB4_WS2812_ERROR_STATUS, 32'h7);
    write_ok(`APB4_WS2812_INTR_STATE, 32'hF);

    test_stage         = 3;
    expected_pixels[0] = 24'h800001;
    expected_pixels[1] = 24'h010203;
    expected_pixels[2] = 24'hA5A5A5;
    expected_pixels[3] = 24'h5A5A5A;
    expected_pixels[4] = 24'hFFFFFF;
    expected_pixels[5] = 24'h000000;
    for (integer index = 0; index < FIFO_DEPTH; index = index + 1) begin
      write_ok(`APB4_WS2812_TXDATA, expected_pixels[index]);
    end
    write_ok(`APB4_WS2812_FRAME_WORDS, 6);
    begin_monitor(6);
    write_ok(`APB4_WS2812_CTRL, 32'h1);
    write_ok(`APB4_WS2812_TXDATA, expected_pixels[4]);
    apb4_write(`APB4_WS2812_TXDATA, expected_pixels[5], 4'hF, 1'b0, wait_cycles);
    if (wait_cycles < (BIT_CYCLES * 20)) begin
      $fatal(1, "full FIFO write was not backpressured: %0d cycles", wait_cycles);
    end
    wait_until_idle();
    end_monitor(1'b1);
    apb4_read(`APB4_WS2812_INTR_STATE, 1'b0, value);
    if ((value & 32'h3) != 32'h3 || !ws2812.irq_o) begin
      $fatal(1, "done/low-watermark interrupt missing: %h", value);
    end
    write_ok(`APB4_WS2812_INTR_STATE, 32'hF);
    if (ws2812.irq_o) begin
      $fatal(1, "IRQ did not clear");
    end

    test_stage         = 4;
    expected_pixels[0] = 24'h123456;
    write_ok(`APB4_WS2812_TXDATA, expected_pixels[0]);
    write_ok(`APB4_WS2812_FRAME_WORDS, 2);
    begin_monitor(1);
    write_ok(`APB4_WS2812_CTRL, 32'h1);
    wait_until_idle();
    end_monitor(1'b1);
    apb4_read(`APB4_WS2812_ERROR_STATUS, 1'b0, value);
    if (!value[`WS2812_ERROR_UNDERFLOW]) begin
      $fatal(1, "underflow was not reported");
    end
    apb4_read(`APB4_WS2812_FIFO_LEVEL, 1'b0, value);
    if (value != 0) begin
      $fatal(1, "underflow did not flush FIFO");
    end
    write_ok(`APB4_WS2812_ERROR_STATUS, 32'h7);
    write_ok(`APB4_WS2812_INTR_STATE, 32'hF);

    test_stage         = 5;
    expected_pixels[0] = 24'hABCDEF;
    expected_pixels[1] = 24'h765432;
    write_ok(`APB4_WS2812_TXDATA, expected_pixels[0]);
    write_ok(`APB4_WS2812_TXDATA, expected_pixels[1]);
    write_ok(`APB4_WS2812_FRAME_WORDS, 2);
    begin_monitor(2);
    write_ok(`APB4_WS2812_CTRL, 32'h1);
    repeat (8) @(posedge clk_i);
    write_ok(`APB4_WS2812_CTRL, 32'h2);
    wait_until_idle();
    end_monitor(1'b0);
    apb4_read(`APB4_WS2812_INTR_STATE, 1'b0, value);
    if (!value[`WS2812_INTR_ABORTED]) begin
      $fatal(1, "abort completion was not reported");
    end

    write_ok(`APB4_WS2812_INTR_TEST, 32'h1);
    if (!ws2812.irq_o) begin
      $fatal(1, "interrupt test did not assert IRQ");
    end
    write_ok(`APB4_WS2812_INTR_STATE, 32'hF);

    $display("WS2812 register, waveform, streaming, and error test passed");
    $finish;
  end
endmodule
