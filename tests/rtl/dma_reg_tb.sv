`timescale 1ns / 1ps

module dma_reg_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic irq_o;
  logic xpi_done_o;
  logic read_active_q = 1'b0;
  logic write_active_q = 1'b0;
  logic write_response_q = 1'b0;
  logic allow_write_response = 1'b0;

  dma_req_if req ();
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if i2s_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if i2s_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if dvp_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if crypto_in_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if crypto_out_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  assign axi4.arready           = !read_active_q;
  assign axi4.rid               = '0;
  assign axi4.rdata             = 32'hC0DE_0001;
  assign axi4.rresp             = `AXI4_RESP_OKAY;
  assign axi4.rlast             = 1'b1;
  assign axi4.ruser             = '0;
  assign axi4.rvalid            = read_active_q;
  assign axi4.awready           = !write_active_q && !write_response_q;
  assign axi4.wready            = write_active_q;
  assign axi4.bid               = '0;
  assign axi4.bresp             = `AXI4_RESP_OKAY;
  assign axi4.buser             = '0;
  assign axi4.bvalid            = write_response_q && allow_write_response;
  assign i2s_tx_axis.tready     = 1'b0;
  assign i2s_rx_axis.tdata      = '0;
  assign i2s_rx_axis.tkeep      = '0;
  assign i2s_rx_axis.tstrb      = '0;
  assign i2s_rx_axis.tlast      = 1'b0;
  assign i2s_rx_axis.tid        = '0;
  assign i2s_rx_axis.tdest      = '0;
  assign i2s_rx_axis.tuser      = '0;
  assign i2s_rx_axis.tvalid     = 1'b0;
  assign dvp_rx_axis.tdata      = '0;
  assign dvp_rx_axis.tkeep      = '0;
  assign dvp_rx_axis.tstrb      = '0;
  assign dvp_rx_axis.tlast      = 1'b0;
  assign dvp_rx_axis.tid        = '0;
  assign dvp_rx_axis.tdest      = '0;
  assign dvp_rx_axis.tuser      = '0;
  assign dvp_rx_axis.tvalid     = 1'b0;
  assign crypto_in_axis.tready  = 1'b0;
  assign crypto_out_axis.tdata  = '0;
  assign crypto_out_axis.tkeep  = '0;
  assign crypto_out_axis.tstrb  = '0;
  assign crypto_out_axis.tlast  = 1'b0;
  assign crypto_out_axis.tid    = '0;
  assign crypto_out_axis.tdest  = '0;
  assign crypto_out_axis.tuser  = '0;
  assign crypto_out_axis.tvalid = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q    <= 1'b0;
      write_active_q   <= 1'b0;
      write_response_q <= 1'b0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        if (axi4.arlen != 8'd0) begin
          $fatal(1, "register-directed transfer unexpectedly burst");
        end
        read_active_q <= 1'b1;
      end
      if (axi4.rvalid && axi4.rready) begin
        read_active_q <= 1'b0;
      end
      if (axi4.awvalid && axi4.awready) begin
        if (axi4.awlen != 8'd0) begin
          $fatal(1, "register-directed transfer unexpectedly burst");
        end
        write_active_q <= 1'b1;
      end
      if (axi4.wvalid && axi4.wready) begin
        if (!axi4.wlast || (axi4.wdata != 32'hC0DE_0001)) begin
          $fatal(1, "DMA register transfer write data mismatch");
        end
        write_active_q   <= 1'b0;
        write_response_q <= 1'b1;
      end
      if (axi4.bvalid && axi4.bready) begin
        write_response_q <= 1'b0;
      end
    end
  end

  apb4_dma u_apb4_dma (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_o(xpi_done_o),
      .irq_o          (irq_o),
      .hw_trg         (req),
      .apb4           (apb4),
      .axi4           (axi4),
      .i2s_tx_axis    (i2s_tx_axis),
      .i2s_rx_axis    (i2s_rx_axis),
      .dvp_rx_axis    (dvp_rx_axis),
      .crypto_in_axis (crypto_in_axis),
      .crypto_out_axis(crypto_out_axis)
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
      #1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr != expected_error) begin
        $fatal(1, "APB write %h PSLVERR=%b expected=%b", address, apb4.pslverr, expected_error);
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
      #1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) begin
        $fatal(1, "APB read %h unexpectedly failed", address);
      end
      data = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] value;

    apb4.paddr          = '0;
    apb4.pprot          = '0;
    apb4.psel           = 1'b0;
    apb4.penable        = 1'b0;
    apb4.pwrite         = 1'b0;
    apb4.pwdata         = '0;
    apb4.pstrb          = '0;
    req.i2s_tx_proc     = 1'b1;
    req.i2s_rx_proc     = 1'b1;
    req.qspi_tx_proc    = 1'b1;
    req.qspi_rx_proc    = 1'b1;
    req.uart_tx_proc    = 1'b1;
    req.uart_rx_proc    = 1'b1;
    req.i2c0_tx_proc    = 1'b1;
    req.i2c0_rx_proc    = 1'b1;
    req.i2c1_tx_proc    = 1'b1;
    req.i2c1_rx_proc    = 1'b1;
    req.crypto_in_proc  = 1'b1;
    req.crypto_out_proc = 1'b1;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    apb_read(32'h000, value);
    if (value != 32'h444D_4134) begin
      $fatal(1, "DMA IP identification mismatch");
    end
    apb_read(32'h004, value);
    if (value != 32'h0002_0000) begin
      $fatal(1, "DMA V2 version mismatch: %h", value);
    end
    apb_read(32'h008, value);
    if ((value[0] != 1'b1) || (value[15:8] != 8'd4)) begin
      $fatal(1, "DMA capability descriptor/channel mismatch: %h", value);
    end
    apb_write(32'h2C8, 32'h4000_8000, 4'hF, 1'b0);
    apb_write(32'h2CC, 32'h0000_0001, 4'hF, 1'b0);
    apb_write(32'h2D0, 32'h1234_5678, 4'hF, 1'b0);
    apb_read(32'h2C8, value);
    if (value != 32'h4000_8000) begin
      $fatal(1, "DMA TCD head register mismatch: %h", value);
    end
    apb_read(32'h2D0, value);
    if (value != 32'h1234_5678) begin
      $fatal(1, "DMA CRC expected register mismatch: %h", value);
    end
    apb_write(32'h02c, 32'h1, 4'hF, 1'b1);
    apb_write(32'h104, 32'h0000_0160, 4'h1, 1'b0);
    apb_write(32'h108, 32'h4000_0000, 4'hF, 1'b0);
    apb_write(32'h10c, 32'h4000_1000, 4'hF, 1'b0);
    apb_write(32'h110, 32'h0000_0004, 4'hF, 1'b0);
    apb_write(32'h114, 32'h0000_0000, 4'hF, 1'b0);
    apb_write(32'h118, 32'h0000_0001, 4'hF, 1'b0);
    apb_write(32'h11c, 32'h0000_0007, 4'hF, 1'b0);
    apb_write(32'h018, 32'h0000_0001, 4'hF, 1'b0);
    apb_write(32'h100, 32'h0000_0001, 4'h1, 1'b0);

    wait (write_response_q);
    apb_write(32'h110, 32'h0000_0008, 4'hF, 1'b1);
    apb_write(32'h100, 32'h0000_0010, 4'h1, 1'b1);
    apb_write(32'h00c, 32'h0000_0001, 4'h1, 1'b1);
    apb_write(32'h100, 32'h0000_0001, 4'h2, 1'b1);
    allow_write_response = 1'b1;
    wait (!write_response_q);
    repeat (2) @(posedge clk_i);
    apb_read(32'h120, value);
    if ((value & 32'h0000_0005) != 32'h0000_0004) begin
      $fatal(1, "DMA status did not report a completed, idle transfer: %h", value);
    end
    apb_read(32'h124, value);
    if (((value & 32'h1) == 32'd0) || !irq_o) begin
      $fatal(1, "DMA done event did not assert the aggregate IRQ");
    end
    apb_write(32'h124, 32'h0000_0007, 4'h2, 1'b1);
    if (!irq_o) begin
      $fatal(1, "DMA event clear ignored unsupported PSTRB");
    end
    apb_write(32'h124, 32'h0000_0007, 4'h1, 1'b0);
    repeat (1) @(posedge clk_i);
    if (irq_o) begin
      $fatal(1, "DMA W1C event clear did not lower the aggregate IRQ");
    end
    apb_write(32'h00c, 32'h0000_0001, 4'h1, 1'b0);

    $display("DMA APB register and aggregate IRQ test passed");
    $finish;
  end
endmodule
