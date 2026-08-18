`timescale 1ns / 1ps

`include "ws2812_define.svh"

module ws2812_dma_tb;
  localparam logic [31:0] SourceBase = 32'h4000_0000;
  localparam logic [31:0] Ws2812Txdata = 32'h1000_8010;
  localparam int BitCycles = 4;
  localparam int T0hCycles = 1;
  localparam int T1hCycles = 3;
  localparam int ResetCycles = 5;

  typedef enum logic [2:0] {
    AxiIdle,
    AxiReadResponse,
    AxiWriteWait,
    AxiWriteSetup,
    AxiWriteAccess,
    AxiWriteResponse
  } axi_state_e;

  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               dma_start = 1'b0;
  logic       [ 31:0] dma_cfg = '0;
  logic       [ 31:0] dma_src_addr = '0;
  logic       [ 31:0] dma_dst_addr = '0;
  logic       [ 31:0] dma_byte_count = '0;
  logic       [ 31:0] dma_request = '0;
  logic       [ 31:0] dma_burst = '0;
  logic               dma_done;
  logic               dma_error;
  logic       [  3:0] dma_done_vector;
  logic       [  3:0] dma_error_vector;
  logic       [127:0] dma_error_status_vector;
  logic       [127:0] dma_error_addr_vector;
  logic               host_active = 1'b1;
  logic               host_psel = 1'b0;
  logic               host_penable = 1'b0;
  logic       [ 31:0] host_addr = '0;
  logic       [ 31:0] host_wdata = '0;
  logic       [  3:0] host_wstrb = '0;
  axi_state_e         axi_state_q = AxiIdle;
  logic       [ 31:0] axi_read_addr_q = '0;
  integer             dma_write_count = 0;
  integer             dma_backpressure_cycles = 0;
  logic       [ 23:0] pixels                      [0:5];
  integer             observed_pixel = 0;
  integer             observed_bit = 0;
  integer             observed_cycle = 0;
  integer             reset_low_cycles = 0;

  dma_req_if req ();
  axi4_if axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  ws2812_if ws2812 ();
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

  always #5 clk_i = ~clk_i;

  initial begin
    repeat (5000) @(posedge clk_i);
    $fatal(1, "WS2812 DMA integration test timeout");
  end

  assign apb4.psel = host_active ? host_psel :
                     ((axi_state_q == AxiWriteSetup) || (axi_state_q == AxiWriteAccess));
  assign apb4.penable = host_active ? host_penable : (axi_state_q == AxiWriteAccess);
  assign apb4.pwrite = 1'b1;
  assign apb4.paddr = host_active ? host_addr : Ws2812Txdata;
  assign apb4.pwdata = host_active ? host_wdata : axi4.wdata;
  assign apb4.pstrb = host_active ? host_wstrb : axi4.wstrb;
  assign apb4.pprot = '0;

  assign axi4.arready = axi_state_q == AxiIdle;
  assign axi4.rid = '0;
  assign axi4.rdata = pixels[axi_read_addr_q[4:2]];
  assign axi4.rresp = `AXI4_RESP_OKAY;
  assign axi4.rlast = 1'b1;
  assign axi4.ruser = '0;
  assign axi4.rvalid = axi_state_q == AxiReadResponse;
  assign axi4.awready = (axi_state_q == AxiIdle) && !axi4.arvalid;
  assign axi4.wready = (axi_state_q == AxiWriteAccess) && apb4.pready;
  assign axi4.bid = '0;
  assign axi4.bresp = `AXI4_RESP_OKAY;
  assign axi4.buser = '0;
  assign axi4.bvalid = axi_state_q == AxiWriteResponse;
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

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      axi_state_q             <= AxiIdle;
      axi_read_addr_q         <= '0;
      dma_write_count         <= 0;
      dma_backpressure_cycles <= 0;
    end else begin
      if (axi4.wvalid && !axi4.wready) begin
        dma_backpressure_cycles <= dma_backpressure_cycles + 1;
      end
      unique case (axi_state_q)
        AxiIdle: begin
          if (axi4.arvalid && axi4.arready) begin
            if ((axi4.arlen != 8'd0) || (axi4.araddr < (SourceBase + 32'd4)) ||
                (axi4.araddr > (SourceBase + 32'd20))) begin
              $fatal(1, "DMA issued an invalid WS2812 source read");
            end
            axi_read_addr_q <= axi4.araddr;
            axi_state_q     <= AxiReadResponse;
          end else if (axi4.awvalid && axi4.awready) begin
            if ((axi4.awlen != 8'd0) || (axi4.awaddr != Ws2812Txdata) ||
                (axi4.awburst != `AXI4_BURST_TYPE_FIXED)) begin
              $fatal(1, "fixed WS2812 destination was not a single AXI4 FIXED beat");
            end
            axi_state_q <= AxiWriteWait;
          end
        end
        AxiReadResponse: begin
          if (axi4.rvalid && axi4.rready) begin
            axi_state_q <= AxiIdle;
          end
        end
        AxiWriteWait: begin
          if (axi4.wvalid) begin
            axi_state_q <= AxiWriteSetup;
          end
        end
        AxiWriteSetup: axi_state_q <= AxiWriteAccess;
        AxiWriteAccess: begin
          if (axi4.wvalid && axi4.wready) begin
            if (!axi4.wlast) begin
              $fatal(1, "single-beat WS2812 write did not assert WLAST");
            end
            dma_write_count <= dma_write_count + 1;
            axi_state_q     <= AxiWriteResponse;
          end
        end
        AxiWriteResponse: begin
          if (axi4.bvalid && axi4.bready) begin
            axi_state_q <= AxiIdle;
          end
        end
        default:       axi_state_q <= AxiIdle;
      endcase
    end
  end

  dma_core #(
      .NumChannels  (4),
      .MaxBurstBeats(16),
      .FifoDepth    (16)
  ) u_dma_core (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .global_reset_i       (1'b0),
      .global_error_clear_i (1'b0),
      .ch_cfg_i             ({96'd0, dma_cfg}),
      .src_addr_i           ({96'd0, dma_src_addr}),
      .dst_addr_i           ({96'd0, dma_dst_addr}),
      .byte_count_i         ({96'd0, dma_byte_count}),
      .request_sel_i        ({96'd0, dma_request}),
      .burst_cfg_i          ({96'd0, dma_burst}),
      .start_i              ({3'd0, dma_start}),
      .suspend_i            ('0),
      .resume_i             ('0),
      .abort_i              ('0),
      .channel_reset_i      ('0),
      .event_clear_i        ('0),
      .busy_o               (),
      .suspended_o          (),
      .done_o               (dma_done_vector),
      .aborted_o            (),
      .error_o              (dma_error_vector),
      .stream_last_o        (),
      .event_status_o       (),
      .error_status_o       (dma_error_status_vector),
      .error_addr_o         (dma_error_addr_vector),
      .current_src_o        (),
      .current_dst_o        (),
      .remaining_o          (),
      .bytes_done_o         (),
      .stall_cycles_lo_o    (),
      .stall_cycles_hi_o    (),
      .first_error_valid_o  (),
      .first_error_channel_o(),
      .first_error_status_o (),
      .first_error_addr_o   (),
      .request_status_o     (),
      .xpi_xfer_done_o      (),
      .req                  (req),
      .axi4                 (axi4),
      .i2s_tx_axis          (i2s_tx_axis),
      .i2s_rx_axis          (i2s_rx_axis),
      .dvp_rx_axis          (dvp_rx_axis)
  );

  assign dma_done  = dma_done_vector[0];
  assign dma_error = dma_error_vector[0];

  apb4_ws2812 #(
      .TxFifoDepth(4)
  ) u_ws2812 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .apb4   (apb4),
      .ws2812 (ws2812)
  );

  task automatic host_write(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      host_addr    = address;
      host_wdata   = data;
      host_wstrb   = 4'hF;
      host_psel    = 1'b1;
      host_penable = 1'b0;
      @(negedge clk_i);
      host_penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "WS2812 host write %h failed", address);
      host_psel    = 1'b0;
      host_penable = 1'b0;
    end
  endtask

  always @(posedge clk_i) begin
    #1;
    if (rst_n_i && u_ws2812.s_busy && !u_ws2812.s_reset_active) begin
      integer high_cycles;
      logic   expected_data;

      high_cycles   = pixels[observed_pixel][23-observed_bit] ? T1hCycles : T0hCycles;
      expected_data = observed_cycle < high_cycles;
      if (ws2812.dat_o !== expected_data) begin
        $fatal(1, "DMA waveform mismatch pixel=%0d bit=%0d cycle=%0d", observed_pixel,
               observed_bit, observed_cycle);
      end
      observed_cycle = observed_cycle + 1;
      if (observed_cycle == BitCycles) begin
        observed_cycle = 0;
        observed_bit   = observed_bit + 1;
        if (observed_bit == 24) begin
          observed_bit   = 0;
          observed_pixel = observed_pixel + 1;
        end
      end
    end
    if (rst_n_i && u_ws2812.s_reset_active) begin
      if (ws2812.dat_o !== 1'b0) begin
        $fatal(1, "DMA frame reset interval drove the output high");
      end
      reset_low_cycles = reset_low_cycles + 1;
    end
    if (dma_error) begin
      $fatal(1, "DMA failed during WS2812 transfer status=%h address=%h",
             dma_error_status_vector[31:0], dma_error_addr_vector[31:0]);
    end
  end

  initial begin
    pixels[0]        = 24'h800001;
    pixels[1]        = 24'h010203;
    pixels[2]        = 24'hA5A5A5;
    pixels[3]        = 24'h5A5A5A;
    pixels[4]        = 24'hFFFFFF;
    pixels[5]        = 24'h000000;
    req.i2s_tx_proc  = 1'b1;
    req.i2s_rx_proc  = 1'b1;
    req.qspi_tx_proc = 1'b1;
    req.qspi_rx_proc = 1'b1;
    req.uart_tx_proc = 1'b1;
    req.uart_rx_proc = 1'b1;
    req.i2c0_tx_proc = 1'b1;
    req.i2c0_rx_proc = 1'b1;
    req.i2c1_tx_proc = 1'b1;
    req.i2c1_rx_proc = 1'b1;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    host_write(`APB4_WS2812_BIT_CYCLES, BitCycles);
    host_write(`APB4_WS2812_T0H_CYCLES, T0hCycles);
    host_write(`APB4_WS2812_T1H_CYCLES, T1hCycles);
    host_write(`APB4_WS2812_RESET_CYCLES, ResetCycles);
    host_write(`APB4_WS2812_FIFO_WATERMARK, 3);
    host_write(`APB4_WS2812_INTR_ENABLE, 1);
    host_write(`APB4_WS2812_TXDATA, pixels[0]);
    host_write(`APB4_WS2812_FRAME_WORDS, 6);
    host_write(`APB4_WS2812_CTRL, 1);

    host_active    = 1'b0;
    dma_cfg        = {22'd0, 2'd1, 1'b0, 1'b1, 2'd2, 1'b0, 3'd0};
    dma_src_addr   = SourceBase + 32'd4;
    dma_dst_addr   = Ws2812Txdata;
    dma_byte_count = 32'd20;
    dma_request    = 32'd0;
    dma_burst      = 32'd16;
    @(negedge clk_i);
    dma_start = 1'b1;
    @(negedge clk_i);
    dma_start = 1'b0;
    wait (dma_done);
    wait (!u_ws2812.s_busy);
    @(posedge clk_i);
    #1;
    if ((dma_write_count != 5) || (dma_backpressure_cycles < 40) ||
        (observed_pixel != 6) || (reset_low_cycles < ResetCycles) || !ws2812.irq_o) begin
      $fatal(1, "DMA WS2812 result writes=%0d stalls=%0d pixels=%0d reset=%0d irq=%b",
             dma_write_count, dma_backpressure_cycles, observed_pixel, reset_low_cycles,
             ws2812.irq_o);
    end

    $display("WS2812 native AXI4 DMA backpressure integration test passed");
    $finish;
  end
endmodule
