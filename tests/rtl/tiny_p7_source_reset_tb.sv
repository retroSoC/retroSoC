`timescale 1ns / 1ps
`include "tiny_topology.svh"

// Production DMA master, admission, CDC and lifecycle/reset components. The
// include is extracted from the current top and its generated bindings by the
// Python test. Unrelated CPU/APB/SDIO clients are idle; the AXI target is a
// backpressured behavioral slave. No reset command bypasses the controller.
module tiny_p7_source_reset_tb;
  logic s_ref_clk = 0, s_exec_clk = 0, s_backend_pclk = 0, s_backend_mem_clk = 0;
  realtime sys_half = 20.833333, pclk_half = 20.833333, mem_half = 20.833333;
  always #20.833333 s_ref_clk = !s_ref_clk;
  always #(sys_half) s_exec_clk = !s_exec_clk;
  always #(pclk_half) s_backend_pclk = !s_backend_pclk;
  always #(mem_half) s_backend_mem_clk = !s_backend_mem_clk;
  logic rst_n_i = 0, s_backend_reset_n = 1;
  logic s_por_rst_n, s_rst_n, s_cpu_ready_rst_n, s_fabric_rst_n, s_xpi_rst_n;
  logic [`RETROSOC_TINY__LEAF_COUNT-1:0] s_leaf_clk, s_leaf_rst_n;
  struct packed {logic reset_req_o;} u_wdg_if;
  assign u_wdg_if.reset_req_o = 0;
  logic s_dma_clk, s_dma_rst_n;
  logic s_periph_apply = 0, s_periph_reset_command = 1;
  logic [13:0] s_periph_request = 14'h200;
  logic [13:0] s_periph_idle, s_periph_idle_ref;
  logic [13:0] s_gate_request, s_local_reset, s_actual_gate, s_reset_held, s_reset_ready;
  logic [13:0] s_gate_ref, s_held_ref, s_ready_ref, s_periph_reset_done;
  logic s_bus_idle_ref, s_periph_block, s_periph_done, s_block_pclk;
  logic [ 4:0] s_periph_fault;
  logic [31:0] s_clock_timeout = 256;
  logic s_clock_block = 0, s_clock_safe, s_dma_admission_idle, s_dma_idle_sys;
  logic s_dma_cdc_ready, s_dma_cdc_busy, s_dma_ready_sys;
  // Completion-mailbox and unrelated clients have no work in this fixture.
  logic s_dma_done_pending_q = 0, s_dma_done_ready = 1;
  logic s_cpu_clock_idle = 1, s_sdio_admission_idle = 1, s_xpi_cdc_busy = 0;
  logic [                             2:0] s_owner_idle;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0] s_target_idle;
  logic [`RETROSOC_TINY__LEAF_COUNT-2:0] s_apb_cdc_idle = '1, s_apb_cdc_ready = '1;
  assign s_actual_gate[13:10] = 0;
  assign s_actual_gate[8:0]   = 0;
  assign s_reset_held[13:10]  = 0;
  assign s_reset_held[8:0]    = 0;
  assign s_reset_ready[13:10] = 0;
  assign s_reset_ready[8:0]   = 0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_dma_pclk_axi4_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_dma_admitted_axi4_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_masters_axi4_if[3] (
      .aclk   (s_exec_clk),
      .aresetn(s_fabric_rst_n)
  );

  `include "source_reset_bindings.svh"

  logic rd_start = 0, wr_start = 0, rd_start_ready, wr_start_ready;
  logic rd_busy, wr_busy, rd_valid, rd_ready = 1, rd_last, rd_done, wr_done;
  logic wr_valid = 0, wr_ready;
  logic [31:0] rd_addr = 32'h30000000, wr_addr = 32'h30000100;
  logic [4:0] rd_beats = 4, wr_beats = 4;
  logic [31:0] rd_data, wr_data = 32'hcafef00d;
  logic [1:0] rd_resp, wr_resp;
  logic rd_id_error, wr_id_error;
  dma_axi4_master u_dma_master (
      .clk_i                 (s_dma_clk),
      .rst_n_i               (s_dma_rst_n),
      .clear_i               (1'b0),
      .read_start_valid_i    (rd_start),
      .read_start_ready_o    (rd_start_ready),
      .read_addr_i           (rd_addr),
      .read_beats_i          (rd_beats),
      .read_fixed_i          (1'b0),
      .read_busy_o           (rd_busy),
      .read_beat_valid_o     (rd_valid),
      .read_beat_ready_i     (rd_ready),
      .read_data_o           (rd_data),
      .read_resp_o           (rd_resp),
      .read_last_o           (rd_last),
      .read_expected_last_o  (),
      .read_id_error_o       (rd_id_error),
      .read_done_o           (rd_done),
      .write_start_valid_i   (wr_start),
      .write_start_ready_o   (wr_start_ready),
      .write_addr_i          (wr_addr),
      .write_beats_i         (wr_beats),
      .write_fixed_i         (1'b0),
      .write_busy_o          (wr_busy),
      .write_data_valid_i    (wr_valid),
      .write_data_ready_o    (wr_ready),
      .write_data_i          (wr_data),
      .write_strb_i          (4'hf),
      .write_done_o          (wr_done),
      .write_resp_o          (wr_resp),
      .write_id_error_o      (wr_id_error),
      .origin_enable_i       (1'b0),
      .read_origin_channel_i (3'd0),
      .write_origin_channel_i(3'd0),
      .axi4                  (u_dma_pclk_axi4_if)
  );
  assign s_periph_idle = {4'hf, !(rd_busy || wr_busy || rd_start || wr_start), 9'h1ff};

  logic hold_ar = 0, hold_aw = 0, hold_w = 0, hold_r = 0, hold_b = 0;
  logic target_rd = 0, target_wr = 0;
  logic [31:0] target_addr;
  integer target_rleft, target_wleft;
  wire target_idle = !target_rd && !target_wr;
  assign s_owner_idle                 = {1'b1, target_idle, 1'b1};
  assign s_target_idle                = {`RETROSOC_TINY__TARGET_COUNT{target_idle}};
  assign u_masters_axi4_if[1].arready = !target_rd && !hold_ar;
  assign u_masters_axi4_if[1].awready = !target_wr && !hold_aw;
  assign u_masters_axi4_if[1].wready  = target_wr && target_wleft != 0 && !hold_w;
  assign u_masters_axi4_if[1].rid     = 0;
  assign u_masters_axi4_if[1].rresp   = 0;
  assign u_masters_axi4_if[1].ruser   = 0;
  assign u_masters_axi4_if[1].bid     = 0;
  assign u_masters_axi4_if[1].bresp   = 0;
  assign u_masters_axi4_if[1].buser   = 0;
  logic ar_stalled = 0, aw_stalled = 0;
  logic [39:0] held_ar, held_aw;
  always @(posedge s_exec_clk or negedge s_fabric_rst_n) begin
    if (!s_fabric_rst_n) begin
      ar_stalled <= 0;
      aw_stalled <= 0;
    end else begin
      if (ar_stalled && (!u_masters_axi4_if[1].arvalid ||
          {u_masters_axi4_if[1].araddr, u_masters_axi4_if[1].arlen} !== held_ar))
        $fatal(1, "SIM_TEST_FAIL stalled AR revoked or changed");
      if (aw_stalled && (!u_masters_axi4_if[1].awvalid ||
          {u_masters_axi4_if[1].awaddr, u_masters_axi4_if[1].awlen} !== held_aw))
        $fatal(1, "SIM_TEST_FAIL stalled AW revoked or changed");
      ar_stalled <= u_masters_axi4_if[1].arvalid && !u_masters_axi4_if[1].arready;
      aw_stalled <= u_masters_axi4_if[1].awvalid && !u_masters_axi4_if[1].awready;
      held_ar    <= {u_masters_axi4_if[1].araddr, u_masters_axi4_if[1].arlen};
      held_aw    <= {u_masters_axi4_if[1].awaddr, u_masters_axi4_if[1].awlen};
    end
  end
  always @(posedge s_exec_clk or negedge s_fabric_rst_n) begin
    if (!s_fabric_rst_n) begin
      target_rd                   <= 0;
      target_wr                   <= 0;
      target_rleft                <= 0;
      target_wleft                <= 0;
      target_addr                 <= 0;
      u_masters_axi4_if[1].rvalid <= 0;
      u_masters_axi4_if[1].rdata  <= 0;
      u_masters_axi4_if[1].rlast  <= 0;
      u_masters_axi4_if[1].bvalid <= 0;
    end else begin
      if (u_masters_axi4_if[1].arvalid && u_masters_axi4_if[1].arready) begin
        target_rd    <= 1;
        target_addr  <= u_masters_axi4_if[1].araddr;
        target_rleft <= int'(u_masters_axi4_if[1].arlen) + 1;
      end
      if (target_rd && !hold_r && !u_masters_axi4_if[1].rvalid) begin
        u_masters_axi4_if[1].rvalid <= 1;
        u_masters_axi4_if[1].rdata  <= target_addr ^ 32'h12345678;
        u_masters_axi4_if[1].rlast  <= target_rleft == 1;
      end
      if (u_masters_axi4_if[1].rvalid && u_masters_axi4_if[1].rready) begin
        u_masters_axi4_if[1].rvalid <= 0;
        target_rleft                <= target_rleft - 1;
        target_addr                 <= target_addr + 4;
        if (u_masters_axi4_if[1].rlast) target_rd <= 0;
      end
      if (u_masters_axi4_if[1].awvalid && u_masters_axi4_if[1].awready) begin
        target_wr    <= 1;
        target_wleft <= int'(u_masters_axi4_if[1].awlen) + 1;
      end
      if (u_masters_axi4_if[1].wvalid && u_masters_axi4_if[1].wready) begin
        if (u_masters_axi4_if[1].wlast !== (target_wleft == 1))
          $fatal(1, "SIM_TEST_FAIL write burst boundary");
        target_wleft <= target_wleft - 1;
      end
      if (target_wr && target_wleft == 0 && !hold_b) u_masters_axi4_if[1].bvalid <= 1;
      if (u_masters_axi4_if[1].bvalid && u_masters_axi4_if[1].bready) begin
        u_masters_axi4_if[1].bvalid <= 0;
        target_wr                   <= 0;
      end
    end
  end

  // Independent scoreboard survives local source reset. Looking only at the
  // bridge's reset-cleared pending bits would conceal an unsafe reset.
  integer reads = 0, read_completions = 0, writes = 0, write_completions = 0;
  integer read_beat = 0, local_resets = 0;
  always @(posedge s_dma_clk or negedge rst_n_i or negedge s_backend_reset_n) begin
    if (!rst_n_i || !s_backend_reset_n) begin
      reads             = 0;
      read_completions  = 0;
      writes            = 0;
      write_completions = 0;
      read_beat         = 0;
    end else if (s_dma_rst_n) begin
      if (u_dma_pclk_axi4_if.arvalid && u_dma_pclk_axi4_if.arready) reads++;
      if (u_dma_pclk_axi4_if.awvalid && u_dma_pclk_axi4_if.awready) writes++;
      if (rd_valid && rd_ready) begin
        if (rd_resp != 0 || rd_id_error || rd_data !== ((rd_addr + 4 * read_beat) ^ 32'h12345678) ||
            rd_last !== (read_beat == int'(rd_beats) - 1))
          $fatal(1, "SIM_TEST_FAIL stale or malformed read response");
        read_beat++;
        if (rd_last) begin
          read_completions++;
          read_beat = 0;
        end
      end
      if (wr_done) begin
        if (wr_resp != 0 || wr_id_error) $fatal(1, "SIM_TEST_FAIL write response");
        write_completions++;
      end
      if (read_completions > reads || write_completions > writes)
        $fatal(1, "SIM_TEST_FAIL duplicate terminal response");
    end
  end
  always @(posedge s_local_reset[9]) begin
    if (reads != read_completions || writes != write_completions || !target_idle ||
        rd_busy || wr_busy || !s_dma_admission_idle)
      $fatal(1, "SIM_TEST_FAIL P7_SOURCE_RESET_UNDRAINED");
    local_resets++;
  end
  // SYS-source reset of XPI is never an independent reset event. Allow delta
  // propagation of the asynchronously asserted production reset tree.
  always @(negedge s_fabric_rst_n) begin
    #0.001;
    if (s_xpi_rst_n !== 0 || s_dma_rst_n !== 0)
      $fatal(1, "SIM_TEST_FAIL common system reset left an endpoint alive");
  end

  task automatic ready;
    wait (s_dma_rst_n && s_dma_cdc_ready && s_dma_ready_sys && s_ready_ref[9]);
    repeat (24) @(negedge s_ref_clk);
  endtask
  task automatic start_read;
    @(negedge s_dma_clk);
    rd_addr += 32'h100;
    rd_start = 1;
    do @(posedge s_dma_clk); while (!rd_start_ready);
    @(negedge s_dma_clk);
    rd_start = 0;
  endtask
  task automatic start_write;
    @(negedge s_dma_clk);
    wr_start = 1;
    do @(posedge s_dma_clk); while (!wr_start_ready);
    @(negedge s_dma_clk);
    wr_start = 0;
  endtask
  task automatic send_words(input integer words);
    @(negedge s_dma_clk);
    wr_valid = 1;
    repeat (words) begin
      do @(posedge s_dma_clk); while (!wr_ready);
      @(negedge s_dma_clk);
    end
    wr_valid = 0;
  endtask
  task automatic reset_command;
    @(negedge s_ref_clk);
    s_periph_apply = 1;
    @(negedge s_ref_clk);
    s_periph_apply = 0;
  endtask
  task automatic completion(input logic [4:0] expected_fault);
    while (!s_periph_done) @(negedge s_ref_clk);
    if (s_periph_fault !== expected_fault ||
        (expected_fault == 0 && s_periph_reset_done !== 14'h200) ||
        (expected_fault != 0 && s_local_reset != 0))
      $fatal(1, "SIM_TEST_FAIL reset command result fault=%h", s_periph_fault);
    @(negedge s_ref_clk);
    if (expected_fault == 0) ready();
  endtask
  task automatic require_draining;
    repeat (48) @(negedge s_ref_clk);
    if (!s_periph_block || s_local_reset != 0 || !s_dma_rst_n || s_periph_done)
      $fatal(1, "SIM_TEST_FAIL reset did not preserve outstanding work");
  endtask
  task automatic recovery_read;
    start_read();
    wait (!rd_busy);
    repeat (24) @(negedge s_ref_clk);
    if (reads != read_completions || writes != write_completions)
      $fatal(1, "SIM_TEST_FAIL recovery completion accounting");
  endtask

  initial begin
    if ($test$plusargs("xin48")) begin
      sys_half  = 10.416667;
      mem_half  = 10.416667;
      pclk_half = 10.416667;
    end
    if ($test$plusargs("xin96")) begin
      sys_half  = 5.208333;
      mem_half  = 5.208333;
      pclk_half = 10.416667;
    end
    if ($test$plusargs("pll192")) begin
      sys_half  = 2.604167;
      mem_half  = 5.208333;
      pclk_half = 10.416667;
    end
    if ($test$plusargs("pll240")) begin
      sys_half  = 2.083333;
      mem_half  = 4.166667;
      pclk_half = 8.333333;
    end
    // Deliberately falsified idle observations must trip the independent
    // scoreboard. This is a negative test, never a qualifying DUT mode.
    if ($test$plusargs("break_drain")) begin
      force s_bus_idle_ref = 1'b1;
      force s_periph_idle_ref = 14'h3fff;
    end
    #1 rst_n_i = 1;
    #1 rst_n_i = 0;
    repeat (8) @(negedge s_ref_clk);
    rst_n_i = 1;
    ready();
    recovery_read();

    // An accepted but downstream-stalled AR survives until normal completion.
    hold_ar = 1;
    start_read();
    wait (u_masters_axi4_if[1].arvalid);
    reset_command();
    require_draining();
    hold_ar = 0;
    completion(0);
    recovery_read();

    // A late R prevents local reset, even after a bounded command timeout.
    hold_r = 1;
    start_read();
    wait (target_rd);
    reset_command();
    require_draining();
    completion(5'b00010);
    if (!rd_busy) $fatal(1, "SIM_TEST_FAIL timeout discarded read");
    hold_r = 0;
    wait (!rd_busy);
    reset_command();
    completion(0);
    recovery_read();

    // AW backpressure, an incomplete W burst, and a delayed B all prohibit
    // source reset. The real DMA master owns BREADY and the original WLAST.
    hold_aw = 1;
    hold_b  = 1;
    start_write();
    wait (u_masters_axi4_if[1].awvalid);
    reset_command();
    require_draining();
    hold_aw = 0;
    send_words(1);
    require_draining();
    hold_w = 1;
    send_words(3);
    require_draining();
    hold_w = 0;
    wait (target_wleft == 0);
    completion(5'b00010);
    if (!wr_busy) $fatal(1, "SIM_TEST_FAIL timeout discarded write");
    hold_b = 0;
    wait (!wr_busy);
    reset_command();
    completion(0);
    // The first post-reset write must also receive its own response exactly once.
    start_write();
    send_words(4);
    wait (!wr_busy);
    recovery_read();

    // A response already in the source holder is still outstanding when the
    // consumer applies backpressure, even if the target is otherwise idle.
    rd_ready = 0;
    start_read();
    wait (rd_valid);
    reset_command();
    require_draining();
    rd_ready = 1;
    completion(0);
    recovery_read();
    if (local_resets != 4) $fatal(1, "SIM_TEST_FAIL reset scenario coverage");

    // The other legal reset route cancels the complete system session.
    hold_r = 1;
    start_read();
    wait (target_rd);
    @(negedge s_ref_clk);
    s_backend_reset_n = 0;
    repeat (8) @(negedge s_ref_clk);
    s_backend_reset_n = 1;
    hold_r            = 0;
    ready();
    recovery_read();
    $display("SIM_TEST_PASS Tiny P7 production source reset local=4 timeout=2 system=1");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny P7 production source reset");
  end
endmodule
