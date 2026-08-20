`timescale 1ns / 1ps
`include "axi4_define.svh"

module spisd_wrapper_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  integer        s_train_rise_count;
  integer        s_training_timeout;
  integer        s_command_timeout;
  logic   [31:0] s_read_data;
  logic          s_access_error;
  logic          s_card_miso;
  logic          s_card_power_on;
  logic          s_count_training;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  spi_if spi ();

  always #5 clk_i = ~clk_i;

  assign spi.miso_i       = s_card_miso;
  assign dma_axi4.awready = 1'b1;
  assign dma_axi4.wready  = 1'b1;
  assign dma_axi4.bid     = '0;
  assign dma_axi4.bresp   = `AXI4_RESP_OKAY;
  assign dma_axi4.buser   = '0;
  assign dma_axi4.bvalid  = 1'b0;
  assign dma_axi4.arready = 1'b1;
  assign dma_axi4.rid     = '0;
  assign dma_axi4.rdata   = '0;
  assign dma_axi4.rresp   = `AXI4_RESP_OKAY;
  assign dma_axi4.rlast   = 1'b1;
  assign dma_axi4.ruser   = '0;
  assign dma_axi4.rvalid  = 1'b0;

  apb4_spisd #(
      .InputClockHz(72_000_000),
      .AddrWidth   (32),
      .DataWidth   (32),
      .DescCount   (16),
      .FifoDepth   (16)
  ) u_apb4_spisd (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (apb4),
      .dma_axi4(dma_axi4),
      .spi     (spi)
  );

  spisd_card u_spisd_card (
      .sck     (spi.sck_o),
      .cs_n    (spi.nss_o),
      .mosi    (spi.mosi_o),
      .miso    (s_card_miso),
      .power_on(s_card_power_on)
  );

  always @(posedge spi.sck_o) begin
    if (s_count_training) begin
      s_train_rise_count = s_train_rise_count + 1;
      if (!spi.nss_o) $fatal(1, "chip select asserted during power-up clock training");
    end
  end

  task automatic apb_write(input logic [31:0] addr, input logic [31:0] data,
                           output logic access_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = addr;
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      @(posedge clk_i);
      while (!apb4.pready) @(posedge clk_i);
      #1;
      access_error = apb4.pslverr;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [31:0] addr, output logic [31:0] data,
                          output logic access_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = addr;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = 4'h0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      @(posedge clk_i);
      while (!apb4.pready) @(posedge clk_i);
      #1;
      data         = apb4.prdata;
      access_error = apb4.pslverr;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    s_train_rise_count = 0;
    s_count_training   = 1'b1;
    s_card_power_on    = 1'b0;
    apb4.paddr         = '0;
    apb4.pprot         = '0;
    apb4.psel          = 1'b0;
    apb4.penable       = 1'b0;
    apb4.pwrite        = 1'b0;
    apb4.pwdata        = '0;
    apb4.pstrb         = '0;
    repeat (3) @(posedge clk_i);
    rst_n_i         = 1'b1;
    s_card_power_on = 1'b1;
    @(posedge clk_i);
    s_card_power_on = 1'b0;

    apb_read(32'h0000_0000, s_read_data, s_access_error);
    if (s_access_error || (s_read_data != 32'h5350_4953)) begin
      $fatal(1, "IP identification read failed: data=%h err=%b", s_read_data, s_access_error);
    end
    apb_read(32'h0000_0008, s_read_data, s_access_error);
    if (s_access_error || (s_read_data[7:0] != 8'hFF)) begin
      $fatal(1, "capability read failed: data=%h err=%b", s_read_data, s_access_error);
    end
    apb_write(32'h0000_0000, 32'd0, s_access_error);
    if (!s_access_error) $fatal(1, "read-only register write did not return PSLVERR");
    apb_read(32'h0000_03FC, s_read_data, s_access_error);
    if (!s_access_error) $fatal(1, "undefined register read did not return PSLVERR");

    apb_write(32'h0000_000C, 32'h0000_0001, s_access_error);
    if (s_access_error) $fatal(1, "HOST_CTRL write failed");
    apb_write(32'h0000_0010, 32'h0000_0103, s_access_error);
    if (s_access_error) $fatal(1, "CLOCK_CTRL training write failed");
    s_training_timeout = 0;
    while ((s_train_rise_count < 80) && (s_training_timeout < 500)) begin
      @(posedge clk_i);
      s_training_timeout = s_training_timeout + 1;
    end
    if (s_train_rise_count != 80) begin
      $fatal(1, "power-up clock training timed out at %0d rising edges", s_train_rise_count);
    end
    repeat (6) @(posedge clk_i);
    if ((s_train_rise_count != 80) || spi.sck_o || !spi.nss_o) begin
      $fatal(1, "training completion failed: edges=%0d sck=%b cs_n=%b", s_train_rise_count,
             spi.sck_o, spi.nss_o);
    end
    apb_read(32'h0000_0024, s_read_data, s_access_error);
    if (s_access_error || s_read_data[0]) begin
      $fatal(1, "controller remained busy after training: status=%h", s_read_data);
    end
    apb_read(32'h0000_0014, s_read_data, s_access_error);
    if (s_access_error || (s_read_data != 32'd36_000_000)) begin
      $fatal(1, "actual clock reporting failed: %0d", s_read_data);
    end
    s_count_training = 1'b0;

    apb_write(32'h0000_0040, 32'd0, s_access_error);
    if (s_access_error) $fatal(1, "CMD_ARG write failed");
    apb_write(32'h0000_0044, 32'h0000_0100, s_access_error);
    if (s_access_error) $fatal(1, "CMD_CFG write failed");
    apb_write(32'h0000_0048, 32'd1, s_access_error);
    if (s_access_error) $fatal(1, "CMD_START write failed");
    s_command_timeout = 0;
    apb_read(32'h0000_004C, s_read_data, s_access_error);
    while (s_read_data[0] && (s_command_timeout < 500)) begin
      apb_read(32'h0000_004C, s_read_data, s_access_error);
      s_command_timeout = s_command_timeout + 1;
    end
    if (s_access_error || s_read_data[2:1] || (s_command_timeout >= 500)) begin
      $fatal(1, "CMD0 failed: status=%h timeout=%0d", s_read_data, s_command_timeout);
    end
    apb_read(32'h0000_0050, s_read_data, s_access_error);
    if (s_access_error || (s_read_data[7:0] != 8'h01)) begin
      $fatal(1, "CMD0 response failed: response=%h", s_read_data);
    end

    u_spisd_card.initialized = 1'b1;
    apb_write(32'h0000_0080, 32'd512, s_access_error);
    apb_write(32'h0000_0084, 32'd1, s_access_error);
    apb_write(32'h0000_0088, 32'h0000_0050, s_access_error);
    apb_write(32'h0000_00C0, 32'h0000_0001, s_access_error);
    apb_write(32'h0000_00C4, 32'd1, s_access_error);
    apb_write(32'h0000_0040, 32'd0, s_access_error);
    apb_write(32'h0000_0044, 32'h0000_2111, s_access_error);
    if (s_access_error) $fatal(1, "DMA command setup failed");
    apb_write(32'h0000_00C8, 32'd1, s_access_error);
    if (s_access_error) $fatal(1, "DMA command alias start failed");
    s_command_timeout = 0;
    apb_read(32'h0000_0024, s_read_data, s_access_error);
    while (s_read_data[0] && (s_command_timeout < 500)) begin
      apb_read(32'h0000_0024, s_read_data, s_access_error);
      s_command_timeout = s_command_timeout + 1;
    end
    if (s_access_error || (s_command_timeout >= 500)) begin
      $fatal(1, "descriptor error did not terminate the transaction");
    end
    apb_read(32'h0000_004C, s_read_data, s_access_error);
    if (s_access_error || !s_read_data[1] || (s_read_data[13:6] != 8'h08)) begin
      $fatal(1, "descriptor error did not abort the command engine: %h", s_read_data);
    end
    apb_read(32'h0000_00CC, s_read_data, s_access_error);
    if (s_access_error || !s_read_data[2] || (s_read_data[10:3] != 8'h02)) begin
      $fatal(1, "descriptor error classification failed: %h", s_read_data);
    end
    apb_read(32'h0000_010C, s_read_data, s_access_error);
    if (s_access_error || !s_read_data[6]) begin
      $fatal(1, "descriptor error was not latched: %h", s_read_data);
    end
    $display("SPISD APB ABI, training, card model, and DMA abort test passed");
    $finish;
  end
endmodule
