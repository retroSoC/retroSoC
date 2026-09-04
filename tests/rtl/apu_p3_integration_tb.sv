// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p3_integration_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam logic [31:0] ImageBase = 32'h3000_0000;

  logic       clk_i = 1'b0;
  logic       rst_n_i = 1'b0;
  logic [1:0] owner_i = 2'd0;
  logic       quiesce_i = 1'b0;
  logic idle_o, irq_o;
  logic [31:0] image         [0:4095];
  logic        read_active_q;
  logic [31:0] read_addr_q;
  logic [7:0] read_len_q, read_beat_q;
  logic  [31:0] s_value;
  string        image_path;

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

  assign axi4.arready       = !read_active_q;
  assign axi4.rid           = 1'b0;
  assign axi4.rdata         = image[(read_addr_q-ImageBase)>>2];
  assign axi4.rresp         = 2'd0;
  assign axi4.rlast         = read_beat_q == read_len_q;
  assign axi4.ruser         = 1'b0;
  assign axi4.rvalid        = read_active_q;
  assign axi4.awready       = 1'b0;
  assign axi4.wready        = 1'b0;
  assign axi4.bid           = 1'b0;
  assign axi4.bresp         = 2'd0;
  assign axi4.buser         = 1'b0;
  assign axi4.bvalid        = 1'b0;

  assign dma_tx_axis.tdata  = 32'd0;
  assign dma_tx_axis.tkeep  = 4'hf;
  assign dma_tx_axis.tstrb  = 4'hf;
  assign dma_tx_axis.tlast  = 1'b0;
  assign dma_tx_axis.tid    = '0;
  assign dma_tx_axis.tdest  = '0;
  assign dma_tx_axis.tuser  = '0;
  assign dma_tx_axis.tvalid = 1'b0;
  assign dma_rx_axis.tready = 1'b1;
  assign i2s_tx_axis.tready = 1'b1;
  assign i2s_rx_axis.tdata  = 32'd0;
  assign i2s_rx_axis.tkeep  = 4'hf;
  assign i2s_rx_axis.tstrb  = 4'hf;
  assign i2s_rx_axis.tlast  = 1'b0;
  assign i2s_rx_axis.tid    = '0;
  assign i2s_rx_axis.tdest  = '0;
  assign i2s_rx_axis.tuser  = '0;
  assign i2s_rx_axis.tvalid = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q <= 1'b0;
      read_addr_q   <= 32'd0;
      read_len_q    <= 8'd0;
      read_beat_q   <= 8'd0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_len_q    <= axi4.arlen;
        read_beat_q   <= 8'd0;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          read_active_q <= 1'b0;
        end else begin
          read_addr_q <= read_addr_q + 32'd4;
          read_beat_q <= read_beat_q + 1'b1;
        end
      end
    end
  end

  apb4_apu u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .owner_i          (owner_i),
      .owner_lock_i     (1'b0),
      .quiesce_i        (quiesce_i),
      .resource_reset_i (1'b0),
      .bridge_epoch_i   (8'd0),
      .i2s_tx_underrun_i(1'b0),
      .i2s_rx_overrun_i (1'b0),
      .apb4             (apb4),
      .axi4             (axi4),
      .dma_tx_axis      (dma_tx_axis),
      .dma_rx_axis      (dma_rx_axis),
      .i2s_tx_axis      (i2s_tx_axis),
      .i2s_rx_axis      (i2s_rx_axis),
      .idle_o           (idle_o),
      .irq_o            (irq_o)
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i,
                           input logic expected_err_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.pprot   = 3'd0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = 4'hf;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr != expected_err_i) $fatal(1, "APU-P3 APB write response mismatch");
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.pprot   = 3'd0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pwdata  = 32'd0;
      apb4.pstrb   = 4'd0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "APU-P3 APB read failed");
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    if (!$value$plusargs("IMAGE=%s", image_path)) $fatal(1, "IMAGE plusarg missing");
    $readmemh(image_path, image);
    apb4.paddr   = 32'd0;
    apb4.pprot   = 3'd0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = 32'd0;
    apb4.pstrb   = 4'd0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    apb_write(`APB4_APU__READ_BASE, ImageBase, 1'b0);
    apb_write(`APB4_APU__READ_LIMIT, ImageBase + image[2] - 1'b1, 1'b0);
    apb_write(`APB4_APU__MC_IMAGE_ADDRESS, ImageBase, 1'b0);
    apb_write(`APB4_APU__MC_IMAGE_SIZE, image[2], 1'b0);
    apb_write(`APB4_APU__MC_EXPECTED_CRC, image[11], 1'b0);
    quiesce_i = 1'b1;
    apb_write(`APB4_APU__COMMAND, 32'h0000_0010, 1'b0);

    for (int unsigned poll = 0; poll < 10000; poll++) begin
      apb_read(`APB4_APU__MC_STATUS, s_value);
      if (s_value[1]) break;
      if (!s_value[0]) $fatal(1, "APU-P3 integrated load failed status=%h", s_value);
    end
    if (!s_value[1]) $fatal(1, "APU-P3 integrated load timed out");
    apb_read(`APB4_APU__MC_ABI, s_value);
    if (s_value != 32'h0001_0000) $fatal(1, "APU-P3 MC_ABI mismatch");
    apb_read(`APB4_APU__MC_BUILD_ID_LO, s_value);
    if (s_value != 32'h5566_7788) $fatal(1, "APU-P3 build ID low mismatch");
    apb_read(`APB4_APU__MC_BUILD_ID_HI, s_value);
    if (s_value != 32'h1122_3344) $fatal(1, "APU-P3 build ID high mismatch");
    apb_read(`APB4_APU__MC_LOCK, s_value);
    if (s_value != 32'd1) $fatal(1, "APU-P3 lock mismatch");
    apb_read(`APB4_APU__MC_LOAD_COUNT, s_value);
    if (s_value != 32'd1) $fatal(1, "APU-P3 load count mismatch");
    apb_read(`APB4_APU__IRQ_STATE, s_value);
    if (!s_value[`APB4_APU__IRQ_MICROCODE_LOAD_DONE]) $fatal(1, "APU-P3 load IRQ missing");
    apb_write(`APB4_APU__COMMAND, 32'h0000_0010, 1'b1);
    apb_write(`APB4_APU__STREAM_ROUTE, 32'd1, 1'b1);

    $display("APU-P3 APB, DMA, loader integration passed");
    $finish;
  end

  initial begin
    repeat (30000) @(posedge clk_i);
    $fatal(1, "APU-P3 integration timed out");
  end

  logic s_unused;
  assign s_unused = irq_o ^ ^axi4.awaddr ^ ^axi4.wdata ^ ^axi4.wstrb ^ axi4.wlast;
endmodule
