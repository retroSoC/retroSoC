`timescale 1ns / 1ps

`include "rib_defs.svh"
`include "ws2812_define.svh"

module ws2812_dma_tb;
  localparam logic [31:0] SOURCE_BASE = 32'h4000_0000;
  localparam logic [31:0] WS2812_TXDATA = 32'h1000_8010;
  localparam int BIT_CYCLES = 4;
  localparam int T0H_CYCLES = 1;
  localparam int T1H_CYCLES = 3;
  localparam int RESET_CYCLES = 5;

  typedef enum logic [1:0] {
    BUS_IDLE,
    BUS_READ_RESP,
    BUS_WRITE_DATA,
    BUS_WRITE_RESP
  } bus_state_t;

  logic              clk_i = 1'b0;
  logic              rst_n_i = 1'b0;
  logic              dma_start = 1'b0;
  logic              dma_done;
  logic              dma_error;
  logic       [ 2:0] dma_error_code;
  logic       [31:0] dma_error_addr;
  logic       [ 1:0] dma_fsm;
  logic              host_active = 1'b1;
  logic              host_valid = 1'b0;
  logic       [31:0] host_addr = '0;
  logic       [31:0] host_wdata = '0;
  logic       [ 3:0] host_wstrb = '0;
  logic              dma_ws_valid;
  bus_state_t        bus_state_q = BUS_IDLE;
  logic       [31:0] bus_addr_q = '0;
  integer            dma_write_count = 0;
  integer            dma_backpressure_cycles = 0;
  logic       [23:0] pixels                      [0:5];
  integer            observed_pixel = 0;
  integer            observed_bit = 0;
  integer            observed_cycle = 0;
  integer            reset_low_cycles = 0;

  dma_hw_trg_if hw_trg ();
  rib_if dma_rib ();
  ribp_if ws_ribp ();
  ws2812_if ws2812 ();

  always #5 clk_i = ~clk_i;

  initial begin
    repeat (5000) @(posedge clk_i);
    $fatal(1, "WS2812 DMA integration test timeout");
  end

  assign ws_ribp.valid     = host_active ? host_valid : dma_ws_valid;
  assign ws_ribp.addr      = host_active ? host_addr : bus_addr_q;
  assign ws_ribp.wdata     = host_active ? host_wdata : dma_rib.wdata;
  assign ws_ribp.wstrb     = host_active ? host_wstrb : dma_rib.wstrb;

  assign dma_rib.cmd_ready = bus_state_q == BUS_IDLE;
  assign dma_rib.w_ready   = (bus_state_q == BUS_WRITE_DATA) && ws_ribp.ready;
  assign dma_rib.rsp_valid = (bus_state_q == BUS_READ_RESP) || (bus_state_q == BUS_WRITE_RESP);
  assign dma_rib.rdata     = pixels[bus_addr_q[4:2]];
  assign dma_rib.resp_err  = 1'b0;
  assign dma_rib.resp_code = `RIB_RESP_OK;
  assign dma_rib.rsp_beat  = 2'd0;
  assign dma_rib.rsp_last  = 1'b1;
  assign dma_ws_valid      = (bus_state_q == BUS_WRITE_DATA) && dma_rib.w_valid;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      bus_state_q             <= BUS_IDLE;
      bus_addr_q              <= '0;
      dma_write_count         <= 0;
      dma_backpressure_cycles <= 0;
    end else begin
      if ((bus_state_q == BUS_WRITE_DATA) && dma_rib.w_valid && !dma_rib.w_ready) begin
        dma_backpressure_cycles <= dma_backpressure_cycles + 1;
      end
      unique case (bus_state_q)
        BUS_IDLE: begin
          if (dma_rib.cmd_valid && dma_rib.cmd_ready) begin
            bus_addr_q <= dma_rib.cmd_addr;
            if (dma_rib.cmd_len != `RIB_LEN_INCR1) begin
              $fatal(1, "fixed-destination WS2812 DMA transfer used a burst");
            end
            if (dma_rib.cmd_write) begin
              if (dma_rib.cmd_addr != WS2812_TXDATA) begin
                $fatal(1, "DMA wrote unexpected destination %h", dma_rib.cmd_addr);
              end
              bus_state_q <= BUS_WRITE_DATA;
            end else begin
              if ((dma_rib.cmd_addr < (SOURCE_BASE + 32'd4)) ||
                  (dma_rib.cmd_addr > (SOURCE_BASE + 32'd20))) begin
                $fatal(1, "DMA read unexpected source %h", dma_rib.cmd_addr);
              end
              bus_state_q <= BUS_READ_RESP;
            end
          end
        end
        BUS_READ_RESP: begin
          if (dma_rib.rsp_valid && dma_rib.rsp_ready) begin
            bus_state_q <= BUS_IDLE;
          end
        end
        BUS_WRITE_DATA: begin
          if (dma_rib.w_valid && dma_rib.w_ready) begin
            if (!dma_rib.wlast) begin
              $fatal(1, "INCR1 WS2812 write did not assert wlast");
            end
            dma_write_count <= dma_write_count + 1;
            bus_state_q     <= BUS_WRITE_RESP;
          end
        end
        BUS_WRITE_RESP: begin
          if (dma_rib.rsp_valid && dma_rib.rsp_ready) begin
            bus_state_q <= BUS_IDLE;
          end
        end
        default: bus_state_q <= BUS_IDLE;
      endcase
    end
  end

  dma_core u_dma_core (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .mode_i      (4'd0),
      .srcaddr_i   (SOURCE_BASE + 32'd4),
      .srcincr_i   (1'b1),
      .dstaddr_i   (WS2812_TXDATA),
      .dstincr_i   (1'b0),
      .xferlen_i   (32'd5),
      .start_i     (dma_start),
      .stop_i      (1'b0),
      .reset_i     (1'b0),
      .done_o      (dma_done),
      .error_o     (dma_error),
      .error_code_o(dma_error_code),
      .error_addr_o(dma_error_addr),
      .fsm_o       (dma_fsm),
      .hw_trg      (hw_trg),
      .rib         (dma_rib)
  );

  ribp_ws2812 #(
      .TX_FIFO_DEPTH(4)
  ) u_ws2812 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (ws_ribp),
      .ws2812 (ws2812)
  );

  task automatic host_write(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      host_addr  = address;
      host_wdata = data;
      host_wstrb = 4'hF;
      host_valid = 1'b1;
      while (!ws_ribp.ready) begin
        @(posedge clk_i);
        #1;
      end
      if (ws_ribp.resp_err) begin
        $fatal(1, "host write %h failed", address);
      end
      @(negedge clk_i);
      host_valid = 1'b0;
      host_wstrb = '0;
    end
  endtask

  always @(posedge clk_i) begin
    #1;
    if (rst_n_i && u_ws2812.s_busy && !u_ws2812.s_reset_active) begin
      integer high_cycles;
      logic   expected_data;
      high_cycles   = pixels[observed_pixel][23-observed_bit] ? T1H_CYCLES : T0H_CYCLES;
      expected_data = observed_cycle < high_cycles;
      if (ws2812.dat_o !== expected_data) begin
        $fatal(1, "DMA waveform mismatch pixel=%0d bit=%0d cycle=%0d", observed_pixel,
               observed_bit, observed_cycle);
      end
      observed_cycle = observed_cycle + 1;
      if (observed_cycle == BIT_CYCLES) begin
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
      $fatal(1, "DMA failed code=%0d address=%h", dma_error_code, dma_error_addr);
    end
  end

  initial begin
    pixels[0]           = 24'h800001;
    pixels[1]           = 24'h010203;
    pixels[2]           = 24'hA5A5A5;
    pixels[3]           = 24'h5A5A5A;
    pixels[4]           = 24'hFFFFFF;
    pixels[5]           = 24'h000000;
    hw_trg.i2s_tx_proc  = 1'b0;
    hw_trg.i2s_rx_proc  = 1'b0;
    hw_trg.qspi_tx_proc = 1'b0;
    hw_trg.qspi_rx_proc = 1'b0;
    hw_trg.uart_tx_proc = 1'b0;
    hw_trg.uart_rx_proc = 1'b0;
    hw_trg.i2c0_tx_proc = 1'b0;
    hw_trg.i2c0_rx_proc = 1'b0;
    hw_trg.i2c1_tx_proc = 1'b0;
    hw_trg.i2c1_rx_proc = 1'b0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    host_write(`RIBP_WS2812_BIT_CYCLES, BIT_CYCLES);
    host_write(`RIBP_WS2812_T0H_CYCLES, T0H_CYCLES);
    host_write(`RIBP_WS2812_T1H_CYCLES, T1H_CYCLES);
    host_write(`RIBP_WS2812_RESET_CYCLES, RESET_CYCLES);
    host_write(`RIBP_WS2812_FIFO_WATERMARK, 3);
    host_write(`RIBP_WS2812_INTR_ENABLE, 1);
    host_write(`RIBP_WS2812_TXDATA, pixels[0]);
    host_write(`RIBP_WS2812_FRAME_WORDS, 6);
    host_write(`RIBP_WS2812_CTRL, 1);

    host_active = 1'b0;
    @(negedge clk_i);
    dma_start = 1'b1;
    @(negedge clk_i);
    dma_start = 1'b0;

    wait (dma_done);
    wait (!u_ws2812.s_busy);
    @(posedge clk_i);
    #1;
    if (dma_write_count != 5) begin
      $fatal(1, "DMA completed %0d WS2812 writes, expected 5", dma_write_count);
    end
    if (dma_backpressure_cycles < 40) begin
      $fatal(1, "DMA did not observe full-FIFO backpressure: %0d cycles", dma_backpressure_cycles);
    end
    if ((observed_pixel != 6) || (reset_low_cycles < RESET_CYCLES) || !ws2812.irq_o) begin
      $fatal(1, "DMA frame did not complete pixels=%0d reset=%0d irq=%b", observed_pixel,
             reset_low_cycles, ws2812.irq_o);
    end

    $display("WS2812 DMA backpressure integration test passed");
    $finish;
  end
endmodule
