// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps

// Production DVP and Tiny-parameterized DMA, with a controllable AXI sink at
// an NSS1 PSRAM address. This is not an XPI serial/pad or full-SoC test.
`ifndef TINY_P9_FIXTURE
`define TINY_P9_FIXTURE tiny_r2_p9_dma_tb
`endif
module `TINY_P9_FIXTURE;
  localparam logic [31:0] Destination = 32'h5400_0c00;
  localparam int FrameWidth = 16;
  localparam int FrameHeight = 8;
  localparam int FrameWords = FrameWidth * FrameHeight / 2;
  localparam int FrameBytes = FrameWords * 4;
  logic clk = 0, pixel_clk = 0, rst_n = 1;
  logic pixel_run = 1;
  logic check_start_barrier = 0;
  logic href = 0, vsync = 0;
  logic [7:0] camera_data = 0;
  logic dvp_irq, dvp_idle, dvp_ready, dma_idle, dma_irq, dma_done;
  logic release_tail = 0, release_response = 0;
  int stream_words = 0, written_words = 0;
  int frame_starts = 0, frame_ends = 0, line_ends = 0;
  logic [31:0] memory[0:FrameWords+1];
  logic write_active = 0, response_pending = 0;
  logic [31:0] write_address;
  logic [ 7:0] burst_left;
  logic [ 3:0] response_id;
  logic [31:0] value;
  wire         inject_write_error = $test$plusargs("write_error");
  logic rcu_apply = 0, rcu_reset_command = 0;
  logic [14:0] rcu_request = 15'h4000;
  logic [14:0] rcu_gates, rcu_resets, rcu_reset_done;
  logic rcu_done, rcu_block;
  logic [ 4:0] rcu_fault;
  logic        s_boot_release_q = 0;
  wire         s_boot_release_d;
  wire         s_cpu_ready_rst_n = rst_n;
  wire         s_xpi_cdc_ready = rst_n;
  wire         s_dma_ready_sys = rst_n;
  wire         s_rcu_link_ready = rst_n;
  wire         s_dvp_rst_n = rst_n;
  wire         s_dvp_reset_ready = dvp_ready;
  wire  [20:0] s_apb_cdc_ready = '1;
  wire  [14:0] s_reset_ready;
  `include "tiny_p9_reset_binding.svh"
tiny_peripheral_control u_rcu (
      .clk_i          (clk),
      .rst_n_i        (rst_n),
      .apply_i        (rcu_apply),
      .reset_command_i(rcu_reset_command),
      .request_i      (rcu_request),
      .idle_i         ({dvp_idle, 14'h3fff}),
      .bus_idle_i     (1'b1),
      .gate_actual_i  (rcu_gates),
      .reset_held_i   (rcu_resets),
      .reset_ready_i  ({dvp_ready, 14'h3fff}),
      .timeout_i      (32'd40),
      .gate_o         (rcu_gates),
      .reset_o        (rcu_resets),
      .reset_done_o   (rcu_reset_done),
      .block_o        (rcu_block),
      .done_o         (rcu_done),
      .fault_o        (rcu_fault)
  );

`ifdef TINY_P9_XPI
  always #20.833 clk = ~clk;
  always #500 if (pixel_run) pixel_clk = ~pixel_clk;
`else
  integer pixel_half_ns = 17;
  initial begin
    if ($value$plusargs("pixel_half_ns=%d", pixel_half_ns)) begin
    end
    if (pixel_half_ns < 1) $fatal(1, "P9 invalid pixel half-period");
  end
  always #5 clk = ~clk;
  always #(pixel_half_ns) if (pixel_run) pixel_clk = ~pixel_clk;
`endif
  apb4_if dvp_apb (
      clk,
      rst_n
  );
  apb4_if dma_apb (
      clk,
      rst_n
  );
  axi4_if #(
      .DATA_WIDTH(32)
  ) bus (
      clk,
      rst_n
  );
  axi4_stream_if camera_axis (
      clk,
      rst_n
  );
  axi4_stream_if dma_axis (
      clk,
      rst_n
  );
  axi4_stream_if i2s_tx (
      clk,
      rst_n
  );
  axi4_stream_if i2s_rx (
      clk,
      rst_n
  );
  axi4_stream_if crypto_tx (
      clk,
      rst_n
  );
  axi4_stream_if crypto_rx (
      clk,
      rst_n
  );
  dma_req_if requests ();
  dvp_if camera ();
  assign camera.pclk_i = pixel_clk;
  assign camera.href_i = href;
  assign camera.vsync_i = vsync;
  assign camera.dat_i = camera_data;

  // Delay the final word across frame-done without changing the payload.
  assign dma_axis.tdata = camera_axis.tdata;
  assign dma_axis.tkeep = camera_axis.tkeep;
  assign dma_axis.tstrb = camera_axis.tstrb;
  assign dma_axis.tlast = camera_axis.tlast;
  assign dma_axis.tuser = camera_axis.tuser;
  assign dma_axis.tid = camera_axis.tid;
  assign dma_axis.tdest = camera_axis.tdest;
  assign dma_axis.tvalid = camera_axis.tvalid && (stream_words < FrameWords - 1 || release_tail);
  assign camera_axis.tready = dma_axis.tready && (stream_words < FrameWords - 1 || release_tail);
  assign i2s_tx.tready = 0;
  assign crypto_tx.tready = 0;
  assign {i2s_rx.tdata, i2s_rx.tkeep, i2s_rx.tstrb, i2s_rx.tlast,
          i2s_rx.tid, i2s_rx.tdest, i2s_rx.tuser, i2s_rx.tvalid} = '0;
  assign {crypto_rx.tdata, crypto_rx.tkeep, crypto_rx.tstrb, crypto_rx.tlast,
          crypto_rx.tid, crypto_rx.tdest, crypto_rx.tuser, crypto_rx.tvalid} = '0;
  assign {requests.i2s_tx_proc, requests.i2s_rx_proc, requests.qspi_tx_proc,
          requests.qspi_rx_proc, requests.uart_tx_proc, requests.uart_rx_proc,
          requests.i2c0_tx_proc, requests.i2c0_rx_proc, requests.i2c1_tx_proc,
          requests.i2c1_rx_proc, requests.crypto_in_proc, requests.crypto_out_proc} = '0;

  axi4s_dvp u_dvp (
      .clk_i                  (clk),
      .rst_n_i                (rst_n),
      .apb4                   (dvp_apb),
      .rx_axis                (camera_axis),
      .dvp                    (camera),
      .irq_o                  (dvp_irq),
      .lifecycle_idle_o       (dvp_idle),
      .lifecycle_reset_ready_o(dvp_ready)
  );
  apb4_dma #(
      `include "tiny_p9_dma_parameters.svh"
  ) u_dma (
      .clk_i           (clk),
      .rst_n_i         (rst_n),
      .apb4            (dma_apb),
      .axi4            (bus),
      .hw_trg          (requests),
      .i2s_tx_axis     (i2s_tx),
      .i2s_rx_axis     (i2s_rx),
      .dvp_rx_axis     (dma_axis),
      .crypto_in_axis  (crypto_tx),
      .crypto_out_axis (crypto_rx),
      .lifecycle_idle_o(dma_idle),
      .irq_o           (dma_irq),
      .dma_xfer_done_o (dma_done)
  );

`ifdef TINY_P9_XPI
  `include "tiny_p9_xpi_sink.svh"
`else
  assign bus.awready = !write_active && !response_pending;
  assign bus.wready = write_active;
  assign bus.bvalid = response_pending && (written_words < FrameWords || release_response);
  assign bus.bid = response_id;
  assign bus.bresp = inject_write_error && written_words == FrameWords ? 2'b10 : 2'b00;
  assign bus.buser = 0;
  assign bus.arready = 0;
  assign {bus.rvalid, bus.rlast, bus.rdata, bus.rid, bus.rresp, bus.ruser} = '0;
`endif

  function automatic logic [31:0] expected_word(input int index);
    return {8'(index * 4 + 2), 8'(index * 4 + 3), 8'(index * 4), 8'(index * 4 + 1)};
  endfunction

  always @(posedge pixel_clk) begin
    if (check_start_barrier && u_dvp.s_clear_busy_q && u_dvp.s_cfg_pclk_q[96])
      $fatal(1, "P9 START passed an unacknowledged error clear");
  end

  always @(posedge clk) begin
    if (rst_n) begin
      if (u_dvp.s_frame_start_event) frame_starts <= frame_starts + 1;
      if (u_dvp.s_frame_done_event) frame_ends <= frame_ends + 1;
      if (u_dvp.s_line_done_event) line_ends <= line_ends + 1;
      if (dma_axis.tvalid && dma_axis.tready) begin
        if (dma_axis.tdata !== expected_word(
                stream_words
            ) || dma_axis.tkeep != 4'hf || dma_axis.tstrb != 4'hf ||
                dma_axis.tlast != (stream_words % (FrameWidth / 2) == FrameWidth / 2 - 1) ||
                dma_axis.tuser != (stream_words == 0))
          $fatal(1, "P9 stream data/sideband mismatch word=%0d", stream_words);
        stream_words <= stream_words + 1;
      end
      if (bus.arvalid) $fatal(1, "P9 unexpected AXI read");
      if (bus.awvalid && bus.awready) begin
        if (bus.awaddr != Destination + 32'(written_words * 4) ||
            bus.awsize != 2 || bus.awburst != 1 || bus.awlen > 3)
          $fatal(1, "P9 invalid destination/burst");
        write_active  <= 1;
        write_address <= bus.awaddr;
        burst_left    <= bus.awlen;
        response_id   <= bus.awid;
      end
      if (bus.wvalid && bus.wready) begin
        if (write_address < Destination || write_address >= Destination + FrameBytes ||
            bus.wstrb != 4'hf || bus.wlast != (burst_left == 0) ||
            bus.wdata !== expected_word(
                written_words
            ))
          $fatal(1, "P9 AXI write/guard mismatch word=%0d", written_words);
        memory[1+(write_address-Destination)/4] <= bus.wdata;
        written_words                           <= written_words + 1;
        write_address                           <= write_address + 4;
        burst_left                              <= burst_left - 1;
        if (bus.wlast) begin
          write_active     <= 0;
          response_pending <= 1;
        end
      end
      if (bus.bvalid && bus.bready) response_pending <= 0;
    end
  end

  task automatic access (input bit dma, input bit write, input logic [11:0] address,
                         input logic [31:0] data, output logic [31:0] result);
    @(negedge clk);
    if (dma) begin
      dma_apb.paddr  = {20'b0, address};
      dma_apb.pwdata = data;
      dma_apb.pwrite = write;
      dma_apb.pstrb  = write ? 4'hf : 0;
      dma_apb.psel   = 1;
    end else begin
      dvp_apb.paddr  = {20'b0, address};
      dvp_apb.pwdata = data;
      dvp_apb.pwrite = write;
      dvp_apb.pstrb  = write ? 4'hf : 0;
      dvp_apb.psel   = 1;
    end
    @(negedge clk);
    if (dma) dma_apb.penable = 1;
    else dvp_apb.penable = 1;
    do @(posedge clk); while (!(dma ? dma_apb.pready : dvp_apb.pready));
    if (dma ? dma_apb.pslverr : dvp_apb.pslverr)
      $fatal(1, "P9 APB error dma=%0d address=%h", dma, address);
    result = dma ? dma_apb.prdata : dvp_apb.prdata;
    @(negedge clk);
    dma_apb.psel    = 0;
    dma_apb.penable = 0;
    dvp_apb.psel    = 0;
    dvp_apb.penable = 0;
  endtask

  task automatic put(input bit dma, input logic [11:0] address, input logic [31:0] data);
    logic [31:0] ignored;
    access (dma, 1, address, data, ignored);
  endtask

  task automatic get(input bit dma, input logic [11:0] address, output logic [31:0] data);
    access (dma, 0, address, 0, data);
  endtask

  task automatic frame(input int width, input int height);
    @(negedge pixel_clk);
    vsync = 1;
    repeat (3) @(negedge pixel_clk);
    vsync = 0;
    repeat (2) @(negedge pixel_clk);
    for (int row = 0; row < height; row++) begin
      href = 1;
      for (int byte_index = 0; byte_index < width * 2; byte_index++) begin
        camera_data = 8'(row * ((width + 1) / 2 * 4) + byte_index);
        @(negedge pixel_clk);
      end
      href = 0;
      repeat (3) @(negedge pixel_clk);
    end
    vsync = 1;
    repeat (3) @(negedge pixel_clk);
    vsync = 0;
  endtask

  task automatic not_complete;
    get(1, 12'h220, value);
    if (!value[0] || value[4:2] != 0 || dma_idle)
      $fatal(1, "P9 early completion or DMA error status=%h", value);
    get(1, 12'h23c, value);
    if (value >= FrameBytes) $fatal(1, "P9 bytes_done published before final response");
  endtask
  task automatic reject_rcu(input bit reset_command);
    @(negedge clk);
    rcu_reset_command = reset_command;
    rcu_apply         = 1;
    @(negedge clk);
    rcu_apply = 0;
    wait (rcu_done);
    @(negedge clk);
    if (!rcu_fault[1] || rcu_gates != 0 || rcu_resets != 0 || rcu_reset_done != 0)
      $fatal(1, "P9 RCU admitted an undrained DVP operation");
  endtask
  task automatic wait_enable(input bit enabled);
    do get(0, 12'h008, value); while (value[0] !== enabled);
  endtask

  task automatic recover_source;
    put(0, 12'h04c, 3);
    // Match the HAL: ABORT traverses CDC; wait for native completion before
    // writing a configuration register that rejects writes during capture.
    do get(0, 12'h038, value); while (!value[5]);
    do get(0, 12'h008, value); while (value[1] || !value[2]);
    put(0, 12'h000, 0);
    wait_enable(0);
    repeat (100) @(negedge pixel_clk);
    put(0, 12'h038, 63);
    put(0, 12'h03c, 127);
    repeat (100) @(negedge pixel_clk);
    get(0, 12'h038, value);
    if (value != 0) $fatal(1, "P9 recovery retained error %h", value);
    get(0, 12'h008, value);
    if (!value[2] || value[1]) $fatal(1, "P9 recovery did not drain/stop");
  endtask

  task automatic recovered_pio;
    put(0, 12'h018, {16'd2, 16'd4});
    put(0, 12'h010, 0);
    put(0, 12'h00c, 0);
    put(0, 12'h000, 3);
    wait_enable(1);
    frame(4, 2);
    repeat (100) @(negedge pixel_clk);
    for (int index = 0; index < 4; index++) begin
      get(0, 12'h004, value);
      if (value !== expected_word(index)) $fatal(1, "P9 recovery payload %0d", index);
    end
    get(0, 12'h030, value);
    if (value != 4) $fatal(1, "P9 recovery word count");
    get(0, 12'h038, value);
    if (value != 0) $fatal(1, "P9 recovery frame invalid");
    get(0, 12'h008, value);
    if (!value[2] || value[1]) $fatal(1, "P9 recovery final drain");
    recover_source();
  endtask

  initial begin
    #1;
    rst_n           = 0;
    dvp_apb.psel    = 0;
    dvp_apb.penable = 0;
    dvp_apb.pwrite  = 0;
    dvp_apb.pstrb   = 0;
    dvp_apb.paddr   = 0;
    dvp_apb.pwdata  = 0;
    dvp_apb.pprot   = 0;
    dma_apb.psel    = 0;
    dma_apb.penable = 0;
    dma_apb.pwrite  = 0;
    dma_apb.pstrb   = 0;
    dma_apb.paddr   = 0;
    dma_apb.pwdata  = 0;
    dma_apb.pprot   = 0;
    for (int index = 0; index < FrameWords + 2; index++) memory[index] = 32'hcafe_babe;
    if ($test$plusargs("native_reset")) pixel_run = 0;
    repeat (5) @(negedge clk);
    rst_n = 1;
`ifdef TINY_P9_XPI
    initialize_psram();
    if ($test$plusargs("xpi_protection")) begin
      // Real XPI rejection: device is initialized but mapped writes disabled.
      // Keep source traffic and the central DMA unmodified.
      xpi_write(12'h00c, 0);
      xpi_write(12'h120, 3);
      xpi_write(12'h00c, 1);
      put(0, 12'h018, {16'(FrameHeight), 16'(FrameWidth)});
      put(0, 12'h00c, 1);
      put(0, 12'h000, 3);
      put(1, 12'h204, 32'ha2);
      put(1, 12'h20c, Destination);
      put(1, 12'h210, FrameBytes);
      put(1, 12'h214, 11);
      put(1, 12'h218, 4);
      put(1, 12'h200, 1);
      repeat (100) @(negedge pixel_clk);
      frame(FrameWidth, FrameHeight);
      wait (dma_idle);
      get(1, 12'h220, value);
      if (!value[4] || value[2] || value[0]) $fatal(1, "P9 XPI error lost at DMA");
      get(1, 12'h23c, value);
      if (value != 0) $fatal(1, "P9 rejected XPI write counted as completed");
      xpi_access(0, 12'h018, 0, xpi_value);
      if (xpi_value !== 32'h80000003) $fatal(1, "P9 XPI error code mismatch %h", xpi_value);
      $display("P9_XPI_FAULT state=%h bytes_done=%0d", xpi_value, value);
      xpi_access(0, 12'h01c, 0, xpi_value);
      if (xpi_value != Destination) $fatal(1, "P9 XPI first error address");
      xpi_access(0, 12'h020, 0, xpi_value);
      if (xpi_value !== 32'h13) $fatal(1, "P9 XPI error slot/PC mismatch %h", xpi_value);
      xpi_access(0, 12'h024, 0, xpi_value);
      if ((xpi_value & 32'h10) == 0) $fatal(1, "P9 XPI AXI-error interrupt missing");
      recover_source();
      test_owner = 1;
      for (int index = 0; index < FrameWords + 2; index++) begin
        memory_word(0, Destination - 4 + 32'(index * 4), 0, xpi_value);
        if (xpi_value !== 32'hcafebabe) $fatal(1, "P9 invalid frame modified PSRAM");
      end
      xpi_wait_idle();
      xpi_write(12'h018, 32'h80000000);
      xpi_write(12'h024, 255);
      xpi_write(12'h00c, 0);
      xpi_write(12'h120, 7);
      xpi_write(12'h00c, 1);
      memory_word(1, Destination, 32'h12345678, xpi_value);
      memory_word(0, Destination, 0, xpi_value);
      if (xpi_value !== 32'h12345678) $fatal(1, "P9 XPI recovery readback");
      recovered_pio();
      $display("SIM_TEST_PASS Tiny P9 XPI rejection diagnostics guards recovery");
      $finish;
    end
`endif
    if ($test$plusargs("row_geometry")) begin
      // Wrong source rows must not cancel in the frame totals or hide outside
      // the crop. Drive real source samples; never force counters or errors.
      for (int format = 0; format < 2; format++) begin
        for (int scenario = 0; scenario < 6; scenario++) begin
          put(0, 12'h018, scenario < 2 ? {16'd2, 16'd4} : {16'd4, 16'd8});
          put(0, 12'h01c, {16'd1, 16'd2});
          put(0, 12'h020, {16'd2, 16'd4});
          put(0, 12'h010, 32'(format));
          put(0, 12'h040, 16);
          put(0, 12'h000, scenario < 2 ? 3 : 7);
          wait_enable(1);
          @(negedge pixel_clk);
          vsync = 1;
          repeat (3) @(negedge pixel_clk);
          vsync = 0;
          repeat (3) @(negedge pixel_clk);
          for (int row = 0; row < (scenario < 2 ? 2 : 4); row++) begin
            int width;
            width = 8;
            if (scenario < 2) width = ((row + scenario) % 2 == 0) ? 6 : 2;
            else if (row == (scenario < 4 ? 0 : 1)) width = scenario % 2 == 0 ? 6 : 10;
            href = 1;
            for (int index = 0; index < width * 2; index++) begin
              camera_data = 8'(row * 16 + index);
              @(negedge pixel_clk);
            end
            href = 0;
            repeat (3) @(negedge pixel_clk);
          end
          vsync = 1;
          repeat (3) @(negedge pixel_clk);
          vsync = 0;
          repeat (100) @(negedge pixel_clk);
          get(0, 12'h038, value);
          $display("P9_ROW_SIZE format=%0d scenario=%0d error=%h", format, scenario, value);
          if (value !== 4) $fatal(1, "P9 source row width mismatch was not rejected");
          get(0, 12'h044, value);
          if ((value & 16) == 0 || !dvp_irq) $fatal(1, "P9 SIZE interrupt missing");
          put(0, 12'h03c, 16);
          repeat (100) @(negedge pixel_clk);
          if (dvp_irq) $fatal(1, "P9 cleared SIZE interrupt reasserted without new event");
          recover_source();
          recovered_pio();
        end
      end
      $display("SIM_TEST_PASS Tiny P9 source row geometry cases=12 recovery=12");
      $finish;
    end
    if ($test$plusargs("service_budget")) begin
      // At 1 MHz input, retain 480 bytes without service, below a 496-byte
      // admission budget with 16 bytes reserved for packing/in-flight skew.
      put(0, 12'h018, {16'd1, 16'd256});
      put(0, 12'h000, 3);
      wait_enable(1);
      @(negedge pixel_clk);
      vsync = 1;
      repeat (3) @(negedge pixel_clk);
      vsync = 0;
      repeat (3) @(negedge pixel_clk);
      href = 1;
      for (int index = 0; index < 480; index++) begin
        camera_data = 8'(index);
        @(negedge pixel_clk);
      end
      // Pause only the external source while the retained payload is checked.
      pixel_run = 0;
      repeat (30) @(negedge clk);
      $display("P9_BUDGET_PAUSE core_valid=%b core_data=%h", u_dvp.s_core_push_valid,
               u_dvp.s_core_push_data);
      get(0, 12'h038, value);
      if (value != 0) $fatal(1, "P9 in-budget no-service window overflowed");
      // The 120th word is held in the source output register until another
      // pixel edge can enqueue it. Drain only the 119 committed FIFO words.
      for (int index = 0; index < 119; index++) begin
        get(0, 12'h004, value);
        if (value !== expected_word(index))
          $fatal(
              1,
              "P9 retained budget payload index=%0d got=%h expected=%h",
              index,
              value,
              expected_word(
                  index
              )
          );
      end
      repeat (10) @(negedge clk);
      get(0, 12'h008, value);
      if (!value[2]) $fatal(1, "P9 stopped-source FIFO should now be empty");
      pixel_run = 1;
      for (int index = 480; index < 512; index++) begin
        camera_data = 8'(index);
        @(negedge pixel_clk);
      end
      href = 0;
      repeat (3) @(negedge pixel_clk);
      vsync = 1;
      repeat (3) @(negedge pixel_clk);
      vsync = 0;
      repeat (100) @(negedge pixel_clk);
      for (int index = 119; index < 128; index++) begin
        get(0, 12'h004, value);
        if (value !== expected_word(index)) $fatal(1, "P9 budget tail payload");
      end
      get(0, 12'h030, value);
      if (value != 128) $fatal(1, "P9 budget frame count");
      get(0, 12'h038, value);
      if (value != 0) $fatal(1, "P9 budget frame error");
      recover_source();
      put(0, 12'h018, {16'd2, 16'd256});
      put(0, 12'h000, 3);
      wait_enable(1);
      frame(256, 2);
      repeat (30) @(negedge pixel_clk);
      get(0, 12'h038, value);
      if (!value[0]) $fatal(1, "P9 beyond-capacity service loss not detected");
      recover_source();
      $display(
          "SIM_TEST_PASS Tiny P9 service budget retained_bytes=480 margin_bytes=16 overflow_rejected=1");
      $finish;
    end
    if ($test$plusargs("fault_matrix")) begin
      // Actual source samples overflow the unchanged FIFO; no DUT state force.
      put(0, 12'h018, {16'd4, 16'd256});
      put(0, 12'h000, 3);
      wait_enable(1);
      frame(256, 4);
      repeat (100) @(negedge pixel_clk);
      get(0, 12'h038, value);
      if (!value[0]) $fatal(1, "P9 real FIFO overflow not reported");
      $display("P9_FAULT overflow errors=%h", value);
      recover_source();
      recovered_pio();

      for (int fault = 0; fault < 3; fault++) begin
        put(0, 12'h018, {16'd2, 16'd4});
        put(0, 12'h000, 3);
        wait_enable(1);
        if (fault == 0) begin
          frame(4, 1);  // Missing source line must invalidate statistics.
        end else begin
          @(negedge pixel_clk);
          vsync = 1;
          repeat (3) @(negedge pixel_clk);
          vsync = 0;
          repeat (3) @(negedge pixel_clk);
          href        = 1;
          camera_data = 8'h31;
          if (fault == 1) begin
            @(negedge pixel_clk);  // An odd byte count is not an odd pixel row.
          end else begin
            vsync = 1;  // HREF/VSYNC overlap is a synchronization error.
            repeat (4) @(negedge pixel_clk);
          end
          href  = 0;
          vsync = 0;
        end
        repeat (100) @(negedge pixel_clk);
        get(0, 12'h038, value);
        if ((value & (fault == 0 ? 4 : fault == 1 ? 8 : 2)) == 0)
          $fatal(1, "P9 missing source error case=%0d errors=%h", fault, value);
        $display("P9_FAULT source_case=%0d errors=%h", fault, value);
        recover_source();
        recovered_pio();
      end
      put(0, 12'h018, {16'd2, 16'd4});
      put(0, 12'h010, 2);  // Reserved wire format, deliberately bypassing HAL.
      put(0, 12'h000, 3);
      wait_enable(1);
      repeat (100) @(negedge pixel_clk);
      get(0, 12'h038, value);
      if (!value[4]) $fatal(1, "P9 configuration error not reported");
      recover_source();
      recovered_pio();
      $display("SIM_TEST_PASS Tiny P9 actual overflow size partial sync config recovery");
      $finish;
    end
    if ($test$plusargs("crop_repeat")) begin
      for (int capture = 0; capture < 2; capture++) begin
        put(0, 12'h018, {16'd4, 16'd8});
        put(0, 12'h01c, {16'd1, 16'd2});
        put(0, 12'h020, {16'd2, 16'd4});
        put(0, 12'h010, 1);
        put(0, 12'h000, 7);
        wait_enable(1);
        frame(8, 4);
        repeat (100) @(negedge pixel_clk);
        for (int index = 0; index < 4; index++) begin
          get(0, 12'h004, value);
          if (value !== expected_word(5 + index % 2 + (index / 2) * 4))
            $fatal(1, "P9 nonzero crop data index=%0d got=%h", index, value);
        end
        get(0, 12'h02c, value);
        if (value != 8) $fatal(1, "P9 crop pixel count");
        get(0, 12'h030, value);
        if (value != 4) $fatal(1, "P9 crop word count");
        get(0, 12'h024, value);
        if (value != 32'(capture + 1)) $fatal(1, "P9 crop frame count");
        get(0, 12'h038, value);
        if (value != 0) $fatal(1, "P9 crop error");
        recover_source();
      end
      $display("SIM_TEST_PASS Tiny P9 repeated nonzero YUV crop");
      $finish;
    end
    if ($test$plusargs("abort_active") || $test$plusargs("abort_applied")) begin
      put(0, 12'h018, {16'd2, 16'd4});
      repeat (150) @(negedge pixel_clk);
      if ($test$plusargs("abort_active")) begin
        put(0, 12'h000, 3);
        wait_enable(1);
        repeat (100) @(negedge pixel_clk);
      end
      @(negedge pixel_clk);
      pixel_run = 0;
      put(0, 12'h000, 3);
      repeat (40) @(negedge clk);
      if ($test$plusargs("abort_active")) begin
        // The already armed core starts before the second config crosses.
        // That config then waits for idle; ABORT must not wait behind it.
        vsync     = 1;
        pixel_run = 1;
        repeat (100) @(negedge pixel_clk);
        vsync = 0;
        if (!u_dvp.s_active_pclk || !u_dvp.s_cfg_v_pclk)
          $fatal(1, "P9 setup: active capture has no blocked config");
      end else begin
        pixel_run = 1;
        wait (u_dvp.s_cfg_apply_pclk_q);
        #1;
        pixel_run = 0;
      end
      put(0, 12'h04c, 3);  // Combined ABORT/FLUSH remains a single command.
      pixel_run = 1;
      repeat (200) @(negedge pixel_clk);
      get(0, 12'h038, value);
      if (!(value & 32'h20) || !dvp_idle || !dvp_ready)
        $fatal(1, "P9 ABORT deadlocked behind configuration");
      begin
        int old_starts;
        old_starts = frame_starts;
        frame(4, 2);
        repeat (100) @(negedge pixel_clk);
        get(0, 12'h008, value);
        if (frame_starts != old_starts || value[1] || !value[2])
          $fatal(1, "P9 applied/pending config undid ABORT");
      end
      // Queue a genuinely later START while a new ABORT is in flight.
      put(0, 12'h000, 0);
      wait_enable(0);
      repeat (100) @(negedge pixel_clk);
      pixel_run = 0;
      put(0, 12'h04c, 1);
      put(0, 12'h000, 3);
      pixel_run = 1;
      repeat (200) @(negedge pixel_clk);
      put(0, 12'h038, 32'h3f);
      repeat (100) @(negedge pixel_clk);
      frame(4, 2);
      repeat (100) @(negedge pixel_clk);
      for (int word_index = 0; word_index < 4; word_index++) begin
        get(0, 12'h004, value);
        if (value !== expected_word(word_index)) $fatal(1, "P9 post-ABORT START was cancelled");
      end
      if (!dvp_idle) $fatal(1, "P9 post-ABORT START did not drain");
      $display("SIM_TEST_PASS Tiny P9 ABORT config application and active progress");
      $finish;
    end
    if ($test$plusargs("abort_order")) begin
      // Both mailboxes may become valid together when an external clock
      // resumes. Exercise real APB writes, including a START still held
      // behind W1C, and reuse this binary for both stopped clock levels.
      for (int stopped_high = 0; stopped_high < 2; stopped_high++) begin
        for (int queued = 0; queued < 2; queued++) begin
          put(0, 12'h000, 0);
          put(0, 12'h018, {16'd2, 16'd4});
          repeat (150) @(negedge pixel_clk);
          if (queued != 0) begin
            put(0, 12'h04c, 1);
            repeat (150) @(negedge pixel_clk);
          end
          if (stopped_high != 0) @(posedge pixel_clk);
          else @(negedge pixel_clk);
          #1;
          pixel_run = 0;
          if (queued != 0) put(0, 12'h038, 32'h3f);
          put(0, 12'h000, 3);
          repeat (40) @(negedge clk);
          if (queued == 0 && !u_dvp.s_cfg_busy_q)
            $fatal(1, "P9 setup: START did not enter config CDC");
          if (queued != 0 && !u_dvp.s_cfg_v_sys)
            $fatal(1, "P9 setup: START not pending behind W1C");
          put(0, 12'h04c, 1);
          // Repeated/coalesced ABORTs must not wrap a cancellation token.
          if (queued != 0) repeat (3) put(0, 12'h04c, 1);
          repeat (40) @(negedge clk);
          if (dvp_idle || dvp_ready) $fatal(1, "P9 abort acknowledged with stopped PIXCLK");
          pixel_run = 1;
          repeat (200) @(negedge pixel_clk);
          get(0, 12'h038, value);
          if (!(value & 32'h20)) $fatal(1, "P9 missing ordered ABORT report");
          begin
            int old_starts;
            old_starts = frame_starts;
            frame(4, 2);
            repeat (100) @(negedge pixel_clk);
            get(0, 12'h008, value);
            if (frame_starts != old_starts || value[1] || !value[2] || !dvp_idle)
              $fatal(
                  1, "P9 stale START resumed after ABORT high=%0d queued=%0d", stopped_high, queued
              );
          end
          // A later, acknowledged disable/enable must still capture data.
          put(0, 12'h038, 32'h3f);
          repeat (100) @(negedge pixel_clk);
          put(0, 12'h000, 0);
          wait_enable(0);
          put(0, 12'h000, 3);
          wait_enable(1);
          frame(4, 2);
          repeat (100) @(negedge pixel_clk);
          for (int word_index = 0; word_index < 4; word_index++) begin
            get(0, 12'h004, value);
            if (value !== expected_word(word_index))
              $fatal(1, "P9 rearm after ordered ABORT lost payload");
          end
          if (!dvp_idle) $fatal(1, "P9 ordered ABORT/rearm did not drain");
        end
      end
      $display("SIM_TEST_PASS Tiny P9 START ABORT ordering stopped-low/high");
      $finish;
    end
    if ($test$plusargs("rearm")) begin
      put(0, 12'h018, {16'd2, 16'd4});
      put(0, 12'h000, 3);
      wait_enable(1);
      for (int capture = 0; capture < 2; capture++) begin
        frame(4, 2);
        repeat (100) @(negedge pixel_clk);
        for (int word_index = 0; word_index < 4; word_index++) begin
          get(0, 12'h004, value);
          if (value !== expected_word(word_index)) $fatal(1, "P9 repeated PIO payload");
        end
        get(0, 12'h024, value);
        if (value != 32'(capture + 1)) $fatal(1, "P9 repeated snapshot frame count");
        if (capture == 0) begin
          @(negedge pixel_clk);
          pixel_run = 0;
          put(0, 12'h000, 2);
          repeat (40) @(negedge clk);
          get(0, 12'h008, value);
          if (!value[0] || dvp_idle) $fatal(1, "P9 rearm acknowledged before pixel apply");
          pixel_run = 1;
          wait_enable(0);
          put(0, 12'h000, 3);
          wait_enable(1);
        end
      end
      wait (dvp_idle);
      @(negedge clk);
      rcu_apply = 1;
      @(negedge clk);
      rcu_apply = 0;
      wait (rcu_done);
      if (rcu_fault != 0 || rcu_gates != 15'h4000) $fatal(1, "P9 drained RCU gate rejected");
      $display("SIM_TEST_PASS Tiny P9 acknowledged same-configuration rearm");
      $finish;
    end
    if ($test$plusargs("native_reset")) begin
      repeat (50) @(negedge clk);
      if (s_boot_release_d !== 1'b1 || s_reset_ready[14] !== 1'b0 || dvp_ready !== 1'b0)
        $fatal(1, "P9 camera-absent global boot binding");
      s_boot_release_q = 1;
      repeat (5) @(negedge clk);
      if (s_reset_ready[14] !== 1'b0) $fatal(1, "P9 local reset claimed absent PIXCLK ready");
      pixel_run = 1;
      repeat (100) @(negedge pixel_clk);
      if (!s_reset_ready[14]) $fatal(1, "P9 pixel reset release not acknowledged");
      pixel_run = 0;
      rst_n     = 0;
      repeat (5) @(negedge clk);
      rst_n = 1;
      repeat (50) @(negedge clk);
      if (s_reset_ready[14] !== 1'b0) $fatal(1, "P9 local reset reused old ready state");
      pixel_run = 1;
      repeat (100) @(negedge pixel_clk);
      if (!s_reset_ready[14]) $fatal(1, "P9 local reset did not recover");
      $display("SIM_TEST_PASS Tiny P9 production boot/local-reset binding");
      $finish;
    end
    if ($test$plusargs("control_pending")) begin
      repeat (100) @(negedge pixel_clk);
      pixel_run = 0;
      put(0, 12'h018, {16'd2, 16'd4});
      repeat (40) @(negedge clk);
      if (dvp_idle || dvp_ready) $fatal(1, "P9 pending configuration reported idle");
      reject_rcu(0);
      pixel_run = 1;
      repeat (100) @(negedge pixel_clk);
      pixel_run = 0;
      put(0, 12'h04c, 1);
      repeat (40) @(negedge clk);
      if (dvp_idle || dvp_ready) $fatal(1, "P9 pending command reported idle");
      reject_rcu(1);
      pixel_run = 1;
      repeat (150) @(negedge pixel_clk);
      put(0, 12'h000, 0);
      repeat (100) @(negedge pixel_clk);
      put(0, 12'h000, 3);
      repeat (100) @(negedge pixel_clk);
      if (dvp_idle) $fatal(1, "P9 armed snapshot reported idle before VSYNC");
      reject_rcu(0);
      $display("SIM_TEST_PASS Tiny P9 pending control and armed capture");
      $finish;
    end
    if ($test$plusargs("error_pair")) begin
      put(0, 12'h018, {16'd2, 16'd4});
      put(0, 12'h040, 16);
      put(0, 12'h000, 1);  // Continuous mode exposes two consecutive sync faults.
      repeat (100) @(negedge pixel_clk);
      vsync = 1;
      repeat (3) @(negedge pixel_clk);
      vsync = 0;
      repeat (6) @(negedge pixel_clk);
      wait (u_dvp.u_status_cdc.src_ready_o);
      @(posedge pixel_clk);
      @(negedge pixel_clk);
      href  = 1;
      vsync = 1;
      repeat (2) @(negedge pixel_clk);
      href  = 0;
      vsync = 0;
      repeat (100) @(negedge pixel_clk);
      get(0, 12'h038, value);
      if ((value & 6) != 6) $fatal(1, "P9 paired sync faults not generated");
      get(0, 12'h044, value);
      if ((value & 16) == 0 || !dvp_irq) $fatal(1, "P9 paired faults lost their interrupt");
      put(0, 12'h03c, 16);
      repeat (100) @(negedge pixel_clk);
      get(0, 12'h044, value);
      if ((value & 16) != 0) $fatal(1, "P9 old error level reasserted cleared interrupt");
      href  = 1;
      vsync = 1;
      repeat (2) @(negedge pixel_clk);
      href  = 0;
      vsync = 0;
      repeat (100) @(negedge pixel_clk);
      get(0, 12'h044, value);
      if ((value & 16) == 0) $fatal(1, "P9 repeated same-cause notification lost");
      $display("SIM_TEST_PASS Tiny P9 paired source errors retained");
      $finish;
    end
    if ($test$plusargs("lifecycle")) begin
      put(0, 12'h018, {16'd2, 16'd4});
      for (int stopped_high = 0; stopped_high < 2; stopped_high++) begin
        put(0, 12'h04c, 1);
        repeat (100) @(negedge pixel_clk);
        get(0, 12'h038, value);
        if (value != 32'h20) $fatal(1, "P9 missing abort report %h", value);
        if (stopped_high == 0) @(negedge pixel_clk);
        else @(posedge pixel_clk);
        pixel_run = 0;
        put(0, 12'h038, 32'h3f);
        check_start_barrier = 1;
        put(0, 12'h000, 3);
        repeat (200) @(negedge clk);
        get(0, 12'h038, value);
        if (value != 32'h20 || dvp_idle || dvp_ready)
          $fatal(1, "P9 acknowledged clear with stopped pixel clock");
        pixel_run = 1;
        repeat (100) @(negedge pixel_clk);
        get(0, 12'h038, value);
        if (value != 0 || dvp_idle) $fatal(1, "P9 clear/rearmed-state mismatch %h", value);
        check_start_barrier = 0;
        put(0, 12'h000, 0);
        repeat (100) @(negedge pixel_clk);
        if (!dvp_idle) $fatal(1, "P9 disabled source did not drain");
      end
      put(0, 12'h000, 0);
      repeat (100) @(negedge pixel_clk);
      put(0, 12'h000, 3);
      repeat (100) @(negedge pixel_clk);
      vsync = 1;
      repeat (3) @(negedge pixel_clk);
      vsync = 0;
      repeat (3) @(negedge pixel_clk);
      pixel_run = 0;
      put(0, 12'h038, 32'h3f);
      pixel_run = 1;
      wait (u_dvp.s_clear_valid_pclk);
      @(negedge pixel_clk);
      href  = 1;
      vsync = 1;
      @(negedge pixel_clk);
      href  = 0;
      vsync = 0;
      repeat (100) @(negedge pixel_clk);
      get(0, 12'h038, value);
      if ((value & 32'h6) != 32'h6)
        $fatal(1, "P9 new pixel error lost to simultaneous clear %h", value);
      $display("SIM_TEST_PASS Tiny P9 clear recovery stopped-low/high");
      $finish;
    end
    put(0, 12'h018, {16'(FrameHeight), 16'(FrameWidth)});
    put(0, 12'h00c, 1);
    put(0, 12'h040, 4);
    put(0, 12'h000, 3);
    put(1, 12'h204, 32'ha2);  // stream-to-MM, width32, increment destination
    put(1, 12'h20c, Destination);
    put(1, 12'h210, FrameBytes);
    put(1, 12'h214, 11);
    put(1, 12'h218, 4);
    put(1, 12'h200, 1);
    not_complete();  // Proves request 11 is admitted on channel 2.
    repeat (100) @(negedge pixel_clk);
    frame(FrameWidth, FrameHeight);
    wait (dvp_irq && camera_axis.tvalid && stream_words == FrameWords - 1);
    repeat (30) @(negedge clk);
    get(0, 12'h024, value);
    if (value != 1 || dvp_idle) $fatal(1, "P9 frame-done/tail lifecycle mismatch");
    not_complete();
    release_tail = 1;
    wait (written_words == FrameWords && response_pending);
    repeat (30) @(negedge clk);
    not_complete();
    release_response = 1;
    wait (dma_idle);
    get(1, 12'h220, value);
    if (inject_write_error) begin
      if (!value[4] || value[2] || value[0] || response_pending)
        $fatal(1, "P9 late write error advertised completion status=%h", value);
      get(1, 12'h23c, value);
      if (value >= FrameBytes) $fatal(1, "P9 late write error counted unconfirmed bytes");
      get(1, 12'h228, value);
      if (value == 0) $fatal(1, "P9 late write error missing diagnostic");
      $display("SIM_TEST_PASS Tiny P9 focused DVP DMA late response error");
      $finish;
    end
    if (!value[2] || value[4] || value[0]) $fatal(1, "P9 DMA completion status=%h", value);
    get(1, 12'h23c, value);
    if (value != FrameBytes) $fatal(1, "P9 exact bytes_done mismatch");
    get(1, 12'h238, value);
    if (value != 0) $fatal(1, "P9 remaining bytes not zero");
    wait (dvp_idle && dvp_ready);
    get(0, 12'h038, value);
    if (value != 0 || !dvp_idle || !dvp_ready || response_pending)
      $fatal(1, "P9 drain/error/lifecycle mismatch errors=%h", value);
`ifdef TINY_P9_XPI
    verify_psram();
`endif
    for (int index = 0; index < FrameWords; index++)
    if (memory[index+1] !== expected_word(index))
      $fatal(
          1,
          "P9 readback mismatch index=%0d got=%h expected=%h",
          index,
          memory[index+1],
          expected_word(
              index
          )
      );
    if (memory[0] != 32'hcafe_babe || memory[FrameWords+1] != 32'hcafe_babe)
      $fatal(1, "P9 canary changed");
    // Another sensor frame must not restart a completed snapshot.
    frame(FrameWidth, FrameHeight);
    repeat (30) @(negedge clk);
    get(0, 12'h024, value);
    if (value != 1 || stream_words != FrameWords || !dvp_idle)
      $fatal(1, "P9 snapshot restarted without rearm");

    // A 7x3 odd-width frame has a partial word at each line end.
    put(0, 12'h000, 0);
    repeat (100) @(negedge pixel_clk);
    put(0, 12'h00c, 0);
    put(0, 12'h018, {16'd3, 16'd7});
    put(0, 12'h03c, 127);
    put(0, 12'h000, 3);
    repeat (100) @(negedge pixel_clk);
    frame(7, 3);
    wait (dvp_irq);
    repeat (30) @(negedge clk);
    for (int index = 0; index < 12; index++) begin
      get(0, 12'h008, value);
      if (value[2]) $fatal(1, "P9 PIO FIFO empty early");
      get(0, 12'h004, value);
      if (value !== ((index % 4 != 3) ? expected_word(index) : (expected_word(index) & 32'hffff)))
        $fatal(1, "P9 odd-width PIO mismatch word=%0d value=%h", index, value);
    end
    get(0, 12'h008, value);
    if (!value[2] || !dvp_idle || written_words != FrameWords)
      $fatal(1, "P9 PIO final drain mismatch");
    get(0, 12'h024, value);
    if (value != 2) $fatal(1, "P9 PIO frame count mismatch");
    get(0, 12'h038, value);
    if (value != 0) $fatal(1, "P9 PIO error=%h", value);
    if (frame_starts != 2 || frame_ends != 2 || line_ends != FrameHeight + 3)
      $fatal(1, "P9 repeated toggle event lost");
    $display(
        "SIM_TEST_PASS Tiny P9 focused DVP DMA bytes=256 tail_hold_min=30 response_hold_min=30 pio_bytes=42");
    $finish;
  end
  initial begin
    if ($test$plusargs("service_budget")) #4000000;
    else #2000000;
    $display(
        "P9_DIAG stream=%0d writes=%0d irq=%b tail=%b response=%b idle=%b/%b cfg=%h active=%b errors=%h",
        stream_words, written_words, dvp_irq, release_tail, release_response, dvp_idle, dma_idle,
        u_dvp.s_cfg_pclk_q, u_dvp.s_active, u_dvp.s_err_flags_pclk);
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P9 focused DVP DMA");
  end
endmodule
`undef TINY_P9_FIXTURE
