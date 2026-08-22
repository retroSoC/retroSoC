`timescale 1ns / 1ps

module sdio_register_tb;
  localparam logic [31:0] Sdio0Base = 32'h1000_F000;
  localparam logic [31:0] Sdio1Base = 32'h1001_5000;

  logic                              clk_i = 1'b0;
  logic                              rst_n_i = 1'b0;
  logic                              busy_i = 1'b0;
  logic                      [ 31:0] status_i = 32'h0000_0011;
  logic                      [ 31:0] clock_actual_i = 32'd400000;
  logic                      [ 31:0] cmd_status_i = '0;
  logic                      [135:0] response_i = '0;
  logic                      [ 31:0] data_status_i = '0;
  logic                      [ 31:0] fifo_status_i = '0;
  logic                      [ 31:0] dma_status_i = '0;
  logic                      [ 31:0] current_desc_i = '0;
  logic                      [ 31:0] bytes_done_i = '0;
  logic                      [ 31:0] dma_error_addr_i = '0;
  logic                      [ 31:0] dma_error_i = '0;
  logic                      [ 31:0] error_status_i = '0;
  logic                      [  5:0] last_cmd_i = '0;
  logic                      [ 31:0] crc_error_count_i = '0;
  logic                      [ 31:0] timeout_count_i = '0;
  logic                      [ 31:0] axi_error_count_i = '0;
  logic                      [ 31:0] stall_count_i = '0;
  logic                      [  7:0] irq_event_i = '0;
  logic                      [ 31:0] pio_rdata_i = '0;
  logic                              pio_valid_i = 1'b0;
  logic                              pio_ready_i = 1'b0;
  logic                              pio_read_consume_o;
  logic                              host_enable_o;
  logic                              host_irq_enable_o;
  logic                              clock_enable_o;
  logic                      [ 15:0] half_period_o;
  logic                      [  1:0] bus_width_o;
  logic                      [ 31:0] timeout_cmd_o;
  logic                      [ 31:0] timeout_data_o;
  logic                      [ 31:0] timeout_busy_o;
  logic                      [  5:0] cmd_index_o;
  logic                      [ 31:0] cmd_arg_o;
  sdio_pkg::sdio_resp_type_e         cmd_resp_type_o;
  logic                              cmd_crc_check_o;
  logic                              cmd_index_check_o;
  logic                              cmd_start_o;
  logic                      [ 15:0] block_size_o;
  logic                      [ 15:0] block_count_o;
  logic                              data_direction_o;
  logic                              data_dma_enable_o;
  logic                              data_block_mode_o;
  logic                              data_fixed_addr_o;
  logic                              data_start_o;
  logic                              pio_wvalid_o;
  logic                      [ 31:0] pio_wdata_o;
  logic                      [  3:0] pio_wstrb_o;
  logic                      [ 31:0] desc_base_o;
  logic                      [ 15:0] desc_count_o;
  logic                              dma_start_o;
  logic                              dma_abort_o;
  logic                              irq_dat1_enable_o;
  logic                              irq_o;
  integer                            pio_consume_count;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  always @(posedge clk_i) begin
    if (pio_read_consume_o) begin
      pio_consume_count = pio_consume_count + 1;
    end
  end

  sdio_reg u_sdio_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .busy_i            (busy_i),
      .status_i          (status_i),
      .clock_actual_i    (clock_actual_i),
      .cmd_status_i      (cmd_status_i),
      .response_i        (response_i),
      .data_status_i     (data_status_i),
      .fifo_status_i     (fifo_status_i),
      .dma_status_i      (dma_status_i),
      .current_desc_i    (current_desc_i),
      .bytes_done_i      (bytes_done_i),
      .dma_error_addr_i  (dma_error_addr_i),
      .dma_error_i       (dma_error_i),
      .error_status_i    (error_status_i),
      .last_cmd_i        (last_cmd_i),
      .crc_error_count_i (crc_error_count_i),
      .timeout_count_i   (timeout_count_i),
      .axi_error_count_i (axi_error_count_i),
      .stall_count_i     (stall_count_i),
      .irq_event_i       (irq_event_i),
      .pio_rdata_i       (pio_rdata_i),
      .pio_valid_i       (pio_valid_i),
      .pio_ready_i       (pio_ready_i),
      .pio_read_consume_o(pio_read_consume_o),
      .host_enable_o     (host_enable_o),
      .host_irq_enable_o (host_irq_enable_o),
      .clock_enable_o    (clock_enable_o),
      .half_period_o     (half_period_o),
      .bus_width_o       (bus_width_o),
      .timeout_cmd_o     (timeout_cmd_o),
      .timeout_data_o    (timeout_data_o),
      .timeout_busy_o    (timeout_busy_o),
      .cmd_index_o       (cmd_index_o),
      .cmd_arg_o         (cmd_arg_o),
      .cmd_resp_type_o   (cmd_resp_type_o),
      .cmd_crc_check_o   (cmd_crc_check_o),
      .cmd_index_check_o (cmd_index_check_o),
      .cmd_start_o       (cmd_start_o),
      .block_size_o      (block_size_o),
      .block_count_o     (block_count_o),
      .data_direction_o  (data_direction_o),
      .data_dma_enable_o (data_dma_enable_o),
      .data_block_mode_o (data_block_mode_o),
      .data_fixed_addr_o (data_fixed_addr_o),
      .data_start_o      (data_start_o),
      .pio_wvalid_o      (pio_wvalid_o),
      .pio_wdata_o       (pio_wdata_o),
      .pio_wstrb_o       (pio_wstrb_o),
      .desc_base_o       (desc_base_o),
      .desc_count_o      (desc_count_o),
      .dma_start_o       (dma_start_o),
      .dma_abort_o       (dma_abort_o),
      .irq_dat1_enable_o (irq_dat1_enable_o),
      .irq_o             (irq_o),
      .apb4              (apb4)
  );

  task automatic apb_write(input logic [31:0] address, input logic [31:0] data,
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
      @(posedge clk_i);
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error)) begin
        $fatal(1, "APB write %h ready=%b err=%b expected=%b", address, apb4.pready, apb4.pslverr,
               expected_error);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read_error(input logic [31:0] address);
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
      @(posedge clk_i);
      #1;
      if (!apb4.pready || !apb4.pslverr) begin
        $fatal(1, "APB read %h did not report empty PIO error", address);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [31:0] address, output logic [31:0] data);
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
      @(posedge clk_i);
      #1;
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "APB read %h ready=%b err=%b", address, apb4.pready, apb4.pslverr);
      end
      data = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] value;
    apb4.paddr   = '0;
    apb4.pprot   = '0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    apb_read(32'h000, value);
    if (value != 32'h5344_494F) $fatal(1, "IP ID mismatch");
    apb_read(32'h008, value);
    if (value != 32'h0000_01FF) $fatal(1, "capability mismatch");
    apb_write(32'h010, 32'h0000_0501, 4'hF, 1'b0);
    apb_read(32'h010, value);
    if (value != 32'h0000_0501) $fatal(1, "clock control mismatch: %h", value);
    apb_write(32'h040, 32'hCAFE_BABE, 4'hF, 1'b0);
    apb_write(32'h044, 32'h0000_3108, 4'hF, 1'b0);
    apb_write(32'h048, 32'h0000_0001, 4'h1, 1'b0);
    #1;
    if (!cmd_start_o || (cmd_index_o != 6'd8) || (cmd_arg_o != 32'hCAFE_BABE)) begin
      $fatal(1, "command pulse/configuration mismatch");
    end
    apb_write(32'h3FC, 32'h0, 4'hF, 1'b1);
    busy_i = 1'b1;
    apb_write(32'h040, 32'h0, 4'hF, 1'b1);
    busy_i = 1'b0;
    apb_write(32'h104, 32'h0000_0001, 4'h1, 1'b0);
    apb_write(32'h108, 32'h0000_0001, 4'h1, 1'b0);
    if (!irq_o) $fatal(1, "IRQ test did not assert IRQ");
    apb_read(32'h100, value);
    if ((value & 32'h1) == 0) $fatal(1, "IRQ status did not latch");
    apb_write(32'h100, 32'h0000_0001, 4'h1, 1'b0);
    if (irq_o) $fatal(1, "IRQ W1C did not clear IRQ");

    apb_write(32'h104, 32'h0000_0004, 4'h1, 1'b0);
    irq_event_i = 8'h04;
    @(posedge clk_i);
    irq_event_i = 8'h00;
    apb_read(32'h100, value);
    if ((value & 32'h04) == 0 || !irq_o) $fatal(1, "descriptor IRQ event did not latch");
    apb_write(32'h100, 32'h0000_0004, 4'h1, 1'b0);
    apb_read(32'h100, value);
    if ((value & 32'h04) != 0 || irq_o) $fatal(1, "descriptor IRQ W1C failed");

    error_status_i = 32'h0000_0001;
    @(posedge clk_i);
    error_status_i = 32'h0000_0000;
    apb_read(32'h10C, value);
    if ((value & 32'h01) == 0) $fatal(1, "error event did not latch");
    apb_write(32'h10C, 32'h0000_0001, 4'h1, 1'b0);
    apb_read(32'h10C, value);
    if ((value & 32'h01) != 0) $fatal(1, "ERROR_STATUS W1C did not clear");
    apb_read(32'h10C, value);
    if ((value & 32'h01) != 0) $fatal(1, "ERROR_STATUS clear was not persistent");
    error_status_i = 32'h0000_0001;
    @(posedge clk_i);
    error_status_i = 32'h0000_0000;
    apb_read(32'h10C, value);
    if ((value & 32'h01) == 0) $fatal(1, "new error event did not re-latch");

    pio_rdata_i = 32'h1122_3344;
    pio_valid_i = 1'b1;
    pio_ready_i = 1'b0;
    apb_read(32'h124, value);
    if (value != 32'h0000_0001) $fatal(1, "DEBUG PIO valid bit mismatch: %h", value);
    pio_valid_i = 1'b0;
    pio_ready_i = 1'b1;
    apb_read(32'h124, value);
    if (value != 32'h0000_0002) $fatal(1, "DEBUG PIO ready bit mismatch: %h", value);
    pio_rdata_i       = 32'h1122_3344;
    pio_valid_i       = 1'b1;
    pio_consume_count = 0;
    apb_read(32'h090, value);
    if ((value != 32'h1122_3344) || (pio_consume_count != 1)) begin
      $fatal(1, "PIO read did not return and consume one word: %h count=%0d", value,
             pio_consume_count);
    end
    pio_valid_i = 1'b0;
    apb_read_error(32'h090);
    pio_rdata_i = 32'h5566_7788;
    pio_valid_i = 1'b1;
    apb_read(32'h090, value);
    if ((value != 32'h5566_7788) || (pio_consume_count != 2)) begin
      $fatal(1, "consecutive PIO read contract failed: %h count=%0d", value, pio_consume_count);
    end

    apb_read(Sdio0Base + `APB4_SDIO__IP_ID, value);
    if (value != 32'h5344_494F) $fatal(1, "SDIO0 base IP ID mismatch");
    apb_write(Sdio0Base + `APB4_SDIO__IRQ_ENABLE, 32'h0000_0001, 4'h1, 1'b0);
    apb_write(Sdio0Base + `APB4_SDIO__IRQ_TEST, 32'h0000_0001, 4'h1, 1'b0);
    apb_read(Sdio0Base + `APB4_SDIO__IRQ_STATUS, value);
    if ((value & 32'h1) == 0 || !irq_o) $fatal(1, "SDIO0 base IRQ test failed");
    apb_write(Sdio0Base + `APB4_SDIO__IRQ_STATUS, 32'h0000_0001, 4'h1, 1'b0);
    if (irq_o) $fatal(1, "SDIO0 base IRQ W1C failed");

    apb_read(Sdio1Base + `APB4_SDIO__IP_VERSION, value);
    if (value != 32'h0001_0000) $fatal(1, "SDIO1 base version mismatch");
    apb_write(Sdio1Base + `APB4_SDIO__IRQ_ENABLE, 32'h0000_0002, 4'h1, 1'b0);
    apb_write(Sdio1Base + `APB4_SDIO__IRQ_TEST, 32'h0000_0002, 4'h1, 1'b0);
    apb_read(Sdio1Base + `APB4_SDIO__IRQ_STATUS, value);
    if ((value & 32'h2) == 0 || !irq_o) $fatal(1, "SDIO1 base IRQ test failed");
    apb_write(Sdio1Base + `APB4_SDIO__IRQ_STATUS, 32'h0000_0002, 4'h1, 1'b0);
    if (irq_o) $fatal(1, "SDIO1 base IRQ W1C failed");

    $display("SDIO APB register test passed");
    $finish;
  end
endmodule
