// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
//
// Scripted testbench for npu_accumulator: two-context acquire/bias preload,
// checked row accumulation with a 64-bit TB model, position-major drain with
// stall patterns, interleaved contexts, K-chunk continuation, back-to-back
// reuse, exactly-once publication, pending drain while another drain is in
// flight, intentional positive/negative overflow faults (sticky flag, lowest
// sum index, no drain from Fault), and clear_i release.

`timescale 1ns / 1ps

module npu_accumulator_tb;
  logic                             clk_i = 1'b0;
  logic                             rst_n_i = 1'b0;
  logic                             clear;
  logic                             start_valid;
  logic                             start_ready;
  logic          [ 7:0][31:0]       start_bias;
  logic                             start_context;
  logic                             row_valid;
  logic                             row_ready;
  logic                             row_context;
  logic          [ 7:0][ 7:0][16:0] row_products;
  logic          [63:0][16:0]       products_drive;
  logic                             drain_valid;
  logic                             drain_context;
  logic                             drain_data_valid;
  logic                             drain_data_ready;
  logic signed   [31:0]             drain_data;
  logic                             drain_last;
  logic                             busy;
  logic                             fault_sticky;
  logic          [ 5:0]             fault_sum;

  // 64-bit TB model of the 2x64 sums; index = context*64 + position*8 + channel.
  longint signed                    model_sum        [0:127];

  always #5 clk_i = ~clk_i;

  assign row_products = products_drive;

  npu_accumulator u_dut (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .clear_i           (clear),
      .start_valid_i     (start_valid),
      .start_ready_o     (start_ready),
      .start_bias_i      (start_bias),
      .start_context_o   (start_context),
      .row_valid_i       (row_valid),
      .row_ready_o       (row_ready),
      .row_context_i     (row_context),
      .row_products_i    (row_products),
      .drain_valid_i     (drain_valid),
      .drain_context_i   (drain_context),
      .drain_data_valid_o(drain_data_valid),
      .drain_data_ready_i(drain_data_ready),
      .drain_data_o      (drain_data),
      .drain_last_o      (drain_last),
      .busy_o            (busy),
      .fault_sticky_o    (fault_sticky),
      .fault_sum_o       (fault_sum)
  );

  function automatic longint signed product_at(input integer index_i);
    logic signed [16:0] s_product;
    begin
      s_product  = products_drive[index_i];
      product_at = s_product;
    end
  endfunction

  task automatic hard_reset;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic fill_products(input logic signed [16:0] value_i);
    begin
      products_drive = {64{value_i}};
    end
  endtask

  task automatic set_product(input integer index_i, input logic signed [16:0] value_i);
    begin
      products_drive[index_i] = value_i;
    end
  endtask

  task automatic acquire(input logic expected_context_i);
    begin
      @(negedge clk_i);
      start_valid = 1'b1;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk_i);
        if (start_ready) begin
          if (start_context !== expected_context_i) begin
            $fatal(1, "NPU accumulator acquire context mismatch got=%0d expected=%0d",
                   start_context, expected_context_i);
          end
          for (int index = 0; index < 64; index++) begin
            model_sum[expected_context_i*64+index] = $signed(start_bias[index%8]);
          end
          @(negedge clk_i);
          start_valid = 1'b0;
          return;
        end
      end
      $fatal(1, "NPU accumulator acquire timeout context=%0d", expected_context_i);
    end
  endtask

  // Accepted rows must never overflow the 64-bit-checked TB model here; the
  // faulting-row task below is the only overflow path. When with_drain_i is
  // set, the drain request for the same context is raised together with the
  // row: the context enters DrainPending in the acceptance cycle and the
  // drain may publish only after this row has landed in the sums.
  task automatic send_row(input logic context_i, input logic with_drain_i);
    begin
      @(negedge clk_i);
      row_context = context_i;
      row_valid   = 1'b1;
      if (with_drain_i) begin
        drain_context = context_i;
        drain_valid   = 1'b1;
      end
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk_i);
        if (row_ready) begin
          for (int index = 0; index < 64; index++) begin
            model_sum[context_i*64+index] = model_sum[context_i*64+index] + product_at(index);
            if ((model_sum[context_i*64+index] > 64'sd2147483647) ||
                (model_sum[context_i*64+index] < -64'sd2147483648)) begin
              $fatal(1, "NPU accumulator TB model overflow on non-fault row context=%0d index=%0d",
                     context_i, index);
            end
          end
          @(negedge clk_i);
          row_valid = 1'b0;
          if (with_drain_i) begin
            drain_valid = 1'b0;
          end
          return;
        end
      end
      $fatal(1, "NPU accumulator row timeout context=%0d", context_i);
    end
  endtask

  // Drive a burst of rows accepted on consecutive cycles (row_valid stays
  // high, products change every cycle) to prove the one-row-per-cycle
  // sustained throughput of the pipelined accumulate: stage A must keep
  // accepting while stage B accumulates the previous row. Row products are
  // base_i + row*step_i replicated on all 64 lanes.
  task automatic send_row_burst(input logic context_i, input integer row_count_i,
                                input integer base_i, input integer step_i);
    begin
      for (int row = 0; row < row_count_i; row++) begin
        @(negedge clk_i);
        row_context    = context_i;
        products_drive = {64{17'(base_i + row * step_i)}};
        row_valid      = 1'b1;
        for (int cycle = 0; cycle < 100; cycle++) begin
          @(posedge clk_i);
          if (row_ready) begin
            for (int index = 0; index < 64; index++) begin
              model_sum[context_i*64+index] = model_sum[context_i*64+index] + product_at(index);
              if ((model_sum[context_i*64+index] > 64'sd2147483647) ||
                  (model_sum[context_i*64+index] < -64'sd2147483648)) begin
                $fatal(1, "NPU accumulator TB model overflow on burst row context=%0d index=%0d",
                       context_i, index);
              end
            end
            break;
          end
          if (cycle == 99) begin
            $fatal(1, "NPU accumulator burst row timeout context=%0d row=%0d", context_i, row);
          end
        end
      end
      @(negedge clk_i);
      row_valid = 1'b0;
    end
  endtask

  // Drive a row whose model predicts at least one overflowing update; the DUT
  // must latch the sticky fault and the lowest overflowing sum index, and the
  // stored sums (and therefore the TB model) stay untouched.
  task automatic send_row_expect_fault(input logic context_i);
    begin
      longint signed s_trial;
      integer        s_fault_index;
      logic          s_found;
      s_found       = 1'b0;
      s_fault_index = 0;
      for (int index = 63; index >= 0; index--) begin
        s_trial = model_sum[context_i*64+index] + product_at(index);
        if ((s_trial > 64'sd2147483647) || (s_trial < -64'sd2147483648)) begin
          s_found       = 1'b1;
          s_fault_index = index;
        end
      end
      if (!s_found) begin
        $fatal(1, "NPU accumulator TB expected a fault but the model does not overflow");
      end
      @(negedge clk_i);
      row_context = context_i;
      row_valid   = 1'b1;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk_i);
        if (row_ready) begin
          @(negedge clk_i);
          row_valid = 1'b0;
          break;
        end
        if (cycle == 99) begin
          $fatal(1, "NPU accumulator fault row timeout context=%0d", context_i);
        end
      end
      repeat (2) @(posedge clk_i);
      if (fault_sticky !== 1'b1) begin
        $fatal(1, "NPU accumulator fault_sticky not set context=%0d", context_i);
      end
      if (fault_sum !== 6'(s_fault_index)) begin
        $fatal(1, "NPU accumulator fault_sum mismatch got=%0d expected=%0d", fault_sum,
               s_fault_index);
      end
    end
  endtask

  task automatic drain_launch(input logic context_i);
    begin
      @(negedge clk_i);
      drain_context = context_i;
      drain_valid   = 1'b1;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk_i);
        if (drain_data_valid) begin
          break;
        end
        if (cycle == 99) begin
          $fatal(1, "NPU accumulator drain launch timeout context=%0d", context_i);
        end
      end
      @(negedge clk_i);
      drain_valid      = 1'b0;
      drain_data_ready = 1'b0;
    end
  endtask

  // Streams the 64 sums of a context already in Draining, checking
  // position-major order, values, and drain_last; applies deterministic stall
  // stretches, optionally interleaves rows to the other accumulating context
  // at items 16/32/48, and optionally raises a held pending drain request for
  // another context at item 40 (left asserted for the caller to observe).
  task automatic drain_stream(input logic context_i, input logic interleave_en_i,
                              input logic interleave_context_i, input logic pending_en_i,
                              input logic pending_context_i);
    begin
      integer stalls;
      for (int index = 0; index < 64; index++) begin
        if (interleave_en_i && ((index == 16) || (index == 32) || (index == 48))) begin
          fill_products(17'sd900);
          send_row(interleave_context_i, 1'b0);
        end
        if (pending_en_i && (index == 40)) begin
          @(negedge clk_i);
          drain_context = pending_context_i;
          drain_valid   = 1'b1;
        end
        stalls = ((index % 7) == 3) ? 3 : (index % 2);
        repeat (stalls) @(posedge clk_i);
        @(negedge clk_i);
        drain_data_ready = 1'b1;
        for (int cycle = 0; cycle < 100; cycle++) begin
          @(posedge clk_i);
          if (drain_data_valid && drain_data_ready) begin
            if ($signed(drain_data) !== model_sum[context_i*64+index]) begin
              $fatal(1, "NPU accumulator drain mismatch context=%0d index=%0d got=%0d expected=%0d",
                     context_i, index, $signed(drain_data), model_sum[context_i*64+index]);
            end
            if (drain_last !== (index == 63)) begin
              $fatal(1, "NPU accumulator drain_last mismatch context=%0d index=%0d", context_i,
                     index);
            end
            break;
          end
          if (cycle == 99) begin
            $fatal(1, "NPU accumulator drain item timeout context=%0d index=%0d", context_i, index);
          end
        end
        @(negedge clk_i);
        drain_data_ready = 1'b0;
      end
    end
  endtask

  task automatic drain_and_check(input logic context_i);
    begin
      drain_launch(context_i);
      drain_stream(context_i, 1'b0, 1'b0, 1'b0, 1'b0);
    end
  endtask

  // A drain request naming an Idle or Fault context must never publish data.
  task automatic check_drain_ignored(input logic context_i);
    begin
      @(negedge clk_i);
      drain_context = context_i;
      drain_valid   = 1'b1;
      repeat (4) @(posedge clk_i);
      if (drain_data_valid) begin
        $fatal(1, "NPU accumulator drain published from non-accumulating context=%0d", context_i);
      end
      @(negedge clk_i);
      drain_valid = 1'b0;
    end
  endtask

  task automatic check_row_rejected(input logic context_i);
    begin
      @(negedge clk_i);
      row_context = context_i;
      row_valid   = 1'b1;
      repeat (3) @(posedge clk_i);
      if (row_ready) begin
        $fatal(1, "NPU accumulator row accepted on non-accumulating context=%0d", context_i);
      end
      @(negedge clk_i);
      row_valid = 1'b0;
    end
  endtask

  task automatic check_start_blocked;
    begin
      @(negedge clk_i);
      start_valid = 1'b1;
      repeat (3) @(posedge clk_i);
      if (start_ready) begin
        $fatal(1, "NPU accumulator start accepted while both contexts occupied");
      end
      @(negedge clk_i);
      start_valid = 1'b0;
    end
  endtask

  task automatic pulse_clear;
    begin
      @(negedge clk_i);
      clear = 1'b1;
      @(negedge clk_i);
      clear = 1'b0;
      @(posedge clk_i);
      if (fault_sticky !== 1'b0) begin
        $fatal(1, "NPU accumulator fault_sticky not released by clear_i");
      end
      if (busy !== 1'b0) begin
        $fatal(1, "NPU accumulator busy not released by clear_i");
      end
      if (start_ready !== 1'b1) begin
        $fatal(1, "NPU accumulator start_ready not restored by clear_i");
      end
    end
  endtask

  initial begin
    clear            = 1'b0;
    start_valid      = 1'b0;
    start_bias       = '0;
    row_valid        = 1'b0;
    row_context      = 1'b0;
    products_drive   = '0;
    drain_valid      = 1'b0;
    drain_context    = 1'b0;
    drain_data_ready = 1'b0;
    for (int index = 0; index < 128; index++) begin
      model_sum[index] = 64'sd0;
    end

    hard_reset();
    if ((busy !== 1'b0) || (start_ready !== 1'b1) || (fault_sticky !== 1'b0)) begin
      $fatal(1, "NPU accumulator bad reset state busy=%0d start_ready=%0d fault=%0d", busy,
             start_ready, fault_sticky);
    end

    // Scenario 1: ctx0 bias preload, two acquire-free accumulate bursts
    // (K-chunk continuation, including an all-zero row), drain with stalls.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = (channel * 12345) - 30000;
    end
    acquire(1'b0);
    if (busy !== 1'b1) begin
      $fatal(1, "NPU accumulator busy not set after acquire");
    end
    fill_products(17'sd300);
    set_product(26, -17'sd1000);
    set_product(47, 17'sd32512);
    send_row(1'b0, 1'b0);
    fill_products(-17'sd250);
    send_row(1'b0, 1'b0);
    fill_products(17'sd1000);
    send_row(1'b0, 1'b0);
    fill_products(17'sd0);
    send_row(1'b0, 1'b0);
    fill_products(-17'sd3000);
    set_product(0, 17'sd32512);
    send_row(1'b0, 1'b0);
    drain_and_check(1'b0);
    if (busy !== 1'b0) begin
      $fatal(1, "NPU accumulator busy stuck after drain");
    end

    // Scenario 1b: back-to-back burst at one row per cycle; stage A must keep
    // accepting while stage B accumulates the previous row (full-rate RAW
    // chaining through the sums).
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = (channel * 91) - 500;
    end
    acquire(1'b0);
    send_row_burst(1'b0, 24, 200, -11);
    drain_and_check(1'b0);
    if (busy !== 1'b0) begin
      $fatal(1, "NPU accumulator busy stuck after burst drain");
    end

    // Scenario 2: exactly-once publication; a repeated drain request on the
    // now-Idle context publishes nothing.
    check_drain_ignored(1'b0);

    // Scenario 3: back-to-back reuse of ctx0 after its drain completed.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = 100000 - (channel * 999);
    end
    acquire(1'b0);
    fill_products(17'sd2000);
    send_row(1'b0, 1'b0);
    set_product(63, -17'sd32768);
    send_row(1'b0, 1'b0);
    drain_and_check(1'b0);

    // Scenario 4: interleave ctx1 acquire/accumulate while ctx0 drains, and
    // start backpressure while both contexts are occupied.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel * 100;
    end
    acquire(1'b0);
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = (channel * 50) - 400;
    end
    acquire(1'b1);
    check_start_blocked();
    fill_products(17'sd500);
    send_row(1'b0, 1'b0);
    fill_products(-17'sd700);
    set_product(63, 17'sd12345);
    send_row(1'b1, 1'b0);
    drain_launch(1'b0);
    drain_stream(1'b0, 1'b1, 1'b1, 1'b0, 1'b0);
    drain_and_check(1'b1);
    if (busy !== 1'b0) begin
      $fatal(1, "NPU accumulator busy stuck after interleaved drains");
    end

    // Scenario 5: a held drain request for ctx1 raised mid-drain of ctx0
    // launches ctx1 automatically once ctx0 finishes (single drain port).
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel * 7;
    end
    acquire(1'b0);
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = 50 - channel;
    end
    acquire(1'b1);
    fill_products(17'sd33);
    send_row(1'b0, 1'b0);
    fill_products(-17'sd44);
    send_row(1'b1, 1'b0);
    drain_launch(1'b0);
    drain_stream(1'b0, 1'b0, 1'b0, 1'b1, 1'b1);
    for (int cycle = 0; cycle < 100; cycle++) begin
      @(posedge clk_i);
      if (drain_data_valid) begin
        break;
      end
      if (cycle == 99) begin
        $fatal(1, "NPU accumulator pending drain did not launch after ctx0 finished");
      end
    end
    @(negedge clk_i);
    drain_valid = 1'b0;
    drain_stream(1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    if (busy !== 1'b0) begin
      $fatal(1, "NPU accumulator busy stuck after pending drain");
    end

    // Scenario 5b: a drain request raised in the same cycle as the final row
    // acceptance must wait for the pipelined row to land in the sums before
    // publishing (DrainPending waits for the accumulate pipeline).
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = 1000 + channel;
    end
    acquire(1'b0);
    fill_products(17'sd123);
    send_row(1'b0, 1'b0);
    fill_products(-17'sd456);
    send_row(1'b0, 1'b1);
    drain_stream(1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    if (busy !== 1'b0) begin
      $fatal(1, "NPU accumulator busy stuck after same-cycle row+drain");
    end

    // Scenario 6: intentional positive overflow on ctx1. Two sums overflow in
    // the same row; the lowest index (10) must win the fault record. The
    // faulting context rejects rows, never drains, and clear_i releases it.
    // ctx0 is acquired first so the near-maximum bias lands on ctx1.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel;
    end
    acquire(1'b0);
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = 100;
    end
    start_bias[2] = 32'h7fff_ff00;
    acquire(1'b1);
    fill_products(17'sd0);
    set_product(10, 17'sd1000);
    set_product(26, 17'sd2000);
    send_row_expect_fault(1'b1);
    check_row_rejected(1'b1);
    check_drain_ignored(1'b1);
    // The other context keeps working while ctx1 is faulted.
    fill_products(17'sd7);
    send_row(1'b0, 1'b0);
    drain_and_check(1'b0);
    pulse_clear();
    // clear_i released the Fault context: acquire and drain both again.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel * 3;
    end
    acquire(1'b0);
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel * 5;
    end
    acquire(1'b1);
    fill_products(17'sd11);
    send_row(1'b1, 1'b0);
    drain_and_check(1'b1);
    fill_products(17'sd13);
    send_row(1'b0, 1'b0);
    drain_and_check(1'b0);

    // Scenario 6b: a stage-B fault landing while the context sits in
    // DrainPending (row and drain request accepted in the same cycle) must win
    // over the drain: the context faults and the drain never publishes.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel * 2;
    end
    acquire(1'b0);
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = 50;
    end
    start_bias[2] = 32'h7fff_ff00;
    acquire(1'b1);
    fill_products(17'sd0);
    set_product(10, 17'sd1000);
    @(negedge clk_i);
    row_context   = 1'b1;
    row_valid     = 1'b1;
    drain_context = 1'b1;
    drain_valid   = 1'b1;
    for (int cycle = 0; cycle < 100; cycle++) begin
      @(posedge clk_i);
      if (row_ready) begin
        break;
      end
      if (cycle == 99) begin
        $fatal(1, "NPU accumulator pending-fault row timeout");
      end
    end
    @(negedge clk_i);
    row_valid   = 1'b0;
    drain_valid = 1'b0;
    // The fault lands one cycle after acceptance; the drain must never publish.
    repeat (6) begin
      @(posedge clk_i);
      if (drain_data_valid) begin
        $fatal(1, "NPU accumulator drain published from faulting pending context");
      end
    end
    if (fault_sticky !== 1'b1) begin
      $fatal(1, "NPU accumulator pending fault not latched");
    end
    if (fault_sum !== 6'd10) begin
      $fatal(1, "NPU accumulator pending fault_sum mismatch got=%0d expected=10", fault_sum);
    end
    check_row_rejected(1'b1);
    pulse_clear();
    // Both contexts are healthy again after the clear.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = channel;
    end
    acquire(1'b0);
    fill_products(17'sd5);
    send_row(1'b0, 1'b0);
    drain_and_check(1'b0);

    // Scenario 7: intentional negative overflow on ctx0 at sum index 5.
    for (int channel = 0; channel < 8; channel++) begin
      start_bias[channel] = 0;
    end
    start_bias[5] = 32'h8000_0010;
    acquire(1'b0);
    fill_products(17'sd0);
    set_product(5, -17'sd1000);
    send_row_expect_fault(1'b0);
    pulse_clear();

    repeat (2) @(posedge clk_i);
    if ((busy !== 1'b0) || (start_ready !== 1'b1) || (fault_sticky !== 1'b0)) begin
      $fatal(1, "NPU accumulator bad final state busy=%0d start_ready=%0d fault=%0d", busy,
             start_ready, fault_sticky);
    end
    $display("NPU accumulator test passed");
    $finish;
  end
endmodule
