`timescale 1ns / 1ps
module tiny_r2_reset_tb;
  logic s_clk = 0;
  logic s_reset_n = 1;
  logic s_watchdog = 0;
  logic s_por_n, s_system_n, s_ready_n;
  logic [16:0] s_leaf_n;
  logic s_hart_req = 0, s_idle = 1, s_core_n, s_done;

  tiny_reset_tree u_tree (
      .clk_i               (s_clk),
      .rst_n_i             (s_reset_n),
      .watchdog_reset_req_i(s_watchdog),
      .por_rst_n_o         (s_por_n),
      .system_rst_n_o      (s_system_n),
      .leaf_rst_n_o        (s_leaf_n),
      .cpu_ready_rst_n_o   (s_ready_n)
  );
  mgmt_debug_reset #(
      .ResetSyncStages(5)
  ) u_hart (
      .clk_i        (s_clk),
      .rst_n_i      (s_ready_n),
      .reset_req_i  (s_hart_req),
      .bridge_idle_i(s_idle),
      .core_rst_n_o (s_core_n),
      .reset_done_o (s_done)
  );

  task automatic cycle;
    #5 s_clk = 1;
    #1;
    if (s_core_n && s_leaf_n !== 17'h1ffff) $fatal(1, "CPU released before all leaves");
    #4 s_clk = 0;
  endtask

  task automatic cold_release;
    for (int edge_count = 1; edge_count <= 20; edge_count++) begin
      cycle();
      if (s_por_n !== (edge_count >= 5)) $fatal(1, "POR release edge %0d", edge_count);
      if (s_system_n !== (edge_count >= 10)) $fatal(1, "system release edge %0d", edge_count);
      if (s_leaf_n !== ((edge_count >= 15) ? 17'h1ffff : 17'd0))
        $fatal(1, "leaf release edge %0d", edge_count);
      if (s_core_n !== (edge_count >= 20)) $fatal(1, "hart release edge %0d", edge_count);
    end
  endtask

  initial begin
    // Generate a real reset edge after elaboration in four-state simulation.
    #1 s_reset_n = 0;
    #1 s_reset_n = 1;
    cold_release();
    #2 s_reset_n = 0;
    #1;
    if ({s_por_n, s_system_n, s_leaf_n, s_core_n} !== '0)
      $fatal(1, "asynchronous stopped-clock assertion failed");
    #2 s_reset_n = 1;
    #100;
    if ({s_por_n, s_system_n, s_leaf_n, s_core_n} !== '0)
      $fatal(1, "stopped clock allowed release");
    repeat (4) cycle();
    if (s_por_n) $fatal(1, "released before five edges");
    #2 s_reset_n = 0;
    #1 s_reset_n = 1;
    cold_release();

    #2 s_watchdog = 1;
    #1;
    if (!s_por_n || s_system_n || s_leaf_n != 0 || s_core_n)
      $fatal(1, "watchdog did not preserve POR and reset the system");
    repeat (8) cycle();
    s_watchdog = 0;
    for (int edge_count = 1; edge_count <= 15; edge_count++) begin
      cycle();
      if (!s_por_n || s_system_n !== (edge_count >= 5) ||
          s_leaf_n !== ((edge_count >= 10) ? 17'h1ffff : 17'd0) ||
          s_core_n !== (edge_count >= 15))
        $fatal(1, "watchdog release sequencing");
    end

    s_idle     = 0;
    s_hart_req = 1;
    cycle();
    s_hart_req = 0;
    repeat (4) begin
      cycle();
      if (!s_core_n || s_done || s_leaf_n != 17'h1ffff)
        $fatal(1, "hart request discarded accepted work or reset other clients");
    end
    s_idle = 1;
    cycle();
    if (s_core_n || s_done) $fatal(1, "idle hart did not assert reset");
    cycle();  // Retained request clears; five release edges follow.
    for (int edge_count = 1; edge_count <= 5; edge_count++) begin
      cycle();
      if (s_leaf_n != 17'h1ffff || s_core_n !== (edge_count == 5))
        $fatal(1, "hart-only release or peripheral preservation failed");
    end
    if (!s_done) $fatal(1, "hart reset completion missing");
    $display("SIM_TEST_PASS Tiny R2 reset");
    $finish;
  end
  initial begin
    #10000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny R2 reset");
  end
endmodule
