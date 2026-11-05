`timescale 1ns / 1ps
`include "dma_define.svh"
`include "ppalite_define.svh"

module ppalite_dma_guard_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  always #5 clk_i = ~clk_i;

  apb4_if host_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if dma_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  logic        route_i = 1'b1;
  logic [ 2:0] capture_state_i = `PPALITE_STATE_IDLE;
  logic        capture_arm_request_i = 1'b0;
  logic        capture_release_i = 1'b0;
  logic        capture_close_i = 1'b0;
  logic [31:0] job_destination_i = 32'h3000_0000;
  logic [31:0] job_transport_bytes_i = 32'd32;
  logic        dma_rst_n_i = 1'b1;
  logic        dma_ready_i = 1'b1;
  logic        dma_start_pending_i = 1'b0;
  logic        dma_busy_i = 1'b0;
  logic        dma_done_i = 1'b0;
  logic [31:0] dma_bytes_done_i = 32'd0;
  logic [31:0] dma_error_status_i = 32'd0;
  logic        dma_start_o;
  logic transport_ready_o, transport_idle_o, transport_admitted_o, transport_done_o;
  logic   [7:0] transport_err_o;
  logic         stream_isolated_o;
  integer       forwarded_writes = 0;
  logic         forwarded_active = 1'b0;

  assign dma_apb.pready  = dma_apb.psel && dma_apb.penable;
  assign dma_apb.prdata  = 32'd0;
  assign dma_apb.pslverr = 1'b0;
  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      forwarded_writes <= 0;
      forwarded_active <= 1'b0;
    end else if (!dma_apb.psel) begin
      forwarded_active <= 1'b0;
    end else if (dma_apb.penable && dma_apb.pwrite && dma_apb.pready && !forwarded_active) begin
      forwarded_writes <= forwarded_writes + 1;
      forwarded_active <= 1'b1;
    end
  end

  ppalite_dma_guard u_dut (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .host_apb4            (host_apb),
      .dma_apb4             (dma_apb),
      .route_i              (route_i),
      .capture_state_i      (capture_state_i),
      .capture_arm_request_i(capture_arm_request_i),
      .capture_release_i    (capture_release_i),
      .capture_close_i      (capture_close_i),
      .job_destination_i    (job_destination_i),
      .job_transport_bytes_i(job_transport_bytes_i),
      .dma_rst_n_i          (dma_rst_n_i),
      .dma_ready_i          (dma_ready_i),
      .dma_start_pending_i  (dma_start_pending_i),
      .dma_busy_i           (dma_busy_i),
      .dma_done_i           (dma_done_i),
      .dma_bytes_done_i     (dma_bytes_done_i),
      .dma_error_status_i   (dma_error_status_i),
      .dma_start_o          (dma_start_o),
      .transport_ready_o    (transport_ready_o),
      .transport_idle_o     (transport_idle_o),
      .transport_admitted_o (transport_admitted_o),
      .transport_done_o     (transport_done_o),
      .transport_err_o      (transport_err_o),
      .stream_isolated_o    (stream_isolated_o)
  );

  task automatic access (input logic write_access, input logic [31:0] address,
                         input logic [31:0] data, input logic expected_error);
    integer timeout;
    begin
      @(negedge clk_i);
      host_apb.paddr   = address;
      host_apb.pwdata  = data;
      host_apb.pstrb   = write_access ? 4'hf : 4'd0;
      host_apb.pwrite  = write_access;
      host_apb.psel    = 1'b1;
      host_apb.penable = 1'b0;
      host_apb.pprot   = 3'd0;
      @(negedge clk_i);
      host_apb.penable = 1'b1;
      timeout          = 0;
      while (!host_apb.pready && timeout < 8) begin
        @(negedge clk_i);
        timeout++;
      end
      if (!host_apb.pready) $fatal(1, "SIM_TEST_TIMEOUT guard APB address=%h", address);
      if (host_apb.pslverr !== expected_error)
        $fatal(
            1,
            "SIM_TEST_FAIL guard APB address=%h error=%b expected=%b",
            address,
            host_apb.pslverr,
            expected_error
        );
      @(negedge clk_i);
      host_apb.psel    = 1'b0;
      host_apb.penable = 1'b0;
      host_apb.pwrite  = 1'b0;
      host_apb.pstrb   = 4'd0;
    end
  endtask

  task automatic write_reg(input logic [31:0] address, input logic [31:0] data,
                           input logic expected_error);
    access (1'b1, address, data, expected_error);
  endtask

  task automatic prepare(input logic [31:0] byte_count);
    begin
      write_reg(32'h0204, 32'h0000_03a2, 1'b0);
      write_reg(32'h0208, 32'd0, 1'b0);
      write_reg(32'h020c, job_destination_i, 1'b0);
      write_reg(32'h0210, byte_count, 1'b0);
      write_reg(32'h0214, 32'd11, 1'b0);
      write_reg(32'h0218, 32'd4, 1'b0);
      write_reg(32'h0248, 32'd0, 1'b0);
      write_reg(32'h024c, 32'd0, 1'b0);
    end
  endtask

  initial begin
    host_apb.psel    = 1'b0;
    host_apb.penable = 1'b0;
    host_apb.pwrite  = 1'b0;
    host_apb.paddr   = 32'd0;
    host_apb.pwdata  = 32'd0;
    host_apb.pstrb   = 4'd0;
    host_apb.pprot   = 3'd0;
    repeat (4) @(negedge clk_i);
    rst_n_i = 1'b1;
    repeat (3) @(negedge clk_i);

    prepare(32'd32);
    if (!transport_ready_o || transport_done_o) $fatal(1, "SIM_TEST_FAIL prepared transport");
    dma_done_i       = 1'b1;
    dma_bytes_done_i = 32'd32;
    if (transport_done_o) $fatal(1, "SIM_TEST_FAIL stale DONE admitted");
    dma_done_i       = 1'b0;
    dma_bytes_done_i = 32'd0;

    write_reg(32'h0210, 32'd28, 1'b0);
    if (transport_ready_o) $fatal(1, "SIM_TEST_FAIL wrong byte count accepted");
    write_reg(32'h0210, 32'd32, 1'b0);
    write_reg(32'h0248, 32'h3000_1000, 1'b1);
    write_reg(32'h0248, 32'd0, 1'b0);
    write_reg(32'h0294, 32'd11, 1'b0);
    write_reg(32'h0280, 32'd1, 1'b1);
    write_reg(32'h0200, 32'd1, 1'b1);

    capture_arm_request_i = 1'b1;
    write_reg(32'h0200, 32'd1, 1'b0);
    capture_arm_request_i = 1'b0;
    if (!transport_admitted_o) $fatal(1, "SIM_TEST_FAIL ARM/START race token");
    write_reg(32'h0200, 32'd8, 1'b0);
    write_reg(32'h0200, 32'd16, 1'b0);
    if (transport_admitted_o) $fatal(1, "SIM_TEST_FAIL drained reset retained token");

    capture_state_i = `PPALITE_STATE_ARMED;
    write_reg(32'h0200, 32'd1, 1'b0);
    dma_start_pending_i = 1'b1;
    if (transport_idle_o) $fatal(1, "SIM_TEST_FAIL admitted START became idle before BUSY");
    dma_start_pending_i = 1'b0;
    dma_busy_i          = 1'b1;
    write_reg(32'h0200, 32'd1, 1'b1);
    write_reg(32'h020c, 32'h3000_0040, 1'b1);
    dma_busy_i         = 1'b0;
    dma_done_i         = 1'b1;
    dma_bytes_done_i   = 32'd32;
    dma_error_status_i = 32'h0000_0100;
    capture_state_i    = `PPALITE_STATE_COMPLETE;
    @(negedge clk_i);
    if (!transport_done_o) $fatal(1, "SIM_TEST_FAIL current-job completion with STREAM_LAST");
    write_reg(32'h0200, 32'd1, 1'b1);
    capture_state_i   = `PPALITE_STATE_IDLE;
    capture_release_i = 1'b1;
    @(negedge clk_i);
    capture_release_i  = 1'b0;
    dma_done_i         = 1'b0;
    dma_bytes_done_i   = 32'd0;
    dma_error_status_i = 32'd0;
    if (transport_admitted_o || !transport_ready_o)
      $fatal(1, "SIM_TEST_FAIL release did not clear admission without reset");

    capture_state_i = `PPALITE_STATE_RUNNING;
    dma_ready_i     = 1'b0;
    @(negedge clk_i);
    if ((transport_err_o == 8'd0) || transport_idle_o)
      $fatal(1, "SIM_TEST_FAIL DMA readiness loss was hidden");
    dma_ready_i     = 1'b1;
    capture_state_i = `PPALITE_STATE_IDLE;

    prepare(32'd32);
    dma_rst_n_i = 1'b0;
    @(negedge clk_i);
    if (u_dut.s_exact_shadow || transport_ready_o)
      $fatal(1, "SIM_TEST_FAIL DMA reset retained stale configuration");
    dma_rst_n_i = 1'b1;
    prepare(32'd32);
    if (!transport_ready_o) $fatal(1, "SIM_TEST_FAIL reprogramming after DMA reset");
    route_i = 1'b0;
    write_reg(32'h020c, 32'h3000_0080, 1'b0);
    if (forwarded_writes != 33)
      $fatal(1, "SIM_TEST_FAIL forwarded write accounting count=%0d", forwarded_writes);

    $display("SIM_TEST_PASS PPALITE_P3_DMA_GUARD writes=%0d", forwarded_writes);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT PPALite DMA guard");
  end
endmodule
