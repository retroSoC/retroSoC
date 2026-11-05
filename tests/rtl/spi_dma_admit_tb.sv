`timescale 1ns / 1ps

module spi_dma_admit_tb;
  localparam logic [31:0] SpiTxAddress = 32'h1001_d054;
  localparam logic [31:0] SpiRxAddress = 32'h1001_d058;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  always #5 clk_i = ~clk_i;

  dma_req_if req ();
  apb4_if dma_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if spi_dut_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if spi_bridge_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if mem_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if spi_axi (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if mem_axi (
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

  logic [1:0] origin_i;
  logic [4:0] request_i;
  logic [2:0] channel_i;
  logic [1:0] credit_valid_i, credit_retire_i;
  logic [1:0] dma_start_pending_i;
  logic [3:0] dma_status_i;
  logic       dma_error_i;
  logic [1:0] spi_credit_valid_o, spi_credit_retire_o;
  logic [ 1:0] spi_start_pending_o;
  logic [ 3:0] spi_status_o;
  logic        spi_error_o;
  logic [ 1:0] dma_admit_ready_o;
  logic [ 1:0] spi_origin;
  logic [ 2:0] spi_channel;
  logic [ 1:0] dma_admit_ready;

  logic [31:0] user_select_i = '0;
  logic [31:0] handoff_i = '0;
  logic [31:0] alt_enable_i = '0;
  logic [31:0] alt_select_i = '0;
  logic [31:0] output_enable_i = '0;
  logic [31:0] open_drain_i = '0;
  logic        gpio_ready_i = 1'b0;
  logic        miso_i = 1'b1;
  logic sck_o, mosi_o, cs_n_o, output_enable_o, irq_o;
  logic session_owned_o, lifecycle_idle_o;
  logic   [ 1:0] credit_commit_o;

  logic          cpu_psel = 1'b0;
  logic          cpu_penable = 1'b0;
  logic          cpu_pwrite = 1'b0;
  logic   [31:0] cpu_paddr = '0;
  logic   [31:0] cpu_pwdata = '0;
  logic   [ 3:0] cpu_pstrb = '0;

  logic   [31:0] memory                   [0:1031];
  logic   [31:0] source_words             [   0:7];
  logic   [15:0] rx_frames                [   0:6];
  logic   [15:0] tx_frames                [  0:15];
  logic   [15:0] tx_shift = '0;
  integer        tx_bit_count = 0;
  integer        tx_frame_count = 0;
  logic          tx_monitor_enable = 1'b0;
  integer        rx_bit_count = 0;
  logic          rx_active = 1'b0;
  integer        response_delay = 0;
  logic   [15:0] mem_delay_q = '0;
  logic   [15:0] spi_delay_q = '0;
  logic          route_write_q = 1'b0;
  logic          route_read_q = 1'b0;
  integer        aw_count = 0;
  integer        ar_count = 0;
  logic          delayed_tx_seen = 1'b0;
  logic          delayed_rx_seen = 1'b0;
  logic          abort_inflight = 1'b0;
  logic          hold_tx_response = 1'b0;

  assign {
    req.i2s_tx_proc, req.i2s_rx_proc, req.qspi_tx_proc, req.qspi_rx_proc,
    req.uart_tx_proc, req.uart_rx_proc, req.i2c0_tx_proc, req.i2c0_rx_proc,
    req.i2c1_tx_proc, req.i2c1_rx_proc, req.crypto_in_proc, req.crypto_out_proc
  } = '0;
  assign i2s_tx_axis.tready = 1'b0;
  assign i2s_rx_axis.tdata = '0;
  assign i2s_rx_axis.tkeep = '0;
  assign i2s_rx_axis.tstrb = '0;
  assign i2s_rx_axis.tlast = 1'b0;
  assign i2s_rx_axis.tid = '0;
  assign i2s_rx_axis.tdest = '0;
  assign i2s_rx_axis.tuser = '0;
  assign i2s_rx_axis.tvalid = 1'b0;
  assign dvp_rx_axis.tdata = '0;
  assign dvp_rx_axis.tkeep = '0;
  assign dvp_rx_axis.tstrb = '0;
  assign dvp_rx_axis.tlast = 1'b0;
  assign dvp_rx_axis.tid = '0;
  assign dvp_rx_axis.tdest = '0;
  assign dvp_rx_axis.tuser = '0;
  assign dvp_rx_axis.tvalid = 1'b0;
  assign crypto_in_axis.tready = 1'b0;
  assign crypto_out_axis.tdata = '0;
  assign crypto_out_axis.tkeep = '0;
  assign crypto_out_axis.tstrb = '0;
  assign crypto_out_axis.tlast = 1'b0;
  assign crypto_out_axis.tid = '0;
  assign crypto_out_axis.tdest = '0;
  assign crypto_out_axis.tuser = '0;
  assign crypto_out_axis.tvalid = 1'b0;

  assign spi_axi.awid = axi4.awid;
  assign spi_axi.awaddr = axi4.awaddr;
  assign spi_axi.awlen = axi4.awlen;
  assign spi_axi.awsize = axi4.awsize;
  assign spi_axi.awburst = axi4.awburst;
  assign spi_axi.awlock = axi4.awlock;
  assign spi_axi.awcache = axi4.awcache;
  assign spi_axi.awprot = axi4.awprot;
  assign spi_axi.awqos = axi4.awqos;
  assign spi_axi.awregion = axi4.awregion;
  assign spi_axi.awuser = axi4.awuser;
  assign mem_axi.awid = axi4.awid;
  assign mem_axi.awaddr = axi4.awaddr;
  assign mem_axi.awlen = axi4.awlen;
  assign mem_axi.awsize = axi4.awsize;
  assign mem_axi.awburst = axi4.awburst;
  assign mem_axi.awlock = axi4.awlock;
  assign mem_axi.awcache = axi4.awcache;
  assign mem_axi.awprot = axi4.awprot;
  assign mem_axi.awqos = axi4.awqos;
  assign mem_axi.awregion = axi4.awregion;
  assign mem_axi.awuser = axi4.awuser;
  assign spi_axi.awvalid = axi4.awvalid && (axi4.awaddr == SpiTxAddress) && !cpu_psel;
  assign mem_axi.awvalid = axi4.awvalid && (axi4.awaddr != SpiTxAddress);
  assign axi4.awready = (axi4.awaddr == SpiTxAddress) ? (spi_axi.awready && !cpu_psel) :
                        mem_axi.awready;

  assign spi_axi.wdata = axi4.wdata;
  assign spi_axi.wstrb = axi4.wstrb;
  assign spi_axi.wlast = axi4.wlast;
  assign spi_axi.wuser = axi4.wuser;
  assign mem_axi.wdata = axi4.wdata;
  assign mem_axi.wstrb = axi4.wstrb;
  assign mem_axi.wlast = axi4.wlast;
  assign mem_axi.wuser = axi4.wuser;
  assign spi_axi.wvalid = axi4.wvalid && route_write_q;
  assign mem_axi.wvalid = axi4.wvalid && !route_write_q;
  assign axi4.wready = route_write_q ? spi_axi.wready : mem_axi.wready;
  assign spi_axi.bready = axi4.bready && route_write_q && !(hold_tx_response && (aw_count >= 9));
  assign mem_axi.bready = axi4.bready && !route_write_q;
  assign axi4.bid = route_write_q ? spi_axi.bid : mem_axi.bid;
  assign axi4.bresp = route_write_q ? spi_axi.bresp : mem_axi.bresp;
  assign axi4.buser = route_write_q ? spi_axi.buser : mem_axi.buser;
  assign axi4.bvalid = route_write_q ?
      (spi_axi.bvalid && !(hold_tx_response && (aw_count >= 9))) : mem_axi.bvalid;

  assign spi_axi.arid = axi4.arid;
  assign spi_axi.araddr = axi4.araddr;
  assign spi_axi.arlen = axi4.arlen;
  assign spi_axi.arsize = axi4.arsize;
  assign spi_axi.arburst = axi4.arburst;
  assign spi_axi.arlock = axi4.arlock;
  assign spi_axi.arcache = axi4.arcache;
  assign spi_axi.arprot = axi4.arprot;
  assign spi_axi.arqos = axi4.arqos;
  assign spi_axi.arregion = axi4.arregion;
  assign spi_axi.aruser = axi4.aruser;
  assign mem_axi.arid = axi4.arid;
  assign mem_axi.araddr = axi4.araddr;
  assign mem_axi.arlen = axi4.arlen;
  assign mem_axi.arsize = axi4.arsize;
  assign mem_axi.arburst = axi4.arburst;
  assign mem_axi.arlock = axi4.arlock;
  assign mem_axi.arcache = axi4.arcache;
  assign mem_axi.arprot = axi4.arprot;
  assign mem_axi.arqos = axi4.arqos;
  assign mem_axi.arregion = axi4.arregion;
  assign mem_axi.aruser = axi4.aruser;
  assign spi_axi.arvalid = axi4.arvalid && (axi4.araddr == SpiRxAddress) && !cpu_psel;
  assign mem_axi.arvalid = axi4.arvalid && (axi4.araddr != SpiRxAddress);
  assign axi4.arready = (axi4.araddr == SpiRxAddress) ? (spi_axi.arready && !cpu_psel) :
                        mem_axi.arready;
  assign spi_axi.rready = axi4.rready && route_read_q;
  assign mem_axi.rready = axi4.rready && !route_read_q;
  assign axi4.rid = route_read_q ? spi_axi.rid : mem_axi.rid;
  assign axi4.rdata = route_read_q ? spi_axi.rdata : mem_axi.rdata;
  assign axi4.rresp = route_read_q ? spi_axi.rresp : mem_axi.rresp;
  assign axi4.rlast = route_read_q ? spi_axi.rlast : mem_axi.rlast;
  assign axi4.ruser = route_read_q ? spi_axi.ruser : mem_axi.ruser;
  assign axi4.rvalid = route_read_q ? spi_axi.rvalid : mem_axi.rvalid;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      route_write_q <= 1'b0;
      route_read_q  <= 1'b0;
    end else begin
      if (axi4.awvalid && axi4.awready) route_write_q <= axi4.awaddr == SpiTxAddress;
      if (axi4.arvalid && axi4.arready) route_read_q <= axi4.araddr == SpiRxAddress;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      mem_delay_q <= '0;
    end else begin
      if (!mem_apb.psel) mem_delay_q <= response_delay[15:0];
      else if (mem_delay_q != 0) mem_delay_q <= mem_delay_q - 16'd1;
    end
  end
  assign mem_apb.prdata  = memory[mem_apb.paddr[13:2]];
  assign mem_apb.pready  = mem_delay_q == 0;
  assign mem_apb.pslverr = 1'b0;
  always_ff @(posedge clk_i) begin
    if (rst_n_i && mem_apb.psel && mem_apb.penable && mem_apb.pready && mem_apb.pwrite)
      memory[mem_apb.paddr[13:2]] <= mem_apb.pwdata;
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      spi_delay_q <= '0;
    end else begin
      if (!spi_bridge_apb.psel) spi_delay_q <= response_delay[15:0];
      else if (spi_delay_q != 0) spi_delay_q <= spi_delay_q - 16'd1;
    end
  end
  assign spi_bridge_apb.prdata  = spi_dut_apb.prdata;
  assign spi_bridge_apb.pready  = spi_dut_apb.pready && (spi_delay_q == 0);
  assign spi_bridge_apb.pslverr = spi_dut_apb.pslverr;

  assign spi_dut_apb.paddr      = cpu_psel ? cpu_paddr : spi_bridge_apb.paddr;
  assign spi_dut_apb.pwdata     = cpu_psel ? cpu_pwdata : spi_bridge_apb.pwdata;
  assign spi_dut_apb.pstrb      = cpu_psel ? cpu_pstrb : spi_bridge_apb.pstrb;
  assign spi_dut_apb.psel       = cpu_psel || spi_bridge_apb.psel;
  assign spi_dut_apb.penable    = cpu_psel ? cpu_penable : spi_bridge_apb.penable;
  assign spi_dut_apb.pwrite     = cpu_psel ? cpu_pwrite : spi_bridge_apb.pwrite;
  assign spi_dut_apb.pprot      = '0;

  tiny_axi42apb4 u_spi_bridge (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .axi4     (spi_axi),
      .apb4     (spi_bridge_apb),
      .origin_o (spi_origin),
      .channel_o(spi_channel)
  );
  tiny_axi42apb4 u_mem_bridge (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .axi4     (mem_axi),
      .apb4     (mem_apb),
      .origin_o (),
      .channel_o()
  );

  assign origin_i            = cpu_psel ? 2'd0 : spi_origin;
  assign request_i           = spi_bridge_apb.pwrite ? 5'd16 : 5'd17;
  assign channel_i           = spi_channel;
  assign credit_valid_i      = spi_credit_valid_o;
  assign credit_retire_i     = spi_credit_retire_o;
  assign dma_start_pending_i = spi_start_pending_o;
  assign dma_status_i        = spi_status_o;
  assign dma_error_i         = spi_error_o;
  assign dma_admit_ready     = dma_admit_ready_o;

  apb4_spi u_spi (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .clock_hz_i         (32'd24000000),
      .origin_i           (origin_i),
      .request_i          (request_i),
      .channel_i          (channel_i),
      .credit_valid_i     (credit_valid_i),
      .credit_retire_i    (credit_retire_i),
      .dma_start_pending_i(dma_start_pending_i),
      .dma_status_i       (dma_status_i),
      .dma_error_i        (dma_error_i),
      .user_select_i      (user_select_i),
      .handoff_i          (handoff_i),
      .alt_enable_i       (alt_enable_i),
      .alt_select_i       (alt_select_i),
      .output_enable_i    (output_enable_i),
      .open_drain_i       (open_drain_i),
      .gpio_ready_i       (gpio_ready_i),
      .miso_i             (miso_i),
      .sck_o              (sck_o),
      .mosi_o             (mosi_o),
      .cs_n_o             (cs_n_o),
      .output_enable_o    (output_enable_o),
      .irq_o              (irq_o),
      .session_owned_o    (session_owned_o),
      .lifecycle_idle_o   (lifecycle_idle_o),
      .credit_commit_o    (credit_commit_o),
      .dma_admit_ready_o  (dma_admit_ready_o),
      .apb4               (spi_dut_apb)
  );

  apb4_dma #(
      .NumChannels          (4),
      .MaxBurstBeats        (16),
      .FifoDepth            (16),
      .RequestMask          (32'h0003_39ff),
      .SupportedRequests    (32'h0003_39ff),
      .IpVersion            (32'h0002_0002),
      .EnableStreams        (1'b1),
      .EnableSpi            (1'b1),
      .EnableOriginQualifier(1'b1),
      .SpiTxAddress         (SpiTxAddress),
      .SpiRxAddress         (SpiRxAddress)
  ) u_dma (
      .lifecycle_idle_o   (),
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .dma_xfer_done_o    (),
      .irq_o              (),
      .hw_trg             (req),
      .apb4               (dma_apb),
      .axi4               (axi4),
      .i2s_tx_axis        (i2s_tx_axis),
      .i2s_rx_axis        (i2s_rx_axis),
      .dvp_rx_axis        (dvp_rx_axis),
      .crypto_in_axis     (crypto_in_axis),
      .crypto_out_axis    (crypto_out_axis),
      .spi_admit_ready_i  (dma_admit_ready),
      .spi_credit_valid_o (spi_credit_valid_o),
      .spi_credit_retire_o(spi_credit_retire_o),
      .spi_start_pending_o(spi_start_pending_o),
      .spi_status_o       (spi_status_o),
      .spi_error_o        (spi_error_o)
  );

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      if (u_dma.u_dma_core.s_axi_write_start_valid && u_dma.u_dma_core.s_axi_write_start_ready &&
          (u_dma.u_dma_core.s_axi_write_start_addr == SpiTxAddress)) begin
        aw_count <= aw_count + 1;
        if (!u_dma.u_dma_core.s_req_ready[16])
          $fatal(1, "TX candidate admitted without live readiness");
      end
      if (u_dma.u_dma_core.s_axi_read_start_valid && u_dma.u_dma_core.s_axi_read_start_ready &&
          (u_dma.u_dma_core.s_axi_read_start_addr == SpiRxAddress)) begin
        ar_count <= ar_count + 1;
        if (!u_dma.u_dma_core.s_req_ready[17])
          $fatal(1, "RX candidate admitted without live readiness");
      end
      if (spi_axi.bvalid && !dma_admit_ready[0]) delayed_tx_seen <= 1'b1;
      if (spi_axi.rvalid && !dma_admit_ready[1]) delayed_rx_seen <= 1'b1;
    end
  end

  always @(negedge cs_n_o) begin
    tx_bit_count = 0;
    tx_shift     = '0;
    if (rx_active) begin
      rx_bit_count = 0;
      miso_i <= rx_frames[0][15];
    end
  end
  always @(posedge cs_n_o) begin
    if (rx_active) rx_active = 1'b0;
  end
  always @(posedge sck_o) begin
    if (!cs_n_o) begin
      if (tx_monitor_enable) begin
        tx_shift     = {tx_shift[14:0], mosi_o};
        tx_bit_count = tx_bit_count + 1;
        if (tx_bit_count == 16) begin
          tx_frames[tx_frame_count] = tx_shift;
          tx_frame_count            = tx_frame_count + 1;
          tx_bit_count              = 0;
          tx_shift                  = '0;
        end
      end
    end
  end
  always @(negedge sck_o) begin
    if (rx_active && !cs_n_o) begin
      rx_bit_count = rx_bit_count + 1;
      if (rx_bit_count < 112) miso_i <= rx_frames[rx_bit_count>>4][15-(rx_bit_count&15)];
    end
  end

  function automatic logic [15:0] expected_tx_frame(input integer index);
    if ((index & 1) == 0) expected_tx_frame = source_words[index>>1][15:0];
    else expected_tx_frame = source_words[index>>1][31:16];
  endfunction

  function automatic logic [31:0] channel_address(input integer channel, input integer offset);
    channel_address = 32'h100 + channel * 32'h80 + offset;
  endfunction

  task automatic spi_write(input logic [11:0] offset, input logic [31:0] data);
    integer timeout;
    begin
      @(negedge clk_i);
      while (spi_bridge_apb.psel || spi_axi.wready) @(negedge clk_i);
      cpu_paddr   = {20'd0, offset};
      cpu_pwdata  = data;
      cpu_pstrb   = 4'hf;
      cpu_pwrite  = 1'b1;
      cpu_psel    = 1'b1;
      cpu_penable = 1'b0;
      @(negedge clk_i);
      cpu_penable = 1'b1;
      #1;
      timeout = 0;
      while (!spi_dut_apb.pready && timeout < 100) begin
        @(negedge clk_i);
        timeout = timeout + 1;
      end
      if (!spi_dut_apb.pready || spi_dut_apb.pslverr)
        $fatal(1, "SPI APB write failed offset=%h", offset);
      @(negedge clk_i);
      cpu_psel    = 1'b0;
      cpu_penable = 1'b0;
    end
  endtask

  task automatic spi_read(input logic [11:0] offset, output logic [31:0] data);
    integer timeout;
    begin
      @(negedge clk_i);
      while (spi_bridge_apb.psel || spi_axi.wready) @(negedge clk_i);
      cpu_paddr   = {20'd0, offset};
      cpu_pwdata  = '0;
      cpu_pstrb   = '0;
      cpu_pwrite  = 1'b0;
      cpu_psel    = 1'b1;
      cpu_penable = 1'b0;
      @(negedge clk_i);
      cpu_penable = 1'b1;
      #1;
      timeout = 0;
      while (!spi_dut_apb.pready && timeout < 100) begin
        @(negedge clk_i);
        timeout = timeout + 1;
      end
      if (!spi_dut_apb.pready || spi_dut_apb.pslverr)
        $fatal(1, "SPI APB read failed offset=%h", offset);
      data = spi_dut_apb.prdata;
      @(negedge clk_i);
      cpu_psel    = 1'b0;
      cpu_penable = 1'b0;
    end
  endtask

  task automatic dma_write(input logic [31:0] address, input logic [31:0] data);
    integer timeout;
    begin
      @(negedge clk_i);
      dma_apb.paddr   = address;
      dma_apb.pwdata  = data;
      dma_apb.pstrb   = 4'hf;
      dma_apb.pwrite  = 1'b1;
      dma_apb.psel    = 1'b1;
      dma_apb.penable = 1'b0;
      @(negedge clk_i);
      dma_apb.penable = 1'b1;
      #1;
      timeout = 0;
      while (!dma_apb.pready && timeout < 100) begin
        @(negedge clk_i);
        timeout = timeout + 1;
      end
      if (!dma_apb.pready || dma_apb.pslverr) begin
        $display("DMA_DEBUG address=%h data=%h err=%b busy=%b start_valid=%b", address, data,
                 u_dma.u_dma_reg.s_access_err, u_dma.u_dma_reg.busy_i,
                 u_dma.u_dma_core.s_start_valid);
        $fatal(1, "DMA APB write failed address=%h", address);
      end
      @(negedge clk_i);
      dma_apb.psel    = 1'b0;
      dma_apb.penable = 1'b0;
    end
  endtask

  task automatic dma_read(input logic [31:0] address, output logic [31:0] data);
    integer timeout;
    begin
      @(negedge clk_i);
      dma_apb.paddr   = address;
      dma_apb.pwdata  = '0;
      dma_apb.pstrb   = '0;
      dma_apb.pwrite  = 1'b0;
      dma_apb.psel    = 1'b1;
      dma_apb.penable = 1'b0;
      @(negedge clk_i);
      dma_apb.penable = 1'b1;
      #1;
      timeout = 0;
      while (!dma_apb.pready && timeout < 100) begin
        @(negedge clk_i);
        timeout = timeout + 1;
      end
      if (!dma_apb.pready || dma_apb.pslverr) $fatal(1, "DMA APB read failed address=%h", address);
      data = dma_apb.prdata;
      @(negedge clk_i);
      dma_apb.psel    = 1'b0;
      dma_apb.penable = 1'b0;
    end
  endtask

  task automatic configure_tx_dma;
    begin
      dma_write(channel_address(3, 7'h04), 32'h0000_0260);
      dma_write(channel_address(3, 7'h08), 32'h3000_0000);
      dma_write(channel_address(3, 7'h0c), SpiTxAddress);
      dma_write(channel_address(3, 7'h10), 32'd32);
      dma_write(channel_address(3, 7'h14), 32'd16);
      dma_write(channel_address(3, 7'h18), 32'd1);
    end
  endtask

  task automatic configure_rx_dma;
    begin
      dma_write(channel_address(2, 7'h04), 32'h0000_02a0);
      dma_write(channel_address(2, 7'h08), SpiRxAddress);
      dma_write(channel_address(2, 7'h0c), 32'h3000_1000);
      dma_write(channel_address(2, 7'h10), 32'd16);
      dma_write(channel_address(2, 7'h14), 32'd17);
      dma_write(channel_address(2, 7'h18), 32'd1);
    end
  endtask

  task automatic wait_spi_mask(input logic [11:0] offset, input logic [31:0] mask,
                               input logic [31:0] expected);
    logic   [31:0] value;
    integer        timeout;
    begin
      timeout = 0;
      value   = 0;
      while (((value & mask) != expected) && (timeout < 10000)) begin
        spi_read(offset, value);
        timeout = timeout + 1;
      end
      if ((value & mask) != expected) begin
        $display(
            "WAIT_DEBUG offset=%h value=%h ready=%b aw=%0d ar=%0d pending=%b txr=%b rxr=%b status=%h fault=%h start_pending=%b frames=%h txw=%h f16r=%b pempty=%b",
            offset, value, dma_admit_ready, aw_count, ar_count, u_spi.s_credit_pending,
            u_spi.u_ctrl.tx_ready, u_spi.u_ctrl.rx_ready, u_spi.s_stat.status, u_spi.s_stat.fault,
            dma_start_pending_i, u_spi.s_stat.frames, u_spi.s_stat.tx_words,
            u_spi.u_master_core.s_tx_frame_ready, u_spi.u_master_core.u_word_packer.s_tx_empty);
        $fatal(1, "SPI wait failed offset=%h value=%h", offset, value);
      end
    end
  endtask

  task automatic wait_dma_idle(input integer channel);
    logic   [31:0] value;
    integer        timeout;
    begin
      timeout = 0;
      value   = 1;
      while ((value & 1) && (timeout < 10000)) begin
        dma_read(channel_address(channel, 7'h20), value);
        timeout = timeout + 1;
      end
      if ((value & 1) != 0) $fatal(1, "DMA channel did not drain");
    end
  endtask

  task automatic wait_dma_done(input integer channel);
    logic   [31:0] value;
    integer        timeout;
    begin
      timeout = 0;
      value   = 0;
      while (((value & 4) == 0) && (timeout < 10000)) begin
        dma_read(channel_address(channel, 7'h20), value);
        if ((value & 24) != 0) $fatal(1, "DMA channel error/abort status=%h", value);
        timeout = timeout + 1;
      end
      if ((value & 4) == 0) begin
        $display(
            "DMA_DONE_DEBUG channel=%0d status=%h ready=%b pending=%b credit=%b used=%b reserved=%b txr=%b spi_status=%h fault=%h start_pending=%b aw=%0d ar=%0d",
            channel, value, dma_admit_ready, u_spi.s_credit_pending, credit_valid_i,
            u_spi.u_reg.s_credit_used_q, u_spi.u_dma_pacing.s_reserved_q, u_spi.u_ctrl.tx_ready,
            u_spi.s_stat.status, u_spi.s_stat.fault, dma_start_pending_i, aw_count, ar_count);
        $display(
            "AXI_DEBUG bridge=%0d aw=%b/%b w=%b/%b b=%b/%b spi_b=%b/%b route=%b cpu=%b hold=%b",
            u_spi_bridge.s_state_q, axi4.awvalid, axi4.awready, axi4.wvalid, axi4.wready,
            axi4.bvalid, axi4.bready, spi_axi.bvalid, spi_axi.bready, route_write_q, cpu_psel,
            hold_tx_response);
        $fatal(1, "DMA channel completion timeout");
      end
    end
  endtask

  initial begin
    logic [31:0] value;
    logic [31:0] old_count;
    for (integer index = 0; index < 1032; index++) memory[index] = '0;
    source_words[0] = 32'h0203_0001;
    source_words[1] = 32'h0607_0405;
    source_words[2] = 32'h0a0b_0809;
    source_words[3] = 32'h0e0f_0c0d;
    source_words[4] = 32'h1213_1011;
    source_words[5] = 32'h1617_1415;
    source_words[6] = 32'h1a1b_1819;
    source_words[7] = 32'h1e1f_1c1d;
    for (integer index = 0; index < 8; index++) memory[index] = source_words[index];
    for (integer index = 8; index < 16; index++) memory[index] = source_words[index-8];
    rx_frames[0]    = 16'h0001;
    rx_frames[1]    = 16'h0203;
    rx_frames[2]    = 16'h0405;
    rx_frames[3]    = 16'h0607;
    rx_frames[4]    = 16'h0809;
    rx_frames[5]    = 16'h0a0b;
    rx_frames[6]    = 16'h0c0d;
    response_delay  = 128;
    gpio_ready_i    = 1'b1;
    alt_enable_i    = 32'h9800_0000;
    alt_select_i    = 32'hd000_0000;
    output_enable_i = 32'h4000_0000;
    repeat (5) @(negedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(negedge clk_i);

    if (dma_admit_ready != 0) $fatal(1, "DMA admission enabled before ARM");
    spi_write(12'h020, 32'h10);
    spi_write(12'h024, 32'd64);
    spi_write(12'h028, 32'd1);
    spi_write(12'h02c, 32'd1);
    spi_write(12'h030, 32'd1);
    spi_write(12'h040, 32'h8000_0003);
    spi_write(12'h018, 32'd1);
    spi_write(12'h034, 32'd1);
    spi_write(12'h038, 32'd32);
    spi_write(12'h03c, 32'hffff);
    spi_write(12'h018, 32'd4);
    spi_write(12'h018, 32'd8);
    configure_tx_dma();
    dma_write(channel_address(3, 7'h10), 32'd64);
    hold_tx_response = 1'b1;
    dma_write(channel_address(3, 7'h00), 32'd1);
    wait_spi_mask(12'h05c, 32'hf, 32'h8);
    if (dma_admit_ready[0]) $fatal(1, "TX admission remained enabled at full FIFO");
    if (!dma_start_pending_i[0]) $fatal(1, "Accepted TX START did not keep the binding pending");
    dma_read(12'h024, value);
    if (value[16]) $fatal(1, "REQUEST_STATUS TX remained static at full FIFO");
    old_count = aw_count;
    repeat (32) @(negedge clk_i);
    if (aw_count != old_count) $fatal(1, "TX AW advanced while FIFO was full");
    if (aw_count >= 16) $fatal(1, "TX quota was consumed before completion");
    if (!delayed_tx_seen) $fatal(1, "Delayed B did not retain TX admission reservation");
    spi_read(12'h06c, value);
    if (value != 0) $fatal(1, "TX full generated a fault instead of backpressure");
    abort_inflight = spi_axi.bvalid;
    if (!abort_inflight) $fatal(1, "Abort did not include an in-flight TX response");
    spi_write(12'h018, 32'd32);
    dma_write(channel_address(3, 7'h00), 32'd8);
    if (!spi_axi.bvalid) $fatal(1, "TX response was not retained through both abort commands");
    hold_tx_response = 1'b0;
    wait_spi_mask(12'h060, 32'h4, 32'h4);
    wait_dma_idle(3);
    spi_read(12'h06c, value);
    if (value != 0) $fatal(1, "Abort injected an SPI fault");
    spi_write(12'h018, 32'd64);
    spi_read(12'h040, value);
    if (value != 0) $fatal(1, "RECOVER retained the old TX binding");

    response_delay  = 2;
    alt_enable_i    = '0;
    output_enable_i = '0;
    spi_write(12'h018, 32'd128);
    alt_enable_i    = 32'h9800_0000;
    output_enable_i = 32'h4000_0000;
    spi_write(12'h018, 32'd1);
    spi_write(12'h040, 32'h8000_0003);
    spi_write(12'h034, 32'd1);
    spi_write(12'h038, 32'd16);
    spi_write(12'h018, 32'd4);
    spi_write(12'h018, 32'd8);
    dma_write(channel_address(3, 7'h00), 32'd16);
    configure_tx_dma();
    tx_frame_count    = 0;
    tx_monitor_enable = 1'b1;
    dma_write(channel_address(3, 7'h00), 32'd1);
    wait_dma_done(3);
    wait_spi_mask(12'h01c, 32'h80, 32'h80);
    tx_monitor_enable = 1'b0;
    spi_read(12'h074, value);
    if (value != 16) $fatal(1, "TX completed frame count mismatch %h", value);
    spi_read(12'h078, value);
    if (value != 8) $fatal(1, "TX transport quota mismatch %h", value);
    spi_read(12'h07c, value);
    if (value != 8) $fatal(1, "TX accepted word count mismatch %h", value);
    spi_read(12'h05c, value);
    if (value != 0) $fatal(1, "TX FIFO did not drain");
    spi_read(12'h06c, value);
    if (value != 0) $fatal(1, "TX completion fault");
    if (tx_frame_count != 16) $fatal(1, "TX pin frame count mismatch %0d", tx_frame_count);
    for (integer index = 0; index < 16; index++) begin
      if (tx_frames[index] != expected_tx_frame(index))
        $fatal(
            1,
            "TX pixel mismatch index=%0d got=%h expected=%h",
            index,
            tx_frames[index],
            expected_tx_frame(
                index
            )
        );
    end

    spi_write(12'h018, 32'd2);
    alt_enable_i    = '0;
    output_enable_i = '0;
    spi_write(12'h018, 32'd128);
    spi_write(12'h020, 32'h8);
    alt_enable_i    = 32'hd800_0000;
    alt_select_i    = 32'hd000_0000;
    output_enable_i = '0;
    spi_write(12'h018, 32'd1);
    spi_write(12'h044, 32'h8000_0002);
    spi_write(12'h034, 32'd5);
    spi_write(12'h038, 32'd7);
    spi_write(12'h018, 32'd4);
    rx_active = 1'b1;
    spi_write(12'h018, 32'd8);
    configure_rx_dma();
    response_delay = 128;
    dma_write(channel_address(2, 7'h00), 32'd1);
    if (dma_admit_ready[1]) $fatal(1, "RX admission enabled with an empty RX FIFO");
    old_count = ar_count;
    repeat (16) @(negedge clk_i);
    if (ar_count != old_count) $fatal(1, "RX AR advanced with an empty RX FIFO");
    wait_dma_done(2);
    wait_spi_mask(12'h01c, 32'h80, 32'h80);
    if (!delayed_rx_seen) $fatal(1, "Delayed R did not retain RX admission reservation");
    spi_read(12'h074, value);
    if (value != 7) $fatal(1, "RX completed frame count mismatch %h", value);
    spi_read(12'h078, value);
    if (value != 4) $fatal(1, "RX transport quota mismatch %h", value);
    spi_read(12'h080, value);
    if (value != 4) $fatal(1, "RX produced word count mismatch %h", value);
    spi_read(12'h084, value);
    if (value != 4) $fatal(1, "RX removed word count mismatch %h", value);
    spi_read(12'h09c, value);
    if (value != 14) $fatal(1, "RX payload size mismatch %h", value);
    spi_read(12'h05c, value);
    if (value != 0) $fatal(1, "RX FIFO did not drain");
    spi_read(12'h06c, value);
    if (value != 0) $fatal(1, "RX completion fault");
    if (memory[1024] != 32'h0203_0001 || memory[1025] != 32'h0607_0405 ||
        memory[1026] != 32'h0a0b_0809 || memory[1027] != 32'h0000_0c0d)
      $fatal(
          1,
          "RX data/tail mismatch %h %h %h %h",
          memory[1024],
          memory[1025],
          memory[1026],
          memory[1027]
      );
    $display(
        "SIM_TEST_PASS SPI_DMA_ADMIT_PASS tx_full=1 rx_empty=1 delayed_B=1 delayed_R=1 abort_inflight=1");
    $finish;
  end

  initial begin
    #5000000;
    $fatal(1, "SIM_TEST_TIMEOUT spi_dma_admit_tb");
  end
endmodule
