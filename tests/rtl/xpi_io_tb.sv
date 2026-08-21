`timescale 1ns / 1ps

module xpi_io_tb;
  import xpi_pkg::*;

  logic              clk_i = 1'b0;
  logic              rst_n_i = 1'b0;
  logic              start_i = 1'b0;
  logic              abort_i = 1'b0;
  logic       [ 1:0] slot_i = 2'd2;
  logic              mode3_i = 1'b0;
  logic       [ 7:0] clkdiv_i = 8'd0;
  logic       [ 7:0] cs_setup_i = 8'd0;
  logic       [ 7:0] cs_hold_i = 8'd0;
  logic       [ 7:0] cs_high_i = 8'd0;
  logic       [31:0] timeout_i = 32'd1000;
  logic       [31:0] address_i = 32'h0012_3456;
  logic       [15:0] data_len_i = 16'd1;
  logic       [15:0] lut_i                     [0:7];
  logic              tx_valid_i = 1'b0;
  logic              tx_ready_o;
  logic       [ 7:0] tx_data_i = 8'hA5;
  logic              rx_valid_o;
  logic              rx_ready_i = 1'b1;
  logic       [ 7:0] rx_data_o;
  logic              busy_o;
  logic              done_o;
  logic              error_o;
  xpi_error_e        error_code_o;
  logic       [ 2:0] error_pc_o;
  logic              phy_byte_event_o;
  xpi_if xpi ();

  logic s_saw_drive;
  logic s_saw_receive_release;
  logic s_saw_selected_slot;

  always #5 clk_i = ~clk_i;

  xpi_core u_dut (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (start_i),
      .abort_i         (abort_i),
      .slot_i          (slot_i),
      .mode3_i         (mode3_i),
      .clkdiv_i        (clkdiv_i),
      .cs_setup_i      (cs_setup_i),
      .cs_hold_i       (cs_hold_i),
      .cs_high_i       (cs_high_i),
      .timeout_i       (timeout_i),
      .address_i       (address_i),
      .data_len_i      (data_len_i),
      .lut_i           (lut_i),
      .tx_valid_i      (tx_valid_i),
      .tx_ready_o      (tx_ready_o),
      .tx_data_i       (tx_data_i),
      .rx_valid_o      (rx_valid_o),
      .rx_ready_i      (rx_ready_i),
      .rx_data_o       (rx_data_o),
      .busy_o          (busy_o),
      .done_o          (done_o),
      .error_o         (error_o),
      .error_code_o    (error_code_o),
      .error_pc_o      (error_pc_o),
      .phy_byte_event_o(phy_byte_event_o),
      .xpi             (xpi)
  );

  task automatic clear_lut;
    begin
      for (int index = 0; index < 8; index++) begin
        lut_i[index] = xpi_instr(XpiInstrStop, 2'd0, 8'd0);
      end
    end
  endtask

  task automatic start_and_wait;
    int timeout;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      timeout = 0;
      while (!done_o && (timeout < 1200)) begin
        @(posedge clk_i);
        timeout++;
      end
      if (!done_o) $fatal(1, "XPI transaction timed out in testbench");
    end
  endtask

  always @(posedge clk_i) begin
    if (rst_n_i && busy_o) begin
      if (xpi.io_oe_o != 4'b0000) s_saw_drive <= 1'b1;
      if (rx_valid_o && (xpi.nss_o == 4'b1011) && (xpi.io_oe_o == 4'b0000)) begin
        s_saw_receive_release <= 1'b1;
      end
      if (xpi.nss_o == 4'b1011) s_saw_selected_slot <= 1'b1;
      if ((xpi.nss_o != 4'b1111) && (xpi.nss_o != 4'b1110) &&
          (xpi.nss_o != 4'b1101) && (xpi.nss_o != 4'b1011) &&
          (xpi.nss_o != 4'b0111)) begin
        $fatal(1, "invalid NSS value %b", xpi.nss_o);
      end
    end
  end

  initial begin
    clear_lut();
    xpi.io_di_i           = 4'hF;
    s_saw_drive           = 1'b0;
    s_saw_receive_release = 1'b0;
    s_saw_selected_slot   = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    if (xpi.sck_o !== 1'b0 || xpi.nss_o !== 4'b1111 || xpi.io_oe_o !== 4'b0000) begin
      $fatal(1, "mode-0 reset pins were not idle");
    end
    lut_i[0] = xpi_instr(XpiInstrCommand, 2'd2, 8'hA5);
    lut_i[1] = xpi_instr(XpiInstrDummy, 2'd0, 8'd2);
    lut_i[2] = xpi_instr(XpiInstrReceive, 2'd2, 8'd1);
    lut_i[3] = xpi_instr(XpiInstrStop, 2'd0, 8'd0);
    start_and_wait();
    if (error_o || !s_saw_drive || !s_saw_receive_release || !s_saw_selected_slot ||
        (rx_data_o !== 8'hFF)) begin
      $fatal(1, "mode-0 failed err=%b drive=%b release=%b slot=%b rx=%02x", error_o, s_saw_drive,
             s_saw_receive_release, s_saw_selected_slot, rx_data_o);
    end

    mode3_i = 1'b1;
    clear_lut();
    lut_i[0] = xpi_instr(XpiInstrCommand, 2'd0, 8'h9F);
    lut_i[1] = xpi_instr(XpiInstrStop, 2'd0, 8'd0);
    repeat (2) @(posedge clk_i);
    if (xpi.sck_o !== 1'b1) $fatal(1, "mode-3 idle clock was not high");
    start_and_wait();
    if (error_o || xpi.sck_o !== 1'b1) $fatal(1, "mode-3 command failed");

    mode3_i = 1'b0;
    for (int index = 0; index < 8; index++) begin
      lut_i[index] = xpi_instr(XpiInstrCommand, 2'd0, 8'h06);
    end
    start_and_wait();
    if (!error_o || (error_code_o != XpiErrorSequence) || (error_pc_o != 3'd7)) begin
      $fatal(1, "unterminated LUT did not report instruction 7");
    end

    $display("XPI v2 LUT and pad isolation test passed");
    $finish;
  end
endmodule
