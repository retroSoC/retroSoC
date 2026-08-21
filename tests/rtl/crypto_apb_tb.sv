`timescale 1ns / 1ps

module crypto_apb_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic dma_input_proc;
  logic dma_output_proc;
  logic irq_o;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
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

  apb4_crypto u_apb4_crypto (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .dma_input_proc_o (dma_input_proc),
      .dma_output_proc_o(dma_output_proc),
      .irq_o            (irq_o),
      .apb4             (apb4),
      .crypto_in_axis   (crypto_in_axis),
      .crypto_out_axis  (crypto_out_axis)
  );

  task automatic apb_write(input logic [11:0] offset, input logic [31:0] data,
                           input logic [3:0] strobe, input logic expected_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset};
      apb4.pwdata  = data;
      apb4.pstrb   = strobe;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error)) begin
        $fatal(1, "APB write %h ready/error mismatch", offset);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset, output logic [31:0] data,
                          input logic expected_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset};
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error)) begin
        $fatal(1, "APB read %h ready/error mismatch", offset);
      end
      data = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic wait_mask(input logic [11:0] offset, input logic [31:0] mask,
                           input logic [31:0] expected);
    logic [31:0] value;
    begin
      value = '0;
      while ((value & mask) != expected) begin
        apb_read(offset, value, 1'b0);
      end
    end
  endtask

  initial begin
    logic [31:0] value;

    apb4.paddr             = '0;
    apb4.pprot             = '0;
    apb4.psel              = 1'b0;
    apb4.penable           = 1'b0;
    apb4.pwrite            = 1'b0;
    apb4.pwdata            = '0;
    apb4.pstrb             = '0;
    crypto_in_axis.tdata   = '0;
    crypto_in_axis.tkeep   = '0;
    crypto_in_axis.tstrb   = '0;
    crypto_in_axis.tlast   = 1'b0;
    crypto_in_axis.tid     = '0;
    crypto_in_axis.tdest   = '0;
    crypto_in_axis.tuser   = '0;
    crypto_in_axis.tvalid  = 1'b0;
    crypto_out_axis.tready = 1'b0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    apb_read(12'h000, value, 1'b0);
    if (value != 32'h4352_5950) begin
      $fatal(1, "crypto IP ID mismatch");
    end
    apb_write(12'h01C, 32'h0000_001f, 4'hf, 1'b0);
    apb_write(12'h140, 32'h0302_0100, 4'hf, 1'b0);
    apb_write(12'h144, 32'h0706_0504, 4'hf, 1'b0);
    apb_write(12'h148, 32'h0b0a_0908, 4'hf, 1'b0);
    apb_write(12'h14c, 32'h0f0e_0d0c, 4'hf, 1'b0);
    apb_read(12'h140, value, 1'b1);
    apb_write(12'h104, 32'h0000_0000, 4'hf, 1'b0);
    apb_write(12'h128, 32'h0000_0001, 4'h1, 1'b0);
    wait_mask(12'h12c, 32'h1, 32'h1);
    apb_write(12'h10c, 32'd16, 4'hf, 1'b0);
    apb_write(12'h100, 32'h1, 4'h1, 1'b0);
    apb_write(12'h110, 32'h3322_1100, 4'hf, 1'b0);
    apb_write(12'h110, 32'h7766_5544, 4'hf, 1'b0);
    apb_write(12'h110, 32'hbbaa_9988, 4'hf, 1'b0);
    apb_write(12'h110, 32'hffee_ddcc, 4'hf, 1'b0);
    wait_mask(12'h118, 32'h2, 32'h2);
    apb_read(12'h114, value, 1'b0);
    if (value != 32'hd8e0_c469) $fatal(1, "AES output word 0 mismatch");
    apb_read(12'h114, value, 1'b0);
    if (value != 32'h3004_7b6a) $fatal(1, "AES output word 1 mismatch");
    apb_read(12'h114, value, 1'b0);
    if (value != 32'h80b7_cdd8) $fatal(1, "AES output word 2 mismatch");
    apb_read(12'h114, value, 1'b0);
    if (value != 32'h5ac5_b470) $fatal(1, "AES output word 3 mismatch");
    wait_mask(12'h018, 32'h1, 32'h1);
    if (!irq_o) $fatal(1, "AES completion did not assert IRQ");
    apb_write(12'h018, 32'h1, 4'h1, 1'b0);

    apb_write(12'h204, 32'h1, 4'hf, 1'b0);
    apb_write(12'h20c, 32'd3, 4'hf, 1'b0);
    apb_write(12'h210, 32'd0, 4'hf, 1'b0);
    apb_write(12'h200, 32'h1, 4'h1, 1'b0);
    apb_write(12'h214, 32'h0063_6261, 4'h7, 1'b0);
    wait_mask(12'h218, 32'h2, 32'h2);
    apb_read(12'h240, value, 1'b0);
    if (value != 32'hba78_16bf) $fatal(1, "SHA digest word 0 mismatch");
    apb_read(12'h25c, value, 1'b0);
    if (value != 32'hf200_15ad) $fatal(1, "SHA digest word 7 mismatch");
    wait_mask(12'h018, 32'h2, 32'h2);

    apb_write(12'h010, 32'h1, 4'h1, 1'b0);
    apb_read(12'h12c, value, 1'b0);
    if (value != 32'd0) $fatal(1, "zeroize did not invalidate AES key");
    wait_mask(12'h018, 32'h10, 32'h10);

    $display("Crypto APB register tests passed");
    $finish;
  end
endmodule
