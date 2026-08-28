`timescale 1ns / 1ps

module xpi_fast_flash_model_tb;

  import xpi_pkg::*;

  logic               clk;
  logic               rst_n;
  logic               start;
  logic               abort;
  logic        [ 1:0] slot;
  logic        [31:0] timeout_cycles;
  logic        [31:0] address;
  logic        [15:0] data_length;
  logic        [15:0] lut                 [0:7];
  logic               rx_valid;
  logic               rx_ready;
  logic        [ 7:0] rx_data;
  logic               busy;
  logic               done;
  logic               error;
  xpi_error_e         error_code;
  logic        [ 2:0] error_pc;
  logic               byte_event;

  int unsigned        s_expected_address;
  int unsigned        s_received_count;
  logic               s_scoreboard_enable;

  xpi_fast_flash_model u_dut (
      .clk_i           (clk),
      .rst_n_i         (rst_n),
      .start_i         (start),
      .abort_i         (abort),
      .slot_i          (slot),
      .timeout_i       (timeout_cycles),
      .address_i       (address),
      .data_len_i      (data_length),
      .lut_i           (lut),
      .rx_valid_o      (rx_valid),
      .rx_ready_i      (rx_ready),
      .rx_data_o       (rx_data),
      .busy_o          (busy),
      .done_o          (done),
      .error_o         (error),
      .error_code_o    (error_code),
      .error_pc_o      (error_pc),
      .phy_byte_event_o(byte_event)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk) begin
    if (s_scoreboard_enable && rx_valid && rx_ready) begin
      if (rx_data != 8'(s_expected_address + s_received_count)) begin
        $fatal(1, "fast flash data mismatch at byte %0d", s_received_count);
      end
      if (!byte_event) begin
        $fatal(1, "accepted byte did not raise the PHY byte event");
      end
      s_received_count <= s_received_count + 1;
    end
  end

  task automatic set_default_lut;
    begin
      lut[0] = xpi_instr(XpiInstrCommand, 2'd0, 8'hEB);
      lut[1] = xpi_instr(XpiInstrAddress, 2'd2, 8'd24);
      lut[2] = xpi_instr(XpiInstrMode, 2'd2, 8'hF0);
      lut[3] = xpi_instr(XpiInstrDummy, 2'd0, 8'd4);
      lut[4] = xpi_instr(XpiInstrReceive, 2'd2, 8'd0);
      lut[5] = xpi_instr(XpiInstrStop, 2'd0, 8'd0);
      lut[6] = xpi_instr(XpiInstrStop, 2'd0, 8'd0);
      lut[7] = xpi_instr(XpiInstrStop, 2'd0, 8'd0);
    end
  endtask

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_for_done;
    begin
      while (!done) begin
        @(negedge clk);
      end
    end
  endtask

  initial begin
    logic [7:0] held_data;

    clk                 = 1'b0;
    rst_n               = 1'b0;
    start               = 1'b0;
    abort               = 1'b0;
    slot                = 2'd0;
    timeout_cycles      = 32'd100;
    address             = 32'd0;
    data_length         = 16'd0;
    rx_ready            = 1'b0;
    s_expected_address  = 0;
    s_received_count    = 0;
    s_scoreboard_enable = 1'b0;
    set_default_lut();
    repeat (3) @(negedge clk);
    rst_n               = 1'b1;

    address             = 32'h0000_01FD;
    data_length         = 16'd6;
    s_expected_address  = address;
    s_received_count    = 0;
    s_scoreboard_enable = 1'b1;
    pulse_start();
    while (!rx_valid) begin
      @(negedge clk);
    end
    held_data = rx_data;
    repeat (3) begin
      @(negedge clk);
      if (!rx_valid || (rx_data != held_data)) begin
        $fatal(1, "fast flash did not hold data during backpressure");
      end
    end
    rx_ready = 1'b1;
    wait_for_done();
    if (error || (s_received_count != 6)) begin
      $fatal(1, "fast flash read did not complete successfully");
    end
    s_scoreboard_enable = 1'b0;
    rx_ready            = 1'b0;

    slot                = 2'd1;
    pulse_start();
    wait_for_done();
    if (!error || (error_code != XpiErrorSequence)) begin
      $fatal(1, "unsupported slot did not report a sequence error");
    end

    slot = 2'd0;
    set_default_lut();
    lut[4] = xpi_instr(XpiInstrTransmit, 2'd0, 8'd0);
    pulse_start();
    wait_for_done();
    if (!error || (error_code != XpiErrorSequence)) begin
      $fatal(1, "write sequence did not report a sequence error");
    end

    set_default_lut();
    timeout_cycles = 32'd1;
    data_length    = 16'd4;
    pulse_start();
    wait_for_done();
    if (!error || (error_code != XpiErrorTimeout)) begin
      $fatal(1, "expired transfer did not report a timeout");
    end

    timeout_cycles = 32'd100;
    data_length    = 16'd4;
    pulse_start();
    while (!busy) begin
      @(negedge clk);
    end
    abort = 1'b1;
    @(negedge clk);
    abort = 1'b0;
    wait_for_done();
    if (!error || (error_code != XpiErrorAborted)) begin
      $fatal(1, "aborted transfer did not report an abort error");
    end

    $display("XPI fast flash model test passed");
    $finish;
  end

endmodule
