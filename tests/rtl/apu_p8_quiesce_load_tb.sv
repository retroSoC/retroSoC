// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// APU-P8 quiesced loader admission regression: with quiesce_i asserted, the
// owner LP, and the core idle, both COMMAND.MICROCODE_LOAD and
// COMMAND.MODEL_LOAD must be admitted and run to completion WITHOUT quiesce
// ever being released. The pre-fix apb4_apu quiesce term
// (s_dma_admission_block && s_mc_idle) kept apu_dma quiesced while the KWS
// model loader was busy, so its fetch DMA never issued a beat and the load
// hung until the firmware poll budget expired (HAL RS_ETIMEOUT). This bench
// fails closed on the fixed design if either load stalls, if the completion
// state/CRC is wrong, or if the image bytes did not cross the AXI read channel
// while quiesce was held.

`include "apu_define.svh"

module apu_p8_quiesce_load_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam logic [31:0] ImageBase = 32'h3000_0000;
  localparam logic [31:0] ModelBase = 32'h3001_0000;
  localparam logic [31:0] ModelBytes = 32'd32768;
  localparam logic [63:0] MaxCycles = 64'd2000000;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        quiesce_q;
  logic [31:0] image          [0:16383];
  logic [31:0] model          [ 0:8191];
  logic        read_active_q;
  logic [31:0] read_addr_q;
  logic [7:0] read_len_q, read_beat_q;
  logic [63:0] cycle_q;
  logic [63:0] quiesced_beats_q;
  logic [63:0] beats_before;
  logic [31:0] s_value;

  string apumc_path, apum_path;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  // Ready-memory AXI read model: no injected stalls, back-to-back beats.
  assign axi4.arready = !read_active_q;
  assign axi4.rid = 1'b0;
  assign axi4.rdata   = (read_addr_q >= ModelBase) ? model[(read_addr_q-ModelBase)>>2] :
      image[(read_addr_q-ImageBase)>>2];
  assign axi4.rresp = 2'd0;
  assign axi4.rlast = read_beat_q == read_len_q;
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = read_active_q;
  assign axi4.awready = 1'b1;
  assign axi4.wready = 1'b0;
  assign axi4.bid = 1'b0;
  assign axi4.bresp = 2'd0;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = 1'b0;

  assign dma_tx_axis.tdata = 32'd0;
  assign dma_tx_axis.tkeep = 4'hf;
  assign dma_tx_axis.tstrb = 4'hf;
  assign dma_tx_axis.tlast = 1'b0;
  assign dma_tx_axis.tid = '0;
  assign dma_tx_axis.tdest = '0;
  assign dma_tx_axis.tuser = '0;
  assign dma_tx_axis.tvalid = 1'b0;
  assign dma_rx_axis.tready = 1'b1;

  assign i2s_tx_axis.tready = 1'b1;

  assign i2s_rx_axis.tdata = 32'd0;
  assign i2s_rx_axis.tkeep = 4'hf;
  assign i2s_rx_axis.tstrb = 4'hf;
  assign i2s_rx_axis.tlast = 1'b0;
  assign i2s_rx_axis.tid = '0;
  assign i2s_rx_axis.tdest = '0;
  assign i2s_rx_axis.tuser = '0;
  assign i2s_rx_axis.tvalid = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q    <= 1'b0;
      read_addr_q      <= 32'd0;
      read_len_q       <= 8'd0;
      read_beat_q      <= 8'd0;
      cycle_q          <= 64'd0;
      quiesced_beats_q <= 64'd0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_len_q    <= axi4.arlen;
        read_beat_q   <= 8'd0;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (quiesce_q) quiesced_beats_q <= quiesced_beats_q + 1'b1;
        if (axi4.rlast) read_active_q <= 1'b0;
        else begin
          read_addr_q <= read_addr_q + 32'd4;
          read_beat_q <= read_beat_q + 1'b1;
        end
      end
      if (axi4.awvalid && axi4.awready)
        $fatal(1, "P8 quiesce load unexpected AXI write %h", axi4.awaddr);
    end
  end

  apb4_apu #(
      .EnableP7(1'b1)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .owner_i            (2'd0),
      .owner_lock_i       (1'b0),
      .quiesce_i          (quiesce_q),
      .resource_reset_i   (1'b0),
      .bridge_epoch_i     (8'd0),
      .i2s_tx_underrun_i  (1'b0),
      .i2s_rx_overrun_i   (1'b0),
      .i2s_rx_flush_busy_i(1'b0),
      .apb4,
      .axi4,
      .dma_tx_axis,
      .dma_rx_axis,
      .i2s_tx_axis,
      .i2s_rx_axis,
      .idle_o             (),
      .irq_o              ()
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = 4'hf;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "P8 quiesce load APB write %h = %h failed", offset_i, value_i);
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = 4'd0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "P8 quiesce load APB read failed %h", offset_i);
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    if (!$value$plusargs("APUMC_HEX=%s", apumc_path)) $fatal(1, "APUMC_HEX plusarg missing");
    if (!$value$plusargs("APUM_HEX=%s", apum_path)) $fatal(1, "APUM_HEX plusarg missing");
    $readmemh(apumc_path, image);
    $readmemh(apum_path, model);

    apb4.paddr   = 32'd0;
    apb4.pprot   = 3'd0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = 32'd0;
    apb4.pstrb   = 4'd0;
    // Quiesce is asserted before reset release and is never deasserted: the
    // whole scenario runs under the frozen LP quiesce discipline.
    quiesce_q    = 1'b1;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    // LP-owned, quiesced, idle: the exact state the frozen release flow loads in.
    apb_read(`APB4_APU__OWNER_STATUS, s_value);
    if ((s_value[`APB4_APU__OWNER_STATUS_OWNER+1:`APB4_APU__OWNER_STATUS_OWNER] != 2'd0) ||
        !s_value[`APB4_APU__OWNER_STATUS_QUIESCE] || s_value[`APB4_APU__OWNER_STATUS_RESET])
      $fatal(1, "P8 quiesce load owner state mismatch %h", s_value);
    apb_read(`APB4_APU__STATUS, s_value);
    if (!s_value[`APB4_APU__STATUS_IDLE]) $fatal(1, "P8 quiesce load core not idle %h", s_value);

    apb_write(`APB4_APU__READ_BASE, ImageBase);
    apb_write(`APB4_APU__READ_LIMIT, ModelBase + ModelBytes - 32'd1);

    // MICROCODE_LOAD under quiesce: the microcode loader was always exempt
    // from the DMA quiesce while it is itself busy; this leg must keep working.
    apb_write(`APB4_APU__MC_IMAGE_ADDRESS, ImageBase);
    apb_write(`APB4_APU__MC_IMAGE_SIZE, image[2]);
    apb_write(`APB4_APU__MC_EXPECTED_CRC, image[11]);
    beats_before = quiesced_beats_q;
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MICROCODE_LOAD);
    for (int poll = 0; poll < 200000; poll++) begin
      apb_read(`APB4_APU__MC_STATUS, s_value);
      if (s_value[`APB4_APU__MC_STATUS_VALID]) break;
      if (!s_value[`APB4_APU__MC_STATUS_BUSY])
        $fatal(1, "P8 quiesce load microcode load failed %h", s_value);
    end
    if (!s_value[`APB4_APU__MC_STATUS_VALID])
      $fatal(1, "P8 quiesce load microcode load timeout (DMA not admitted under quiesce)");
    apb_read(`APB4_APU__MC_LOCK, s_value);
    if (!s_value[`APB4_APU__MC_LOCK_LOCKED]) $fatal(1, "P8 quiesce load microcode not locked");
    apb_read(`APB4_APU__MC_ACTUAL_CRC, s_value);
    if (s_value != image[11])
      $fatal(1, "P8 quiesce load microcode CRC mismatch actual=%h expected=%h", s_value, image[11]);
    if (quiesced_beats_q - beats_before < {32'd0, image[2]} >> 2)
      $fatal(
          1,
          "P8 quiesce load microcode bytes did not cross AXI under quiesce beats=%0d",
          quiesced_beats_q - beats_before
      );
    $display("P8_QUIESCE_MC crc=%h beats=%0d", s_value, quiesced_beats_q - beats_before);

    apb_read(`APB4_APU__STATUS, s_value);
    if (!s_value[`APB4_APU__STATUS_IDLE])
      $fatal(1, "P8 quiesce load core not idle before model load %h", s_value);

    // MODEL_LOAD under quiesce: the APU-P8 regression. Before the apb4_apu fix
    // the KWS model loader's fetch DMA stayed quiesced here and the load never
    // completed; the fixed admission term lets it run while quiesce holds.
    apb_write(`APB4_APU__KWS_MODEL_ADDRESS, ModelBase);
    apb_write(`APB4_APU__KWS_MODEL_SIZE, ModelBytes);
    apb_write(`APB4_APU__KWS_MODEL_EXPECTED_CRC, `APB4_APU__APUM_PAYLOAD_CRC);
    beats_before = quiesced_beats_q;
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MODEL_LOAD);
    for (int poll = 0; poll < 200000; poll++) begin
      apb_read(`APB4_APU__KWS_MODEL_STATUS, s_value);
      if (!s_value[0]) break;
    end
    if (s_value[0])
      $fatal(1, "P8 quiesce load model load timeout (loader DMA not admitted under quiesce)");
    if (s_value != 32'h0000_0006) begin
      apb_read(`APB4_APU__ERROR_STATUS, s_value);
      $display("P8 quiesce load model load error status=%h", s_value);
      apb_read(`APB4_APU__ERROR_DETAIL, s_value);
      $fatal(1, "P8 quiesce load model load failed detail=%h", s_value);
    end
    apb_read(`APB4_APU__KWS_MODEL_ACTUAL_CRC, s_value);
    if (s_value != `APB4_APU__APUM_PAYLOAD_CRC)
      $fatal(1, "P8 quiesce load model CRC mismatch actual=%h", s_value);
    if (quiesced_beats_q - beats_before < ModelBytes >> 2)
      $fatal(
          1,
          "P8 quiesce load model bytes did not cross AXI under quiesce beats=%0d",
          quiesced_beats_q - beats_before
      );
    $display("P8_QUIESCE_MODEL crc=%h beats=%0d", s_value, quiesced_beats_q - beats_before);

    // Quiesce was never released: the owner view must still show LP+quiesce and
    // the core must be idle with clean error state.
    apb_read(`APB4_APU__OWNER_STATUS, s_value);
    if ((s_value[`APB4_APU__OWNER_STATUS_OWNER+1:`APB4_APU__OWNER_STATUS_OWNER] != 2'd0) ||
        !s_value[`APB4_APU__OWNER_STATUS_QUIESCE] || s_value[`APB4_APU__OWNER_STATUS_RESET])
      $fatal(1, "P8 quiesce load final owner state mismatch %h", s_value);
    apb_read(`APB4_APU__STATUS, s_value);
    if (!s_value[`APB4_APU__STATUS_IDLE]) $fatal(1, "P8 quiesce load core busy at end %h", s_value);
    apb_read(`APB4_APU__ERROR_STATUS, s_value);
    if (s_value != 32'd0) $fatal(1, "P8 quiesce load first-error status set %h", s_value);

    $display("APU-P8 quiesced loader admission test passed");
    $finish;
  end

  initial begin
    wait (cycle_q > MaxCycles);
    $fatal(1, "P8 quiesce load global timeout");
  end

endmodule
