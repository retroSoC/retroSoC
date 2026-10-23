// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// HP lifecycle release-window transaction retention test. Composes the exact
// release path used by retrosoc.sv: the AON lifecycle controller, the two
// cdc_sync chains into the HP domain, the MMIO address gate and the HP-to-LP
// async bridge, and proves that writes/reads issued in the same HP cycle as
// the release completes intact, that a full stop/re-release cycle leaves the
// chain clean, and that a transaction held at the gate during drain is
// dropped without corrupting the next release window.

`timescale 1ns / 1ps

`include "axi4_define.svh"

module hp_release_window_tb;
  logic clk_hp_i = 1'b0;
  logic clk_lp_i = 1'b0;
  logic clk_aon_i = 1'b0;
  logic rst_hp_n_i = 1'b0;
  logic rst_lp_n_i = 1'b0;
  logic rst_aon_n_i = 1'b0;

  logic release_req_i = 1'b0;
  logic hp_idle_i = 1'b1;
  logic flush_busy_i;
  logic cache_clean_i = 1'b0;
  logic s_cdc_clear_busy;

  logic s_release_aon;
  logic s_block_aon;
  logic s_flush_aon;
  logic s_hp_release_hp;
  logic s_hp_block_hp;
  logic s_hp_recovery_hp;
  logic s_hp_flush_hp;

  always #5 clk_hp_i = ~clk_hp_i;
  always #17 clk_lp_i = ~clk_lp_i;
  always #40 clk_aon_i = ~clk_aon_i;

  // As in the SoC, the lifecycle controller's flush-busy input tracks the
  // bridge's clear-busy report: flush stays asserted until the bridge has
  // fully cycled its warm flush.
  assign flush_busy_i = s_cdc_clear_busy;

  // The exact lifecycle wiring from retrosoc.sv.
  hp_lifecycle_controller u_dut_lifecycle (
      .clk_i          (clk_aon_i),
      .rst_n_i        (rst_aon_n_i),
      .release_req_i  (release_req_i),
      .hp_idle_i      (hp_idle_i),
      .flush_busy_i   (flush_busy_i),
      .cache_clean_i  (cache_clean_i),
      .timeout_i      (16'd64),
      .hp_release_o   (s_release_aon),
      .block_new_o    (s_block_aon),
      .flush_o        (s_flush_aon),
      .cache_request_o(),
      .draining_o     (),
      .forced_fault_o ()
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_hp_release_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_release_aon),
      .dat_o  (s_hp_release_hp)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(3)
  ) u_hp_lifecycle_control_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  ({s_block_aon, 1'b0, s_flush_aon}),
      .dat_o  ({s_hp_block_hp, s_hp_recovery_hp, s_hp_flush_hp})
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_gate_src_if (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_gate_sink_if (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_lp_if (
      .aclk   (clk_lp_i),
      .aresetn(rst_lp_n_i)
  );

  axi4_address_gate u_dut_gate (
      .clk_i          (clk_hp_i),
      .rst_n_i        (rst_hp_n_i),
      .block_new_i    (s_hp_block_hp),
      .clear_i        (s_hp_flush_hp),
      .source         (u_gate_src_if),
      .sink           (u_gate_sink_if),
      .idle_o         (),
      .write_pending_o()
  );

  axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1)
  ) u_dut_cdc (
      .src_clk_i   (clk_hp_i),
      .src_rst_n_i (rst_hp_n_i),
      .dst_clk_i   (clk_lp_i),
      .dst_rst_n_i (rst_lp_n_i),
      .clear_i     (s_hp_flush_hp),
      .clear_busy_o(s_cdc_clear_busy),
      .epoch_o     (),
      .src_axi4    (u_gate_sink_if),
      .dst_axi4    (u_lp_if)
  );

  // ---------------- LP-side slave stub ----------------
  logic [31:0] s_stub_writes      [8];
  int          s_stub_write_count;
  logic        s_wr_active_q;
  logic [31:0] s_wr_addr_q;
  logic        s_rd_active_q;
  logic [31:0] s_rd_addr_q;

  assign u_lp_if.bid   = '0;
  assign u_lp_if.buser = '0;
  assign u_lp_if.bresp = `AXI4_RESP_OKAY;
  assign u_lp_if.rid   = '0;
  assign u_lp_if.ruser = '0;
  assign u_lp_if.rresp = `AXI4_RESP_OKAY;

  always_ff @(posedge clk_lp_i or negedge rst_lp_n_i) begin
    if (!rst_lp_n_i) begin
      u_lp_if.awready    <= 1'b0;
      u_lp_if.wready     <= 1'b0;
      u_lp_if.bvalid     <= 1'b0;
      u_lp_if.arready    <= 1'b0;
      u_lp_if.rvalid     <= 1'b0;
      u_lp_if.rlast      <= 1'b0;
      u_lp_if.rdata      <= '0;
      s_wr_active_q      <= 1'b0;
      s_wr_addr_q        <= '0;
      s_rd_active_q      <= 1'b0;
      s_rd_addr_q        <= '0;
      s_stub_write_count <= 0;
    end else begin
      if (!s_wr_active_q && !u_lp_if.bvalid) begin
        u_lp_if.awready <= 1'b1;
        if (u_lp_if.awvalid && u_lp_if.awready) begin
          s_wr_active_q   <= 1'b1;
          s_wr_addr_q     <= u_lp_if.awaddr;
          u_lp_if.awready <= 1'b0;
        end
      end
      u_lp_if.wready <= s_wr_active_q;
      if (s_wr_active_q && u_lp_if.wvalid && u_lp_if.wready) begin
        if (s_stub_write_count < 8) begin
          s_stub_writes[s_stub_write_count] <= {s_wr_addr_q[15:0], u_lp_if.wdata[15:0]};
          s_stub_write_count                <= s_stub_write_count + 1;
        end
        if (u_lp_if.wlast) begin
          s_wr_active_q  <= 1'b0;
          u_lp_if.bvalid <= 1'b1;
        end
      end
      if (u_lp_if.bvalid && u_lp_if.bready) u_lp_if.bvalid <= 1'b0;

      if (!s_rd_active_q && !u_lp_if.rvalid) begin
        u_lp_if.arready <= 1'b1;
        if (u_lp_if.arvalid && u_lp_if.arready) begin
          s_rd_active_q   <= 1'b1;
          s_rd_addr_q     <= u_lp_if.araddr;
          u_lp_if.arready <= 1'b0;
          u_lp_if.rvalid  <= 1'b1;
          u_lp_if.rdata   <= 32'hC0DE_0000 ^ u_lp_if.araddr;
          u_lp_if.rlast   <= (u_lp_if.arlen == 8'd0);
        end
      end else if (u_lp_if.rvalid && u_lp_if.rready) begin
        if (u_lp_if.rlast) begin
          u_lp_if.rvalid <= 1'b0;
          u_lp_if.rlast  <= 1'b0;
          s_rd_active_q  <= 1'b0;
        end else begin
          s_rd_addr_q   <= s_rd_addr_q + 32'd4;
          u_lp_if.rdata <= 32'hC0DE_0000 ^ (s_rd_addr_q + 32'd4);
          u_lp_if.rlast <= '0;
        end
      end
    end
  end

  // ---------------- HP-side BFM ----------------
  logic        s_bvalid_seen;
  logic [31:0] s_last_rdata;
  logic [31:0] s_last_rdata_addr;

  task automatic bfm_idle;
    begin
      u_gate_src_if.awid     = '0;
      u_gate_src_if.awaddr   = '0;
      u_gate_src_if.awlen    = '0;
      u_gate_src_if.awsize   = 3'd2;
      u_gate_src_if.awburst  = `AXI4_BURST_TYPE_INCR;
      u_gate_src_if.awlock   = '0;
      u_gate_src_if.awcache  = '0;
      u_gate_src_if.awprot   = '0;
      u_gate_src_if.awqos    = '0;
      u_gate_src_if.awregion = '0;
      u_gate_src_if.awuser   = '0;
      u_gate_src_if.awvalid  = 1'b0;
      u_gate_src_if.wdata    = '0;
      u_gate_src_if.wstrb    = '0;
      u_gate_src_if.wlast    = 1'b0;
      u_gate_src_if.wuser    = '0;
      u_gate_src_if.wvalid   = 1'b0;
      u_gate_src_if.bready   = 1'b0;
      u_gate_src_if.arid     = '0;
      u_gate_src_if.araddr   = '0;
      u_gate_src_if.arlen    = '0;
      u_gate_src_if.arsize   = 3'd2;
      u_gate_src_if.arburst  = `AXI4_BURST_TYPE_INCR;
      u_gate_src_if.arlock   = '0;
      u_gate_src_if.arcache  = '0;
      u_gate_src_if.arprot   = '0;
      u_gate_src_if.arqos    = '0;
      u_gate_src_if.arregion = '0;
      u_gate_src_if.aruser   = '0;
      u_gate_src_if.arvalid  = 1'b0;
      u_gate_src_if.rready   = 1'b0;
    end
  endtask

  task automatic bfm_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      @(negedge clk_hp_i);
      u_gate_src_if.awaddr  = addr;
      u_gate_src_if.awvalid = 1'b1;
      u_gate_src_if.wdata   = data;
      u_gate_src_if.wstrb   = 4'hF;
      u_gate_src_if.wlast   = 1'b1;
      u_gate_src_if.wvalid  = 1'b1;
      u_gate_src_if.bready  = 1'b1;
      do @(posedge clk_hp_i); while (!u_gate_src_if.awready);
      @(negedge clk_hp_i);
      u_gate_src_if.awvalid = 1'b0;
      do @(posedge clk_hp_i); while (!u_gate_src_if.wready);
      @(negedge clk_hp_i);
      u_gate_src_if.wvalid = 1'b0;
      wait (u_gate_src_if.bvalid);
      if (u_gate_src_if.bresp != `AXI4_RESP_OKAY) $fatal(1, "write response not OKAY");
      @(negedge clk_hp_i);
      u_gate_src_if.bready = 1'b0;
    end
  endtask

  task automatic bfm_read(input logic [31:0] addr);
    begin
      @(negedge clk_hp_i);
      u_gate_src_if.araddr  = addr;
      u_gate_src_if.arvalid = 1'b1;
      u_gate_src_if.rready  = 1'b1;
      do @(posedge clk_hp_i); while (!u_gate_src_if.arready);
      @(negedge clk_hp_i);
      u_gate_src_if.arvalid = 1'b0;
      wait (u_gate_src_if.rvalid);
      if (!u_gate_src_if.rlast || u_gate_src_if.rresp != `AXI4_RESP_OKAY) begin
        $fatal(1, "read response malformed");
      end
      s_last_rdata      = u_gate_src_if.rdata;
      s_last_rdata_addr = addr;
      @(negedge clk_hp_i);
      u_gate_src_if.rready = 1'b0;
    end
  endtask

  task automatic complete_stop;
    begin
      // Drive the exact lifecycle stop handshake: the flush-busy level comes
      // from the bridge's clear-busy report, as on the SoC data plane.
      @(negedge clk_aon_i);
      release_req_i = 1'b0;
      wait (!s_release_aon);
    end
  endtask

  // Watchdog: the whole test must complete well within this budget.
  initial begin
    #5_000_000;
    $fatal(1, "global timeout");
  end

  initial begin
    bfm_idle();
    s_stub_write_count = 0;
    repeat (4) @(posedge clk_hp_i);
    rst_hp_n_i  = 1'b1;
    rst_lp_n_i  = 1'b1;
    rst_aon_n_i = 1'b1;
    repeat (4) @(posedge clk_aon_i);

    // Scenario a+b: write and read issued in the same HP cycle that the
    // synced release asserts.
    release_req_i = 1'b1;
    wait (s_hp_release_hp);
    fork
      bfm_write(32'h1001_9000, 32'hA5A5_0001);
      bfm_read(32'h1001_8000);
    join
    if (s_last_rdata != (32'hC0DE_0000 ^ 32'h1001_8000))
      $fatal(1, "release-window read data mismatch");
    repeat (4) @(posedge clk_lp_i);
    if (s_stub_write_count != 1 || s_stub_writes[0] != 32'h9000_0001) begin
      $fatal(1, "release-window write did not reach the LP side intact");
    end

    // Full stop, then re-release; the chain must be clean.
    complete_stop();
    repeat (2) @(posedge clk_aon_i);
    release_req_i = 1'b1;
    wait (s_hp_release_hp);
    fork
      bfm_write(32'h1001_9004, 32'h5A5A_0002);
      bfm_read(32'h1001_8004);
    join
    if (s_last_rdata != (32'hC0DE_0000 ^ 32'h1001_8004)) begin
      $fatal(1, "post-stop release-window read data mismatch");
    end
    repeat (4) @(posedge clk_lp_i);
    if (s_stub_write_count != 2 || s_stub_writes[1] != 32'h9004_0002) begin
      $fatal(1, "post-stop release-window write did not reach the LP side intact");
    end

    // Scenario c: a write presented while the gate blocks (drain phase) is
    // held, then dropped by flush; the BFM withdraws it when the HP re-holds,
    // and the next release window still works.
    release_req_i = 1'b1;
    wait (s_hp_release_hp);
    @(negedge clk_aon_i);
    release_req_i = 1'b0;
    wait (s_hp_block_hp);
    @(negedge clk_hp_i);
    u_gate_src_if.awaddr  = 32'h1001_9008;
    u_gate_src_if.awvalid = 1'b1;
    u_gate_src_if.wdata   = 32'hDEAD_BEEF;
    u_gate_src_if.wstrb   = 4'hF;
    u_gate_src_if.wlast   = 1'b1;
    u_gate_src_if.wvalid  = 1'b1;
    repeat (4) @(posedge clk_hp_i);
    if (u_gate_src_if.awready) $fatal(1, "gate accepted a new write while blocking");
    // Complete the drain handshake so the lifecycle can re-hold the HP; the
    // flush-busy level is driven by the bridge's clear-busy report.
    wait (!s_hp_release_hp);
    @(negedge clk_hp_i);
    u_gate_src_if.awvalid = 1'b0;
    u_gate_src_if.wvalid  = 1'b0;
    repeat (4) @(posedge clk_aon_i);
    release_req_i = 1'b1;
    wait (s_hp_release_hp);
    bfm_write(32'h1001_900C, 32'h1234_5678);
    repeat (4) @(posedge clk_lp_i);
    if (s_stub_write_count != 3 || s_stub_writes[2] != 32'h900C_5678) begin
      $fatal(1, "third release-window write did not reach the LP side intact");
    end
    if (s_stub_writes[2] == 32'h9008_BEEF) begin
      $fatal(1, "the drain-held write leaked into the next release window");
    end

    $display("HP release window transaction retention test passed");
    $finish;
  end
endmodule
