// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Focused OpenC906 boot test: runs the real HP smoke payload (hp_smoke.bin,
// preloaded at the 0x38000000 reset vector) on the hp_core_wrapper integration
// (C906 + tdt_dmi_top + axi4_downsizer_128to64 + axi4_mmio_demux) and drives
// the MMIO port through the same chain the SoC uses (axi4_downsizer_64to32,
// axi4_address_gate, axi4_async_bridge into the LP clock domain) to a 32-bit
// MMIO stub modelling UART1 TX and the HP mailbox registers.
//
// Passes when the payload prints HP_SMOKE_READY over UART1, posts the mailbox
// ready event, accepts the injected GA2D start command, and completes the
// GA2D phase (the GA2D engine itself is stubbed, so the expected result event
// is the payload's fail path).
//
// The payload binary is supplied as a byte-wide hex file via `HP_SMOKE_HEX`.

`timescale 1ns / 1ps

`include "axi4_define.svh"

module hp_c906_boot_tb;
  localparam logic [31:0] RamBase = 32'h3800_0000;
  localparam int RamBytes = 128 * 1024;
  localparam logic [31:0] Uart1Base = 32'h1001_8000;
  localparam logic [31:0] MailboxBase = 32'h1001_9000;
  localparam int MaxCycles = 4_000_000;

  logic        clk_i = 1'b0;
  logic        clk_lp_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        rst_lp_n_i = 1'b0;
  logic        core_reset_i = 1'b1;
  logic [63:0] time_i = '0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) mem_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) mmio_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_mmio_narrow_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_mmio_gated_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_mmio_lp_if (
      .aclk   (clk_lp_i),
      .aresetn(rst_lp_n_i)
  );

  always #5 clk_i = ~clk_i;
  always #17 clk_lp_i = ~clk_lp_i;
  always @(posedge clk_i) time_i <= time_i + 64'd1;

  hp_core_wrapper u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .core_reset_i     (core_reset_i),
      .time_i           (time_i),
      .plic_src_i       ('0),
      .jtag_tck_i       (1'b0),
      .jtag_tms_i       (1'b1),
      .jtag_tdi_i       (1'b0),
      .jtag_trst_n_i    (1'b1),
      .jtag_tdo_o       (),
      .debug_reset_req_o(),
      .mem_axi4         (mem_axi4),
      .mmio_axi4        (mmio_axi4)
  );

  // The SoC MMIO chain: 64->32 downsizer, address gate, HP->LP CDC bridge.
  axi4_downsizer_64to32 u_mmio_downsizer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(1'b0),
      .wide   (mmio_axi4),
      .narrow (u_mmio_narrow_if)
  );

  axi4_address_gate u_mmio_gate (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .block_new_i    (1'b0),
      .clear_i        (1'b0),
      .source         (u_mmio_narrow_if),
      .sink           (u_mmio_gated_if),
      .idle_o         (),
      .write_pending_o()
  );

  axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1)
  ) u_mmio_cdc (
      .src_clk_i   (clk_i),
      .src_rst_n_i (rst_n_i),
      .dst_clk_i   (clk_lp_i),
      .dst_rst_n_i (rst_lp_n_i),
      .clear_i     (1'b0),
      .clear_busy_o(),
      .epoch_o     (),
      .src_axi4    (u_mmio_gated_if),
      .dst_axi4    (u_mmio_lp_if)
  );

  // ---------------- 64-bit AXI4 RAM (mem port) ----------------
  // Single outstanding per channel matches the serializing downsizer.
  logic [ 7:0] ram           [RamBytes];
  logic [31:0] s_rd_addr_q;
  logic [ 7:0] s_rd_len_q;
  logic [ 1:0] s_rd_burst_q;
  logic        s_rd_active_q;
  logic [31:0] s_wr_addr_q;
  logic        s_wr_active_q;

  assign mem_axi4.bid   = '0;
  assign mem_axi4.buser = '0;
  assign mem_axi4.rid   = '0;
  assign mem_axi4.ruser = '0;
  assign mem_axi4.rresp = `AXI4_RESP_OKAY;
  assign mem_axi4.bresp = `AXI4_RESP_OKAY;

  function automatic logic [31:0] next_addr(input logic [31:0] addr, input logic [1:0] burst);
    if (burst == `AXI4_BURST_TYPE_WRAP) begin
      return (addr & ~32'd63) | ((addr + 32'd8) & 32'd63);
    end
    return addr + 32'd8;
  endfunction

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      mem_axi4.arready <= 1'b0;
      mem_axi4.rvalid  <= 1'b0;
      mem_axi4.rlast   <= 1'b0;
      s_rd_active_q    <= 1'b0;
      mem_axi4.awready <= 1'b0;
      mem_axi4.wready  <= 1'b0;
      mem_axi4.bvalid  <= 1'b0;
      s_wr_active_q    <= 1'b0;
      s_rd_addr_q      <= '0;
      s_rd_len_q       <= '0;
      s_rd_burst_q     <= '0;
      s_wr_addr_q      <= '0;
    end else begin
      // Read address accept.
      if (!s_rd_active_q && !mem_axi4.rvalid) begin
        mem_axi4.arready <= 1'b1;
        if (mem_axi4.arvalid && mem_axi4.arready) begin
          s_rd_active_q    <= 1'b1;
          s_rd_addr_q      <= mem_axi4.araddr;
          s_rd_len_q       <= mem_axi4.arlen;
          s_rd_burst_q     <= mem_axi4.arburst;
          mem_axi4.arready <= 1'b0;
        end
      end
      // Read data.
      if (s_rd_active_q && !mem_axi4.rvalid) begin
        for (int b = 0; b < 8; b++) begin
          mem_axi4.rdata[b*8+:8] <= ram[s_rd_addr_q-RamBase+32'(b)];
        end
        mem_axi4.rlast  <= (s_rd_len_q == 8'd0);
        mem_axi4.rvalid <= 1'b1;
      end else if (mem_axi4.rvalid && mem_axi4.rready) begin
        if (mem_axi4.rlast) begin
          mem_axi4.rvalid <= 1'b0;
          mem_axi4.rlast  <= 1'b0;
          s_rd_active_q   <= 1'b0;
        end else begin
          s_rd_addr_q     <= next_addr(s_rd_addr_q, s_rd_burst_q);
          s_rd_len_q      <= s_rd_len_q - 8'd1;
          mem_axi4.rvalid <= 1'b0;
        end
      end
      // Write address accept.
      if (!s_wr_active_q && !mem_axi4.bvalid) begin
        mem_axi4.awready <= 1'b1;
        if (mem_axi4.awvalid && mem_axi4.awready) begin
          s_wr_active_q    <= 1'b1;
          s_wr_addr_q      <= mem_axi4.awaddr;
          mem_axi4.awready <= 1'b0;
        end
      end
      // Write data.
      mem_axi4.wready <= s_wr_active_q;
      if (s_wr_active_q && mem_axi4.wvalid && mem_axi4.wready) begin
        for (int b = 0; b < 8; b++) begin
          if (mem_axi4.wstrb[b]) ram[s_wr_addr_q-RamBase+32'(b)] <= mem_axi4.wdata[b*8+:8];
        end
        if (mem_axi4.wlast) begin
          s_wr_active_q   <= 1'b0;
          mem_axi4.bvalid <= 1'b1;
        end else begin
          s_wr_addr_q <= s_wr_addr_q + 32'd8;
        end
      end
      if (mem_axi4.bvalid && mem_axi4.bready) mem_axi4.bvalid <= 1'b0;
    end
  end

  // ---------------- 32-bit MMIO stub (LP clock domain) -------------
  logic [31:0] s_mmio_wr_addr_q;
  logic        s_mmio_wr_active_q;
  logic [ 7:0] s_mmio_rd_len_q;
  logic        s_saw_ready_q;
  logic [31:0] s_result_event_q;

  assign u_mmio_lp_if.bid   = '0;
  assign u_mmio_lp_if.buser = '0;
  assign u_mmio_lp_if.rid   = '0;
  assign u_mmio_lp_if.ruser = '0;
  assign u_mmio_lp_if.rresp = `AXI4_RESP_OKAY;
  assign u_mmio_lp_if.bresp = `AXI4_RESP_OKAY;

  always_ff @(posedge clk_lp_i or negedge rst_lp_n_i) begin
    if (!rst_lp_n_i) begin
      u_mmio_lp_if.arready <= 1'b0;
      u_mmio_lp_if.rvalid  <= 1'b0;
      u_mmio_lp_if.rlast   <= 1'b0;
      u_mmio_lp_if.awready <= 1'b0;
      u_mmio_lp_if.wready  <= 1'b0;
      u_mmio_lp_if.bvalid  <= 1'b0;
      s_mmio_wr_active_q   <= 1'b0;
      s_mmio_wr_addr_q     <= '0;
      s_mmio_rd_len_q      <= '0;
      s_saw_ready_q        <= 1'b0;
      s_result_event_q     <= '0;
    end else begin
      if (!u_mmio_lp_if.rvalid) begin
        u_mmio_lp_if.arready <= 1'b1;
        if (u_mmio_lp_if.arvalid && u_mmio_lp_if.arready) begin
          u_mmio_lp_if.arready <= 1'b0;
          u_mmio_lp_if.rvalid  <= 1'b1;
          // UART1 STATUS reads report TX ready (all status bits clear).
          u_mmio_lp_if.rdata   <= '0;
          if (s_saw_ready_q) begin
            // Once the payload is ready, drive the LP-side GA2D start
            // command into the mailbox read registers.
            if (u_mmio_lp_if.araddr == (MailboxBase + 32'h18)) u_mmio_lp_if.rdata <= 32'd1;
            if (u_mmio_lp_if.araddr == (MailboxBase + 32'h10)) u_mmio_lp_if.rdata <= 32'h4741_3250;
            if (u_mmio_lp_if.araddr == (MailboxBase + 32'h14)) u_mmio_lp_if.rdata <= 32'h4741_3244;
          end
          // GA2D STATUS (0x10012014): done (bit 4), no error/busy.
          if (u_mmio_lp_if.araddr == 32'h1001_2014) u_mmio_lp_if.rdata <= 32'h10;
          s_mmio_rd_len_q    <= u_mmio_lp_if.arlen;
          u_mmio_lp_if.rlast <= (u_mmio_lp_if.arlen == 8'd0);
        end
      end else if (u_mmio_lp_if.rvalid && u_mmio_lp_if.rready) begin
        if (u_mmio_lp_if.rlast) begin
          u_mmio_lp_if.rvalid <= 1'b0;
          u_mmio_lp_if.rlast  <= 1'b0;
        end else begin
          s_mmio_rd_len_q    <= s_mmio_rd_len_q - 8'd1;
          u_mmio_lp_if.rlast <= (s_mmio_rd_len_q == 8'd1);
        end
      end
      if (!s_mmio_wr_active_q && !u_mmio_lp_if.bvalid) begin
        u_mmio_lp_if.awready <= 1'b1;
        if (u_mmio_lp_if.awvalid && u_mmio_lp_if.awready) begin
          s_mmio_wr_active_q   <= 1'b1;
          s_mmio_wr_addr_q     <= u_mmio_lp_if.awaddr;
          u_mmio_lp_if.awready <= 1'b0;
        end
      end
      u_mmio_lp_if.wready <= s_mmio_wr_active_q;
      if (s_mmio_wr_active_q && u_mmio_lp_if.wvalid && u_mmio_lp_if.wready) begin
        if (s_mmio_wr_addr_q == (Uart1Base + 32'h10)) begin
          $write("%c", 8'(u_mmio_lp_if.wdata[7:0]));
        end
        if ((s_mmio_wr_addr_q == (MailboxBase + 32'h24)) &&
            (u_mmio_lp_if.wdata == 32'h4c4e_5801)) begin
          s_saw_ready_q <= 1'b1;
        end
        // HP_EVENT writes (MailboxBase+0x20): the first event is the ready
        // notification; any later event is a GA2D-phase result (2=pass,
        // 3=fail, 4=cache).
        if (s_saw_ready_q && (s_mmio_wr_addr_q == (MailboxBase + 32'h20)) &&
            (u_mmio_lp_if.wdata != 32'd1)) begin
          s_result_event_q <= u_mmio_lp_if.wdata;
        end
        if (u_mmio_lp_if.wlast) begin
          s_mmio_wr_active_q  <= 1'b0;
          u_mmio_lp_if.bvalid <= 1'b1;
        end
      end
      if (u_mmio_lp_if.bvalid && u_mmio_lp_if.bready) u_mmio_lp_if.bvalid <= 1'b0;
    end
  end

  // ---------------- sequence ----------------
  int   s_cycle;
  logic s_done;
  initial begin
`ifdef HP_SMOKE_HEX
    $readmemh(`HP_SMOKE_HEX, ram, 0);
`else
    $fatal(1, "HP_SMOKE_HEX define missing");
`endif
    s_done = 1'b0;
    repeat (20) @(posedge clk_i);
    rst_n_i    = 1'b1;
    rst_lp_n_i = 1'b1;
    repeat (20) @(posedge clk_i);
    core_reset_i = 1'b0;
    for (s_cycle = 0; s_cycle < MaxCycles; s_cycle++) begin
      @(posedge clk_i);
      if (s_saw_ready_q && (s_result_event_q != 32'd0)) begin
        s_done = 1'b1;
        break;
      end
    end
    if (s_done) begin
      $display("\nC906 booted the HP smoke payload: HP_SMOKE_READY printed,");
      $display("the mailbox ready event was posted, the GA2D start command was");
      $display("accepted, and the payload completed the GA2D phase with event %0d",
               s_result_event_q);
      $display("(the TB stubs the GA2D engine, so a fail event is expected here)");
      $display("HP_C906_BOOT_TEST_PASS");
    end else if (s_saw_ready_q) begin
      $fatal(1, "payload stalled between ready and the GA2D-phase result event");
    end else begin
      $fatal(1, "timeout waiting for the HP smoke ready mailbox event");
    end
    $finish;
  end
endmodule
