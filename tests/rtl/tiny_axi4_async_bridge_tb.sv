`timescale 1ns / 1ps

module tiny_axi4_async_bridge_tb;
  logic   src_clk = 1'b0;
  logic   dst_clk = 1'b0;
  logic   src_rst_n = 1'b0;
  logic   dst_rst_n = 1'b0;
  logic   clear = 1'b0;
  logic   clear_busy;
  logic   ready;
  integer sink_ar_count = 0;
  integer sink_aw_count = 0;
  integer source_r_count = 0;
  integer source_b_count = 0;
  logic   test_reset_response;
  logic   test_write_response;

  always @(posedge src_clk) begin
    if (src_rst_n && source.rvalid && source.rready) source_r_count++;
    if (src_rst_n && source.bvalid && source.bready) source_b_count++;
  end

  always #5 src_clk = !src_clk;
  always #7 dst_clk = !dst_clk;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) source (
      .aclk   (src_clk),
      .aresetn(src_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sink (
      .aclk   (dst_clk),
      .aresetn(dst_rst_n)
  );

  tiny_axi4_async_bridge u_dut (
      .src_clk_i   (src_clk),
      .src_rst_n_i (src_rst_n),
      .dst_clk_i   (dst_clk),
      .dst_rst_n_i (dst_rst_n),
      .clear_i     (clear),
      .clear_busy_o(clear_busy),
      .ready_o     (ready),
      .epoch_o     (),
      .src_axi4    (source),
      .dst_axi4    (sink)
  );

  always @(posedge dst_clk) begin
    if (dst_rst_n && sink.arvalid && sink.arready) sink_ar_count = sink_ar_count + 1;
    if (dst_rst_n && sink.awvalid && sink.awready) sink_aw_count = sink_aw_count + 1;
  end

  task automatic source_defaults;
    begin
      source.awid     = 0;
      source.awaddr   = '0;
      source.awlen    = 0;
      source.awsize   = 2;
      source.awburst  = 1;
      source.awlock   = 0;
      source.awcache  = 0;
      source.awprot   = 0;
      source.awqos    = 0;
      source.awregion = 0;
      source.awuser   = 0;
      source.awvalid  = 0;
      source.wdata    = 32'h1234_5678;
      source.wstrb    = 4'hf;
      source.wlast    = 1;
      source.wuser    = 0;
      source.wvalid   = 0;
      source.bready   = 1;
      source.arid     = 0;
      source.araddr   = '0;
      source.arlen    = 0;
      source.arsize   = 2;
      source.arburst  = 1;
      source.arlock   = 0;
      source.arcache  = 0;
      source.arprot   = 0;
      source.arqos    = 0;
      source.arregion = 0;
      source.aruser   = 0;
      source.arvalid  = 0;
      source.rready   = 1;
    end
  endtask

  task automatic sink_defaults;
    begin
      sink.awready = 1;
      sink.wready  = 1;
      sink.bid     = 0;
      sink.bresp   = 0;
      sink.buser   = 0;
      sink.bvalid  = 0;
      sink.arready = 1;
      sink.rid     = 0;
      sink.rdata   = 32'hcafe_babe;
      sink.rresp   = 0;
      sink.rlast   = 1;
      sink.ruser   = 0;
      sink.rvalid  = 0;
    end
  endtask

  task automatic wait_ready;
    begin
      wait (ready === 1'b1);
      repeat (3) @(posedge src_clk);
    end
  endtask

  task automatic issue_read(input logic [31:0] address);
    begin
      @(negedge src_clk);
      source.araddr  = address;
      source.arvalid = 1;
      do @(posedge src_clk); while (!source.arready);
      @(negedge src_clk);
      source.arvalid = 0;
    end
  endtask

  task automatic issue_write(input logic [31:0] address);
    begin
      @(negedge src_clk);
      source.awaddr  = address;
      source.awvalid = 1;
      do @(posedge src_clk); while (!source.awready);
      @(negedge src_clk);
      source.awvalid = 0;
      source.wvalid  = 1;
      do @(posedge src_clk); while (!source.wready);
      @(negedge src_clk);
      source.wvalid = 0;
    end
  endtask

  initial begin
    source_defaults();
    sink_defaults();
    test_reset_response = $test$plusargs("same_cycle_reset_read") ||
        $test$plusargs("same_cycle_reset_write");
    test_write_response = $test$plusargs("same_cycle_write") ||
        $test$plusargs("held_write_stability") || $test$plusargs("same_cycle_reset_write");
    repeat (5) @(posedge src_clk);
    src_rst_n = 1;
    dst_rst_n = 1;
    wait_ready();

    if ($test$plusargs("clear_pending")) begin
      source.rready = 0;
      issue_read(32'h5400_0010);
      repeat (12) @(negedge dst_clk);
      @(negedge src_clk);
      clear = 1;
      wait (source.rvalid === 1'b1);
      @(negedge src_clk);
      if (source.rresp !== 2'b11) $fatal(1, "SIM_TEST_FAIL clear must return error");
      clear         = 0;
      source.rready = 1;
      @(posedge src_clk);
      @(negedge src_clk);
      repeat (200) @(negedge src_clk);
      if (source_r_count != 1 || ready || source.arready)
        $fatal(1, "SIM_TEST_FAIL pending clear lost isolation");
      // A delayed pre-clear response must never complete a new request.
      @(negedge dst_clk);
      sink.rvalid = 1;
      do @(posedge dst_clk); while (!sink.rready);
      @(negedge dst_clk);
      sink.rvalid = 0;
      repeat (20) @(negedge src_clk);
      if (source.rvalid || source_r_count != 1)
        $fatal(1, "SIM_TEST_FAIL late response escaped clear isolation");
      dst_rst_n = 0;
      repeat (8) @(negedge src_clk);
      dst_rst_n = 1;
      wait_ready();
      repeat (20) @(negedge src_clk);
      if (source.rvalid || source_r_count != 1)
        $fatal(1, "SIM_TEST_FAIL late response replay after reset");
      $display("SIM_TEST_PASS Tiny AXI pending-clear quarantine/recovery");
      $finish;
    end

    if ($test$plusargs("burst_abort")) begin
      source.arlen  = 3;
      source.arid   = 1;
      source.rready = 0;
      issue_read(32'h5400_0100);
      wait (sink.arvalid === 1'b1);
      @(negedge dst_clk);
      sink.rvalid = 1;
      sink.rlast  = 0;
      sink.rid    = 1;
      do @(posedge dst_clk); while (!sink.rready);
      @(negedge dst_clk);
      sink.rvalid = 0;
      wait (source.rvalid === 1'b1);
      @(negedge src_clk);
      dst_rst_n = 0;
      repeat (8) @(negedge src_clk);
      // Preserve the already exposed first beat; synthesize exactly the three
      // missing error beats, with RLAST only on the original fourth beat.
      for (integer beat = 0; beat < 4; beat++) begin
        wait (source.rvalid === 1'b1);
        @(negedge src_clk);
        if (source.rid !== 1'b1 || source.rlast !== (beat == 3) ||
            source.rresp !== (beat == 0 ? 2'b00 : 2'b11))
          $fatal(1, "SIM_TEST_FAIL reset read burst beat=%0d", beat);
        source.rready = 1;
        @(posedge src_clk);
        @(negedge src_clk);
        source.rready = 0;
      end
      dst_rst_n = 1;
      wait_ready();
      if (source_r_count != 4 || source.rvalid) $fatal(1, "SIM_TEST_FAIL read burst count");

      source.awlen  = 3;
      source.awid   = 1;
      source.bready = 0;
      @(negedge src_clk);
      source.awvalid = 1;
      do @(posedge src_clk); while (!source.awready);
      @(negedge src_clk);
      source.awvalid = 0;
      dst_rst_n      = 0;
      repeat (8) @(negedge src_clk);
      for (integer beat = 0; beat < 4; beat++) begin
        if (source.bvalid) $fatal(1, "SIM_TEST_FAIL reset B before write data drain");
        source.wvalid = 1;
        source.wlast  = beat == 3;
        do @(posedge src_clk); while (!source.wready);
        @(negedge src_clk);
        source.wvalid = 0;
      end
      wait (source.bvalid === 1'b1);
      @(negedge src_clk);
      if (source.bid !== 1'b1 || source.bresp !== 2'b11)
        $fatal(1, "SIM_TEST_FAIL reset burst write response");
      source.bready = 1;
      @(posedge src_clk);
      @(negedge src_clk);
      dst_rst_n = 1;
      wait_ready();
      repeat (20) @(negedge src_clk);
      if (source_b_count != 1 || source.bvalid) $fatal(1, "SIM_TEST_FAIL write burst count");
      $display("SIM_TEST_PASS Tiny AXI burst abort conservation");
      $finish;
    end

    if (test_reset_response || $test$plusargs(
            "same_cycle_clear"
        ) || $test$plusargs(
            "same_cycle_write"
        ) || $test$plusargs(
            "held_read_stability"
        ) || $test$plusargs(
            "held_write_stability"
        )) begin
      if (test_write_response) begin
        source.bready = 0;
        issue_write(32'h5400_0020);
        repeat (12) @(negedge dst_clk);
        sink.bvalid = 1;
        do @(posedge dst_clk); while (!sink.bready);
        @(negedge dst_clk);
        sink.bvalid = 0;
        wait (source.bvalid === 1'b1);
      end else begin
        source.rready = 0;
        issue_read(32'h5400_0020);
        wait (sink.arvalid === 1'b1);
        @(negedge dst_clk);
        sink.rvalid = 1;
        do @(posedge dst_clk); while (!sink.rready);
        @(negedge dst_clk);
        sink.rvalid = 0;
        wait (source.rvalid === 1'b1);
      end
      @(negedge src_clk);
      if ($test$plusargs("held_read_stability") || $test$plusargs("held_write_stability")) begin
        // Source reset remains high. A stalled response is still owned by
        // the source interface even when the remote endpoint resets.
        dst_rst_n = 0;
        repeat (8) begin
          @(negedge src_clk);
          if ($test$plusargs(
                  "held_read_stability"
              ) && (source.rvalid !== 1'b1 || source.rresp !== 2'b00 ||
                    source.rdata !== 32'hcafe_babe || source.rlast !== 1'b1))
            $fatal(1, "SIM_TEST_FAIL stalled source R response changed on remote reset");
          if ($test$plusargs(
                  "held_write_stability"
              ) && (source.bvalid !== 1'b1 || source.bresp !== 2'b00))
            $fatal(1, "SIM_TEST_FAIL stalled source B response changed on remote reset");
        end
        $display("SIM_TEST_PASS Tiny AXI held response stability");
        $finish;
      end
      if (test_reset_response) begin
        dst_rst_n = 0;
      end else begin
        clear = 1;
        wait (u_dut.s_clear_src_pulse === 1'b1);
        @(negedge src_clk);
      end
      source.rready = 1;
      source.bready = 1;
      @(posedge src_clk);
      @(negedge src_clk);
      clear = 0;
      repeat (200) @(negedge src_clk);
      if (test_write_response && source_b_count != 1)
        $fatal(1, "SIM_TEST_FAIL one AW produced %0d B handshakes during clear", source_b_count);
      if (!test_write_response && source_r_count != 1)
        $fatal(1, "SIM_TEST_FAIL one AR produced %0d R handshakes during clear", source_r_count);
      $display("SIM_TEST_PASS Tiny AXI same-cycle clear conservation");
      $finish;
    end

    issue_read(32'h5400_0040);
    wait (sink.arvalid === 1'b1);
    @(negedge dst_clk);
    sink.rvalid = 1;
    do @(posedge dst_clk); while (!sink.rready);
    @(negedge dst_clk);
    sink.rvalid = 0;
    wait (source.rvalid === 1'b1);
    if (source.rresp != 2'b00 || source.rdata != 32'hcafe_babe || !source.rlast)
      $fatal(1, "normal Tiny AXI read response mismatch");
    @(posedge src_clk);
    @(negedge src_clk);

    source.rready = 0;
    issue_read(32'h5400_0060);
    wait (sink.arvalid === 1'b1);
    @(negedge dst_clk);
    sink.rvalid = 1;
    do @(posedge dst_clk); while (!sink.rready);
    @(negedge dst_clk);
    sink.rvalid = 0;
    wait (source.rvalid === 1'b1);
    dst_rst_n = 0;
    wait (u_dut.s_abort_read_q === 1'b1);
    #1;
    if (!source.rvalid || source.rresp != 2'b00 || !source.rlast || source.rdata != 32'hcafe_babe)
      $fatal(1, "remote reset changed held read response");
    source.rready = 1;
    do @(posedge src_clk); while (u_dut.s_abort_read_q);
    source.rready = 0;
    @(negedge dst_clk);
    dst_rst_n = 1;
    wait_ready();
    source.rready = 1;

    issue_read(32'h5400_0080);
    wait (sink.arvalid === 1'b1);
    sink.arready = 0;
    @(negedge dst_clk);
    dst_rst_n = 0;
    wait (source.rvalid === 1'b1);
    if (source.rresp != 2'b11 || !source.rlast || source.rdata != 0)
      $fatal(1, "destination reset did not return read DECERR");
    if (sink.arvalid || sink.awvalid) $fatal(1, "destination reset retained stale request");
    @(negedge dst_clk);
    dst_rst_n    = 1;
    sink.arready = 1;
    wait_ready();
    if (sink_ar_count != 2) $fatal(1, "reset replayed the read request");

    sink.awready = 0;
    sink.wready  = 0;
    issue_write(32'h5400_00c0);
    wait (sink.awvalid === 1'b1);
    @(negedge dst_clk);
    dst_rst_n = 0;
    wait (source.bvalid === 1'b1);
    if (source.bresp != 2'b11) $fatal(1, "destination reset did not return write DECERR");
    if (sink.arvalid || sink.awvalid || sink.wvalid)
      $fatal(1, "destination reset retained stale write request");
    @(negedge dst_clk);
    dst_rst_n    = 1;
    sink.awready = 1;
    sink.wready  = 1;
    wait_ready();
    if (sink_aw_count != 0) $fatal(1, "reset replayed the write request");

    source.bready = 0;
    issue_write(32'h5400_00e0);
    repeat (12) @(negedge dst_clk);
    @(negedge dst_clk);
    sink.bvalid = 1;
    do @(posedge dst_clk); while (!sink.bready);
    @(negedge dst_clk);
    sink.bvalid = 0;
    wait (source.bvalid === 1'b1);
    dst_rst_n = 0;
    wait (u_dut.s_abort_write_q === 1'b1);
    #1;
    if (!source.bvalid || source.bresp != 2'b00)
      $fatal(1, "remote reset changed held write response");
    source.bready = 1;
    do @(posedge src_clk); while (u_dut.s_abort_write_q);
    source.bready = 0;
    @(negedge dst_clk);
    dst_rst_n = 1;
    wait_ready();
    source.bready = 1;

    $display("SIM_TEST_PASS Tiny AXI CDC reset abort/error/no-replay");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny AXI CDC");
  end
endmodule
