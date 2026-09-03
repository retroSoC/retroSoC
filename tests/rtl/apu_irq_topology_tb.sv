`timescale 1ns / 1ps

`include "apu_define.svh"
`include "soc_irq_config.svh"

module apu_irq_topology_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam logic [11:0] Resource7Owner = 12'h1e0;
  localparam logic [11:0] Resource7Control = 12'h1e4;
  localparam logic [11:0] Resource7Fault = 12'h1ec;

  logic                                       clk_i = 1'b0;
  logic                                       rst_n_i = 1'b0;
  logic                                       s_apu_idle;
  logic                                       s_apu_irq_raw;
  logic [                           7:0]      s_resource_idle;
  logic [                           7:0]      s_resource_block_ack;
  logic [                           7:0]      s_resource_irq_raw;
  logic [                           7:0][1:0] s_resource_owner;
  logic [                           7:0]      s_resource_owner_lock;
  logic [                           7:0]      s_resource_quiesce;
  logic [                           7:0]      s_resource_reset;
  logic [                           7:0]      s_resource_irq_lp;
  logic [                           7:0]      s_resource_irq_hp;
  logic [                           6:0]      s_resource_irq_lp_compact;
  logic [                           6:0]      s_resource_irq_hp_compact;
  logic                                       s_resource_fault_irq;
  logic                                       s_cache_clean;
  logic [`SOC_IRQ_APB4_PERIPH_WIDTH-1:0]      s_apb4_periph_irq;
  logic [`SOC_IRQ_APB4_SYSTEM_WIDTH-1:0]      s_apb4_system_irq;
  logic [     `SOC_IRQ_VECTOR_WIDTH-1:0]      s_irq;
  logic [                          31:0]      s_hp_plic_source;
  logic [                           1:0]      s_hp_plic_context_irq;
  logic [                          31:0]      s_value;

  apb4_if u_apu_apb4_if (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if u_resource_apb4_if (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if u_plic_apb4_if (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_apu_axi4_if (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dma_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dma_rx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_tx_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_rx_axis (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;

  assign s_resource_idle = {s_apu_idle, 7'h7f};
  assign s_resource_block_ack = {
    s_apu_idle && (s_resource_quiesce[7] || s_resource_reset[7]), 7'd0
  };
  assign s_resource_irq_raw = {s_apu_irq_raw, 7'd0};
  assign s_resource_irq_lp_compact = {s_resource_irq_lp[7:6], s_resource_irq_lp[4:0]};
  assign s_resource_irq_hp_compact = {s_resource_irq_hp[7:6], s_resource_irq_hp[4:0]};
  assign s_apb4_periph_irq = {s_resource_irq_lp_compact[6], 23'd0};
  assign s_apb4_system_irq = '0;
  assign s_hp_plic_source = {21'd0, s_resource_irq_hp_compact[6], 10'd0};

  `include "soc_irq_wiring.svh"

apb4_apu u_apu (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .owner_i          (s_resource_owner[7]),
      .owner_lock_i     (s_resource_owner_lock[7]),
      .quiesce_i        (s_resource_quiesce[7]),
      .resource_reset_i (s_resource_reset[7]),
      .bridge_epoch_i   (8'd0),
      .i2s_tx_underrun_i(1'b0),
      .i2s_rx_overrun_i (1'b0),
      .apb4             (u_apu_apb4_if),
      .axi4             (u_apu_axi4_if),
      .dma_tx_axis      (u_dma_tx_axis),
      .dma_rx_axis      (u_dma_rx_axis),
      .i2s_tx_axis      (u_i2s_tx_axis),
      .i2s_rx_axis      (u_i2s_rx_axis),
      .idle_o           (s_apu_idle),
      .irq_o            (s_apu_irq_raw)
  );

  resource_controller #(
      .ResourceCount(8)
  ) u_resource_controller (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .idle_i         (s_resource_idle),
      .block_ack_i    (s_resource_block_ack),
      .irq_i          (s_resource_irq_raw),
      .cache_request_i(1'b0),
      .cache_clean_o  (s_cache_clean),
      .owner_o        (s_resource_owner),
      .owner_lock_o   (s_resource_owner_lock),
      .quiesce_o      (s_resource_quiesce),
      .reset_o        (s_resource_reset),
      .irq_lp_o       (s_resource_irq_lp),
      .irq_hp_o       (s_resource_irq_hp),
      .fault_irq_o    (s_resource_fault_irq),
      .apb4           (u_resource_apb4_if)
  );

  apb4_plic u_hp_plic (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .source_i     (s_hp_plic_source),
      .apb4         (u_plic_apb4_if),
      .context_irq_o(s_hp_plic_context_irq)
  );

  task automatic drive_apb_idle;
    begin
      u_apu_apb4_if.paddr        = 32'd0;
      u_apu_apb4_if.pprot        = 3'd0;
      u_apu_apb4_if.psel         = 1'b0;
      u_apu_apb4_if.penable      = 1'b0;
      u_apu_apb4_if.pwrite       = 1'b0;
      u_apu_apb4_if.pwdata       = 32'd0;
      u_apu_apb4_if.pstrb        = 4'd0;
      u_resource_apb4_if.paddr   = 32'd0;
      u_resource_apb4_if.pprot   = 3'd0;
      u_resource_apb4_if.psel    = 1'b0;
      u_resource_apb4_if.penable = 1'b0;
      u_resource_apb4_if.pwrite  = 1'b0;
      u_resource_apb4_if.pwdata  = 32'd0;
      u_resource_apb4_if.pstrb   = 4'd0;
      u_plic_apb4_if.paddr       = 32'd0;
      u_plic_apb4_if.pprot       = 3'd0;
      u_plic_apb4_if.psel        = 1'b0;
      u_plic_apb4_if.penable     = 1'b0;
      u_plic_apb4_if.pwrite      = 1'b0;
      u_plic_apb4_if.pwdata      = 32'd0;
      u_plic_apb4_if.pstrb       = 4'd0;
    end
  endtask

  task automatic apu_write(input logic [11:0] offset_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      u_apu_apb4_if.paddr   = ApuBase + offset_i;
      u_apu_apb4_if.pwdata  = data_i;
      u_apu_apb4_if.pstrb   = 4'hf;
      u_apu_apb4_if.pwrite  = 1'b1;
      u_apu_apb4_if.psel    = 1'b1;
      u_apu_apb4_if.penable = 1'b0;
      @(negedge clk_i);
      u_apu_apb4_if.penable = 1'b1;
      while (!u_apu_apb4_if.pready) @(negedge clk_i);
      if (u_apu_apb4_if.pslverr) $fatal(1, "APU topology write failed at %h", offset_i);
      @(negedge clk_i);
      u_apu_apb4_if.psel    = 1'b0;
      u_apu_apb4_if.penable = 1'b0;
      u_apu_apb4_if.pwrite  = 1'b0;
      u_apu_apb4_if.pstrb   = 4'd0;
    end
  endtask

  task automatic resource_write(input logic [11:0] offset_i, input logic [31:0] data_i,
                                input logic expected_err_i);
    begin
      @(negedge clk_i);
      u_resource_apb4_if.paddr   = {20'd0, offset_i};
      u_resource_apb4_if.pwdata  = data_i;
      u_resource_apb4_if.pstrb   = 4'hf;
      u_resource_apb4_if.pwrite  = 1'b1;
      u_resource_apb4_if.psel    = 1'b1;
      u_resource_apb4_if.penable = 1'b0;
      @(negedge clk_i);
      u_resource_apb4_if.penable = 1'b1;
      while (!u_resource_apb4_if.pready) @(negedge clk_i);
      if (u_resource_apb4_if.pslverr != expected_err_i) begin
        $fatal(1, "Resource topology write response mismatch at %h", offset_i);
      end
      @(negedge clk_i);
      u_resource_apb4_if.psel    = 1'b0;
      u_resource_apb4_if.penable = 1'b0;
      u_resource_apb4_if.pwrite  = 1'b0;
      u_resource_apb4_if.pstrb   = 4'd0;
    end
  endtask

  task automatic plic_write(input logic [25:0] offset_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      u_plic_apb4_if.paddr   = {6'd0, offset_i};
      u_plic_apb4_if.pwdata  = data_i;
      u_plic_apb4_if.pstrb   = 4'hf;
      u_plic_apb4_if.pwrite  = 1'b1;
      u_plic_apb4_if.psel    = 1'b1;
      u_plic_apb4_if.penable = 1'b0;
      @(negedge clk_i);
      u_plic_apb4_if.penable = 1'b1;
      while (!u_plic_apb4_if.pready) @(negedge clk_i);
      if (u_plic_apb4_if.pslverr) $fatal(1, "PLIC topology write failed at %h", offset_i);
      @(negedge clk_i);
      u_plic_apb4_if.psel    = 1'b0;
      u_plic_apb4_if.penable = 1'b0;
      u_plic_apb4_if.pwrite  = 1'b0;
      u_plic_apb4_if.pstrb   = 4'd0;
    end
  endtask

  task automatic plic_read(input logic [25:0] offset_i, output logic [31:0] data_o);
    begin
      @(negedge clk_i);
      u_plic_apb4_if.paddr   = {6'd0, offset_i};
      u_plic_apb4_if.pstrb   = 4'd0;
      u_plic_apb4_if.pwrite  = 1'b0;
      u_plic_apb4_if.psel    = 1'b1;
      u_plic_apb4_if.penable = 1'b0;
      @(negedge clk_i);
      u_plic_apb4_if.penable = 1'b1;
      while (!u_plic_apb4_if.pready) @(negedge clk_i);
      if (u_plic_apb4_if.pslverr) $fatal(1, "PLIC topology read failed at %h", offset_i);
      data_o = u_plic_apb4_if.prdata;
      @(negedge clk_i);
      u_plic_apb4_if.psel    = 1'b0;
      u_plic_apb4_if.penable = 1'b0;
    end
  endtask

  initial begin
    drive_apb_idle();
    u_apu_axi4_if.awready = 1'b0;
    u_apu_axi4_if.wready  = 1'b0;
    u_apu_axi4_if.bid     = '0;
    u_apu_axi4_if.bresp   = '0;
    u_apu_axi4_if.buser   = '0;
    u_apu_axi4_if.bvalid  = 1'b0;
    u_apu_axi4_if.arready = 1'b0;
    u_apu_axi4_if.rid     = '0;
    u_apu_axi4_if.rdata   = '0;
    u_apu_axi4_if.rresp   = '0;
    u_apu_axi4_if.rlast   = 1'b0;
    u_apu_axi4_if.ruser   = '0;
    u_apu_axi4_if.rvalid  = 1'b0;
    u_dma_tx_axis.tdata   = '0;
    u_dma_tx_axis.tkeep   = '1;
    u_dma_tx_axis.tstrb   = '1;
    u_dma_tx_axis.tlast   = 1'b0;
    u_dma_tx_axis.tid     = '0;
    u_dma_tx_axis.tdest   = '0;
    u_dma_tx_axis.tuser   = '0;
    u_dma_tx_axis.tvalid  = 1'b0;
    u_dma_rx_axis.tready  = 1'b1;
    u_i2s_tx_axis.tready  = 1'b1;
    u_i2s_rx_axis.tdata   = '0;
    u_i2s_rx_axis.tkeep   = '1;
    u_i2s_rx_axis.tstrb   = '1;
    u_i2s_rx_axis.tlast   = 1'b0;
    u_i2s_rx_axis.tid     = '0;
    u_i2s_rx_axis.tdest   = '0;
    u_i2s_rx_axis.tuser   = '0;
    u_i2s_rx_axis.tvalid  = 1'b0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    plic_write(26'h000028, 32'd3);
    plic_write(26'h002000, 32'h0000_0400);
    plic_write(26'h200000, 32'd0);
    apu_write(`APB4_APU__IRQ_ENABLE, 32'h0000_0001);
    apu_write(`APB4_APU__IRQ_TEST, 32'h0000_0001);
    repeat (2) @(posedge clk_i);
    #1;
    if ((s_resource_owner[7] != 2'd0) || !s_resource_irq_lp[7] || s_resource_irq_hp[7] ||
        !s_apb4_periph_irq[23] || !s_irq[31] || s_hp_plic_source[10] ||
        s_hp_plic_context_irq[0]) begin
      $fatal(1, "APU event was not delivered exclusively to LP IRQ31");
    end

    resource_write(Resource7Control, 32'h0000_0001, 1'b0);
    resource_write(Resource7Owner, 32'h0000_0101, 1'b0);
    repeat (2) @(posedge clk_i);
    #1;
    if ((s_resource_owner[7] != 2'd1) || !s_resource_owner_lock[7] ||
        s_resource_irq_lp[7] || !s_resource_irq_hp[7] || s_apb4_periph_irq[23] ||
        s_irq[31] || !s_hp_plic_source[10] || !s_hp_plic_context_irq[0]) begin
      $fatal(1, "APU event was not delivered exclusively to HP PLIC source 10");
    end
    plic_read(26'h200004, s_value);
    if (s_value != 32'd10) $fatal(1, "HP PLIC did not claim APU source 10");

    resource_write(Resource7Owner, 32'd0, 1'b1);
    if ((s_resource_owner[7] != 2'd1) || !s_resource_owner_lock[7] || !s_resource_fault_irq) begin
      $fatal(1, "APU owner lock did not preserve HP ownership");
    end
    resource_write(Resource7Fault, 32'h0000_0001, 1'b0);
    if (s_resource_fault_irq) $fatal(1, "APU resource fault did not clear");

    resource_write(Resource7Control, 32'h0000_0003, 1'b0);
    repeat (2) @(posedge clk_i);
    #1;
    if (s_resource_irq_lp[7] || s_resource_irq_hp[7] || s_apb4_periph_irq[23] || s_irq[31] ||
        s_hp_plic_source[10]) begin
      $fatal(1, "APU resource reset did not mask both interrupt routes");
    end

    if (s_resource_fault_irq || s_cache_clean) begin
      $fatal(1, "APU topology test left an unrelated controller output asserted");
    end
    $display("APU-P1 integrated IRQ ownership topology passed");
    $finish;
  end

  initial begin
    repeat (1000) @(posedge clk_i);
    $fatal(1, "APU-P1 IRQ ownership topology timed out");
  end
endmodule
