`timescale 1ns / 1ps

module rib_bus_tb;
  localparam logic TARGET_IDLE = 1'b0;
  localparam logic TARGET_RESP = 1'b1;

  logic         clk_i = 1'b0;
  logic         rst_n_i = 1'b0;
  logic         target_state_q = TARGET_IDLE;
  logic   [1:0] target_len_q = '0;
  logic   [1:0] target_beat_q = '0;
  integer       rib_command_count = 0;
  integer       cycle_count = 0;
  integer       last_response_cycle;
  integer       response_count;
  logic         fault_valid_o;
  logic   [2:0] fault_code_o;
  logic         user_bus_idle_o;
  rib_if mgmt_rib ();
  rib_if user_rib ();
  rib_if dma_rib ();
  rib_if rib ();
  rib_if apb_rib ();

  always #5 clk_i = ~clk_i;
  always @(posedge clk_i) cycle_count <= cycle_count + 1;

  assign rib.cmd_ready = target_state_q == TARGET_IDLE;
  assign rib.w_ready   = 1'b0;
  assign rib.rsp_valid = target_state_q == TARGET_RESP;
  assign rib.rdata     = 32'hCAFE_0000 + target_beat_q;
  assign rib.resp_err  = 1'b0;
  assign rib.resp_code = `RIB_RESP_OK;
  assign rib.rsp_beat  = target_beat_q;
  assign rib.rsp_last  = target_beat_q == target_len_q;

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      target_state_q    <= TARGET_IDLE;
      target_len_q      <= '0;
      target_beat_q     <= '0;
      rib_command_count <= 0;
    end else if (target_state_q == TARGET_IDLE) begin
      if (rib.cmd_valid && rib.cmd_ready) begin
        if (rib.cmd_write) $fatal(1, "read-only target received write command");
        target_len_q      <= rib.cmd_len;
        target_beat_q     <= '0;
        target_state_q    <= TARGET_RESP;
        rib_command_count <= rib_command_count + 1;
      end
    end else if (rib.rsp_valid && rib.rsp_ready) begin
      if (rib.rsp_last) begin
        target_state_q <= TARGET_IDLE;
      end else begin
        target_beat_q <= target_beat_q + 1'b1;
      end
    end
  end

  assign apb_rib.cmd_ready = 1'b1;
  assign apb_rib.w_ready   = 1'b1;
  assign apb_rib.rsp_valid = 1'b0;
  assign apb_rib.rdata     = 32'h1234_5678;
  assign apb_rib.resp_err  = 1'b0;
  assign apb_rib.resp_code = `RIB_RESP_OK;
  assign apb_rib.rsp_beat  = '0;
  assign apb_rib.rsp_last  = 1'b1;

  rib_bus u_bus (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_rib         (mgmt_rib),
      .user_rib         (user_rib),
      .dma_rib          (dma_rib),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_bus_idle_o),
      .rib              (rib),
      .apb_rib          (apb_rib),
      .perf_enable_i    (1'b0),
      .perf_clear_i     (1'b0),
      .fault_valid_o    (fault_valid_o),
      .fault_addr_o     (),
      .fault_wstrb_o    (),
      .fault_reserved_o (),
      .fault_access_o   (),
      .fault_master_o   (),
      .fault_code_o     (fault_code_o),
      .perf_mgmt_wait_o (),
      .perf_user_wait_o (),
      .perf_dma_wait_o  (),
      .perf_apb4_wait_o (),
      .perf_apb_wait_o  (),
      .perf_sdram_wait_o(),
      .perf_psram_wait_o(),
      .perf_flash_wait_o()
  );

  task automatic issue_read(input logic [31:0] address, input logic [1:0] length,
                            input logic expect_error);
    begin
      @(negedge clk_i);
      dma_rib.cmd_addr  = address;
      dma_rib.cmd_write = 1'b0;
      dma_rib.cmd_len   = length;
      dma_rib.cmd_valid = 1'b1;
      while (!dma_rib.cmd_ready) @(posedge clk_i);
      @(negedge clk_i);
      dma_rib.cmd_valid   = 1'b0;
      response_count      = 0;
      last_response_cycle = -1;
      while (response_count <= length) begin
        while (!dma_rib.rsp_valid) @(posedge clk_i);
        if (dma_rib.resp_err !== expect_error) begin
          $fatal(1, "unexpected response status for %h", address);
        end
        if (expect_error) begin
          if (dma_rib.resp_code !== `RIB_RESP_BURSTERR || !dma_rib.rsp_last) begin
            $fatal(1, "illegal burst did not return terminal BURSTERR");
          end
          response_count = length + 1;
        end else begin
          if (dma_rib.rsp_beat !== response_count[1:0]) begin
            $fatal(1, "response beat index mismatch");
          end
          if ((last_response_cycle >= 0) && (cycle_count != last_response_cycle + 1)) begin
            $fatal(1, "bubble detected between INCR4 response beats");
          end
          last_response_cycle = cycle_count;
          response_count      = response_count + 1;
        end
        @(posedge clk_i);
        @(negedge clk_i);
      end
    end
  endtask

  initial begin
    mgmt_rib.cmd_valid = 1'b0;
    mgmt_rib.cmd_addr  = '0;
    mgmt_rib.cmd_write = 1'b0;
    mgmt_rib.cmd_len   = `RIB_LEN_INCR1;
    mgmt_rib.w_valid   = 1'b0;
    mgmt_rib.wdata     = '0;
    mgmt_rib.wstrb     = '0;
    mgmt_rib.wlast     = 1'b0;
    mgmt_rib.rsp_ready = 1'b1;
    user_rib.cmd_valid = 1'b0;
    user_rib.cmd_addr  = '0;
    user_rib.cmd_write = 1'b0;
    user_rib.cmd_len   = '0;
    user_rib.w_valid   = 1'b0;
    user_rib.wdata     = '0;
    user_rib.wstrb     = '0;
    user_rib.wlast     = 1'b0;
    user_rib.rsp_ready = 1'b1;
    dma_rib.cmd_valid  = 1'b0;
    dma_rib.cmd_addr   = '0;
    dma_rib.cmd_write  = 1'b0;
    dma_rib.cmd_len    = '0;
    dma_rib.w_valid    = 1'b0;
    dma_rib.wdata      = '0;
    dma_rib.wstrb      = '0;
    dma_rib.wlast      = 1'b0;
    dma_rib.rsp_ready  = 1'b1;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    issue_read(32'h3800_1000, `RIB_LEN_INCR4, 1'b0);
    if (rib_command_count != 1) begin
      $fatal(1, "INCR4 was split before reaching the burst RIB target");
    end
    issue_read(32'h3800_1004, `RIB_LEN_INCR4, 1'b1);
    issue_read(32'h1000_0000, `RIB_LEN_INCR4, 1'b1);
    issue_read(32'h2000_0000, `RIB_LEN_INCR4, 1'b1);
    issue_read(32'h3800_1000, 2'd2, 1'b1);
    if (rib_command_count != 1 || apb_rib.cmd_valid) begin
      $fatal(1, "illegal burst reached a downstream target");
    end

    $display("RIB burst arbitration and protocol test passed");
    $finish;
  end

endmodule
