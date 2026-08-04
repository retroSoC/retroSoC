`timescale 1ns / 1ps

module dma_error_tb;
  localparam logic [1:0] MODEL_IDLE = 2'd0;
  localparam logic [1:0] MODEL_WDATA = 2'd1;
  localparam logic [1:0] MODEL_RESP = 2'd2;

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
  integer        incr4_read_count = 0;
  integer        incr4_write_count = 0;
  integer        legacy_cycles;
  integer        burst_cycles;
  logic   [ 1:0] model_state_q = MODEL_IDLE;
  logic   [ 1:0] model_len_q = '0;
  logic   [ 1:0] model_beat_q = '0;
  logic          model_write_q = 1'b0;
  logic          model_error_q = 1'b0;
  dma_hw_trg_if hw_trg ();
  rib_if rib ();

  always #5 clk_i = ~clk_i;

  assign rib.cmd_ready = model_state_q == MODEL_IDLE;
  assign rib.w_ready   = model_state_q == MODEL_WDATA;
  assign rib.rsp_valid = model_state_q == MODEL_RESP;
  assign rib.rdata     = 32'hA5A5_5A5A + model_beat_q;
  assign rib.resp_err  = model_error_q;
  assign rib.resp_code = model_error_q ? `RIB_RESP_DECERR : `RIB_RESP_OK;
  assign rib.rsp_beat  = model_beat_q;
  assign rib.rsp_last  = model_write_q || model_error_q || (model_beat_q == model_len_q);

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      model_state_q <= MODEL_IDLE;
      model_len_q   <= '0;
      model_beat_q  <= '0;
      model_write_q <= 1'b0;
      model_error_q <= 1'b0;
      write_count   <= 0;
    end else begin
      unique case (model_state_q)
        MODEL_IDLE: begin
          if (rib.cmd_valid && rib.cmd_ready) begin
            model_len_q   <= rib.cmd_len;
            model_beat_q  <= '0;
            model_write_q <= rib.cmd_write;
            model_error_q <= error_mode && !rib.cmd_write;
            model_state_q <= rib.cmd_write ? MODEL_WDATA : MODEL_RESP;
            if (rib.cmd_len == `RIB_LEN_INCR4 && rib.cmd_write) begin
              incr4_write_count <= incr4_write_count + 1;
            end
            if (rib.cmd_len == `RIB_LEN_INCR4 && !rib.cmd_write) begin
              incr4_read_count <= incr4_read_count + 1;
            end
          end
        end
        MODEL_WDATA: begin
          if (rib.w_valid && rib.w_ready) begin
            write_count <= write_count + 1;
            if (rib.wlast) begin
              model_beat_q  <= model_len_q;
              model_state_q <= MODEL_RESP;
            end else begin
              model_beat_q <= model_beat_q + 1'b1;
            end
          end
        end
        MODEL_RESP: begin
          if (rib.rsp_valid && rib.rsp_ready) begin
            if (rib.rsp_last) begin
              model_state_q <= MODEL_IDLE;
            end else begin
              model_beat_q <= model_beat_q + 1'b1;
            end
          end
        end
        default: model_state_q <= MODEL_IDLE;
      endcase
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
      .rib         (rib)
  );

  task automatic start_transfer;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic measure_transfer(output integer elapsed);
    begin
      start_transfer();
      elapsed = 0;
      while (!done_o) begin
        @(posedge clk_i);
        elapsed = elapsed + 1;
      end
      @(negedge clk_i);
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
    if (error_code_o !== `RIB_RESP_DECERR || error_addr_o !== srcaddr_i) begin
      $fatal(1, "DMA error response was not propagated");
    end
    if (write_count != 1) begin
      $fatal(1, "DMA issued a write after a read error");
    end

    error_mode = 1'b0;
    xferlen_i  = 32'd8;
    srcincr_i  = 1'b0;
    dstincr_i  = 1'b1;
    measure_transfer(legacy_cycles);

    srcincr_i = 1'b1;
    measure_transfer(burst_cycles);
    if (incr4_read_count != 2 || incr4_write_count != 2) begin
      $fatal(1, "aligned eight-word transfer did not use two INCR4 chunks");
    end
    if ((burst_cycles * 3) > (legacy_cycles * 2)) begin
      $fatal(1, "INCR4 DMA speedup is below 1.5x: legacy=%0d burst=%0d", legacy_cycles,
             burst_cycles);
    end

    srcaddr_i = 32'h1000_0000;
    dstaddr_i = 32'h1000_1000;
    measure_transfer(legacy_cycles);
    if (incr4_read_count != 2 || incr4_write_count != 2) begin
      $fatal(1, "DMA did not fall back to INCR1 for a register window");
    end

    $display("dma error and burst performance test passed");
    $finish;
  end
endmodule
