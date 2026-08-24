`timescale 1ns / 1ps

module usb2_packet_store_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          fill_start_valid_i = 1'b0;
  logic          fill_start_ready_o;
  logic   [11:0] fill_base_i = '0;
  logic   [14:0] fill_bytes_i = '0;
  logic          fill_valid_i = 1'b0;
  logic          fill_ready_o;
  logic   [31:0] fill_data_i = '0;
  logic   [ 3:0] fill_strb_i = '0;
  logic          fill_last_i = 1'b0;
  logic          fill_done_o;
  logic          fill_error_o;
  logic          drain_start_valid_i = 1'b0;
  logic          drain_start_ready_o;
  logic   [11:0] drain_base_i = '0;
  logic   [14:0] drain_bytes_i = '0;
  logic          drain_valid_o;
  logic          drain_ready_i = 1'b1;
  logic   [31:0] drain_data_o;
  logic   [ 3:0] drain_strb_o;
  logic          drain_last_o;
  logic          drain_done_o;
  logic          rx_start_valid_i = 1'b0;
  logic          rx_start_ready_o;
  logic   [11:0] rx_base_i = '0;
  logic   [14:0] rx_limit_i = '0;
  logic          rx_valid_i = 1'b0;
  logic          rx_ready_o;
  logic   [ 7:0] rx_data_i = '0;
  logic          rx_commit_i = 1'b0;
  logic          rx_cancel_i = 1'b0;
  logic          rx_done_o;
  logic   [14:0] rx_bytes_o;
  logic          rx_overflow_o;
  logic          tx_start_valid_i = 1'b0;
  logic          tx_start_ready_o;
  logic   [11:0] tx_base_i = '0;
  logic   [14:0] tx_bytes_i = '0;
  logic          tx_valid_o;
  logic          tx_ready_i = 1'b1;
  logic   [ 7:0] tx_data_o;
  logic          tx_done_o;
  logic          busy_o;
  logic          ecc_corrected_o;
  logic          ecc_uncorrectable_o;
  integer        tx_count;
  integer        drain_count;
  logic   [ 7:0] tx_bytes                   [0:4];
  logic   [31:0] drain_words                [0:1];
  logic   [ 3:0] drain_strb                 [0:1];

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      tx_count    <= 0;
      drain_count <= 0;
    end else begin
      if (tx_valid_o && tx_ready_i) begin
        tx_bytes[tx_count] <= tx_data_o;
        tx_count           <= tx_count + 1;
      end
      if (drain_valid_o && drain_ready_i) begin
        drain_words[drain_count] <= drain_data_o;
        drain_strb[drain_count]  <= drain_strb_o;
        drain_count              <= drain_count + 1;
      end
    end
  end

  usb2_packet_store u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .fill_start_valid_i (fill_start_valid_i),
      .fill_start_ready_o (fill_start_ready_o),
      .fill_base_i        (fill_base_i),
      .fill_bytes_i       (fill_bytes_i),
      .fill_valid_i       (fill_valid_i),
      .fill_ready_o       (fill_ready_o),
      .fill_data_i        (fill_data_i),
      .fill_strb_i        (fill_strb_i),
      .fill_last_i        (fill_last_i),
      .fill_done_o        (fill_done_o),
      .fill_error_o       (fill_error_o),
      .drain_start_valid_i(drain_start_valid_i),
      .drain_start_ready_o(drain_start_ready_o),
      .drain_base_i       (drain_base_i),
      .drain_bytes_i      (drain_bytes_i),
      .drain_valid_o      (drain_valid_o),
      .drain_ready_i      (drain_ready_i),
      .drain_data_o       (drain_data_o),
      .drain_strb_o       (drain_strb_o),
      .drain_last_o       (drain_last_o),
      .drain_done_o       (drain_done_o),
      .rx_start_valid_i   (rx_start_valid_i),
      .rx_start_ready_o   (rx_start_ready_o),
      .rx_base_i          (rx_base_i),
      .rx_limit_i         (rx_limit_i),
      .rx_valid_i         (rx_valid_i),
      .rx_ready_o         (rx_ready_o),
      .rx_data_i          (rx_data_i),
      .rx_commit_i        (rx_commit_i),
      .rx_cancel_i        (rx_cancel_i),
      .rx_done_o          (rx_done_o),
      .rx_bytes_o         (rx_bytes_o),
      .rx_overflow_o      (rx_overflow_o),
      .tx_start_valid_i   (tx_start_valid_i),
      .tx_start_ready_o   (tx_start_ready_o),
      .tx_base_i          (tx_base_i),
      .tx_bytes_i         (tx_bytes_i),
      .tx_valid_o         (tx_valid_o),
      .tx_ready_i         (tx_ready_i),
      .tx_data_o          (tx_data_o),
      .tx_done_o          (tx_done_o),
      .busy_o             (busy_o),
      .ecc_corrected_o    (ecc_corrected_o),
      .ecc_uncorrectable_o(ecc_uncorrectable_o)
  );

  task automatic pulse_fill(input logic [31:0] data_i, input logic [3:0] strb_i,
                            input logic last_i);
    begin
      @(negedge clk_i);
      fill_data_i  = data_i;
      fill_strb_i  = strb_i;
      fill_last_i  = last_i;
      fill_valid_i = 1'b1;
      while (!fill_ready_o) @(negedge clk_i);
      @(negedge clk_i);
      fill_valid_i = 1'b0;
    end
  endtask

  task automatic pulse_rx(input logic [7:0] data_i);
    begin
      @(negedge clk_i);
      rx_data_i  = data_i;
      rx_valid_i = 1'b1;
      while (!rx_ready_o) @(negedge clk_i);
      @(negedge clk_i);
      rx_valid_i = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    @(negedge clk_i);
    fill_base_i        = 12'd8;
    fill_bytes_i       = 15'd5;
    fill_start_valid_i = 1'b1;
    @(negedge clk_i);
    fill_start_valid_i = 1'b0;
    pulse_fill(32'h4433_2211, 4'hF, 1'b0);
    pulse_fill(32'h0000_0055, 4'h1, 1'b1);
    wait (fill_done_o);
    if (fill_error_o) $fatal(1, "packet store fill failed");

    @(negedge clk_i);
    tx_base_i        = 12'd8;
    tx_bytes_i       = 15'd5;
    tx_start_valid_i = 1'b1;
    @(negedge clk_i);
    tx_start_valid_i = 1'b0;
    wait (tx_done_o);
    @(posedge clk_i);
    if ((tx_count != 5) || (tx_bytes[0] != 8'h11) || (tx_bytes[1] != 8'h22) ||
        (tx_bytes[2] != 8'h33) || (tx_bytes[3] != 8'h44) || (tx_bytes[4] != 8'h55)) begin
      $fatal(1, "packet store transmit mismatch count=%0d", tx_count);
    end

    @(negedge clk_i);
    rx_base_i        = 12'd16;
    rx_limit_i       = 15'd5;
    rx_start_valid_i = 1'b1;
    @(negedge clk_i);
    rx_start_valid_i = 1'b0;
    pulse_rx(8'hA1);
    pulse_rx(8'hB2);
    pulse_rx(8'hC3);
    pulse_rx(8'hD4);
    pulse_rx(8'hE5);
    @(negedge clk_i);
    rx_commit_i = 1'b1;
    @(negedge clk_i);
    rx_commit_i = 1'b0;
    wait (rx_done_o);
    if ((rx_bytes_o != 15'd5) || rx_overflow_o) $fatal(1, "packet store receive failed");

    @(negedge clk_i);
    drain_base_i        = 12'd16;
    drain_bytes_i       = 15'd5;
    drain_start_valid_i = 1'b1;
    @(negedge clk_i);
    drain_start_valid_i = 1'b0;
    wait (drain_done_o);
    @(posedge clk_i);
    if ((drain_count != 2) || (drain_words[0] != 32'hD4C3_B2A1) ||
        (drain_words[1][7:0] != 8'hE5) || (drain_strb[0] != 4'hF) ||
        (drain_strb[1] != 4'h1)) begin
      $fatal(1, "packet store drain mismatch count=%0d", drain_count);
    end
    if (ecc_corrected_o || ecc_uncorrectable_o) $fatal(1, "unexpected ECC event");

    $display("USB2 packet store paths passed");
    $finish;
  end
endmodule
