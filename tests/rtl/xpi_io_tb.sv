`timescale 1ns / 1ps

`include "xpi_define.svh"

module xpi_io_tb;
  logic                    clk_i = 1'b0;
  logic                    rst_n_i = 1'b0;
  logic                    mode_i = 1'b0;
  logic [`XPI_LNS_NUM-1:0] nss_i = '0;
  logic [             7:0] clkdiv_i = '0;
  logic                    rdwr_i = 1'b0;
  logic                    revdat_i = 1'b0;
  logic [             1:0] cmdtyp_i = `XPI_TYPE_NONE;
  logic [             2:0] cmdlen_i = '0;
  logic [            31:0] cmddat_i = '0;
  logic [             1:0] adrtyp_i = `XPI_TYPE_NONE;
  logic [             2:0] adrlen_i = '0;
  logic [            31:0] adrdat_i = '0;
  logic [             7:0] tdulen_i = '0;
  logic [             7:0] rdulen_i = '0;
  logic [             1:0] dattyp_i = `XPI_TYPE_NONE;
  logic [             7:0] datlen_i = '0;
  logic [             2:0] datbit_i = '0;
  logic [             7:0] hlvlen_i = '0;
  logic                    tx_data_rdy_i = 1'b0;
  logic [            31:0] tx_data_i = '0;
  logic                    rx_data_rdy_i = 1'b0;
  logic                    start_i = 1'b0;
  logic [             7:0] tx_elem_num_i = '0;
  logic                    dma_xfer_done_i = 1'b0;
  logic                    tx_data_req_o;
  logic                    rx_data_req_o;
  logic [            31:0] rx_data_o;
  logic                    done_o;
  xpi_if xpi ();

  always #5 clk_i = ~clk_i;

  xpi_core dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .mode_i         (mode_i),
      .nss_i          (nss_i),
      .clkdiv_i       (clkdiv_i),
      .rdwr_i         (rdwr_i),
      .revdat_i       (revdat_i),
      .cmdtyp_i       (cmdtyp_i),
      .cmdlen_i       (cmdlen_i),
      .cmddat_i       (cmddat_i),
      .adrtyp_i       (adrtyp_i),
      .adrlen_i       (adrlen_i),
      .adrdat_i       (adrdat_i),
      .tdulen_i       (tdulen_i),
      .rdulen_i       (rdulen_i),
      .dattyp_i       (dattyp_i),
      .datlen_i       (datlen_i),
      .datbit_i       (datbit_i),
      .hlvlen_i       (hlvlen_i),
      .tx_data_req_o  (tx_data_req_o),
      .tx_data_rdy_i  (tx_data_rdy_i),
      .tx_data_i      (tx_data_i),
      .rx_data_req_o  (rx_data_req_o),
      .rx_data_rdy_i  (rx_data_rdy_i),
      .rx_data_o      (rx_data_o),
      .start_i        (start_i),
      .done_o         (done_o),
      .tx_elem_num_i  (tx_elem_num_i),
      .dma_xfer_done_i(dma_xfer_done_i),
      .xpi            (xpi)
  );

  task automatic expect_pad(input logic [3:0] oe, input logic [3:0] data, input string state);
    begin
      #1;
      if (xpi.io_oe_o !== oe || xpi.io_do_o !== data) begin
        $fatal(1, "%s pad drive was oe=%b data=%b", state, xpi.io_oe_o, xpi.io_do_o);
      end
    end
  endtask

  initial begin
    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;
    force dut.s_xfer_data_q = 32'hABCD_1234;

    force dut.s_fsm_q = 3'd0;
    expect_pad(4'b0001, 4'b0000, "idle");

    cmdtyp_i = `XPI_TYPE_QUAD;
    force dut.s_fsm_q = 3'd1;
    expect_pad(4'b1111, 4'b1010, "command");

    dattyp_i = `XPI_TYPE_DUAL;
    force dut.s_fsm_q = 3'd4;
    expect_pad(4'b0011, 4'b0010, "transmit");

    force dut.s_fsm_q = 3'd3;
    expect_pad(4'b0000, 4'b0000, "dummy");

    force dut.s_fsm_q = 3'd5;
    xpi.io_di_i = 4'b0000;
    expect_pad(4'b0000, 4'b0000, "receive low");
    xpi.io_di_i = 4'b1111;
    expect_pad(4'b0000, 4'b0000, "receive high");

    release dut.s_fsm_q;
    release dut.s_xfer_data_q;
    $display("XPI pad drive isolation test passed");
    $finish;
  end
endmodule
