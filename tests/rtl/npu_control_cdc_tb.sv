`timescale 1ns / 1ps

// NPU-P2 adversarial control-CDC test: two independent clock domains (10 ns
// PCLK, 14 ns HP, drifting phases), snapshot round trips, either-side reset
// mid-handshake, epoch reconciliation with generation counting including the
// counter wrap, double and rapid reset sequences, quiesce/reset round-trip
// acknowledgement timing, immediate idle clock-pause acknowledge, and fabric
// flush on an idle endpoint (no artificial cancellation event).
`include "npu_define.svh"

module npu_control_cdc_tb;
  localparam int unsigned LaunchWidth = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH;
  localparam int unsigned ResultWidth = `APB4_NPU__RESULT_PAYLOAD_WIDTH;
  localparam int unsigned SnapWidth = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH;
  localparam int unsigned EpochWidth = `APB4_NPU__EPOCH_WIDTH;

  logic                          clk_i = 1'b0;
  logic                          clk_hp_i = 1'b0;
  logic                          rst_n_i = 1'b0;
  logic                          rst_hp_n_i = 1'b0;
  logic                          s_launch_req_valid = 1'b0;
  logic                          s_launch_req_ready;
  logic        [LaunchWidth-1:0] s_launch_req_payload = '0;
  logic                          s_result_valid;
  logic                          s_result_ready = 1'b1;
  logic        [ResultWidth-1:0] s_result_payload;
  logic                          s_snap_req_valid = 1'b0;
  logic                          s_snap_req_ready;
  logic                          s_snap_resp_valid;
  logic                          s_snap_resp_ready = 1'b0;
  logic        [  SnapWidth-1:0] s_snap_resp_payload;
  logic                          s_soft_reset = 1'b0;
  logic                          s_shell_idle = 1'b1;
  logic                          s_resource_quiesce = 1'b0;
  logic                          s_resource_reset = 1'b0;
  logic                          s_link_up;
  logic                          s_flush_active;
  logic        [           31:0] s_generation;
  logic                          s_block_ack;
  logic                          hp_launch_valid;
  logic                          hp_launch_ready;
  logic        [LaunchWidth-1:0] hp_launch_payload;
  logic                          hp_result_valid;
  logic                          hp_result_ready;
  logic        [ResultWidth-1:0] hp_result_payload;
  logic                          hp_snap_req_valid;
  logic                          hp_snap_req_ready;
  logic                          hp_snap_resp_valid;
  logic                          hp_snap_resp_ready;
  logic        [  SnapWidth-1:0] hp_snap_resp_payload;
  logic        [ EpochWidth-1:0] hp_epoch_req;
  logic        [ EpochWidth-1:0] hp_epoch_ack;
  logic                          hp_quiesce_req;
  logic                          hp_quiesce_ack;
  logic                          hp_busy;
  logic                          hp_draining;
  logic                          hp_pause_active;
  logic                          hp_busy_pclk;
  logic                          hp_draining_pclk;
  logic                          clock_paused;
  logic                          hp_block_new = 1'b0;
  logic                          hp_pause_ack;
  logic                          hp_flush = 1'b0;
  logic                          hp_flush_busy;
  logic                          hp_idle;
  int unsigned                   s_wait_cycles;
  int unsigned                   s_ack_latency;
  string                         s_phase;

  always #5 clk_i = ~clk_i;
  always #7 clk_hp_i = ~clk_hp_i;

  npu_control_cdc u_dut (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .clk_hp_i                  (clk_hp_i),
      .rst_hp_n_i                (rst_hp_n_i),
      .launch_req_valid_i        (s_launch_req_valid),
      .launch_req_ready_o        (s_launch_req_ready),
      .launch_req_payload_i      (s_launch_req_payload),
      .result_valid_o            (s_result_valid),
      .result_ready_i            (s_result_ready),
      .result_payload_o          (s_result_payload),
      .snapshot_req_valid_i      (s_snap_req_valid),
      .snapshot_req_ready_o      (s_snap_req_ready),
      .snapshot_resp_valid_o     (s_snap_resp_valid),
      .snapshot_resp_ready_i     (s_snap_resp_ready),
      .snapshot_resp_payload_o   (s_snap_resp_payload),
      .soft_reset_i              (s_soft_reset),
      .shell_idle_i              (s_shell_idle),
      .resource_quiesce_i        (s_resource_quiesce),
      .resource_reset_i          (s_resource_reset),
      .link_up_o                 (s_link_up),
      .flush_active_o            (s_flush_active),
      .recovery_generation_o     (s_generation),
      .block_ack_o               (s_block_ack),
      .hp_launch_valid_o         (hp_launch_valid),
      .hp_launch_ready_i         (hp_launch_ready),
      .hp_launch_payload_o       (hp_launch_payload),
      .hp_result_valid_i         (hp_result_valid),
      .hp_result_ready_o         (hp_result_ready),
      .hp_result_payload_i       (hp_result_payload),
      .hp_snapshot_req_valid_o   (hp_snap_req_valid),
      .hp_snapshot_req_ready_i   (hp_snap_req_ready),
      .hp_snapshot_resp_valid_i  (hp_snap_resp_valid),
      .hp_snapshot_resp_ready_o  (hp_snap_resp_ready),
      .hp_snapshot_resp_payload_i(hp_snap_resp_payload),
      .hp_epoch_req_o            (hp_epoch_req),
      .hp_epoch_ack_i            (hp_epoch_ack),
      .hp_quiesce_req_o          (hp_quiesce_req),
      .hp_quiesce_ack_i          (hp_quiesce_ack),
      .hp_busy_i                 (hp_busy),
      .hp_draining_i             (hp_draining),
      .hp_pause_active_i         (hp_pause_active),
      .hp_flush_i                (hp_flush),
      .hp_busy_o                 (hp_busy_pclk),
      .hp_draining_o             (hp_draining_pclk),
      .clock_paused_o            (clock_paused)
  );

  npu_core u_core (
      .clk_hp_i             (clk_hp_i),
      .rst_hp_n_i           (rst_hp_n_i),
      .launch_valid_i       (hp_launch_valid),
      .launch_ready_o       (hp_launch_ready),
      .launch_data_i        (hp_launch_payload),
      .result_valid_o       (hp_result_valid),
      .result_ready_i       (hp_result_ready),
      .result_data_o        (hp_result_payload),
      .snapshot_req_valid_i (hp_snap_req_valid),
      .snapshot_req_ready_o (hp_snap_req_ready),
      .snapshot_resp_valid_o(hp_snap_resp_valid),
      .snapshot_resp_ready_i(hp_snap_resp_ready),
      .snapshot_resp_data_o (hp_snap_resp_payload),
      .epoch_req_i          (hp_epoch_req),
      .epoch_ack_o          (hp_epoch_ack),
      .quiesce_req_i        (hp_quiesce_req),
      .quiesce_ack_o        (hp_quiesce_ack),
      .busy_o               (hp_busy),
      .draining_o           (hp_draining),
      .block_new_i          (hp_block_new),
      .clock_pause_ack_o    (hp_pause_ack),
      .flush_i              (hp_flush),
      .flush_busy_o         (hp_flush_busy),
      .pause_active_o       (hp_pause_active),
      .idle_o               (hp_idle)
  );

  // No terminal result may ever appear at Phase 2, in any scenario.
  always @(posedge clk_i) begin
    if (rst_n_i && s_result_valid) $fatal(1, "NPU CDC produced a result at Phase 2");
  end

  task automatic wait_link_up;
    begin
      s_wait_cycles = 0;
      while (!s_link_up) begin
        @(posedge clk_i);
        s_wait_cycles++;
        if (s_wait_cycles > 2000) $fatal(1, "NPU CDC link did not reconcile in %s", s_phase);
      end
    end
  endtask

  task automatic wait_link_down;
    begin
      s_wait_cycles = 0;
      while (!s_flush_active) begin
        @(posedge clk_i);
        s_wait_cycles++;
        if (s_wait_cycles > 2000) $fatal(1, "NPU CDC link did not drop in %s", s_phase);
      end
    end
  endtask

  task automatic wait_block_ack(input logic expected_i);
    begin
      s_wait_cycles = 0;
      while (s_block_ack != expected_i) begin
        @(posedge clk_i);
        s_wait_cycles++;
        if (s_wait_cycles > 2000)
          $fatal(1, "NPU CDC block_ack %0b timed out in %s", expected_i, s_phase);
      end
    end
  endtask

  // A full shell-side snapshot round trip with the response payload check.
  task automatic shell_snapshot;
    begin
      @(negedge clk_i);
      s_snap_req_valid = 1'b1;
      s_shell_idle     = 1'b0;
      s_wait_cycles    = 0;
      while (!s_snap_req_ready) begin
        @(posedge clk_i);
        s_wait_cycles++;
        if (s_wait_cycles > 200) $fatal(1, "NPU snapshot request not accepted in %s", s_phase);
      end
      @(negedge clk_i);
      s_snap_req_valid  = 1'b0;
      s_snap_resp_ready = 1'b1;
      s_wait_cycles     = 0;
      while (!s_snap_resp_valid) begin
        @(posedge clk_i);
        s_wait_cycles++;
        if (s_wait_cycles > 500) $fatal(1, "NPU snapshot response missing in %s", s_phase);
      end
      if (s_snap_resp_payload !== {SnapWidth{1'b0}}) begin
        $fatal(1, "NPU idle snapshot returned a nonzero payload");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      s_snap_resp_ready = 1'b0;
      s_shell_idle      = 1'b1;
    end
  endtask

  // Launch one payload through the PCLK->HP mailbox and check its integrity.
  task automatic shell_launch(input logic [LaunchWidth-1:0] payload_i);
    begin
      @(negedge clk_i);
      s_launch_req_payload = payload_i;
      s_launch_req_valid   = 1'b1;
      s_shell_idle         = 1'b0;
      s_wait_cycles        = 0;
      while (!hp_launch_valid) begin
        @(posedge clk_hp_i);
        s_wait_cycles++;
        if (s_wait_cycles > 200) $fatal(1, "NPU launch never reached the HP endpoint");
      end
      if (hp_launch_payload !== payload_i) begin
        $fatal(1, "NPU launch payload mismatch: got %h expected %h", hp_launch_payload, payload_i);
      end
      s_wait_cycles = 0;
      while (!s_launch_req_ready) begin
        @(posedge clk_i);
        s_wait_cycles++;
        if (s_wait_cycles > 200) $fatal(1, "NPU launch source never completed");
      end
      @(negedge clk_i);
      s_launch_req_valid = 1'b0;
      s_shell_idle       = 1'b1;
    end
  endtask

  task automatic pulse_hp_reset(input int unsigned hold_cycles);
    begin
      #3 rst_hp_n_i = 1'b0;
      repeat (hold_cycles) @(posedge clk_hp_i);
      #2 rst_hp_n_i = 1'b1;
    end
  endtask

  task automatic pulse_pclk_reset(input int unsigned hold_cycles);
    begin
      #2 rst_n_i = 1'b0;
      s_snap_req_valid   = 1'b0;
      s_snap_resp_ready  = 1'b0;
      s_launch_req_valid = 1'b0;
      s_soft_reset       = 1'b0;
      s_shell_idle       = 1'b1;
      repeat (hold_cycles) @(posedge clk_i);
      #3 rst_n_i = 1'b1;
    end
  endtask

  initial begin
    s_phase = "power-on reconcile";
    repeat (5) @(posedge clk_i);
    #2 rst_hp_n_i = 1'b1;
    @(negedge clk_i);
    rst_n_i = 1'b1;
    wait_link_up();
    if (s_generation !== 32'd0) $fatal(1, "NPU initial reconcile changed the generation");
    if (s_flush_active) $fatal(1, "NPU link flush stuck after power-on");
    if (hp_busy_pclk || hp_draining_pclk || clock_paused) begin
      $fatal(1, "NPU idle HP endpoint reported activity");
    end

    s_phase = "snapshot round trips";
    shell_snapshot();
    shell_snapshot();
    shell_launch({16'd0, 16'd5, 32'h044a_a200, 32'hcafe_babe, 32'h3000_0000});
    shell_snapshot();

    s_phase = "hp reset mid snapshot";
    @(negedge clk_i);
    s_snap_req_valid = 1'b1;
    s_shell_idle     = 1'b0;
    #9;
    pulse_hp_reset(4);
    wait_link_down();
    @(negedge clk_i);
    s_snap_req_valid = 1'b0;
    s_shell_idle     = 1'b1;
    if (s_snap_resp_valid) $fatal(1, "NPU stale snapshot response survived the HP reset");
    wait_link_up();
    if (s_generation !== 32'd1) $fatal(1, "NPU HP-reset recovery did not count exactly once");
    shell_snapshot();

    s_phase = "pclk reset mid snapshot";
    @(negedge clk_i);
    s_snap_req_valid = 1'b1;
    s_shell_idle     = 1'b0;
    #9;
    pulse_pclk_reset(3);
    if (s_generation !== 32'd0) $fatal(1, "NPU shell reset did not rezero the generation");
    wait_link_up();
    if (s_generation !== 32'd0) begin
      $fatal(1, "NPU initial reconcile after shell reset changed the generation");
    end
    shell_snapshot();

    s_phase = "pclk reset during snapshot response";
    @(negedge clk_i);
    s_snap_req_valid = 1'b1;
    s_shell_idle     = 1'b0;
    s_wait_cycles    = 0;
    while (!s_snap_req_ready) begin
      @(posedge clk_i);
      s_wait_cycles++;
      if (s_wait_cycles > 200) $fatal(1, "NPU snapshot request not accepted");
    end
    @(negedge clk_i);
    s_snap_req_valid = 1'b0;
    s_wait_cycles    = 0;
    while (!s_snap_resp_valid) begin
      @(posedge clk_i);
      s_wait_cycles++;
      if (s_wait_cycles > 500) $fatal(1, "NPU snapshot response missing before reset");
    end
    pulse_pclk_reset(3);
    if (s_snap_resp_valid) $fatal(1, "NPU shell reset kept a stale snapshot response");
    wait_link_up();
    shell_snapshot();

    s_phase = "double reset";
    #2 rst_n_i = 1'b0;
    #17 rst_hp_n_i = 1'b0;
    repeat (4) @(posedge clk_i);
    #3 rst_n_i = 1'b1;
    repeat (2) @(posedge clk_hp_i);
    #2 rst_hp_n_i = 1'b1;
    wait_link_up();
    if (s_generation !== 32'd0) $fatal(1, "NPU double reset did not rezero the generation");
    shell_snapshot();

    s_phase = "rapid reset sequence";
    for (int unsigned reset_index = 0; reset_index < 3; reset_index++) begin
      pulse_hp_reset(2 + reset_index);
    end
    pulse_pclk_reset(2);
    pulse_hp_reset(3);
    wait_link_up();
    // The PCLK pulse rezeroes the counter and the completing reconcile is the
    // post-reset initial one, which does not count as a recovery.
    if (s_generation !== 32'd0) begin
      $fatal(1, "NPU rapid reset sequence generation mismatch: %0d", s_generation);
    end
    shell_snapshot();

    s_phase       = "quiesce round trip";
    s_wait_cycles = 0;
    @(negedge clk_i);
    s_resource_quiesce = 1'b1;
    #1;
    if (s_block_ack) $fatal(1, "NPU quiesce acknowledged combinationally");
    while (!s_block_ack) begin
      @(posedge clk_i);
      s_wait_cycles++;
      if (s_wait_cycles > 200) $fatal(1, "NPU quiesce acknowledgement timed out");
    end
    if (s_wait_cycles < 3) $fatal(1, "NPU quiesce acknowledged without a CDC round trip");
    s_ack_latency = s_wait_cycles;
    shell_snapshot();
    if (s_generation !== 32'd0) $fatal(1, "NPU idle quiesce changed the generation");
    @(negedge clk_i);
    s_resource_quiesce = 1'b0;
    wait_block_ack(1'b0);

    s_phase = "resource reset handshake";
    @(negedge clk_i);
    s_resource_reset = 1'b1;
    #1;
    if (s_block_ack) $fatal(1, "NPU reset acknowledged combinationally");
    wait_link_down();
    s_wait_cycles = 0;
    while (!s_block_ack) begin
      @(posedge clk_i);
      s_wait_cycles++;
      if (s_wait_cycles > 200) $fatal(1, "NPU reset acknowledgement timed out");
    end
    if (s_wait_cycles < 3) $fatal(1, "NPU reset acknowledged without a fresh epoch");
    @(negedge clk_i);
    s_resource_reset = 1'b0;
    wait_block_ack(1'b0);
    wait_link_up();
    if (s_generation !== 32'd1) $fatal(1, "NPU resource reset recovery miscounted");

    s_phase = "reset cancels pending snapshot before ack";
    @(negedge clk_i);
    s_snap_req_valid = 1'b1;
    s_shell_idle     = 1'b0;
    #6;
    @(negedge clk_i);
    s_resource_reset = 1'b1;
    wait_link_down();
    @(negedge clk_i);
    s_snap_req_valid = 1'b0;
    repeat (10) @(posedge clk_i);
    if (s_block_ack) begin
      $fatal(1, "NPU reset acknowledged with a pending shell snapshot");
    end
    s_shell_idle = 1'b1;
    wait_block_ack(1'b1);
    @(negedge clk_i);
    s_resource_reset = 1'b0;
    wait_link_up();
    if (s_snap_resp_valid) $fatal(1, "NPU stale snapshot response survived the reset");
    shell_snapshot();

    s_phase = "hp reset during quiesce window";
    @(negedge clk_i);
    s_resource_quiesce = 1'b1;
    wait_block_ack(1'b1);
    pulse_hp_reset(3);
    wait_block_ack(1'b0);
    wait_block_ack(1'b1);
    @(negedge clk_i);
    s_resource_quiesce = 1'b0;
    wait_block_ack(1'b0);
    wait_link_up();

    s_phase = "clock pause and flush on idle";
    @(negedge clk_hp_i);
    hp_block_new = 1'b1;
    #1;
    if (!hp_pause_ack) $fatal(1, "NPU idle clock pause was not acknowledged immediately");
    if (!hp_idle) $fatal(1, "NPU paused idle endpoint held global idle low");
    shell_snapshot();
    @(negedge clk_hp_i);
    hp_block_new = 1'b0;
    #1;
    if (hp_pause_ack) $fatal(1, "NPU clock pause acknowledge stuck");
    begin
      logic [31:0] s_generation_before_flush;
      s_generation_before_flush = s_generation;
      @(negedge clk_hp_i);
      hp_flush = 1'b1;
      repeat (4) @(posedge clk_hp_i);
      if (hp_flush_busy) $fatal(1, "NPU idle endpoint reported flush drain work");
      @(negedge clk_hp_i);
      hp_flush = 1'b0;
      wait_link_up();
      if (s_result_valid) $fatal(1, "NPU idle flush invented a cancellation event");
      if (s_generation != s_generation_before_flush + 32'd1) begin
        $fatal(1, "NPU flush did not advance the epoch generation exactly once");
      end
    end

    s_phase = "generation wrap";
    // Hold the poke for one PCLK edge so the register primitive internalizes
    // it; the steady-state d=q feedback then retains the poked value.
    @(negedge clk_i);
    force u_dut.s_generation_q = 32'hffff_fffe;
    @(posedge clk_i);
    #1;
    if (u_dut.s_generation_q != 32'hffff_fffe) $fatal(1, "NPU generation poke failed");
    release u_dut.s_generation_q;
    if (u_dut.s_generation_q != 32'hffff_fffe) $fatal(1, "NPU generation poke did not hold");
    pulse_hp_reset(3);
    wait_link_up();
    if (s_generation !== 32'hffff_ffff) $fatal(1, "NPU generation did not reach all ones");
    pulse_hp_reset(3);
    wait_link_up();
    if (s_generation !== 32'd0) $fatal(1, "NPU generation did not wrap to zero");
    shell_snapshot();

    s_phase = "done";
    $display("NPU control CDC test passed");
    $finish;
  end

  initial begin
    repeat (200000) @(posedge clk_i);
    $fatal(1, "NPU control CDC test timed out in %s", s_phase);
  end
endmodule
