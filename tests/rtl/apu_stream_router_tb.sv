`timescale 1ns / 1ps

module apu_stream_router_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        flush_i = 1'b0;
  logic        counter_clear_i = 1'b0;
  logic        xrun_clear_i = 1'b0;
  logic        tx_route_apu_i = 1'b0;
  logic        rx_route_apu_i = 1'b0;
  logic        tx_session_active_i = 1'b0;
  logic        rx_session_active_i = 1'b0;
  logic [ 7:0] rx_high_watermark_i = 8'd0;
  logic [ 7:0] tx_low_watermark_i = 8'd0;
  logic        tx_underrun_i = 1'b0;
  logic        rx_overrun_i = 1'b0;
  logic [31:0] status_o;
  logic        input_watermark_evt_o;
  logic        output_watermark_evt_o;
  logic        stream_xrun_evt_o;
  logic        idle_o;
  logic        input_watermark_seen;
  logic        output_watermark_seen;

  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_rx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_rx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) apu_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) apu_rx_axis (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      input_watermark_seen  <= 1'b0;
      output_watermark_seen <= 1'b0;
    end else begin
      if (input_watermark_evt_o) input_watermark_seen <= 1'b1;
      if (output_watermark_evt_o) output_watermark_seen <= 1'b1;
    end
  end

  apu_stream_router u_dut (
      .clk_i,
      .rst_n_i,
      .flush_i,
      .counter_clear_i,
      .xrun_clear_i,
      .tx_route_apu_i,
      .rx_route_apu_i,
      .tx_session_active_i,
      .rx_session_active_i,
      .rx_high_watermark_i,
      .tx_low_watermark_i,
      .tx_underrun_i,
      .rx_overrun_i,
      .dma_tx_axis,
      .dma_rx_axis,
      .i2s_tx_axis,
      .i2s_rx_axis,
      .apu_tx_axis,
      .apu_rx_axis,
      .status_o,
      .input_watermark_evt_o,
      .output_watermark_evt_o,
      .stream_xrun_evt_o,
      .idle_o
  );

  task automatic push_apu_tx(input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      apu_tx_axis.tdata  = data_i;
      apu_tx_axis.tvalid = 1'b1;
      do @(posedge clk_i); while (!apu_tx_axis.tready);
      @(negedge clk_i);
      apu_tx_axis.tvalid = 1'b0;
    end
  endtask

  task automatic push_i2s_rx(input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      i2s_rx_axis.tdata  = data_i;
      i2s_rx_axis.tvalid = 1'b1;
      do @(posedge clk_i); while (!i2s_rx_axis.tready);
      @(negedge clk_i);
      i2s_rx_axis.tvalid = 1'b0;
    end
  endtask


  task automatic pop_i2s_tx(input logic [31:0] expected_i, input int unsigned stall_cycles_i);
    logic [31:0] held_data;
    begin
      i2s_tx_axis.tready = 1'b0;
      held_data          = i2s_tx_axis.tdata;
      repeat (stall_cycles_i) begin
        @(posedge clk_i);
        #1;
        if (!i2s_tx_axis.tvalid || (i2s_tx_axis.tdata != held_data)) begin
          $fatal(1, "TX payload changed under backpressure");
        end
      end
      if (held_data != expected_i) $fatal(1, "TX FIFO ordering mismatch");
      @(negedge clk_i);
      i2s_tx_axis.tready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      i2s_tx_axis.tready = 1'b0;
    end
  endtask

  task automatic pop_apu_rx(input logic [31:0] expected_i, input int unsigned stall_cycles_i);
    logic [31:0] held_data;
    begin
      apu_rx_axis.tready = 1'b0;
      held_data          = apu_rx_axis.tdata;
      repeat (stall_cycles_i) begin
        @(posedge clk_i);
        #1;
        if (!apu_rx_axis.tvalid || (apu_rx_axis.tdata != held_data)) begin
          $fatal(1, "RX payload changed under backpressure");
        end
      end
      if (held_data != expected_i) $fatal(1, "RX FIFO ordering mismatch");
      @(negedge clk_i);
      apu_rx_axis.tready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      apu_rx_axis.tready = 1'b0;
    end
  endtask

  initial begin
    dma_tx_axis.tdata  = 32'h1122_3344;
    dma_tx_axis.tkeep  = 4'hf;
    dma_tx_axis.tstrb  = 4'hf;
    dma_tx_axis.tlast  = 1'b1;
    dma_tx_axis.tid    = '0;
    dma_tx_axis.tdest  = '0;
    dma_tx_axis.tuser  = '0;
    dma_tx_axis.tvalid = 1'b0;
    dma_rx_axis.tready = 1'b1;
    i2s_tx_axis.tready = 1'b1;
    i2s_rx_axis.tdata  = 32'd0;
    i2s_rx_axis.tkeep  = 4'hf;
    i2s_rx_axis.tstrb  = 4'hf;
    i2s_rx_axis.tlast  = 1'b0;
    i2s_rx_axis.tid    = '0;
    i2s_rx_axis.tdest  = '0;
    i2s_rx_axis.tuser  = '0;
    i2s_rx_axis.tvalid = 1'b0;
    apu_tx_axis.tdata  = 32'd0;
    apu_tx_axis.tkeep  = 4'hf;
    apu_tx_axis.tstrb  = 4'hf;
    apu_tx_axis.tlast  = 1'b0;
    apu_tx_axis.tid    = '0;
    apu_tx_axis.tdest  = '0;
    apu_tx_axis.tuser  = '0;
    apu_tx_axis.tvalid = 1'b0;
    apu_rx_axis.tready = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    #1;
    if ((status_o != 32'h0000_0014) || !idle_o) $fatal(1, "stream reset status mismatch");

    dma_tx_axis.tvalid = 1'b1;
    #1;
    if (!i2s_tx_axis.tvalid || (i2s_tx_axis.tdata != 32'h1122_3344) || !dma_tx_axis.tready)
      $fatal(1, "central DMA TX bypass failed");
    dma_tx_axis.tvalid = 1'b0;
    i2s_rx_axis.tdata  = 32'haabb_ccdd;
    i2s_rx_axis.tvalid = 1'b1;
    #1;
    if (!dma_rx_axis.tvalid || (dma_rx_axis.tdata != 32'haabb_ccdd) || !i2s_rx_axis.tready)
      $fatal(1, "central DMA RX bypass failed");
    i2s_rx_axis.tvalid  = 1'b0;

    tx_route_apu_i      = 1'b1;
    rx_route_apu_i      = 1'b1;
    tx_session_active_i = 1'b1;
    rx_session_active_i = 1'b1;
    tx_low_watermark_i  = 8'd2;
    rx_high_watermark_i = 8'd2;
    i2s_tx_axis.tready  = 1'b0;
    push_apu_tx(32'd1);
    push_apu_tx(32'd2);
    push_apu_tx(32'd3);
    if (!status_o[0]) $fatal(1, "APU TX route did not become active");
    i2s_tx_axis.tready = 1'b1;
    @(posedge clk_i);
    #1;
    if (!output_watermark_seen) $fatal(1, "TX low-watermark crossing was not detected");

    push_i2s_rx(32'h1010_1010);
    push_i2s_rx(32'h2020_2020);
    if (!input_watermark_seen) $fatal(1, "RX high-watermark crossing was not detected");
    apu_rx_axis.tready = 1'b1;
    repeat (2) @(posedge clk_i);

    @(negedge clk_i);
    flush_i = 1'b1;
    @(negedge clk_i);
    flush_i            = 1'b0;
    i2s_tx_axis.tready = 1'b0;
    apu_rx_axis.tready = 1'b0;
    for (int unsigned word_index = 0; word_index < 64; word_index++) begin
      push_apu_tx(32'h7100_0000 + word_index);
    end
    #1;
    if (!status_o[3] || apu_tx_axis.tready) $fatal(1, "TX FIFO did not reach depth 64");
    for (int unsigned word_index = 0; word_index < 64; word_index++) begin
      pop_i2s_tx(32'h7100_0000 + word_index, (word_index * 5 + 1) % 4);
    end
    #1;
    if (!status_o[2] || (status_o[15:8] != 8'd64)) begin
      $fatal(1, "TX FIFO empty/count status mismatch");
    end

    for (int unsigned word_index = 0; word_index < 64; word_index++) begin
      push_i2s_rx(32'h7200_0000 + word_index);
    end
    #1;
    if (!status_o[5] || i2s_rx_axis.tready) $fatal(1, "RX FIFO did not reach depth 64");
    for (int unsigned word_index = 0; word_index < 64; word_index++) begin
      pop_apu_rx(32'h7200_0000 + word_index, (word_index * 7 + 2) % 5);
    end
    #1;
    if (!status_o[4] || (status_o[23:16] != 8'd64)) begin
      $fatal(1, "RX FIFO empty/count status mismatch");
    end
    counter_clear_i = 1'b1;
    @(posedge clk_i);
    counter_clear_i = 1'b0;
    #1;
    if (status_o[23:8] != 16'd0) $fatal(1, "stream counter clear failed");

    tx_underrun_i = 1'b1;
    rx_overrun_i  = 1'b1;
    #1;
    if (!stream_xrun_evt_o) $fatal(1, "xrun event pulse failed");
    @(posedge clk_i);
    tx_underrun_i = 1'b0;
    rx_overrun_i  = 1'b0;
    #1;
    if (status_o[7:6] != 2'b11) $fatal(1, "xrun capture failed");
    xrun_clear_i  = 1'b1;
    tx_underrun_i = 1'b1;
    @(posedge clk_i);
    xrun_clear_i  = 1'b0;
    tx_underrun_i = 1'b0;
    #1;
    if (!status_o[6]) $fatal(1, "hardware xrun did not win same-cycle clear");

    $display("APU-P2 stream router tests passed");
    $finish;
  end

  initial begin
    repeat (5000) @(posedge clk_i);
    $fatal(1, "APU-P2 stream router timed out");
  end
endmodule
