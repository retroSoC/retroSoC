`timescale 1ns / 1ps

module dma_error_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic   [ 2:0] mode_i = 3'd0;
  logic   [31:0] srcaddr_i = 32'h3800_1000;
  logic          srcincr_i = 1'b1;
  logic   [31:0] dstaddr_i = 32'h4000_1000;
  logic          dstincr_i = 1'b1;
  logic   [31:0] xferlen_i = 32'd1;
  logic          start_i = 1'b0;
  logic          stop_i = 1'b0;
  logic          reset_i = 1'b0;
  logic          done_o;
  logic          error_o;
  logic   [ 2:0] error_code_o;
  logic   [31:0] error_addr_o;
  logic   [ 1:0] fsm_o;
  logic          error_mode = 1'b0;
  integer        write_count = 0;
  dma_hw_trg_if hw_trg ();
  soc_nmi_if nmi ();

  always #5 clk_i = ~clk_i;

  assign nmi.ready     = nmi.valid;
  assign nmi.rdata     = 32'hA5A5_5A5A;
  assign nmi.resp_err  = error_mode && nmi.valid;
  assign nmi.resp_code = error_mode ? `SOC_NMI_RESP_DECERR : `SOC_NMI_RESP_OK;

  always @(posedge clk_i) begin
    if (nmi.valid && nmi.ready && (|nmi.wstrb)) begin
      write_count <= write_count + 1;
    end
  end

  dma_core u_dma_core (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .mode_i      (mode_i),
      .srcaddr_i   (srcaddr_i),
      .srcincr_i   (srcincr_i),
      .dstaddr_i   (dstaddr_i),
      .dstincr_i   (dstincr_i),
      .xferlen_i   (xferlen_i),
      .start_i     (start_i),
      .stop_i      (stop_i),
      .reset_i     (reset_i),
      .done_o      (done_o),
      .error_o     (error_o),
      .error_code_o(error_code_o),
      .error_addr_o(error_addr_o),
      .fsm_o       (fsm_o),
      .hw_trg      (hw_trg),
      .nmi         (nmi)
  );

  task automatic start_transfer;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  initial begin
    hw_trg.i2s_tx_proc  = 1'b0;
    hw_trg.i2s_rx_proc  = 1'b0;
    hw_trg.qspi_tx_proc = 1'b0;
    hw_trg.qspi_rx_proc = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    start_transfer();
    wait (done_o);
    @(negedge clk_i);
    if (write_count != 1) begin
      $fatal(1, "one-word DMA transfer issued %0d writes", write_count);
    end

    error_mode = 1'b1;
    start_transfer();
    wait (error_o);
    @(negedge clk_i);
    if (error_code_o !== `SOC_NMI_RESP_DECERR || error_addr_o !== srcaddr_i) begin
      $fatal(1, "DMA error response was not propagated");
    end
    if (write_count != 1) begin
      $fatal(1, "DMA issued a write after a read error");
    end

    $display("dma error responder test passed");
    $finish;
  end
endmodule
